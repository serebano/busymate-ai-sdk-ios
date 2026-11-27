import Combine
import OSLog
import UIKit
import WebKit

// Busymate AI — unread follow-ups in YOUR app (unread 1.0.0).
//
// The chat page and the app talk over one channel:
//
//   page → app   window.webkit.messageHandlers.busymate.postMessage(obj)
//                  support.chat.v1.unread   {n, t, at}   unread count, first sentence, time
//                  support.chat.v1.identity {v}          opaque visitor token (kept in the Keychain)
//   app → page   support.chat.v1.open                    "show the conversation" (launcher or bubble tapped)
//
// Only frames on Busymate's chat origins for your assistant (plus the exact https origins you list)
// are heard; every message is schema-checked and unknown types are dropped. With the token the SDK
// also asks `POST /api/chat/unread` on configure and whenever the app comes to the foreground, so
// your launcher shows the badge and the follow-up bubble while the chat is closed.
//
// Use:
//
//   Busymate.shared.configure(.init(assistant: "acme"))          // app start: restores the badge
//   Busymate.shared.attach(to: webView)                           // before the chat's first load
//   Busymate.shared.onOpenChat = { [weak self] in self?.presentChat() }
//   // then show BusymateLauncher() (SwiftUI) / BusymateLauncherView() (UIKit), or draw your own from
//   // Busymate.shared.unread (AsyncStream), .unreadPublisher (Combine) or the delegate.

/// Hear about unread changes and launcher taps without Combine or async code. Called on the main thread.
@MainActor
public protocol BusymateDelegate: AnyObject {
    /// The unread value changed (main thread). `unread.count == 0` clears the badge.
    func busymateDidUpdateUnread(_ unread: BusymateUnread)
    /// The person tapped the launcher or the bubble: present your chat screen.
    func busymateDidRequestChat()
}

public extension BusymateDelegate {
    func busymateDidRequestChat() {}
}

/// The words the built-in launcher and bubble show and speak. Replace them with your localized ones.
public struct BusymateStrings {
    /// The launcher's VoiceOver name.
    public var launcher = "Chat"
    /// The launcher's VoiceOver value for a count, e.g. "2 unread messages".
    public var unreadCount: (Int) -> String = { $0 == 1 ? "1 unread message" : "\($0) unread messages" }
    /// The small heading of the follow-up bubble.
    public var teaserTitle = "New message"
    /// Shown when the server sent no preview text.
    public var teaserFallback = "You have a new message"
    /// VoiceOver hint of the bubble.
    public var teaserHint = "Opens the chat"
    /// VoiceOver name of the bubble's close control.
    public var dismiss = "Dismiss"
    public init() {}
}

@available(iOS 15.0, *)
@MainActor
public final class Busymate: NSObject, ObservableObject {
    public static let shared = Busymate()
    /// The script message handler's name: `window.webkit.messageHandlers.busymate`.
    public static let handlerName = "busymate"

    public struct Configuration {
        /// Your assistant slug (`acme` in `https://busymate.ai/chat/w/acme`).
        public let assistant: String
        /// The chat address your app loads. Its origin also answers the unread question.
        public let chatURL: URL
        /// Extra exact https origins that may talk to the app (your mapped support host). No wildcards.
        public let origins: [String]

        public init(assistant: String, chatURL: URL? = nil, origins: [String] = []) {
            self.assistant = assistant
            self.chatURL = chatURL ?? URL(string: "https://busymate.ai/chat/w/\(assistant)")
                ?? URL(string: "https://busymate.ai")!
            self.origins = origins
        }
    }

    /// The latest unread value. SwiftUI views observing `Busymate.shared` redraw when it changes.
    @Published public private(set) var currentUnread = BusymateUnread.none
    /// The message the follow-up bubble shows, or nil (nothing unread, or the person dismissed it).
    @Published public private(set) var teaser: BusymateUnread?

