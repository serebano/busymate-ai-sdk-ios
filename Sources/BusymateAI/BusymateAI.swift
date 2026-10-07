import Foundation
import UIKit
import WebKit

public struct BusymateAIIdentity: Sendable {
    public let token: String
    public let nonce: String

    public init(token: String, nonce: String) {
        self.token = token
        self.nonce = nonce
    }
}

public protocol BusymateAIIdentityProvider: Sendable {
    /// Mint on the customer's authenticated backend. Never store a signing key in the app.
    ///
    /// CALLED ONCE PER ASK. A launch assertion is SINGLE-USE, so this must make
    /// a real round trip every time and must NEVER return a cached pair: a
    /// replayed token is refused, and the visitor lands anonymous with nothing
    /// in the app reporting a failure.
    func mintBusymateAIIdentity() async throws -> BusymateAIIdentity?
}

@MainActor
public final class BusymateAIWebViewBridge: NSObject, WKScriptMessageHandler {
    /// Primary handler for every Busymate AI use case.
    public static let handlerName = "BusymateAI"
    /// Compatibility handler for apps shipped before the generic API name.
    public static let supportHandlerName = "SupportChat"

    private weak var webView: WKWebView?
    private let identityProvider: any BusymateAIIdentityProvider
    private let openExternal: @MainActor (URL) -> Void
    /// audit docs-and-developer-path-07 (2026-09-18): the frame's own ✕ posts
    /// `busymate.ai.v1.close` — the web widget's own listener already reacts
    /// to it (widget-page-api.md "Chat to page"); the native bridge silently
    /// dropped it in the `default: return` arm, so a host app embedding the
    /// hosted page full-screen (mobile-in-app-support.md) had no signal to
    /// dismiss its own presentation.
    private let onClose: (@MainActor () -> Void)?
    /// #3540 — THE ORIGIN ALLOW-LIST. A message handler is reachable by every
    /// document the WKWebView loads, including one a redirect navigated to. An
    /// empty set keeps the historical behaviour (answer whatever is loaded) so
    /// nothing already shipped changes; a non-empty set refuses to mint for any
    /// other origin. Pass your assistant's origin.
    private let allowedOrigins: Set<String>

    public init(
        webView: WKWebView,
        identityProvider: any BusymateAIIdentityProvider,
        openExternal: @escaping @MainActor (URL) -> Void = { UIApplication.shared.open($0) },
        onClose: (@MainActor () -> Void)? = nil,
        allowedOrigins: Set<String> = []
    ) {
        self.webView = webView
        self.identityProvider = identityProvider
        self.openExternal = openExternal
        self.onClose = onClose
        self.allowedOrigins = allowedOrigins
        super.init()
        // Register BEFORE `load(_:)`. A handler added afterwards can miss the
        // first ask; the frame does run a bounded late-bridge watch (#3536),
        // but a bridge present from the first byte never needs it.
        webView.configuration.userContentController.add(self, name: Self.handlerName)
        webView.configuration.userContentController.add(self, name: Self.supportHandlerName)
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.supportHandlerName)
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName || message.name == Self.supportHandlerName,
              let payload = message.body as? [String: Any],
              let type = payload["type"] as? String
        else { return }

