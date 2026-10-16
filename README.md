# Busymate AI SDK for iOS — 1.0.2

Official independent iOS source package for Busymate AI hosted chat. Install once in your app; hosted chat receives web updates independently.

## Install with Swift Package Manager

In Xcode, File → Add Package Dependencies, use:

`https://github.com/serebano/busymate-ai-sdk-ios.git`

Choose **Exact Version 1.0.2** and add the `BusymateAI` product to your app target. Requires iOS 15+ and Swift tools 5.9+ (Swift 5 language mode). In a package manifest:

```swift
.package(url: "https://github.com/serebano/busymate-ai-sdk-ios.git", exact: "1.0.2")
// In your target's dependencies:
.product(name: "BusymateAI", package: "busymate-ai-sdk-ios")
```

`import BusymateAI`. Use `BusymateBridge` (identity wire v2, immutable build 2.0.0) plus `BusymateMicrophone` (adapter 1.0.0). Existing v1 integrations can retain `BusymateAIWebViewBridge`; do not install both identity handlers on the same chat.

## Integrate

The [combined UIKit example](Examples/ChatViewController.swift) compiles against the package and injects your current-account reader and authenticated-backend mint function. It installs both bridges before loading the tenant's actual HTTPS chat URL, forwards WebKit media permission and handles renderer termination. Add [NSMicrophoneUsageDescription](Examples/Info.plist) to your app target and localize it.

1. Read [identity and authentication](docs/identity.md).
2. Configure the [complete SDK reference](docs/configuration.md).
3. Follow [microphone and voice integration](docs/microphone.md).
4. Validate on physical iOS devices using the acceptance checklist; no OS prompt should occur merely on opening chat.

When the user taps microphone or voice, chat asks the native adapter; iOS permission is requested then. Only an OS grant plus an allowed-origin WebKit media grant permits recording. Denial offers Retry; revoked permission is rechecked; cancelled chat cannot start capture after a late reply.

## Run the example app

Open `example-app/BusymateSDKExample.xcodeproj`, select `BusymateSDKExample` and an iOS Simulator/device, and run. It consumes this actual SDK as a local Swift package. See the [full demo guide](example-app/README.md) for Settings, real guest chat, identity backend integration, microphone enable/disable, callbacks, lifecycle and device acceptance checks. Build with `bash example-app/scripts/build.sh`; test with `bash example-app/scripts/test-config.sh`.

The default guest chat is `https://busymate.ai/support/busyproxy?channel=ios&locale=en`. Your workspace owns hosted voice/history/knowledge/tools/handoff availability; native configuration does not fabricate backend capabilities or authenticate merely from an account ID.

## Download the adapter

`BusymateMicrophone.swift` (microphone adapter 1.0.0, wire 1) ships in this SDK and is attached to every GitHub release, with `SHA256SUMS`:

- Latest release: https://github.com/serebano/busymate-ai-sdk-ios/releases/latest/download/BusymateMicrophone.swift
- Pinned, SDK 1.0.2: https://github.com/serebano/busymate-ai-sdk-ios/releases/download/1.0.2/BusymateMicrophone.swift
- Checksums: https://github.com/serebano/busymate-ai-sdk-ios/releases/download/1.0.2/SHA256SUMS (`shasum -a 256 -c SHA256SUMS --ignore-missing`)

This repository and its releases are the only source of the adapter. busymate.ai no longer publishes adapter copies; its legacy `https://busymate.ai/sdk/microphone/1.0.0/` files stay frozen for existing integrations.

## Versions and ownership

Platform distribution 1.0.2 is distinct from identity wire 2/build 2.0.0 and microphone wire 1/adapter 1.0.0. [Release manifest](release-manifest.json) pins unchanged source hashes. This repository is canonical for iOS SDK releases. Official rendered developer documentation is hosted on [busymate.ai](https://busymate.ai/docs/guides/mobile-in-app-support). Frozen web/shared contracts remain owned by the hosted product; do not modify old native source bytes.

Run `bash scripts/check-ios.sh` on an Xcode-equipped macOS host. This builds the package for iOS Simulator and typechecks the consumer sample. It does not certify physical OS permission dialogs, app-store publication or your backend integration. See [changelog](CHANGELOG.md) and [v2 wire contract](CONTRACT-v2.md).

## Release process

Every release attaches each `adapterAssets` file from [release-manifest.json](release-manifest.json) under its basename (`BusymateMicrophone.swift`) plus `SHA256SUMS` covering every attached asset. `python3 scripts/verify-release.py` checks the manifest version, the pinned source hashes and the adapter asset list.
