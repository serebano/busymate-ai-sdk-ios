// Busymate AI — kit v2 native bridge for iOS (`busymate.bridge/2`, build 2.0.0).
//
// FROZEN. This file is a pipe, not a policy: it moves one JSON envelope between
// the Busymate chat (served from busymate.ai) and five fixed operations of YOUR
// app. Every message name, timeout, retry, fallback and decision lives in the
// chat, which Busymate updates on its side — so a fix never needs a new build
// of your app. Do not edit it; a new version is a new immutable URL
// (https://busymate.ai/sdk/v2/<version>/), announced in advance.
//
// Contract: https://busymate.ai/sdk/v2/2.0.0/CONTRACT.md
//
// Requires iOS 14+. Store policy: no new permissions, no downloaded native code,
// and the page reaches only your own mint, an https open and close — never a
// general native API (App Review 2.5.2, 4.7.2; DPLA 3.3.1(B)).
//
// Who may ask: EXACTLY https://<assistant>.busymate.ai plus the exact https
// origins you list (your mapped support host). No wildcards: another tenant's
// chat, or any other busymate.ai page, is refused and never reaches your mint.
//
// Use (before the first load):
//
//   BusymateBridge.install(on: webView, config: .init(
//       assistant: "acme",
//       origins: ["https://support.acme.com"],          // your mapped support host, if any
//       account: { Auth.shared.userId },                 // nil = signed out
//       mint: { request in try await Backend.mintBusymate(nonce: request.nonce, aud: request.aud) }))
//   // `request.assistant` and `request.origin` are set by this file (never by the
//   // page), so your backend may bind the token to them.
//   // in your WKNavigationDelegate:
//   func webViewWebContentProcessDidTerminate(_ w: WKWebView) { BusymateBridge.contentProcessDidTerminate(w) }
//   // optional, only makes sign-in / sign-out show up faster:
//   BusymateBridge.accountChanged()
//
// If your app sets WKAppBoundDomains, list the assistant origins there too.

import AuthenticationServices
import CryptoKit
import UIKit
import WebKit

@available(iOS 14.0, *)
@MainActor
public final class BusymateBridge: NSObject {
    public static let name = "BusymateBridge"
    public static let version = 2
    public static let build = "2.0.0"
    private static let maxEnvelope = 64 * 1024
    private static let mintCeiling: UInt64 = 15_000_000_000

    /// The exact origins allowed to ask: the assistant's own busymate.ai host + your exact https origins.
    public static func allowedOrigins(_ config: Config) -> [String] {
        var out: [String] = []
        if config.assistant.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil {
            out.append("https://\(config.assistant).busymate.ai")
        }
        for origin in config.origins {
            if let value = normalizedOrigin(origin), !out.contains(value) { out.append(value) }
        }
        return out
    }

    /// "https://host[:port]", lower-case, default port dropped; nil for anything else (wildcards included).
    static func normalizedOrigin(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(":443") { value.removeLast(4) }
        let exact = #"^https://[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?(?::[0-9]{1,5})?$"#
        return value.range(of: exact, options: .regularExpression) != nil ? value : nil
    }

    /// What the chat passes to your mint. Unknown future fields are in `raw`.
    /// `assistant` and `origin` are set by this file, never by the page.
    public struct MintRequest {
        public let nonce: String
        public let aud: String?
        public let reason: String?
        public let assistant: String
        public let origin: String
        public let raw: [String: Any]
    }

    /// What your mint returns. Return nil (or throw `MintError.notSignedIn`) when nobody is signed in.
    public struct MintToken {
        public let token: String
        public let nonce: String
        public init(token: String, nonce: String) { self.token = token; self.nonce = nonce }
    }

    public enum MintError: Error { case notSignedIn, failed }

    public struct Config {
        public let assistant: String
        public let origins: [String]
        public let account: () -> String?
        public let mint: @MainActor (MintRequest) async throws -> MintToken?
        public let onAction: ((String, [String: Any]) -> Bool)?
        public let onClose: (() -> Void)?
        /// Set when your sign-in page returns to the app through a custom scheme (RFC 8252).
        public let authCallbackScheme: String?

