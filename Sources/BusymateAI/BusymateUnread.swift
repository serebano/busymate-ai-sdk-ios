import Foundation
import Security

// Busymate AI — unread follow-ups (unread 1.0.0): the pure half.
//
// The chat page tells the app how many messages from the assistant wait unread
// (`support.chat.v1.unread`) and hands it an opaque visitor token
// (`support.chat.v1.identity`). This file holds everything that needs no UI:
// the value the app shows, the checks every page message must pass, the
// Keychain store for the token and the request to `POST /api/chat/unread`.
// Foundation and Security only, so the same bytes are unit-tested on the host.

/// What waits unread for this person in the workspace's chat.
public struct BusymateUnread: Equatable, Sendable {
    /// Unread messages from the assistant (follow-ups included). `0` = nothing unread.
    public let count: Int
    /// The first sentence of the newest unread message (at most 80 characters, links removed). May be empty.
    public let preview: String
    /// When the newest unread message was sent, when known.
    public let at: Date?

    public init(count: Int, preview: String = "", at: Date? = nil) {
        self.count = max(0, count)
        self.preview = count > 0 ? preview : ""
        self.at = count > 0 ? at : nil
    }

    /// Nothing unread.
    public static let none = BusymateUnread(count: 0)

    /// The badge text: the count, `99+` above 99, `nil` when nothing is unread.
    public var badgeText: String? { count <= 0 ? nil : count > 99 ? "99+" : String(count) }
}

/// One checked message from the chat page. Anything else is dropped before it reaches the app.
enum BusymateChatMessage: Equatable {
    case unread(BusymateUnread)
    case identity(token: String)

    static let unreadType = "support.chat.v1.unread"
    static let identityType = "support.chat.v1.identity"
    static let openType = "support.chat.v1.open"
    static let maxBytes = 4096
    static let maxPreview = 80

    /// The script the app runs in the chat frame to ask it to show the conversation. A constant: no host or page text is ever spliced in.
    static let openScript = "window.postMessage({type:\"support.chat.v1.open\"},location.origin);"

    /// A page message body (`postMessage(obj)` arrives as a dictionary; a JSON string of the object is accepted too).
    static func parse(_ body: Any) -> BusymateChatMessage? {
        if let object = body as? [String: Any] {
            // Bound what a page can make the app hold on to: the token (≤ 2048) is the largest legal field.
            guard object.count <= 8 else { return nil }
            return parse(object: object)
        }
        guard let raw = body as? String, raw.utf8.count <= maxBytes, let data = raw.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return parse(object: object)
    }

    static func parse(object: [String: Any]) -> BusymateChatMessage? {
        guard let type = object["type"] as? String else { return nil }
        switch type {
        case unreadType:
            guard let count = integer(object["n"]), count >= 0, count <= 1_000_000 else { return nil }
            var preview = ""
            if let value = object["t"] {
                if let text = value as? String { preview = clean(text) } else if !(value is NSNull) { return nil }
            }
            var at: Date?
            if let value = object["at"], !(value is NSNull) {
                guard let text = value as? String, text.utf8.count <= 40, let date = isoDate(text) else { return nil }
                at = date
            }
            return .unread(BusymateUnread(count: count, preview: preview, at: at))
        case identityType:
            guard let token = object["v"] as? String, isValidToken(token) else { return nil }
            return .identity(token: token)
        default:
            return nil
        }
    }

    /// An opaque visitor token: 16 to 2048 characters of `A-Z a-z 0-9 . _ ~ + / = : -`.
    static func isValidToken(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._~+/=:-]{16,2048}$"#, options: .regularExpression) != nil
    }

    /// An assistant slug, as the server accepts it.
    static func isValidAssistant(_ value: String) -> Bool {
        value.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil
    }

    /// JSON numbers arrive as NSNumber; a Bool is also an NSNumber and is not a count.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded(), abs(double) < 1e15 else { return nil }
        return Int(double)
    }

    /// One line, no control characters, at most 80 characters.
    private static func clean(_ text: String) -> String {
        let flat = String(text.prefix(512).unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? " " : Character(scalar)
        })
        let trimmed = flat.trimmingCharacters(in: .whitespaces)
        return trimmed.count > maxPreview ? String(trimmed.prefix(maxPreview)) : trimmed
    }

    static func isoDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}

/// The exact origins whose frames may talk to the app.
enum BusymateOrigins {
    /// "https://host[:port]", lower-case, default port dropped; nil for anything else (http, wildcards, paths, credentials).
    static func normalized(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(":443") { value.removeLast(4) }
        let exact = #"^https://[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?(?::[0-9]{1,5})?$"#
        return value.range(of: exact, options: .regularExpression) != nil ? value : nil
    }

    /// A frame's origin from its WebKit parts (`WKSecurityOrigin.protocol/host/port`; port 0 = default).
    static func origin(scheme: String, host: String, port: Int) -> String? {
        guard scheme.lowercased() == "https", !host.isEmpty else { return nil }
        return normalized("https://\(host)" + (port == 0 || port == 443 ? "" : ":\(port)"))
    }

