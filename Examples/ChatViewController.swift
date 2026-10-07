import UIKit
import WebKit
import BusymateAI

@MainActor
final class ChatViewController: UIViewController, WKUIDelegate, WKNavigationDelegate {
    private let assistant: String
    private let chatURL: URL
    private let account: () -> String?
    private let mint: @MainActor (BusymateBridge.MintRequest) async throws -> BusymateBridge.MintToken?
    private var webView: WKWebView!
    private var microphone: BusymateMicrophone!

    init(assistant: String, chatURL: URL, account: @escaping () -> String?,
         mint: @escaping @MainActor (BusymateBridge.MintRequest) async throws -> BusymateBridge.MintToken?) {
        self.assistant = assistant; self.chatURL = chatURL
        self.account = account; self.mint = mint
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use dependency-injected initializer") }
    override func loadView() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view = webView
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        webView.uiDelegate = self
        webView.navigationDelegate = self
        let origin = "https://" + chatURL.host! + (chatURL.port.map { ":\($0)" } ?? "")
        BusymateBridge.install(on: webView, config: .init(
            assistant: assistant, origins: [origin], account: account, mint: mint,
            onClose: { [weak self] in self?.dismiss(animated: true) }))
        microphone = BusymateMicrophone(webView: webView, origins: [origin])
        webView.load(URLRequest(url: chatURL))
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(microphone.allowMedia(origin: origin, type: type))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        BusymateBridge.contentProcessDidTerminate(webView)
    }
    // Invoke after your own login/logout/account switch succeeds.
    func accountChanged() { BusymateBridge.accountChanged() }
    // Call when the host owns disposal; the WebView must no longer be in use.
    func disposeChat() {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "BusymateMicrophone", contentWorld: .page)
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
    }
}
