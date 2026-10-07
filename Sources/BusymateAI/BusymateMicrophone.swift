import AVFoundation
import WebKit

/// Optional add-on to either identity bridge. Install before the first load.
/// Keep this instance alive and route WKUIDelegate media requests to allowMedia.
@available(iOS 15.0, *)
public final class BusymateMicrophone: NSObject, WKScriptMessageHandlerWithReply {
    private let origins: Set<String>
    public init(webView: WKWebView, origins: Set<String>) {
        self.origins = Set(origins.filter { origin in
            guard let url = URL(string: origin), url.scheme == "https",
                  url.host != nil, !origin.contains("*"), url.path.isEmpty,
                  url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { return false }
            return true
        }.map { origin in
            let url = URL(string: origin)!
            let port = url.port == nil || url.port == 443 ? "" : ":\(url.port!)"
            return "https://\(url.host!.lowercased())\(port)"
        })
        super.init()
        webView.configuration.userContentController.addScriptMessageHandler(
            self, contentWorld: .page, name: "BusymateMicrophone")
    }
    private func origin(_ value: WKSecurityOrigin) -> String {
        let port = value.port == 0 || value.port == 443 ? "" : ":\(value.port)"
        return "\(value.protocol)://\(value.host)\(port)"
    }
    public func userContentController(_ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void) {
        guard origins.contains(origin(message.frameInfo.securityOrigin)),
              let raw = message.body as? String, raw.utf8.count <= 4096,
              let data = raw.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              request["type"] as? String == "busymate.microphone.v1.request",
              let id = request["id"] as? String else {
            replyHandler(nil, "Unsupported microphone request"); return
        }
        // AVAudioSession asks iOS for the app's OS permission on first access.
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { replyHandler(["id": id, "granted": granted], nil) }
        }
    }
    /// In your WKUIDelegate requestMediaCapturePermissionFor callback, pass
    /// the requesting origin and type. Camera or other origins fail closed.
    public func allowMedia(origin: WKSecurityOrigin, type: WKMediaCaptureType) -> WKPermissionDecision {
        origins.contains(self.origin(origin)) && type == .microphone &&
            AVAudioSession.sharedInstance().recordPermission == .granted ? .grant : .deny
    }
}
