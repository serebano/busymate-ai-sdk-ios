import SwiftUI
import WebKit

@main
struct BusymateSDKExampleApp: App {
    @StateObject private var session = DemoSession()
    var body: some Scene {
        WindowGroup { DemoRootView(session: session) }
    }
}

struct ChatWebView: UIViewRepresentable {
    @ObservedObject var session: DemoSession
    func makeUIView(context: Context) -> WKWebView { session.startIfNeeded(); return session.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct DemoRootView: View {
    @ObservedObject var session: DemoSession
    var body: some View {
        TabView(selection: $session.selectedTab) {
            NavigationView {
                VStack(spacing: 0) {
                    Text(session.status).font(.caption).foregroundColor(.secondary).padding(6)
                    ChatWebView(session: session)
                }
                .navigationTitle("SDK chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Reload") { session.reload() } }
            }.tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(0)
            NavigationView {
                Form {
                    Section("Hosted chat") {
                        input("Assistant slug", $session.configuration.assistant)
                        input("Chat HTTPS URL", $session.configuration.chatURL)
                        input("Exact HTTPS origins (comma separated)", $session.configuration.origins)
                        Text("The hosted tenant controls appearance, language, voice availability and business behavior. This SDK does not expose arbitrary flags for them.").font(.caption)
                    }
                    Section("Native microphone") {
                        Toggle("Enable tap-triggered OS permission", isOn: $session.configuration.microphoneEnabled)
                        Text("No prompt on page load. Apply installs or removes the optional adapter; the OS controls permission prompts. Disabled mode retains the hosted fallback, while this demo denies native media requests.").font(.caption)
                    }
                    Section("Identity — your real app session") {
                        Toggle("Use identified account", isOn: $session.configuration.signedIn)
                        input("Signed-in account ID", $session.configuration.accountID)
                        input("Authenticated HTTPS mint endpoint", $session.configuration.mintURL)
                        SecureField("Existing backend session token (optional)", text: $session.configuration.backendSessionToken)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("An account ID is not authentication. Your own backend must authenticate the existing app session and mint fresh assertions. The optional session token stays in memory and is sent only to that endpoint; redirects are refused. Never enter signing keys or admin credentials. There is no fake login.").font(.caption)
                        Button("Forward accountChanged()") { session.accountChanged() }
                    }
                    Section("Actions and HTTPS opens") {
                        Toggle("Handle close through onAction", isOn: $session.configuration.handleCloseAction)
                        Toggle("Enable onClose fallback", isOn: $session.configuration.closeCallbackEnabled)
                        Toggle("Use authentication callback for auth opens", isOn: $session.configuration.authenticationOpen)
                        input("Registered callback scheme", $session.configuration.callbackScheme)
                        Text("V2 opens external HTTPS URLs through the OS. Auth mode uses ASWebAuthenticationSession when bmaisdkdemo is configured. Only close is handled by this sample; unknown app actions remain unhandled.").font(.caption)
                    }
                    Section("Lifecycle and diagnostics") {
                        Button("Invoke renderer recovery forwarding") { session.testRestoreForwarding() }
                        Text("Foreground resume is emitted automatically by the SDK. Recovery invokes the actual SDK method; it does not manufacture a renderer crash.").font(.caption)
                        Button("Apply and open chat") { session.apply() }.font(.headline)
                        Button("Reset to guest defaults") { session.reset() }
                        if let error = session.validationError { Text(error).foregroundColor(.red) }
                    }
                }.navigationTitle("SDK settings")
            }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(1)
            NavigationView {
                List {
                    Text("Events include SDK callbacks and public bridge event names. Payloads, account IDs, tokens, nonces and audio are omitted.").font(.caption).foregroundColor(.secondary)
                    ForEach(Array(session.events.enumerated()), id: \.offset) { _, event in Text(event).font(.caption.monospaced()) }
                }.navigationTitle("SDK events")
                 .toolbar { Button("Clear") { session.events.removeAll() } }
            }.tabItem { Label("Events", systemImage: "list.bullet.rectangle") }.tag(2)
        }
    }
    private func input(_ label: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundColor(.secondary)
            TextField(label, text: value).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
}
