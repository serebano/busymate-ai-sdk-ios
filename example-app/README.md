# Buildable iOS SDK example app

This is an actual Xcode application consuming the **local official BusymateAI
Swift package** in the parent directory. It defaults to frozen identity bridge
v2 build2.0.0 and optional microphone adapter1.0.0. There are no copied or mock
SDK implementations in the app.

## Build and open

The committed project uses Xcode 15's project format (`objectVersion = 60`),
explicitly selected by `projectFormat: xcode15_0` in the generator spec ([XcodeGen reference](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#options)).
Use an iOS 15+ target and a compatible installed simulator runtime. Local build
and shared configuration tests were actually validated with **Xcode 26.6,
build 17F113**; a build with Xcode 15 itself has not been run. CI logs its exact
Xcode/Swift toolchain versions. Project-format compatibility does not claim
physical-device or every-toolchain certification.
From the SDK repository root:

```sh
example-app/scripts/build.sh
example-app/scripts/test-config.sh
open example-app/BusymateSDKExample.xcodeproj
```

The committed Xcode project has a shared `BusymateSDKExample` scheme and a local
Swift package reference to `..`. XcodeGen is optional: regenerate with
`xcodegen generate --spec example-app/project.yml --project example-app` when
changing project structure. The build script compiles the actual app and SDK for
an iOS simulator with signing disabled and one build job. The configuration-test
script runs XCTest against the **same** validator, callback factory and backend
mint mapper compiled into the app, using a host-side Swift package; it does not
boot a simulator or claim device-dialog coverage.

To run the application, select an installed iPhone simulator in Xcode and press
Run. For a physical device, configure your own development team/signing in
Xcode; signing is your responsibility. The simulator `.app` cannot be installed
on a physical device.

## Try the live guest flow

The default URL is the real hosted chat:
`https://busymate.ai/support/busyproxy?channel=ios`.
The assistant slug is `busyproxy`, and the explicit extra origin is
`https://busymate.ai`. This is a guest support assistant, not an authenticated
example workspace or a local stub. Its availability, knowledge and enabled
hosted features belong to that tenant and deployment.

Open **Chat**, send a message, and tap dictation or voice if enabled by the hosted
chat. Microphone permission is requested by the actual SDK adapter in response
to that tap. The host forwards WebKit's separate microphone decision. Test real
permission acceptance/refusal on your device; simulator compilation does not
prove audio routing or an OS dialog.

## Settings and actual SDK controls

Change controls under **Settings**, then **Apply and open chat**. Applying
reuses the app's WebView and installs the actual SDK configuration before reload.

| Control | What it configures |
|---|---|
| Assistant slug | V2 `Config.assistant`; validated slug. |
| Chat HTTPS URL | Host URL loaded in WKWebView, including supported tenant query parameters. |
| Exact HTTPS origins | V2 `Config.origins` and the independently configured microphone origin set. No wildcard, credentials, query, fragment or path is accepted for an origin; the actual chat origin must be present. |
| Enable tap-triggered OS permission | Installs/removes the optional microphone adapter. When disabled, the hosted fallback remains available but this demo denies native WebKit media capture. |
| Use identified account / account ID | Supplies the current value to V2 `Config.account`. An entered ID is **not** a login or authentication proof. |
| Authenticated mint endpoint | The host implementation of V2 `Config.mint` calls your own HTTPS backend. |
| Optional backend session token | Your existing tenant backend access token, held only in memory. This is host authentication, not an SDK flag. Never enter signing keys, admin keys or service-role credentials. |
| Handle close through onAction | Supplies the actual optional `Config.onAction`; OFF supplies **nil**. The handler returns true only for `close`; `ready` is informational and unknown actions stay unhandled. |
| Enable onClose fallback | Supplies the actual `Config.onClose`; OFF supplies **nil**, so it cannot falsely report a handled close. |
| Authentication callback mode | Sets `Config.authCallbackScheme` to `bmaisdkdemo` or nil. That scheme is registered in `Info.plist`; different schemes require app configuration changes. External HTTPS opens stay OS-owned. |
| Forward accountChanged() | Applies the current identity/session fields and invokes the real `BusymateBridge.accountChanged()`. No token is fabricated or pushed. |
| Renderer recovery forwarding | Invokes the real `contentProcessDidTerminate` recovery path. This manual control is explicitly not a simulated crash; actual WebKit termination is forwarded by its delegate. |
| Reset | Restores guest defaults and clears the in-memory account/session token. It does not reset an OS-owned microphone permission. |

Foreground resume is observed automatically by the SDK. The host restricts
navigation to its configured HTTPS origins. Closing chat navigates away from its
document to end its media lifetime. Frozen identity build2.0.0 has no public
uninstall API; this example does not invent one.

## Your authenticated backend

Guest mode makes no mint HTTP request. To test identified mode, use your real
assistant/chat URL and a real authenticated tenant backend. Your backend must
verify the existing app session (shared app cookies or the optional in-memory
Bearer token), then sign fresh single-use Busymate launch assertions. The demo
contains no backend implementation, login shortcut, embedded signing key,
provider credential or fabricated identity.

Each callback POSTs the SDK's `nonce`, optional `aud` and `reason`, plus the
bridge-supplied `assistant` and `origin`. It bypasses response caching and
**refuses all HTTP redirects** through a per-request `URLSessionTaskDelegate`,
so authentication is never forwarded to another endpoint or scheme. The response
must be successful JSON `{"token":"...","nonce":"same-request-nonce"}`.
A401/403 response means signed out; other errors, empty tokens, redirects and
mismatched nonces fail closed. Assertions are never cached or reused by the app.

Backend authentication remains specific to your own tenant. A live guest chat,
an entered account ID, a configured endpoint, or a passing mapping test does not
prove your backend's identified end-to-end flow. See the SDK's
[identity guide](../docs/identity.md) for that contract.

## Events and verification

**Events** displays native callbacks and actual public `busymate-bridge` event
names `resume`, `state`, `restored` and auth completion where configured. It logs
no event payloads, account IDs, JWTs, tokens, nonces, callback URLs or audio. The
list is bounded to100 entries and is not persisted. The example does not expose
an invented microphone-event observer API: microphone requests travel through
the real adapter, and the host logs only its WebKit media decision.

The same XCTest suite can also run as the Xcode app test target on an installed
simulator:

```sh
xcodebuild -project example-app/BusymateSDKExample.xcodeproj \
  -scheme BusymateSDKExample -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR' \
  -jobs 1 CODE_SIGNING_ALLOWED=NO test
```

Test default guest navigation, invalid origins/URLs, identity without a backend,
callback OFF/ON semantics, fresh correlated mint responses and redirect refusal.
For device acceptance, additionally test first-tap grant, refusal and Settings
retry, cancellation while permission is pending, background/foreground,
renderer recovery, and reopening chat. Real authenticated service use, OS
permission dialogs and audio playback/capture require your own device/backend
verification.