        switch type {
        case "busymate.ai.v1.identity_request", "support.chat.v1.identity_request":
            let responseType = type == "busymate.ai.v1.identity_request"
                ? "busymate.ai.v1.identity"
                : "support.chat.v1.identity"
            guard originAllowed() else {
                // A refusal the frame can SEE. Silence is indistinguishable
                // from an app with no bridge at all.
                Task { [weak self] in try? await self?.postUnavailable("unsupported") }
                return
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    guard let identity = try await identityProvider.mintBusymateAIIdentity() else {
                        try await postUnavailable("not_signed_in")
                        return
                    }
                    try await post([
                        "type": responseType,
                        "token": identity.token,
                        "nonce": identity.nonce,
                    ])
                } catch {
                    // The frame stays anonymous but KNOWS why: `mint_failed` is
                    // a different story from "this visitor is not signed in",
                    // and an operator reading the Console needs to tell them
                    // apart. The host app still decides how to report it.
                    try? await postUnavailable("mint_failed")
                }
            }
        case "busymate.ai.v1.open_url", "busymate.ai.v1.auth_request",
             "support.chat.v1.open_url", "support.chat.v1.auth_request":
            guard let raw = payload["url"] as? String,
                  let url = URL(string: raw),
                  url.scheme == "https" || url.scheme == "http"
            else { return }
            openExternal(url)
        case "busymate.ai.v1.close", "support.chat.v1.close":
            onClose?()
        default:
            return
        }
    }

    private func originAllowed() -> Bool {
        if allowedOrigins.isEmpty { return true }
        guard let url = webView?.url,
              let scheme = url.scheme,
              let host = url.host
        else { return false }
        let origin = url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
        return allowedOrigins.contains(origin)
    }

    /// Call this the moment your user signs in, signs out, or switches account.
    ///
    /// #3536: the frame itself now installs `window.BusymateAI`, so this reaches
    /// a real implementation whether the WKWebView loads the hosted experience
    /// DIRECTLY (the usual shape for an in-app assistant) or a page of yours
    /// that embeds the widget through `embed/v1.js`. Nothing in this file
    /// changed and nothing in your app has to: it used to be a silent no-op on
    /// the direct-load shape, and it is not any more. The chat upgrades in
    /// place — same conversation, no reload.
    public func refreshIdentity() async throws {
        _ = try await webView?.callAsyncJavaScript(
            "return await window.BusymateAI?.refreshIdentity?.()",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    /// #3540 — the LOGIN / TOKEN-ROTATION / ACCOUNT-SWITCH signal, by the name
    /// the contract uses. It deliberately does NOT push a token: it makes the
    /// frame ASK, and the ask is answered by `mintBusymateAIIdentity()` with a
    /// fresh pair. One question, one mint — pushing an identity here as well
    /// would burn a single-use assertion nobody spent.
    public func identityChanged() async throws {
        try await refreshIdentity()
    }

    /// #3540/#3538 — YOUR USER SIGNED OUT. Sends `busymate.identity.v1.revoked`,
    /// which drops the verified identity, ends the session server-side and
    /// clears the previous person's transcript before the next one can read it.
    /// Without this call a signed-out customer keeps a verified chat until the
    /// web view is torn down — a privacy defect, not a UX one.
    ///
    /// `reason` is one of `signed_out` (default), `switched`, `expired`.
    ///
    /// #3542 — it calls `window.BusymateAI.signedOut()` and falls back to the
    /// window post. A bare post reaches the frame only when the web view loads
    /// the assistant DIRECTLY; on the far more common tenant shape — a page of
    /// yours mounting the widget through `embed/v1.js` — the listener lives
    /// inside the iframe and the loader forwards nothing it did not send
    /// itself, so the revocation arrived nowhere while this call reported
    /// success. The façade exists on both shapes (the loader installs it on
    /// the host page; since #3536 the frame installs it on a direct load).
    public func signedOut(reason: String = "signed_out") async throws {
        _ = try await webView?.callAsyncJavaScript(
            """
            const api = window.BusymateAI || window.SupportChat;
            if (api && typeof api.signedOut === "function") { api.signedOut(message.reason); return true; }
            window.postMessage(message, '*');
            return false;
            """,
            arguments: ["message": ["type": "busymate.identity.v1.revoked", "reason": reason]],
            in: nil,
            contentWorld: .page
        )
    }

    /// #3540 — call from `viewWillAppear` / `scenePhase == .active`. The frame
    /// already re-asks on `visibilitychange`/`pageshow`, so this is
    /// belt-and-braces for the shells where a web view is restored without
    /// firing either; an unchanged answer is a no-op at the frame's listener,
    /// so it is safe on every resume.
    public func onResume() async throws {
        try await refreshIdentity()
    }

    private func postUnavailable(_ reason: String) async throws {
        try await post(["type": "busymate.identity.v1.unavailable", "reason": reason])
    }

    private func post(_ payload: [String: String]) async throws {
        _ = try await webView?.callAsyncJavaScript(
            "window.postMessage(message, '*')",
            arguments: ["message": payload],
            in: nil,
            contentWorld: .page
        )
    }
}
