# Configuration reference

| Setting | v2 behavior |
|---|---|
| `assistant` | Required assistant slug; adds exactly `https://<assistant>.busymate.ai` to allowed origins. Obtain the actual assistant URL from Busymate; a marketing page is not a chat URL. |
| `origins` | Extra exact HTTPS origins for mapped support hosts/frames. No wildcards. Supply the actual chat frame origin independently to the microphone adapter. |
| `account` | Closure returning current account ID or nil/null, read when state/mint is requested. |
| `mint` | Required authenticated-backend callback, fresh token/nonce for every request; never a cached assertion. |
| `onAction` | Optional fixed app-action handler; return true only when handled. |
| `onClose` | Optional host dismissal callback; fallback for the `close` action. |

The microphone adapter accepts only `webView` and exact `origins` (plus Android host activity). It is installed once before load, not on each tap. Chat triggers dictation/voice requests and controls a 60-second wait. There is no SDK setting for automatic OS prompts on page load, camera access, opening Settings, timeout override, audio-session category, provider credentials or token caching.

Hosted chat appearance, theme, locale, voice availability and tenant behavior are configured through the hosted chat/embed surface and Busymate Console, not by arbitrary native SDK flags. Preserve the tenant-generated chat URL, including its supported query parameters. The SDK does not own safe-area/layout/navigation styling or audio routing; your host does.

V1 configuration: iOS initializer takes `webView`, `identityProvider`, optional `openExternal`, `onClose`, `allowedOrigins`; Android `install` takes `context`, `webView`, `identityProvider`, optional `onClose`, `allowedOrigins`. Android enables JavaScript but does not alter cookie policy. Third-party cookies are not required for native identity. Legacy compatibility handler names remain present; do not register another handler using those names.

Microphone registration: iOS `BusymateMicrophone`; Android `BusymateMicrophone`. Request type `busymate.microphone.v1.request`, source `dictation` or `voice`, correlated `id`; reply has the same `id` and a boolean `granted`. See [microphone integration](microphone.md) for denial, retry, Settings and cancellation behavior.

## iOS-specific APIs

`authCallbackScheme`: optional custom scheme used by `ASWebAuthenticationSession` for auth-mode URL opens; register that scheme in your app URL types and follow your app OAuth flow. Without it the SDK opens HTTPS externally. The authentication presentation anchor is the WebView window.

`BusymateBridge.install(on:config:)` registers before first load. `allowedOrigins(config)` returns the normalized allowed origins. `accountChanged()` emits current state for installed views. `contentProcessDidTerminate(webView)` reloads the same view and emits `restored` after hello. Foreground resume is observed automatically. When `WKAppBoundDomains` is enabled, include the actual chat origins in the app's configuration.

UIKit: retain the microphone adapter and forward the media callback on your existing `WKUIDelegate`; keep navigation callbacks too. SwiftUI: own the WebView and adapter in your `UIViewRepresentable.Coordinator`, install during `makeUIView`, and remove the microphone handler during `dismantleUIView` before replacing it. Do not create duplicate handlers during `updateUIView`. V2 has no public uninstall API in frozen build 2.0.0; do not invent one. Dispose your host's handlers and references deliberately and test reopening chat.

V1 iOS additionally supports a custom `openExternal(URL)` callback. `refreshIdentity`, `identityChanged`, `signedOut(reason:)` and `onResume` are async throwing; handle failures within your app's lifecycle tasks.
