import Combine
import SwiftUI
import UIKit

// Busymate AI — the built-in launcher and follow-up bubble (unread 1.0.0).
//
// SwiftUI: `BusymateLauncherButton`, `BusymateTeaserBubble`, or both stacked as `BusymateLauncher`
// (`.busymateLauncher()` pins that to a corner of any view).
// UIKit:   `BusymateLauncherButtonView`, `BusymateTeaserBubbleView`, `BusymateLauncherView`.
//
// They follow the system: your tint colour, light and dark, Dynamic Type, Reduce Motion, VoiceOver.
// Prefer your own UI? Draw it from `Busymate.shared.unread` and call `Busymate.shared.openChat()`.

// MARK: - Launcher button

/// A round chat button with the unread count as a badge. A tap calls `Busymate.shared.openChat()`.
@available(iOS 15.0, *)
public struct BusymateLauncherButton: View {
    @ObservedObject private var busymate = Busymate.shared
    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 56
    @ScaledMetric(relativeTo: .title2) private var glyph: CGFloat = 23
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let systemImage: String
    private let fixed: BusymateUnread?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - systemImage: the SF Symbol in the button.
    ///   - unread: a fixed value to show (previews, your own source); nil follows `Busymate.shared`.
    ///   - action: replaces the default tap (`Busymate.shared.openChat()`).
    public init(systemImage: String = "bubble.left.and.bubble.right.fill", unread: BusymateUnread? = nil,
                action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.fixed = unread
        self.action = action
    }

    public var body: some View {
        let unread = fixed ?? busymate.currentUnread
        let side = min(diameter, 88)
        Button {
            if let action { action() } else { busymate.openChat() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: min(glyph, 38), weight: .semibold))
                .foregroundColor(.white)
                .frame(width: side, height: side)
                .background(Circle().fill(Color.accentColor))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                .overlay(alignment: .topTrailing) {
                    if let text = unread.badgeText {
                        BusymateBadge(text: text).offset(x: 5, y: -5).transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(BusymatePressStyle())
        .hoverEffect(.lift)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.62), value: unread.count)
        .accessibilityLabel(busymate.strings.launcher)
        .accessibilityValue(unread.count > 0 ? busymate.strings.unreadCount(unread.count) : "")
        .accessibilityShowsLargeContentViewer {
            Image(systemName: systemImage)
            Text(busymate.strings.launcher)
        }
    }
}

/// The red count capsule, ringed in the background colour so it reads on any button.
@available(iOS 15.0, *)
struct BusymateBadge: View {
    let text: String
    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 20

    var body: some View {
        let side = min(height, 34)
        Text(text)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, side * 0.3)
            .frame(minWidth: side, minHeight: side)
            .background(Capsule().fill(Color(.systemRed)))
            .overlay(Capsule().strokeBorder(Color(.systemBackground), lineWidth: 2).padding(-2))
            .accessibilityHidden(true)
    }
}

// MARK: - Follow-up bubble

/// The newest unread message as a small card: tap to open the chat at it, ✕ to close the card.
/// Closing leaves the message unread (the badge stays). Draws nothing when there is nothing to show.
@available(iOS 15.0, *)
public struct BusymateTeaserBubble: View {
    @ObservedObject private var busymate = Busymate.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var avatar: CGFloat = 30

    private let title: String?
    private let maxWidth: CGFloat
    private let fixed: BusymateUnread?
    private let onOpen: (() -> Void)?
    private let onDismiss: (() -> Void)?

    /// - Parameters:
    ///   - title: the small heading (your assistant's name); nil uses `Busymate.shared.strings.teaserTitle`.
    ///   - maxWidth: the card never grows wider than this.
    ///   - unread: a fixed message to show (previews, your own source); nil follows `Busymate.shared.teaser`.
    ///   - onOpen: replaces the default tap (`Busymate.shared.openChat()`).
    ///   - onDismiss: replaces the default ✕ (`Busymate.shared.dismissTeaser()`).
    public init(title: String? = nil, maxWidth: CGFloat = 320, unread: BusymateUnread? = nil,
                onOpen: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.title = title
        self.maxWidth = maxWidth
        self.fixed = unread
        self.onOpen = onOpen
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let message = fixed ?? busymate.teaser
        Group {
            if let message, message.count > 0 {
                card(message)
                    .transition(reduceMotion ? .opacity
                                : .scale(scale: 0.86, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.8),
                   value: message)
    }

    private func open() { if let onOpen { onOpen() } else { busymate.openChat() } }
    private func dismiss() { if let onDismiss { onDismiss() } else { busymate.dismissTeaser() } }

    private func card(_ message: BusymateUnread) -> some View {
        let strings = busymate.strings
        let heading = title ?? strings.teaserTitle
        let text = message.preview.isEmpty ? strings.teaserFallback : message.preview
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: min(avatar, 44) * 0.46, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: min(avatar, 44), height: min(avatar, 44))
                        .background(Circle().fill(Color.accentColor))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(heading)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text(text)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(typeSize.isAccessibilitySize ? 6 : 3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.vertical, 12)
                .padding(.trailing, 44)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .background(shape.fill(.regularMaterial))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .contentShape(shape)
            }
            .buttonStyle(BusymatePressStyle(scale: 0.98))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(heading): \(text)")
            .accessibilityHint(strings.teaserHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text(strings.dismiss), dismiss)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BusymatePressStyle(scale: 0.9))
            .accessibilityLabel(strings.dismiss)
        }
        .frame(maxWidth: maxWidth)
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
        .hoverEffect(.highlight)
    }
}

