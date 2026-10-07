# Native microphone integration for iOS and Android — adapter 1.0.0

This guide adds microphone permission requests to a hosted chat in your native app.
A user taps the chat microphone or voice button; the chat sends an event to the
app, the app asks the operating system for microphone access, and the chat starts
capture only after permission is granted. No separate native permission button
is needed. The OS decides whether a prompt is shown: an existing grant starts
immediately; a previous refusal can require the user to change app Settings.

## Before you integrate

- Keep your existing identity bridge and authentication flow. This optional
  adapter works with either identity bridge; the immutable kit v2 files stay unchanged.
- Download [the Swift adapter](https://busymate.ai/sdk/microphone/1.0.0/ios/BusymateMicrophone.swift)
  or [the Kotlin adapter](https://busymate.ai/sdk/microphone/1.0.0/android/BusymateMicrophone.kt)
  and include it in your app target. The source files contain the bridge implementation.
- Use the chat URL generated for your tenant. The examples use
  `https://YOUR_ASSISTANT.busymate.ai`; replace it with your actual chat origin
  and URL. Authentication and chat loading follow your existing integration.
- Install the adapter **before the first chat load**, once per WebView. Keep it
  alive for that WebView's lifetime. Retain existing navigation and media delegates.
- Allow only the exact HTTPS origins serving your assistant. Use scheme + host
  + optional port, with no trailing slash, path, credentials, wildcard, query or
  fragment. Include the actual chat frame origin when embedded inside another page.
  Host names normalize to lowercase; the default HTTPS port 443 is equivalent to
  an omitted port. Navigating the WebView to an untrusted origin must not grant access.

This is native app code: integrating it requires **your app's own release**.
Apps without the adapter retain their existing WebView permission flow.

## iOS installation

Use iOS 15 or later and add `BusymateMicrophone.swift` to your app target.
The file imports the system `AVFoundation` and `WebKit` frameworks; no third-party
package is needed. Add an explanation to the target's `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Use the microphone to speak to our support assistant.</string>
```

Localize that explanation for your app's supported languages. Without this key,
the app cannot request microphone access safely.

For a new UIKit host, this minimal controller shows the registration order and
the required separate WebKit media-permission callback:

```swift
import UIKit
import WebKit

@available(iOS 15.0, *)
final class ChatViewController: UIViewController, WKUIDelegate {
    private var webView: WKWebView!
    private var microphone: BusymateMicrophone!

    override func loadView() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.uiDelegate = self
        microphone = BusymateMicrophone(webView: webView,
            origins: ["https://YOUR_ASSISTANT.busymate.ai"])
        // Configure your existing identity bridge before loading the chat too.
        webView.load(URLRequest(url:
            URL(string: "https://YOUR_ASSISTANT.busymate.ai")!))
    }

    func webView(_ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(microphone.allowMedia(origin: origin, type: type))
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: "BusymateMicrophone", contentWorld: .page)
    }
}
```

For an existing host, keep its `WKUIDelegate` and forward this callback to
`microphone.allowMedia`; do not discard its other callbacks. SwiftUI hosts can
retain the adapter in their WebView coordinator and remove its handler when the
WebView is dismantled. Remove the handler before installing a replacement on
that same content controller.

The event calls `AVAudioSession.requestRecordPermission`. WebKit's media callback
is a second decision: the adapter grants **only microphone** capture from an
allowed origin after the OS grant. It denies camera and mixed camera/microphone
requests. It does not configure the rest of your app's audio session or interrupt
other audio; preserve your existing audio-session management.

## Android installation

Add `BusymateMicrophone.kt` to your source set. Its package is
`ai.busymate.whitelabel`; import that class from your host. Your app needs
AndroidX `androidx.activity:activity`, `androidx.core:core` and
`androidx.webkit:webkit` (1.3.0 or later) dependencies: the message-listener APIs
were added in WebKit 1.3.0. Use versions compatible with your existing
Android project and satisfy their declared compile/min SDK requirements.

`PermissionRequest` uses Android API 21+; OS runtime permission dialogs apply on
API 23+. Bridge availability also depends on the installed WebView provider,
checked at runtime with `WebViewFeature.WEB_MESSAGE_LISTENER`. API level alone
does not prove bridge support. Update the device's Android System WebView/Chrome
when that feature is unavailable; there is no `addJavascriptInterface` fallback.

Add these permissions outside `<application>` in `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

A minimal `ComponentActivity` host follows. Keep your existing layout, navigation
client and authentication setup when adding this to an existing app:

```kotlin
import android.os.Bundle
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebView
import ai.busymate.whitelabel.BusymateMicrophone
import androidx.activity.ComponentActivity
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

class ChatActivity : ComponentActivity() {
    private lateinit var webView: WebView
    private lateinit var microphone: BusymateMicrophone

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        webView = WebView(this)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        setContentView(webView)
        microphone = BusymateMicrophone(this, webView,
            setOf("https://YOUR_ASSISTANT.busymate.ai"))
        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                microphone.allowMedia(request)
            }
        }
        // Configure your existing identity bridge before loading the chat too.
        webView.loadUrl("https://YOUR_ASSISTANT.busymate.ai")
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
                WebViewCompat.removeWebMessageListener(webView, "BusymateMicrophone")
            }
            webView.stopLoading()
            webView.destroy()
        }
        super.onDestroy()
    }
}
```

