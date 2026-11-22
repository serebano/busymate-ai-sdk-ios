import Foundation

/// Busymate AI launch parameters (launch 1.0.0).
///
/// Tells the hosted chat which SDK release, in which app, is showing it, so
/// the workspace's Insights can answer "which SDK version, in which app".
/// Build the address you load with `BusymateLaunch.chatURL(_:)`:
///
///     webView.load(URLRequest(url: BusymateLaunch.chatURL(chatURL)))
///
/// It appends `sdkVersion=<this SDK's version>` and, when it is a plain
/// identifier, `hostAppId=<your bundle id>`. Nothing else: no request, no
/// permission, no stored id (a version and an app id are not personal data).
/// Your own query items (for example `channel=ios`) are kept as they are.
public enum BusymateLaunch {
    /// The SDK release (`release-manifest.json` `version`; `scripts/verify-release.py` refuses a mismatch).
    public static let sdkVersion = "1.0.5"

    /// Digits, letters, `.`, `+`, `-`, at most 32 characters.
    public static func isValidSDKVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z.+-]{1,32}$"#, options: .regularExpression) != nil
    }

    /// `^[A-Za-z][A-Za-z0-9._-]{1,127}$`: a bundle identifier; anything else is left out.
    public static func isValidHostAppID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z][A-Za-z0-9._-]{1,127}$"#, options: .regularExpression) != nil
    }

    /// `base` with the launch parameters appended (an earlier `sdkVersion` / `hostAppId` is replaced).
    public static func chatURL(_ base: URL, hostAppId: String? = Bundle.main.bundleIdentifier) -> URL {
        launchURL(base, sdkVersion: sdkVersion, hostAppId: hostAppId)
    }

    static func launchURL(_ base: URL, sdkVersion: String, hostAppId: String?) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        var items = (components.percentEncodedQueryItems ?? []).filter { $0.name != "sdkVersion" && $0.name != "hostAppId" }
        func encoded(_ value: String) -> String { value.replacingOccurrences(of: "+", with: "%2B") }
        if isValidSDKVersion(sdkVersion) { items.append(URLQueryItem(name: "sdkVersion", value: encoded(sdkVersion))) }
        if let hostAppId, isValidHostAppID(hostAppId) { items.append(URLQueryItem(name: "hostAppId", value: encoded(hostAppId))) }
        components.percentEncodedQueryItems = items.isEmpty ? nil : items
        return components.url ?? base
    }
}