        public init(
            assistant: String,
            origins: [String] = [],
            account: @escaping () -> String?,
            mint: @escaping @MainActor (MintRequest) async throws -> MintToken?,
            onAction: ((String, [String: Any]) -> Bool)? = nil,
            onClose: (() -> Void)? = nil,
            authCallbackScheme: String? = nil
        ) {
            self.assistant = assistant
            self.origins = origins
            self.account = account
            self.mint = mint
            self.onAction = onAction
            self.onClose = onClose
            self.authCallbackScheme = authCallbackScheme
        }
    }

    private let config: Config
    private let origins: [String]
    private weak var webView: WKWebView?
    private var helloFrame: WKFrameInfo?
    private var pendingRestored = false
    private var authSession: ASWebAuthenticationSession?
    private var observer: NSObjectProtocol?

    private static var installed: [ObjectIdentifier: BusymateBridge] = [:]

    private init(webView: WKWebView, config: Config) {
        self.config = config
        self.origins = Self.allowedOrigins(config)
        self.webView = webView
        super.init()
    }

    /// Install on a WKWebView BEFORE its first load.
    @discardableResult
    public static func install(on webView: WKWebView, config: Config) -> BusymateBridge {
        let bridge = BusymateBridge(webView: webView, config: config)
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: name, contentWorld: .page)
        controller.addScriptMessageHandler(WeakHandler(bridge), contentWorld: .page, name: name)
        bridge.observer = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak bridge] _ in Task { @MainActor in bridge?.emit("resume", [:]) } }
        installed[ObjectIdentifier(webView)] = bridge
        return bridge
    }

    /// Call from `webViewWebContentProcessDidTerminate`: reloads, and the chat restores itself.
    public static func contentProcessDidTerminate(_ webView: WKWebView) {
        installed[ObjectIdentifier(webView)]?.pendingRestored = true
        webView.reload()
    }

    /// Optional: tell the chat the signed-in account changed (sign-in, sign-out, switch).
    public static func accountChanged() {
        for bridge in installed.values { bridge.emit("state", bridge.state()) }
    }


    // MARK: the pipe

    fileprivate func receive(_ message: WKScriptMessage, reply: @escaping @MainActor (Any?, String?) -> Void) {
        let raw: String?
        if let text = message.body as? String { raw = text }
        else if JSONSerialization.isValidJSONObject(message.body),
                let data = try? JSONSerialization.data(withJSONObject: message.body) { raw = String(data: data, encoding: .utf8) }
        else { raw = nil }
        guard let text = raw, text.utf8.count <= Self.maxEnvelope,
              let data = text.data(using: .utf8),
              let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (envelope["bm"] as? Int) == Self.version,
              let id = envelope["id"] else { reply(nil, nil); return }
        let respond: ([String: Any]) -> Void = { body in
            var out = body
            out["bm"] = Self.version
            out["id"] = id
            reply(Self.json(out), nil)
        }
        guard let origin = Self.origin(of: message.frameInfo.securityOrigin), origins.contains(origin) else {
            respond(["ok": false, "e": "denied"]); return
        }
        let p = envelope["p"] as? [String: Any] ?? [:]
        switch envelope["op"] as? String {
        case "hello":
            helloFrame = message.frameInfo
            respond(["ok": true, "r": hello(origin)])
            if pendingRestored { pendingRestored = false; emit("restored", [:]) }
        case "state":
            respond(["ok": true, "r": state()])
        case "mint":
            mint(p, origin, respond)
        case "open":
            respond(open(p))
        case "action":
            respond(action(p))
        default:
            respond(["ok": false, "e": "unsupported"])
        }
    }

    private func mint(_ p: [String: Any], _ origin: String, _ respond: @escaping ([String: Any]) -> Void) {
        guard config.account() != nil else { respond(["ok": false, "e": "not_signed_in"]); return }
        // Who asked is stated by this file, never by the page.
        var raw = p
        raw["assistant"] = config.assistant
        raw["origin"] = origin
        let request = MintRequest(
            nonce: p["nonce"] as? String ?? "",
            aud: p["aud"] as? String,
            reason: p["reason"] as? String,
            assistant: config.assistant,
            origin: origin,
            raw: raw
        )
        let mint = config.mint
        Task { @MainActor in
            var done = false
            let finish: ([String: Any]) -> Void = { body in if !done { done = true; respond(body) } }
            // The ceiling only reclaims the callback; the chat owns every real budget.
            let ceiling = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.mintCeiling)
                finish(["ok": false, "e": "timeout"])
            }
            do {
                if let token = try await mint(request) {
                    finish(["ok": true, "r": ["token": token.token, "nonce": token.nonce]])
                } else {
                    finish(["ok": false, "e": "not_signed_in"])
                }
            } catch MintError.notSignedIn {
                finish(["ok": false, "e": "not_signed_in"])
            } catch {
                finish(["ok": false, "e": "mint_failed"])
            }
            ceiling.cancel()
        }
    }

    private func open(_ p: [String: Any]) -> [String: Any] {
        guard let text = p["url"] as? String, let url = URL(string: text),
              url.scheme == "https", url.host?.isEmpty == false else {
            return ["ok": false, "e": "bad_request"]
        }
        if (p["mode"] as? String) == "auth", let scheme = config.authCallbackScheme {
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, _ in
                self?.authSession = nil
                if let callback = callback { self?.emit("auth", ["url": callback.absoluteString]) }
            }
            session.presentationContextProvider = self
            authSession = session
            return ["ok": true, "r": ["opened": session.start()]]
        }
        UIApplication.shared.open(url)
        return ["ok": true, "r": ["opened": true]]
    }

    private func action(_ p: [String: Any]) -> [String: Any] {
        guard let name = p["name"] as? String, !name.isEmpty, name.count <= 64 else {
            return ["ok": false, "e": "bad_request"]
        }
        let params = p["params"] as? [String: Any] ?? [:]
        var handled = config.onAction?(name, params) ?? false
        if !handled && name == "close", let onClose = config.onClose {
            onClose()
            handled = true
        }
        return ["ok": true, "r": ["handled": handled]]
    }

    private func hello(_ origin: String) -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "bridge": "busymate", "v": Self.version, "build": Self.build,
            "platform": "ios", "transport": "reply",
            "assistant": config.assistant, "origin": origin, "origins": origins,
            "caps": ["hello", "state", "mint", "open", "action", "ev:resume", "ev:state", "ev:restored", "ev:auth"],
            "webview": "iOS " + UIDevice.current.systemVersion,
            "app": [
                "id": Bundle.main.bundleIdentifier ?? NSNull(),
                "version": info["CFBundleShortVersionString"] ?? NSNull(),
                "build": info["CFBundleVersion"] ?? NSNull(),
            ],
        ]
    }

    private func state() -> [String: Any] {
        guard let account = config.account() else { return ["signedIn": false, "account": NSNull()] }
        return ["signedIn": true, "account": Self.accountKey(Bundle.main.bundleIdentifier ?? "", account)]
    }

    /// SHA-256(appId + ":" + account), first 128 bits, hex. The raw id never crosses.
    private static func accountKey(_ appId: String, _ account: String) -> String {
        let digest = SHA256.hash(data: Data("\(appId):\(account)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func emit(_ ev: String, _ r: [String: Any]) {
        guard let webView = webView, let body = Self.json(["bm": Self.version, "ev": ev, "r": r]) else { return }
        webView.callAsyncJavaScript(
            "window.dispatchEvent(new CustomEvent('busymate-bridge', { detail: e }))",
            arguments: ["e": body], in: helloFrame, in: .page, completionHandler: nil
        )
    }

    /// The FRAME's own origin; nil for a non-https or opaque (sandboxed) frame.
    private static func origin(of origin: WKSecurityOrigin) -> String? {
        guard origin.protocol == "https", !origin.host.isEmpty else { return nil }
        let port = origin.port == 0 || origin.port == 443 ? "" : ":\(origin.port)"
        return normalizedOrigin("https://\(origin.host)\(port)")
    }

    private static func json(_ value: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@available(iOS 14.0, *)
extension BusymateBridge: ASWebAuthenticationPresentationContextProviding {
    nonisolated public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { webView?.window ?? ASPresentationAnchor() }
    }
}

/// Holds the bridge weakly so the content controller never keeps a web view alive.
@available(iOS 14.0, *)
@MainActor
private final class WeakHandler: NSObject, WKScriptMessageHandlerWithReply {
    private weak var bridge: BusymateBridge?
    init(_ bridge: BusymateBridge) { self.bridge = bridge }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) {
        guard let bridge = bridge else { replyHandler(nil, "gone"); return }
        bridge.receive(message, reply: replyHandler)
    }
}