Construct the adapter in `onCreate`, **before the activity reaches `STARTED`**;
its Activity Result launcher must register at that stage. Do not construct a new
adapter on every microphone tap. On activity recreation, the host recreates its
WebView and adapter normally. If a Fragment or Compose host owns the WebView,
register with the activity early and coordinate that WebView's disposal with its
actual owner; do not destroy a WebView still used by another view.

Keep your existing `WebChromeClient` and forward `onPermissionRequest` on the UI
thread. The adapter grants only `RESOURCE_AUDIO_CAPTURE`, only for an allowed
requesting origin, and only after the app's OS permission is granted; other
resources are not granted. The runtime permission dialog is launched only when
needed. For a chat iframe, its parent page must also allow microphone access
through its iframe Permissions Policy.

## Event and reply contract

The handler is named `BusymateMicrophone`. iOS receives a **JSON string** through
`WKScriptMessageHandlerWithReply`; Android receives the same string through
`WebViewCompat.addWebMessageListener`:

```json
{"type":"busymate.microphone.v1.request","id":"mic-unique-id","source":"dictation"}
```

`source` is `dictation` or `voice`. Keep `type` and handler names exactly as shown.
The adapters accept messages only from allowed origins and bound message size to
4096. The reply preserves the request id and contains a boolean `granted`:

```json
{"id":"mic-unique-id","granted":true}
```

On iOS the reply is a native dictionary resolved by the message Promise; on
Android it is a JSON string returned through the message reply proxy. Do not
manually invoke the bridge from a page-load script or request OS permission when
opening chat: the chat owns the user-tap trigger and request correlation.

The chat waits before `getUserMedia` or voice session creation. A native refusal,
invalid reply or 60-second timeout shows the blocked notice. **Try again** asks
the app again; concurrent requests share one pending ask. Each later activation
rechecks permission, including a grant revoked in Settings. The OS may refuse
without another prompt after a denial; direct the user to the app's microphone
setting. The adapter does not open Settings automatically.

Cancel dictation with another microphone tap, or leave voice mode with its
keyboard control. A late permission result cannot start capture after cancel or
unmount. Cancelling chat does not dismiss an OS-owned prompt or undo an OS grant.

## Troubleshooting

| Symptom | Check |
|---|---|
| No OS prompt on first tap | Permission may already be decided. On a fresh permission state, confirm the adapter was installed before load, the exact chat/frame origin is allowed, and Android exposes `WEB_MESSAGE_LISTENER`. |
| OS accepted, chat still cannot record | Verify `WKUIDelegate` / `WebChromeClient` forwarding and the requesting origin. Check iframe Permissions Policy and the WebView's media capability. OS permission alone is insufficient. |
| Retry shows no new prompt | Open this app's microphone setting and grant access, then return and tap **Try again**. The OS controls repeat prompts. |
| Android launcher registration error | Create the adapter in `ComponentActivity.onCreate`, before `STARTED`, once for that WebView. |
| Request times out | Confirm the adapter receives the string event and returns a correlated boolean reply. Never log identity tokens or audio when debugging. |
| Duplicate iOS handler error | Remove the prior handler before replacing it; retain one adapter per WebView. |
| Camera request denied | Expected: this adapter provides microphone access only. |

## Acceptance checklist for your app release

Build the integration in your own Xcode and Android Gradle projects, then verify
on supported physical iOS and Android devices:

1. Fresh permission state: open chat without a prompt; tap **microphone**, see the
   OS prompt, allow, and dictate successfully. Repeat separately for **voice mode**.
2. Deny: see the blocked notice, with no capture or automatic prompt loop.
   Grant access in app Settings, return, and use **Try again** successfully.
3. Already granted: another activation starts without an unnecessary OS prompt.
   Revoke permission in Settings and confirm the next activation rechecks it.
4. While permission is pending, cancel dictation or leave voice mode. Accept the
   OS prompt afterward and confirm capture does not start from the cancelled action.
5. Leave/reopen chat, recreate the Android activity, and repeat an activation;
   verify delegates, listeners and the adapter lifetime remain correct.
6. Confirm untrusted origins and camera requests are refused. Test each supported
   WebView provider and any parent-page iframe configuration.

Hosted browser bridge simulations verify event order and cancellation; they
cannot verify real OS dialogs. This guide does not claim your tenant app was
compiled, store-published or device-certified. Record those results with your
own app release before rollout.

## Platform references

- [Apple: remove a script message handler](https://developer.apple.com/documentation/webkit/wkusercontentcontroller/removescriptmessagehandler(forname:contentworld:))
- [Android: WebView setup, JavaScript and INTERNET](https://developer.android.com/develop/ui/views/layout/webapps/webview)
- [AndroidX: WebViewCompat message listener APIs](https://developer.android.com/reference/androidx/webkit/WebViewCompat)
