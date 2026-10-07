import Foundation

struct DemoConfiguration {
    var assistant = "busyproxy"
    var chatURL = "https://busymate.ai/support/busyproxy?channel=ios"
    var origins = "https://busymate.ai"
    var signedIn = false
    var accountID = ""
    var mintURL = ""
    // Existing tenant backend session credential, memory only; never a signing/admin key.
    var backendSessionToken = ""
    var microphoneEnabled = true
    var handleCloseAction = false
    var closeCallbackEnabled = true
    var authenticationOpen = false
    var callbackScheme = "bmaisdkdemo"

    struct Validated {
        let assistant: String
        let chatURL: URL
        let origins: [String]
        let backendURL: URL?
        let callbackScheme: String?
    }
    enum Invalid: LocalizedError {
        case assistant, chatURL, origin, missingOrigin, backend, account, callback
        var errorDescription: String? {
            switch self {
            case .assistant: return "Use a valid assistant slug."
            case .chatURL: return "Chat URL must use HTTPS with no embedded credentials."
            case .origin: return "Origins must be exact HTTPS origins, without paths or wildcards."
            case .missingOrigin: return "Include the actual chat origin in the allowed origins."
            case .backend: return "Identified mode requires your authenticated HTTPS mint endpoint."
            case .account: return "Identified mode requires your actual signed-in account ID. This is not a login."
            case .callback: return "This demo registers only the bmaisdkdemo callback scheme."
            }
        }
    }
    static func secureURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func origin(_ url: URL) -> String {
        let port = url.port == nil || url.port == 443 ? "" : ":\(url.port!)"
        return "https://\(url.host!.lowercased())\(port)"
    }
    func validated() throws -> Validated {
        guard assistant.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil else { throw Invalid.assistant }
        guard let url = Self.secureURL(chatURL), url.fragment == nil else { throw Invalid.chatURL }
        let list = origins.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        var normalized: [String] = []
        for raw in list {
            guard !raw.contains("*"), let candidate = Self.secureURL(raw), candidate.path.isEmpty,
                  candidate.query == nil, candidate.fragment == nil else { throw Invalid.origin }
            let value = Self.origin(candidate)
            if !normalized.contains(value) { normalized.append(value) }
        }
        guard normalized.contains(Self.origin(url)) else { throw Invalid.missingOrigin }
        let backend = mintURL.isEmpty ? nil : Self.secureURL(mintURL)
        if signedIn {
            guard !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Invalid.account }
            guard backend != nil else { throw Invalid.backend }
        } else if !mintURL.isEmpty && backend == nil { throw Invalid.backend }
        if authenticationOpen && callbackScheme != "bmaisdkdemo" { throw Invalid.callback }
        return Validated(assistant: assistant, chatURL: url, origins: normalized,
                         backendURL: backend, callbackScheme: authenticationOpen ? callbackScheme : nil)
    }
}

struct DemoMintPayload {
    let nonce: String
    let audience: String?
    let reason: String?
    let assistant: String
    let origin: String
    var body: [String: Any] {
        var value: [String: Any] = ["nonce": nonce, "assistant": assistant, "origin": origin]
        if let audience { value["aud"] = audience }
        if let reason { value["reason"] = reason }
        return value
    }
    func request(to url: URL, sessionToken: String = "") throws -> URLRequest {
        guard DemoConfiguration.secureURL(url.absoluteString) != nil else { throw DemoConfiguration.Invalid.backend }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if !sessionToken.isEmpty {
            guard !sessionToken.utf8.contains(where: { $0 == 10 || $0 == 13 }) else { throw DemoConfiguration.Invalid.backend }
            request.setValue("Bearer " + sessionToken, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 12
        return request
    }
    func decode(_ data: Data, status: Int) throws -> (token: String, nonce: String)? {
        if status == 401 || status == 403 { return nil }
        guard (200..<300).contains(status),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty,
              let replyNonce = json["nonce"] as? String, replyNonce == nonce else { throw DemoConfiguration.Invalid.backend }
        return (token, replyNonce)
    }
}

// This is the actual callback factory used by the demo, not an SDK setting.
enum DemoCallbacks {
    static func action(enabled: Bool, close: @escaping () -> Void, ready: @escaping () -> Void) -> ((String, [String: Any]) -> Bool)? {
        guard enabled else { return nil }
        return { name, _ in
            if name == "close" { close(); return true }
            if name == "ready" { ready() }
            return false
        }
    }
    static func close(enabled: Bool, perform: @escaping () -> Void) -> (() -> Void)? {
        enabled ? perform : nil
    }
}

final class NoMintRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
