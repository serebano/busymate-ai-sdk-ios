import Foundation
import os

/// Busymate AI attachments check (files check 1.0.0).
///
/// The hosted chat's attach (+) button is a standard `<input type="file">`.
/// WKWebView presents its own menu for it (Photo Library, Take Photo, Choose
/// Files) with no delegate code. Photo Library and Choose Files need nothing
/// from your app. **Take Photo needs `NSCameraUsageDescription` in your app's
/// Info.plist: without it iOS terminates the app the moment the user picks it**
/// (verified on a physical iPhone, 2026-11-19), and WebKit offers no API to
/// hide that choice. `BusymateMicrophone` runs this check when it is
/// installed; call it yourself if you do not use the microphone adapter.
public enum BusymateFiles {
    public static let version = "1.0.0"
    /// Info.plist keys the chat's attachment menu needs.
    public static let requiredUsageDescriptions = ["NSCameraUsageDescription"]

    /// The required keys that are missing or empty in `bundle`.
    public static func missingUsageDescriptions(in bundle: Bundle = .main) -> [String] {
        requiredUsageDescriptions.filter { key in
            let value = bundle.object(forInfoDictionaryKey: key) as? String
            return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
    }

    private static let logged = OSAllocatedFlag()

    /// Logs one fault per process when a key is missing. Returns true when the host is ready.
    @discardableResult
    public static func checkHost(bundle: Bundle = .main) -> Bool {
        let missing = missingUsageDescriptions(in: bundle)
        guard !missing.isEmpty else { return true }
        if logged.setOnce() {
            Logger(subsystem: "ai.busymate.sdk", category: "files").fault(
                "Busymate AI: add \(missing.joined(separator: ", "), privacy: .public) to Info.plist. The chat's attach menu offers Take Photo, and iOS terminates the app when it is chosen without NSCameraUsageDescription.")
        }
        return false
    }
}

/// A process-wide once flag (no Swift 6 global-state warnings, iOS 15+).
private final class OSAllocatedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func setOnce() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
