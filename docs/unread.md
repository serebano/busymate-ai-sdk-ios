# Unread follow-ups: badge and message bubble in your app

When the assistant follows up with a person (or answers while the chat is closed), your app can show it where the person is: a **count badge on your chat launcher** and a **small message bubble** with the first sentence. A tap opens the chat at that message. It works while the chat screen is closed and after the app was in the background.

## How it works

The chat page and your app talk over one channel, a `WKScriptMessageHandler` named `busymate`:

| Direction | Message | Meaning |
|---|---|---|
| chat → app | `support.chat.v1.unread` `{n, t, at}` | Unread count, first sentence (at most 80 characters, links removed), ISO time. `n: 0` clears the badge. |
| chat → app | `support.chat.v1.identity` `{v}` | An opaque, signed visitor token for this workspace. The SDK keeps it in the Keychain. |
| app → chat | `support.chat.v1.open` | The person tapped the launcher or the bubble: show the conversation. |

With the stored token the SDK also asks `POST /api/chat/unread` itself: on `configure`, on every return to the foreground (`UIApplication` and `UIScene` will-enter-foreground) and after the chat closes. So the badge is right even when the web view was never loaded in this app run.

## Set up (3 lines)

```swift
import BusymateAI

// 1. App start (App.init or application(_:didFinishLaunchingWithOptions:)): restores the badge.
Busymate.shared.configure(.init(assistant: "acme"))            // chatURL defaults to https://busymate.ai/chat/w/acme

// 2. Where you create the chat web view, BEFORE its first load:
Busymate.shared.attach(to: webView)

// 3. Present your chat screen when the launcher or the bubble is tapped:
Busymate.shared.onOpenChat = { [weak self] in self?.presentChat() }
```

When your chat screen goes away, call `Busymate.shared.chatDidClose()`. On your sign-out call `Busymate.shared.reset()` (deletes the token, clears the badge).

`Configuration(assistant:chatURL:origins:)`: pass `chatURL` when you load another address (a mapped support host), and `origins` for extra exact https origins that may talk to the app. No wildcards.

## Built-in launcher and bubble

SwiftUI:

```swift
ContentView()
    .busymateLauncher(title: "Acme support")     // button + badge + bubble, bottom trailing

// or place the parts yourself
BusymateLauncherButton()                          // round button with the count badge
BusymateTeaserBubble(title: "Acme support")       // the follow-up bubble; draws nothing when there is none
BusymateLauncher()                                // both, stacked
```

UIKit:

```swift
let launcher = BusymateLauncherView(title: "Acme support")   // or BusymateLauncherButtonView / BusymateTeaserBubbleView
launcher.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(launcher)
NSLayoutConstraint.activate([
    launcher.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
    launcher.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)])
```

The views size themselves (intrinsic content size) and pass touches outside their drawn parts through to your screen.

- **Tap** on the button or the bubble: `Busymate.shared.openChat()` runs your `onOpenChat`, then the chat shows the conversation. The badge clears when the chat reports the message seen.
- **✕ on the bubble** closes only the bubble. **The message stays unread**: the badge keeps its count, and the bubble returns only for a newer message (also after a relaunch).
- They use your app's tint colour (`.tint(...)` / `tintColor`), follow light and dark, scale with Dynamic Type, respect Reduce Motion, and speak in VoiceOver ("Chat, 2 unread messages"; the bubble reads its text, with a "Dismiss" action). Counts above 99 show `99+`.
- Words: set `Busymate.shared.strings` (`launcher`, `unreadCount`, `teaserTitle`, `teaserFallback`, `teaserHint`, `dismiss`) to your localized strings.

## Your own UI

```swift
// Swift concurrency
for await unread in Busymate.shared.unread {            // AsyncStream<BusymateUnread>, current value first
    tabBarItem.badgeValue = unread.badgeText            // nil when nothing is unread
}

// Combine
Busymate.shared.unreadPublisher                          // AnyPublisher<BusymateUnread, Never>, main thread
    .sink { unread in … }

// Delegate
final class Home: UIViewController, BusymateDelegate {
    func busymateDidUpdateUnread(_ unread: BusymateUnread) { … }
    func busymateDidRequestChat() { presentChat() }      // optional
}
Busymate.shared.delegate = home

// SwiftUI: Busymate.shared is an ObservableObject
@ObservedObject var busymate = Busymate.shared           // busymate.currentUnread, busymate.teaser
```

`BusymateUnread`: `count: Int`, `preview: String` (may be empty), `at: Date?`, `badgeText: String?`. Call `Busymate.shared.openChat()` from your own launcher and `Busymate.shared.dismissTeaser()` from your own bubble's close control.

## API

| API | What it does |
|---|---|
| `Busymate.shared.configure(_:)` | Sets the assistant; asks the server once; starts the foreground refresh. |
| `Busymate.shared.attach(to:)` / `detach(from:)` | Installs / removes the `busymate` channel on a `WKWebView`. Attach before the first load. |
| `Busymate.shared.unread` | `AsyncStream<BusymateUnread>`. |
| `Busymate.shared.unreadPublisher` | Combine publisher of the same values. |
| `Busymate.shared.currentUnread`, `.teaser` | The latest value; the message the bubble shows (nil when dismissed). |
| `Busymate.shared.delegate` | `busymateDidUpdateUnread(_:)`, `busymateDidRequestChat()`. |
| `Busymate.refreshUnread()` | Asks `POST /api/chat/unread` now. Runs by itself on configure, on foreground and after `chatDidClose()`. |
| `Busymate.shared.openChat()` | Launcher/bubble tap: your `onOpenChat`, then `support.chat.v1.open` to the page (queued until the page is ready). |
| `Busymate.shared.chatDidClose()` | Your chat screen closed. |
| `Busymate.shared.dismissTeaser()` | Closes the bubble; the message stays unread. |
| `Busymate.shared.reset()` | Deletes the visitor token and clears the badge (sign-out). |

## Security and privacy

- The channel hears only frames whose origin is `https://busymate.ai`, `https://<assistant>.busymate.ai`, the origin of your `chatURL`, or an exact https origin you listed. Everything else is ignored.
- Every message is checked (type, field types, sizes, at most 4 KB). Unknown message types are dropped. The app → page message is a constant script; no text is ever spliced into it.
- The visitor token is opaque to the SDK, bound to the workspace by the server, and carries no personal data. It is stored as a Keychain generic password (service `ai.busymate.sdk.visitor`, account = assistant slug, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synced), is never logged and never placed in a URL.
- `POST /api/chat/unread` goes to the chat's own origin over https, without cookies, with a 10 s timeout; redirects are refused. `204` means nothing unread; an error leaves the last known count.
- No new permission, no push notification, no background task: the SDK asks only while your app is in the foreground. To alert a person while the app is not running, send your own push and call `Busymate.refreshUnread()` when the app opens.

## Check your integration

1. Open the chat once (the page hands the app its token), then close it.
2. Have a follow-up sent to that conversation.
3. Bring the app to the foreground: the launcher shows the badge and the bubble.
4. Tap the bubble: your chat opens at the message and the badge clears. Tap ✕ instead: the bubble goes, the badge stays.

The example app shows all of it on its **Home** tab; **Settings → Post a sample unread event from the chat page** sends one sample event through the real channel.
