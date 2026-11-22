// swift-tools-version: 5.9
import PackageDescription
// Host-side tests compile the same validator, callback factory and mint mapping
// used by the iOS app; BusymateLaunch is the SDK file itself (symlink). The actual app/SDK is built by the Xcode project.
let package = Package(
    name: "BusymateExampleConfigurationChecks",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DemoConfiguration", path: "Sources",
                exclude: ["DemoApp.swift", "DemoSession.swift"], sources: ["DemoConfiguration.swift"]),
        .target(name: "BusymateLaunch", path: "LaunchChecks"),
        .testTarget(name: "BusymateLaunchTests", dependencies: ["BusymateLaunch"], path: "LaunchTests"),
        .testTarget(name: "DemoConfigurationTests", dependencies: ["DemoConfiguration"], path: "Tests", exclude: ["redirect-fixture.py"])
    ],
    swiftLanguageVersions: [.v5]
)
