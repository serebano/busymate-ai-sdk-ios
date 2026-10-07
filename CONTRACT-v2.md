# `busymate.bridge/2` — the frozen app bridge (kit v2, build 2.0.0)

This is the whole contract between your app and the Busymate chat. It is the
last integration change we ask of you: after this, every fix and every new
feature ships from busymate.ai, and your app never needs a new build because
of us.

## Why this is the last change

- The native file is a **pipe**. It carries one JSON envelope between the chat
  and five operations in your app. It has no message names, timings, retries or
  fallbacks of its own.
- Everything that decides behaviour is served from busymate.ai at runtime: the
  chat frame, the embed loader and the launch server. We change those, not your
  binary.
- New capabilities are **additive**. The bridge reports what it supports in
  `hello`, and the chat uses a feature only when it has been announced.
- The files are **immutable**. `https://busymate.ai/sdk/v2/2.0.0/…` will never
  change. A future version gets a new path and is announced in advance.

## Transport

| Platform | Mechanism | Sender identity |
|---|---|---|
| Android | `WebViewCompat.addWebMessageListener(webView, "BusymateBridge", allowedOriginRules, …)` (androidx.webkit ≥ 1.8, WebView ≥ 82). Older WebViews fall back to `addJavascriptInterface`, reported as transport `jsi`. | `sourceOrigin` of the posting frame |
| iOS 14+ | `WKScriptMessageHandlerWithReply`, name `BusymateBridge`, content world `.page` | `message.frameInfo.securityOrigin` |
| React Native, Flutter | The same envelope over the platform's own channel | The top page URL's origin |
| Electron | The same envelope over IPC | `event.senderFrame.origin` (the frame's security origin) |

The origin allow-list is **exact**: `https://<assistant>.busymate.ai` (your own
chat) plus the exact `https` origins you configure (for example your mapped
support host). There are no wildcards and no platform-wide entry: another
tenant's chat, a busymate.ai artifact or any other busymate.ai page is refused
with `denied`, and your mint is never called. An `origins` entry that is not an
exact `https://host[:port]` (a wildcard, a path, `http:`) is ignored. A frame
with an opaque origin (a sandboxed document) is always refused.

React Native and Flutter WebViews report only the top page's URL, so on those
hosts the top page's origin is checked and every reply is delivered to the top
page only.

## Envelope

JSON, at most 64 KB. Readers ignore fields they do not know.

- Request (chat → app): `{"bm":2,"id":…,"op":"…","p":{…}}`
- Reply (app → chat): `{"bm":2,"id":…,"ok":true,"r":{…}}` or `{"bm":2,"id":…,"ok":false,"e":"…"}`
- Event (app → chat): `{"bm":2,"ev":"…","r":{…}}`

Errors: `unsupported` · `denied` · `not_signed_in` · `mint_failed` · `timeout` · `bad_request`.

## The five operations

| Op | Request `p` | Reply `r` |
|---|---|---|
| `hello` | — | `{bridge:"busymate", v:2, build, platform, transport, assistant, origin, origins[], caps[], webview, app:{id, version, build}}` — `assistant` is your configured slug, `origin` the asking frame's origin, `origins` the exact allow-list |
| `state` | — | `{signedIn, account}` — `account` is SHA-256(`appId:accountId`) truncated to 128 bits (hex), or `null` when signed out. The raw id never leaves the device. |
| `mint` | The chat's fields (today: `nonce`, `aud`, `reason`) passed to your `mint` callback, plus `assistant` and `origin`, which the bridge sets itself and a page can never choose. | `{token, nonce}` from your backend's signer |
| `open` | `{url, mode}` — `https` only; `mode` is `external` or `auth` | `{opened}` |
| `action` | `{name, params}` — given to your optional `onAction`; `close` falls back to `onClose`. Names used: `close`, `ready` (informational). The chat never depends on `handled`. | `{handled}` |

An unknown `op` is answered `unsupported`.

## Events the bridge sends by itself

| Event | When |
|---|---|
| `resume` | The app returns to the foreground |
| `state` | You call `accountChanged()` (optional; the chat also re-reads `state` on its own) |
| `restored` | The bridge reloaded the chat after the web content process died |

## What you write

- `install(webView, config)` before the first load, with `assistant`, `origins`,
  `account()` and `mint(request, done)`. Your backend signs the `nonce` in the
  request; it may also bind the token to `request.assistant` and
  `request.origin`.
- One line forwarding renderer death (`onRenderProcessGone` on Android,
  `webViewWebContentProcessDidTerminate` on iOS).
- Optional: `accountChanged()` after sign-in, sign-out or an account switch, and
  `onAction` / `onClose`.

## Store compliance

- No new permissions. No downloaded native code (Apple DPLA 3.3.1(B); Google
  Play Device and Network Abuse).
- The web page reaches only your own mint, an `https` open and close. It never
  gets a general native API (Apple 4.7.2).
- The AI disclosure, consent and report controls are served inside the chat.
  Your privacy label should mention chat data shared with busymate.ai (Apple
  5.1.2(i)).

## Machine-readable

`contract.json` in this directory is the same contract as data (ops, request and
reply fields, events, errors, action names). Our gates check every served
change against it, and a new version must be a superset of the previous one.

## Our compatibility promise

- Every version ever shipped keeps working. We never switch an old bridge off.
  Deprecation is a notice, never a runtime cut.
- Changes after 2.0.0 are additive only and used only once `hello` announces
  them.
- A breaking change would be a new major (v3): approved by our owner, batched
  with every other pending native need, announced at least 6 months ahead, with
  v2 supported for at least 2 years.
- A working guest chat is always the floor: if identity cannot be established,
  the customer can still chat.
