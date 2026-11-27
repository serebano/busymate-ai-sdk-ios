# Changelog

## 1.0.6

Unread follow-ups in your app: a channel between the chat web view and the app, a launcher badge and a follow-up bubble (unread 1.0.0). New `Busymate.swift`, `BusymateUnread.swift`, `BusymateUnreadUI.swift`.

- **Channel.** `Busymate.shared.attach(to: webView)` registers the `WKScriptMessageHandler` `busymate`. The chat page posts `support.chat.v1.unread {n, t, at}` and `support.chat.v1.identity {v}`; the app sends `support.chat.v1.open` when the person taps the launcher or the bubble. Only frames on Busymate's chat origins for your assistant (plus exact https origins you list) are heard; every message is schema-checked and unknown types are dropped.
- **Works with the chat closed.** The visitor token is kept in the Keychain (this device only, never logged). `Busymate.refreshUnread()` asks `POST /api/chat/unread`; it runs by itself on `configure`, on every return to the foreground and after `chatDidClose()`.
- **API.** `Busymate.shared.unread` (`AsyncStream`), `.unreadPublisher` (Combine), `BusymateDelegate.busymateDidUpdateUnread(_:)`, value `BusymateUnread { count, preview, at }`.
- **Built-in UI** (SwiftUI and UIKit; tint colour, light/dark, Dynamic Type, Reduce Motion, VoiceOver): `BusymateLauncherButton` with a count badge, `BusymateTeaserBubble` (tap opens the chat at the message; ✕ closes the bubble and leaves the message unread), `BusymateLauncher` / `.busymateLauncher()`; UIKit `BusymateLauncherButtonView`, `BusymateTeaserBubbleView`, `BusymateLauncherView`.
- Example app: a **Home** tab with the launcher, badge and bubble; the Chat tab carries the count. Guide: `docs/unread.md`. 23 new host-side tests (channel validation, origins, Keychain token store, request/answers, bubble state).
- No new permission. Identity v1/v2, microphone adapter and files check bytes are unchanged; `BusymateLaunch.swift` changes only its version constant. Version 1.0.5 stays immutable.

## 1.0.5

Launch parameters. New `BusymateLaunch.swift` (launch 1.0.0): `BusymateLaunch.chatURL(_:)` appends `sdkVersion=<this SDK's version>` and `hostAppId=<your bundle id>` (only when it matches `^[A-Za-z][A-Za-z0-9._-]{1,127}$`) to the chat address you load, so the workspace's Insights can show which SDK release, in which app, a chat ran in. Your own query items (`channel=ios`) are kept. No new request, permission or stored id. Wrap the URL you load: `webView.load(URLRequest(url: BusymateLaunch.chatURL(chatURL)))`; the example app and `Examples/ChatViewController.swift` do. Identity v1/v2 and microphone/files sources are unchanged. Version 1.0.4 stays immutable.

## 1.0.4

Chat address: the hosted chat's frame address is now `https://busymate.ai/chat/w/<assistant>` (busymate-ai-src#6079: no `/support` URLs). The example app defaults to `https://busymate.ai/chat/w/demos?channel=ios` and the README names the new address. `/support/<assistant>` keeps working forever as a silent alias, so apps built on 1.0.3 and older need no change. No SDK source bytes changed (identity v1/v2, microphone adapter and files check identical to 1.0.3).

## 1.0.3

Attachments (visitor images and PDFs went live in every workspace chat on 2026-11-19). WKWebView handles the chat's attach (+) button by itself, verified on a physical iPhone SE: + opens Photo Library / Take Photo / Choose Files. But **Take Photo terminates an app without `NSCameraUsageDescription`** (the example app had only the microphone key and crashed). New `BusymateFiles.swift` (files check 1.0.0): `missingUsageDescriptions()` / `checkHost()`, which logs one fault when the key is missing; microphone adapter 1.0.1 (wire 1 unchanged) runs it at install. Example app and `Examples/Info.plist` declare `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`; docs gain "Attachments (the + button)". The example app now defaults to the public `demos` workspace. Identity v1/v2 bytes unchanged.

## 1.0.2

Release packaging: the microphone adapter source (`BusymateMicrophone.swift`, adapter 1.0.0, wire 1, sha256 `a99ae81eb1ac2bf75d268724e94120e3953eb793a10321f16430d5c6594859a8`) is attached to every GitHub release and listed in `SHA256SUMS`; docs link the release, not busymate.ai. No SDK code change; native source hashes are unchanged. Versions 1.0.0 and 1.0.1 stay immutable. (refs serebano/busymate-ai-src#2156)

## 1.0.1

Fix the example application's saved project format to Xcode 15 (`objectVersion 60`) by explicitly configuring XcodeGen, instead of the newer default format used in 1.0.0. Document the actual validated Xcode 26.6/build 17F113 toolchain and add a format regression guard. Native identity/microphone sources and their hashes remain unchanged. Version 1.0.0 stays immutable.

## 1.0.0

First independent OS distribution: existing identity v1 bridge, frozen identity v2 bridge build 2.0.0, and microphone adapter 1.0.0. Identity source bytes are unchanged. Hosted chat receives updates separately; your native app release is needed to install or upgrade native SDK code.
