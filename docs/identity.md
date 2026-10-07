# Identity and authentication

Use the v2 `BusymateBridge` for a new integration. Existing applications may keep `BusymateAIWebViewBridge` and add the microphone adapter without changing identity versions. Install exactly one identity bridge before the first load.

Your authenticated backend mints a fresh single-use launch assertion for each SDK mint callback. Never cache or reuse a token/nonce pair. Never put a signing key, Busymate admin key or service-role credential in the app. Use your existing authenticated HTTPS backend API. The callback returns only `token` and `nonce`; preserve the nonce requested by v2 and bind assistant, audience and origin server-side. A signed-out app returns no identity. Do not invent a public Busymate mint endpoint for your app: implement your tenant's authenticated backend endpoint using the official [identity guide](https://busymate.ai/docs/guides/mobile-in-app-support).

For v2, `account` is a synchronous closure reading your current account ID or nil/null. Its hash identifies account changes; the raw ID is not sent by the bridge. Call `accountChanged()` after login, logout or account switching. V2 emits a state update; hosted chat owns identity refresh and clearing behavior. Configure `onClose` to dismiss your host and `onAction` only for a fixed app-owned set of actions, returning whether handled. Do not expose arbitrary native execution.

For v1, call `identityChanged()` after login/token rotation/account switch, `signedOut(reason)` immediately on logout (reason `signed_out`, `switched` or `expired`), and `onResume()` when returning to foreground. The provider must mint a new pair on every ask. The v1 default empty origin allow-list preserves historical permissive behavior; always supply an explicit trusted origin for new integrations. V1 checks the loaded top-level URL, whereas v2 verifies the sending frame's origin. Microphone origins are independently enforced.

Keep navigation restricted to your trusted chat URLs. External URLs should open via the SDK's external/auth callback rather than leave a privileged bridge exposed to arbitrary pages. Identity availability failures keep chat anonymous (`not_signed_in`, `mint_failed`, `unsupported`); never log token, nonce, raw account ID or audio while troubleshooting.

The byte-frozen [v2 wire contract](../CONTRACT-v2.md) defines hello/state/mint/open/action, error envelopes, version negotiation and events. Its no-new-permissions statement applies to the identity bridge alone. Optional microphone integration explicitly adds microphone permission.
