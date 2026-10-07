import AVFoundation
import BusymateAI
import SwiftUI
import WebKit

@MainActor
final class DemoSession: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    @Published var configuration = DemoConfiguration()
    @Published var selectedTab = 0
    @Published var events: [String] = []
    @Published var status = "Ready — guest chat"
    @Published var validationError: String?
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private var applied = DemoConfiguration()
    private var microphone: BusymateMicrophone?
    private var installed = false

    override init() {
        super.init()
        webView.uiDelegate = self
        webView.navigationDelegate = self
        let controller = webView.configuration.userContentController
        controller.add(self, name: "DemoEvents")
        controller.addUserScript(WKUserScript(source: """
            window.addEventListener('busymate-bridge', function(event) {
              try {
                const value = typeof event.detail === 'string' ? JSON.parse(event.detail) : event.detail;
                if (['resume','state','restored','auth'].includes(value.ev)) {
                  window.webkit.messageHandlers.DemoEvents.postMessage(value.ev);
                }
              } catch (_) {}
            });
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }
    func startIfNeeded() { if !installed { apply() } }
    func log(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        events.insert("\(time) · \(message)", at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
    }
    func apply() {
        do {
            let valid = try configuration.validated()
            applied = configuration
            validationError = nil
            webView.stopLoading()
            // Reuse the WebView: frozen v2 has no public uninstall API.
            let controller = webView.configuration.userContentController
            controller.removeScriptMessageHandler(forName: "BusymateMicrophone", contentWorld: .page)
            microphone = nil
            BusymateBridge.install(on: webView, config: .init(
                assistant: valid.assistant, origins: valid.origins,
                account: { [weak self] in
                    guard let self, self.applied.signedIn else { return nil }
                    return self.applied.accountID
                },
                mint: { [weak self] request in
                    guard let self else { return nil }
                    return try await self.mint(request)
                },
                onAction: DemoCallbacks.action(enabled: applied.handleCloseAction,
                    close: { [weak self] in self?.log("SDK action: close handled by onAction"); self?.closeChat() },
                    ready: { [weak self] in self?.log("SDK action: ready") }),
                onClose: validCloseCallback(), authCallbackScheme: valid.callbackScheme))
            if applied.microphoneEnabled {
                microphone = BusymateMicrophone(webView: webView, origins: Set(valid.origins))
            }
            installed = true
            status = applied.signedIn ? "Identified mode requires authenticated backend" : "Guest chat"
            log("Installed identity v2; native microphone \(applied.microphoneEnabled ? "enabled" : "disabled")")
            webView.load(URLRequest(url: valid.chatURL))
            selectedTab = 0
        } catch {
            validationError = error.localizedDescription
            log("Configuration rejected")
        }
    }
    private func validCloseCallback() -> (() -> Void)? {
        DemoCallbacks.close(enabled: applied.closeCallbackEnabled) { [weak self] in
            self?.log("SDK close fallback"); self?.closeChat()
        }
    }
    private func closeChat() {
        // Navigating away destroys the chat document and its media tracks.
        webView.loadHTMLString("<html><body>Chat closed. Reload to reopen.</body></html>", baseURL: nil)
        selectedTab = 1
        status = "Chat closed"
    }
    private func mint(_ request: BusymateBridge.MintRequest) async throws -> BusymateBridge.MintToken? {
        guard applied.signedIn else { log("Mint: signed out, no backend request"); return nil }
        guard let url = try applied.validated().backendURL else { throw DemoConfiguration.Invalid.backend }
        let payload = DemoMintPayload(nonce: request.nonce, audience: request.aud,
                                      reason: request.reason, assistant: request.assistant, origin: request.origin)
        log("Mint: authenticated backend requested")
        // Use existing app session cookies or an in-memory tenant backend session token.
        // Reject all redirects so authentication never travels to another endpoint.
        do {
            let (data, response) = try await URLSession.shared.data(for: payload.request(to: url, sessionToken: applied.backendSessionToken), delegate: NoMintRedirects())
            guard let http = response as? HTTPURLResponse else { throw DemoConfiguration.Invalid.backend }
            guard let identity = try payload.decode(data, status: http.statusCode) else {
                log("Mint: backend reports not signed in"); return nil
            }
            log("Mint: fresh correlated assertion received")
            return .init(token: identity.token, nonce: identity.nonce)
        } catch { log("Mint: backend request failed; guest fallback"); throw error }
    }
    func accountChanged() {
        do {
            _ = try configuration.validated()
            applied.signedIn = configuration.signedIn
            applied.accountID = configuration.accountID
            applied.mintURL = configuration.mintURL
            applied.backendSessionToken = configuration.backendSessionToken
            BusymateBridge.accountChanged()
            log("accountChanged() forwarded; no identity fabricated")
        } catch { validationError = error.localizedDescription }
    }
    func reset() { configuration = DemoConfiguration(); apply(); log("Demo settings reset to guest defaults") }
    func reload() { apply(); log("Chat reloaded") }
    func testRestoreForwarding() {
        BusymateBridge.contentProcessDidTerminate(webView)
        log("Renderer recovery forwarding invoked manually (no crash simulated)")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        BusymateBridge.contentProcessDidTerminate(webView)
        log("Actual renderer termination forwarded to SDK")
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let decision = microphone?.allowMedia(origin: origin, type: type) ?? .deny
        log("WebView media decision: \(decision == .grant ? "grant" : "deny")")
        decisionHandler(decision)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { log("Chat document loaded") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        status = "Chat unavailable — verify network and configured URL"; log("Navigation failed")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about" { decisionHandler(.allow); return }
        guard let valid = try? applied.validated(), let secure = DemoConfiguration.secureURL(url.absoluteString),
              valid.origins.contains(DemoConfiguration.origin(secure)) else {
            log("Navigation refused: outside configured HTTPS origins")
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let event = message.body as? String, ["resume", "state", "restored", "auth"].contains(event),
              let url = message.frameInfo.request.url, let valid = try? applied.validated(),
              DemoConfiguration.secureURL(url.absoluteString) != nil,
              valid.origins.contains(DemoConfiguration.origin(url)) else { return }
        log("SDK event: \(event) (payload omitted)")
    }
}