    static func origin(of url: URL) -> String? {
        guard url.user == nil, url.password == nil, let scheme = url.scheme, let host = url.host else { return nil }
        return origin(scheme: scheme, host: host, port: url.port ?? 0)
    }

    /// Busymate's chat origins for one assistant, plus the host's own exact origins (a mapped support host).
    static func allowed(assistant: String, chatURL: URL?, extra: [String]) -> Set<String> {
        var out: Set<String> = ["https://busymate.ai"]
        if BusymateChatMessage.isValidAssistant(assistant) { out.insert("https://\(assistant).busymate.ai") }
        for raw in extra { if let value = normalized(raw) { out.insert(value) } }
        if let chatURL, let value = origin(of: chatURL) { out.insert(value) }
        return out
    }
}

/// Where the visitor token lives. The SDK uses the Keychain; tests use memory.
protocol BusymateTokenStoring {
    func token(for assistant: String) -> String?
    @discardableResult func save(_ token: String, for assistant: String) -> Bool
    @discardableResult func delete(for assistant: String) -> Bool
}

/// The visitor token in the Keychain: a generic password per assistant, this device only, never synced, never logged.
struct BusymateKeychainTokenStore: BusymateTokenStoring {
    static let service = "ai.busymate.sdk.visitor"
    let service: String

    init(service: String = BusymateKeychainTokenStore.service) { self.service = service }

    private func query(_ assistant: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: assistant]
    }

    func token(for assistant: String) -> String? {
        guard BusymateChatMessage.isValidAssistant(assistant) else { return nil }
        var query = query(assistant)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let token = String(data: data, encoding: .utf8), BusymateChatMessage.isValidToken(token) else { return nil }
        return token
    }

    @discardableResult
    func save(_ token: String, for assistant: String) -> Bool {
        guard BusymateChatMessage.isValidAssistant(assistant), BusymateChatMessage.isValidToken(token) else { return false }
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false]
        let status = SecItemUpdate(query(assistant) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = query(assistant)
        attributes.forEach { add[$0.key] = $0.value }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func delete(for assistant: String) -> Bool {
        let status = SecItemDelete(query(assistant) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// `POST /api/chat/unread`: the question the app asks while the chat page is not loaded.
enum BusymateUnreadRequest {
    /// The request, or nil when anything is off (no slug, no token, not https). No cookies, no caching.
    static func make(origin: String, assistant: String, token: String, sdkVersion: String) -> URLRequest? {
        guard let base = BusymateOrigins.normalized(origin), BusymateChatMessage.isValidAssistant(assistant),
              BusymateChatMessage.isValidToken(token), let url = URL(string: base + "/api/chat/unread"),
              let body = try? JSONSerialization.data(withJSONObject: ["a": assistant, "v": token]) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue("ios/" + sdkVersion, forHTTPHeaderField: "X-Busymate-SDK")
        request.httpBody = body
        return request
    }

    /// The server's answer: `204` = nothing unread, `200 {"n","t","at"}` = that; anything else = no answer (keep what we know).
    static func answer(status: Int, data: Data) -> BusymateUnread? {
        if status == 204 { return BusymateUnread.none }
        guard status == 200, data.count <= BusymateChatMessage.maxBytes,
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        object["type"] = BusymateChatMessage.unreadType
        guard case .unread(let unread)? = BusymateChatMessage.parse(object: object) else { return nil }
        return unread
    }
}

/// What the launcher shows: the unread value, and whether its teaser bubble is up.
/// Dismissing the bubble leaves the message unread: the badge stays, only the bubble goes,
/// until a newer message arrives.
struct BusymateUnreadState: Equatable {
    private(set) var unread = BusymateUnread.none
    /// The message the person closed the bubble on ("<time>|<preview>"); persisted by the owner of this state.
    private(set) var dismissedKey: String?

    init(dismissedKey: String? = nil) { self.dismissedKey = dismissedKey }

    /// The newest unread message to tease, or nil (nothing unread, or the person dismissed this one).
    var teaser: BusymateUnread? {
        guard unread.count > 0, Self.key(unread) != dismissedKey else { return nil }
        return unread
    }

    /// Take a new value; returns true when it differs from the last one.
    @discardableResult
    mutating func apply(_ value: BusymateUnread) -> Bool {
        // A bare count (no text, no time) for the count we already show adds nothing: keep the preview we have.
        if value.count == unread.count, value.preview.isEmpty, value.at == nil { return false }
        guard value != unread else { return false }
        unread = value
        if value.count == 0 { dismissedKey = nil }
        return true
    }

    /// The person closed the bubble. The count is untouched.
    mutating func dismissTeaser() {
        if unread.count > 0 { dismissedKey = Self.key(unread) }
    }

    /// Identifies one unread message: its time and text. A newer follow-up has another key and teases again.
    static func key(_ unread: BusymateUnread) -> String {
        "\(unread.at.map { String(Int($0.timeIntervalSince1970)) } ?? "-")|\(unread.preview)"
    }
}