// MARK: - Both together

/// The bubble above the launcher button, trailing-aligned: drop it in a corner of your main screen.
@available(iOS 15.0, *)
public struct BusymateLauncher: View {
    private let title: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - title: the bubble's heading (your assistant's name).
    ///   - action: replaces the default tap of both parts (`Busymate.shared.openChat()`).
    public init(title: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            BusymateTeaserBubble(title: title, onOpen: action)
            BusymateLauncherButton(action: action)
        }
    }
}

@available(iOS 15.0, *)
public extension View {
    /// Pin the Busymate launcher (button, badge and follow-up bubble) over this view.
    func busymateLauncher(alignment: Alignment = .bottomTrailing, padding: CGFloat = 16, title: String? = nil,
                          action: (() -> Void)? = nil) -> some View {
        overlay(alignment: alignment) {
            BusymateLauncher(title: title, action: action).padding(padding)
        }
    }
}

/// The system's pressed feel: a slight shrink and dim.
@available(iOS 15.0, *)
struct BusymatePressStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - UIKit

/// Hosts one of the SwiftUI parts in a UIView that sizes itself to its content (Auto Layout intrinsic size).
@available(iOS 15.0, *)
@MainActor
public class BusymateHostedView: UIView {
    private let host: UIHostingController<AnyView>
    private var changes: AnyCancellable?

    init(_ content: AnyView) {
        host = UIHostingController(rootView: content)
        super.init(frame: .zero)
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor)])
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        // The content changes size with the unread value (the bubble appears, the badge grows).
        changes = Busymate.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.invalidateIntrinsicContentSize()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Create Busymate views in code") }

    public override var intrinsicContentSize: CGSize {
        host.sizeThatFits(in: CGSize(width: UIView.layoutFittingExpandedSize.width,
                                     height: UIView.layoutFittingExpandedSize.height))
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize { host.sizeThatFits(in: size) }

    public override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        invalidateIntrinsicContentSize()
    }

    /// Join the nearest view controller, so the content gets its environment (tint, traits, focus).
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { host.willMove(toParent: nil); host.removeFromParent(); return }
        guard host.parent == nil else { return }
        var responder: UIResponder? = next
        while let current = responder, !(current is UIViewController) { responder = current.next }
        if let parent = responder as? UIViewController {
            parent.addChild(host)
            host.didMove(toParent: parent)
        }
    }

    /// Touches outside the drawn parts fall through to your screen.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// UIKit: the round chat button with its unread badge.
@available(iOS 15.0, *)
public final class BusymateLauncherButtonView: BusymateHostedView {
    /// - Parameter action: replaces the default tap (`Busymate.shared.openChat()`).
    public init(systemImage: String = "bubble.left.and.bubble.right.fill", action: (() -> Void)? = nil) {
        super.init(AnyView(BusymateLauncherButton(systemImage: systemImage, action: action)))
    }
}

/// UIKit: the follow-up bubble. Its intrinsic size is zero while there is nothing to show.
@available(iOS 15.0, *)
public final class BusymateTeaserBubbleView: BusymateHostedView {
    public init(title: String? = nil, maxWidth: CGFloat = 320, onOpen: (() -> Void)? = nil,
                onDismiss: (() -> Void)? = nil) {
        super.init(AnyView(BusymateTeaserBubble(title: title, maxWidth: maxWidth, onOpen: onOpen, onDismiss: onDismiss)))
    }
}

/// UIKit: the bubble above the button. Pin its trailing and bottom anchors to your safe area.
@available(iOS 15.0, *)
public final class BusymateLauncherView: BusymateHostedView {
    public init(title: String? = nil, action: (() -> Void)? = nil) {
        super.init(AnyView(BusymateLauncher(title: title, action: action)))
    }
}
