# Busymate AI SDK for iOS — 1.0.6

Official independent iOS source package for Busymate AI hosted chat. Install once in your app; hosted chat receives web updates independently.

## Install with Swift Package Manager

In Xcode, File → Add Package Dependencies, use:

`https://github.com/serebano/busymate-ai-sdk-ios.git`

Choose **Exact Version 1.0.6** and add the `BusymateAI` product to your app target. Requires iOS 15+ and Swift tools 5.9+ (Swift 5 language mode). In a package manifest:

```swift
.package(url: "https://github.com/serebano/busymate-ai-sdk-ios.git", exact: "1.0.6")
// In your target's dependencies:
.product(name: "BusymateAI", package: "busymate-ai-sdk-ios")
```

`import BusymateAI`. Use `BusymateBridge` (identity wire v2, immutable build 2.0.0) plus `BusymateMicrophone` (adapter 1.0.1). Existing v1 integrations can retain `BusymateAIWebViewBridge`; do not install both identity handlers on the same chat.

## Integrate

The [combined UIKit example](Examples/ChatViewController.swift) compiles against the package and injects your current-account reader and authenticated-backend mint function. It installs both bridges before loading the tenant's actual HTTPS chat URL, forwards WebKit media permission and handles renderer termination. Add [NSMicrophoneUsageDescription and NSCameraUsageDescription](Examples/Info.plist) to your app target and localize them. The chat's attach (+) button opens WebKit's own menu (Photo Library, Take Photo, Choose Files) with no delegate code; **without NSCameraUsageDescription iOS terminates your app when the user picks Take Photo** ([attachments](docs/configuration.md#attachments-the--button)).

1. Read [identity and authentication](docs/identity.md).
2. Configure the [complete SDK reference](docs/configuration.md).
3. Follow [microphone and voice integration](docs/microphone.md).
4. Add `NSCameraUsageDescription` for the chat's attach menu ([attachments](docs/configuration.md#attachments-the--button)).
5. Show [unread follow-ups in your app](docs/unread.md): a badge on your launcher and a message bubble, also while the chat is closed.
6. Load the chat through `BusymateLaunch.chatURL(_:)` so the workspace sees your SDK version and app id ([launch parameters](docs/configuration.md#launch-parameters)).
7. Validate on physical iOS devices using the acceptance checklist; no OS prompt should occur merely on opening chat.

When the user taps microphone or voice, chat asks the native adapter; iOS permission is requested then. Only an OS grant plus an allowed-origin WebKit media grant permits recording. Denial offers Retry; revoked permission is rechecked; cancelled chat cannot start capture after a late reply.

## Unread follow-ups: badge and bubble in your app

The chat page and your app talk over one channel (`window.webkit.messageHandlers.busymate`): the page reports what is unread (`support.chat.v1.unread`) and hands the app an opaque visitor token (`support.chat.v1.identity`, kept in the Keychain); the app asks the page to show the conversation (`support.chat.v1.open`). With the token the SDK also asks the server on start and on every return to the foreground, so the badge works while the chat is closed.

```swift
Busymate.shared.configure(.init(assistant: "acme"))           // app start
Busymate.shared.attach(to: webView)                            // before the chat's first load
Busymate.shared.onOpenChat = { [weak self] in self?.presentChat() }

ContentView().busymateLauncher(title: "Acme support")          // SwiftUI: button + badge + bubble
view.addSubview(BusymateLauncherView(title: "Acme support"))   // UIKit
```

| API | |
|---|---|
| `Busymate.shared.unread` / `.unreadPublisher` | `AsyncStream` / Combine publisher of `BusymateUnread { count, preview, at }`. |
| `BusymateDelegate.busymateDidUpdateUnread(_:)` | The same as a delegate call. |
| `Busymate.refreshUnread()` | Asks `POST /api/chat/unread`; automatic on configure and on app foreground. |
| `BusymateLauncherButton`, `BusymateTeaserBubble`, `BusymateLauncher` | SwiftUI launcher with count badge, follow-up bubble (✕ leaves the message unread), both. UIKit: `BusymateLauncherButtonView`, `BusymateTeaserBubbleView`, `BusymateLauncherView`. |
| `Busymate.shared.openChat()`, `dismissTeaser()`, `chatDidClose()`, `reset()` | For your own launcher UI and lifecycle. |

Only Busymate's chat origins for your assistant (plus exact origins you list) are heard, every message is schema-checked, unknown types are dropped, and the token is never logged. Full guide: [docs/unread.md](docs/unread.md).

## Run the example app

Open `example-app/BusymateSDKExample.xcodeproj`, select `BusymateSDKExample` and an iOS Simulator/device, and run. It consumes this actual SDK as a local Swift package. See the [full demo guide](example-app/README.md) for Settings, real guest chat, identity backend integration, microphone enable/disable, callbacks, lifecycle and device acceptance checks. Build with `bash example-app/scripts/build.sh`; test with `bash example-app/scripts/test-config.sh`.

The default guest chat is `https://busymate.ai/chat/w/demos?channel=ios`. Your workspace owns hosted voice/history/knowledge/tools/handoff availability; native configuration does not fabricate backend capabilities or authenticate merely from an account ID.

## Download the adapter

`BusymateMicrophone.swift` (microphone adapter 1.0.1, wire 1) and `BusymateFiles.swift` (files check 1.0.0; the microphone adapter calls it) ship in this SDK and are attached to every GitHub release, with `SHA256SUMS`:

- Latest release: https://github.com/serebano/busymate-ai-sdk-ios/releases/latest/download/BusymateMicrophone.swift
- Pinned, SDK 1.0.6: https://github.com/serebano/busymate-ai-sdk-ios/releases/download/1.0.6/BusymateMicrophone.swift and https://github.com/serebano/busymate-ai-sdk-ios/releases/download/1.0.6/BusymateFiles.swift
- Checksums: https://github.com/serebano/busymate-ai-sdk-ios/releases/download/1.0.6/SHA256SUMS (`shasum -a 256 -c SHA256SUMS --ignore-missing`)

This repository and its releases are the only source of the adapter. busymate.ai no longer publishes adapter copies; its legacy `https://busymate.ai/sdk/microphone/1.0.0/` files stay frozen for existing integrations.

## Versions and ownership

Platform distribution 1.0.6 is distinct from identity wire 2/build 2.0.0, microphone wire 1/adapter 1.0.1, files check 1.0.0, launch 1.0.0 and unread 1.0.0. [Release manifest](release-manifest.json) pins unchanged source hashes. This repository is canonical for iOS SDK releases. Official rendered developer documentation is hosted on [busymate.ai](https://busymate.ai/docs/guides/mobile-in-app-support?utm_source=github&utm_medium=readme&utm_campaign=busymate-ai-sdk-ios). Frozen web/shared contracts remain owned by the hosted product; do not modify old native source bytes.

Run `bash scripts/check-ios.sh` on an Xcode-equipped macOS host. This builds the package for iOS Simulator and typechecks the consumer sample. It does not certify physical OS permission dialogs, app-store publication or your backend integration. See [changelog](CHANGELOG.md) and [v2 wire contract](CONTRACT-v2.md).

## Release process

Every release attaches each `adapterAssets` file from [release-manifest.json](release-manifest.json) under its basename (`BusymateMicrophone.swift`) plus `SHA256SUMS` covering every attached asset. `python3 scripts/verify-release.py` checks the manifest version, the pinned source hashes and the adapter asset list.