    public weak var delegate: BusymateDelegate?
    /// Called when the person taps the launcher or the bubble: present your chat screen here.
    public var onOpenChat: (() -> Void)?
    public var strings = BusymateStrings()

    private var configuration: Configuration?
    private var allowedOrigins: Set<String> = []
    private var apiOrigin = "https://busymate.ai"
    private var state = BusymateUnreadState()
    private var store: BusymateTokenStoring = BusymateKeychainTokenStore()
    private var defaults = UserDefaults.standard
    private var continuations: [UUID: AsyncStream<BusymateUnread>.Continuation] = [:]
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config, delegate: BusymateNoRedirects(), delegateQueue: nil)
    }()

    private weak var webView: WKWebView?
    private var lastFrame: WKFrameInfo?
    private var loadingObservation: NSKeyValueObservation?
    /// The current chat document has sent a valid message (its listener for `open` is installed).
    private var pageIsListening = false
    private var pendingOpen = false

    private override init() { super.init() }

    // MARK: Set-up

    /// Call once at app start (and again when the assistant changes). Restores the badge from the
    /// server when a visitor token is stored, and keeps it fresh on every return to the foreground.
    public func configure(_ configuration: Configuration) {
        guard BusymateChatMessage.isValidAssistant(configuration.assistant),
              let origin = BusymateOrigins.origin(of: configuration.chatURL) else {
            Logger(subsystem: "ai.busymate.sdk", category: "unread").fault(
                "Busymate.configure: the assistant slug or chat URL is not valid; unread is off.")
            return
        }
        let changed = self.configuration?.assistant != configuration.assistant
        self.configuration = configuration
        apiOrigin = origin
        allowedOrigins = BusymateOrigins.allowed(
            assistant: configuration.assistant, chatURL: configuration.chatURL, extra: configuration.origins)
        if changed {
            state = BusymateUnreadState(dismissedKey: defaults.string(forKey: dismissedDefaultsKey))
            publish(force: true)
        }
        if observers.isEmpty {
            for name in [UIApplication.willEnterForegroundNotification, UIScene.willEnterForegroundNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refreshUnread() }
                })
            }
        }
        refreshUnread()
    }

    /// Install the channel on the chat's web view BEFORE its first load. Safe to call again for a new web view.
    public func attach(to webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .page)
        controller.add(BusymateWeakMessageHandler(self), contentWorld: .page, name: Self.handlerName)
        self.webView = webView
        lastFrame = nil
        pageIsListening = false
        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
            guard change.newValue == true else { return }
            Task { @MainActor in self?.pageIsListening = false; self?.lastFrame = nil }
        }
    }

    /// Remove the channel (when you dispose the web view).
    public func detach(from webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .page)
        guard self.webView === webView else { return }
        loadingObservation = nil
        self.webView = nil
        lastFrame = nil
        pageIsListening = false
    }

    // MARK: Observing

    /// Every unread value, starting with the current one: `for await unread in Busymate.shared.unread { … }`.
    public var unread: AsyncStream<BusymateUnread> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(currentUnread)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    /// The same values for Combine (the current one first, on the main thread).
    public var unreadPublisher: AnyPublisher<BusymateUnread, Never> {
        $currentUnread.removeDuplicates().eraseToAnyPublisher()
    }

    // MARK: Actions

    /// Ask the server what is unread (needs the stored visitor token; does nothing without one).
    /// Runs by itself on `configure` and on every return to the foreground.
    public func refreshUnread() {
        guard refreshTask == nil, let configuration,
              let token = store.token(for: configuration.assistant),
              let request = BusymateUnreadRequest.make(origin: apiOrigin, assistant: configuration.assistant,
                                                       token: token, sdkVersion: BusymateLaunch.sdkVersion) else { return }
        let assistant = configuration.assistant
        let session = self.session
        refreshTask = Task { [weak self] in
            let result = try? await session.data(for: request)
            guard let self else { return }
            self.refreshTask = nil
            guard let (data, response) = result, let http = response as? HTTPURLResponse,
                  self.configuration?.assistant == assistant,
                  let answer = BusymateUnreadRequest.answer(status: http.statusCode, data: data) else { return }
            self.apply(answer)
        }
    }

    /// `Busymate.refreshUnread()`: the same as `Busymate.shared.refreshUnread()`.
    public static func refreshUnread() { shared.refreshUnread() }

    /// The launcher or the bubble was tapped (call it from your own launcher UI too): asks your app to
    /// present the chat (`onOpenChat`, delegate) and tells the chat page to show the conversation.
    public func openChat() {
        if state.teaser != nil {
            // The bubble has done its job; the badge stays until the chat reports the message seen.
            state.dismissTeaser()
            persistDismissed()
            teaser = nil
        }
        pendingOpen = true
        onOpenChat?()
        delegate?.busymateDidRequestChat()
        flushOpen()
    }

    /// Tell the SDK the chat screen was closed: it asks the server again, so the badge is right.
    public func chatDidClose() {
        pendingOpen = false
        refreshUnread()
    }

    /// Close the follow-up bubble. The message stays unread: the badge keeps its count, and the
    /// bubble returns only for a newer message.
    public func dismissTeaser() {
        state.dismissTeaser()
        persistDismissed()
        teaser = state.teaser
    }

    /// Forget this person (your sign-out): deletes the visitor token and clears the badge.
    public func reset() {
        if let configuration { store.delete(for: configuration.assistant) }
        refreshTask?.cancel()
        refreshTask = nil
        apply(.none)
    }

    // MARK: The channel

    fileprivate func receive(_ message: WKScriptMessage) {
        let security = message.frameInfo.securityOrigin
        guard let configuration,
              let origin = BusymateOrigins.origin(scheme: security.protocol, host: security.host, port: security.port),
              allowedOrigins.contains(origin),
              let parsed = BusymateChatMessage.parse(message.body) else { return }
        if message.webView === webView {
            lastFrame = message.frameInfo
            pageIsListening = true
        }
        switch parsed {
        case .identity(let token):
            if store.token(for: configuration.assistant) != token { store.save(token, for: configuration.assistant) }
        case .unread(let value):
            apply(value)
        }
        flushOpen()
    }

    /// Send `support.chat.v1.open` once the chat document can hear it.
    private func flushOpen() {
        guard pendingOpen, pageIsListening, let webView, !webView.isLoading,
              let url = webView.url, let origin = BusymateOrigins.origin(of: url) else { return }
        if let frame = lastFrame {
            pendingOpen = false
            webView.evaluateJavaScript(BusymateChatMessage.openScript, in: frame, in: .page, completionHandler: nil)
        } else if allowedOrigins.contains(origin) {
            pendingOpen = false
            webView.evaluateJavaScript(BusymateChatMessage.openScript, in: nil, in: .page, completionHandler: nil)
        }
    }

    private func apply(_ value: BusymateUnread) {
        guard state.apply(value) else { return }
        persistDismissed()
        publish(force: false)
    }

    private func publish(force: Bool) {
        let value = state.unread
        if teaser != state.teaser { teaser = state.teaser }
        guard force || value != currentUnread else { return }
        currentUnread = value
        delegate?.busymateDidUpdateUnread(value)
        for continuation in continuations.values { continuation.yield(value) }
    }

    private var dismissedDefaultsKey: String { "ai.busymate.sdk.teaser.dismissed." + (configuration?.assistant ?? "") }

    private func persistDismissed() {
        guard configuration != nil else { return }
        if let key = state.dismissedKey { defaults.set(key, forKey: dismissedDefaultsKey) } else { defaults.removeObject(forKey: dismissedDefaultsKey) }
    }
}

/// Holds `Busymate` weakly so the content controller never keeps it (or a web view) alive.
@available(iOS 15.0, *)
@MainActor
private final class BusymateWeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var owner: Busymate?
    init(_ owner: Busymate) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

/// The visitor token goes only to the origin it was asked of: a redirect is refused.
private final class BusymateNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
