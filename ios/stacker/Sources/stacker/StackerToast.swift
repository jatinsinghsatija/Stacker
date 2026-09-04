import UIKit

/// Shows a per-call toast in a **native iOS** host app, styled to match the
/// Flutter dashboard.
///
/// In a Flutter app the toast stack is drawn by `StackerOverlay`. A native
/// host has no Flutter widget tree on screen — the engine only runs while the
/// dashboard is presented — so that overlay can never appear. Without this, a
/// native iOS app captures everything correctly but shows nothing, which reads
/// as "the library is not working".
///
/// The design deliberately mirrors `_ToastCard` and `StackerAndroid`'s
/// `StackerToast`: the same dark surface, accent border, tinted status badge,
/// monospaced type scale and chevron affordance. A developer who sees the
/// Flutter and native versions on one project should not be able to tell them
/// apart.
///
/// Enabled via `StackerAutoAttach.enable`; a no-op until then.
@objc public final class StackerToast: NSObject {

    /// Toast policy, mirroring `ToastPolicy` on the Dart side.
    @objc public enum Policy: Int {
        /// A toast for every completed call.
        case all

        /// Only non-2xx responses and transport failures.
        case errorsOnly

        /// No toasts.
        case none
    }

    // Design tokens copied from StackerTheme. The card paints its own dark
    // surface, so the *dark* variant of each status colour is correct
    // regardless of the host app's appearance.
    private static let surface = UIColor(red: 0.106, green: 0.125, blue: 0.161, alpha: 0.94)
    private static let success = UIColor(red: 0.290, green: 0.871, blue: 0.502, alpha: 1)
    private static let redirect = UIColor(red: 0.655, green: 0.545, blue: 0.980, alpha: 1)
    private static let warn = UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)
    private static let errorColor = UIColor(red: 0.973, green: 0.443, blue: 0.443, alpha: 1)
    private static let neutral = UIColor(red: 0.580, green: 0.639, blue: 0.722, alpha: 1)

    /// How long a toast stays on screen, matching the Flutter default.
    private static let visibleDuration: TimeInterval = 3.0

    /// Bursts are coalesced so parallel requests cannot cover the screen.
    private static let maxVisible = 3

    private static var policy: Policy = .none
    private static var liveToasts: [UIView] = []

    /// Whether toasts are currently enabled.
    @objc public static var isEnabled: Bool { policy != .none }

    /// Configures the emitter. Called by `StackerAutoAttach.enable`.
    @objc public static func configure(policy: Policy) {
        self.policy = policy
    }

    /// Turns toasts off and removes any on screen.
    @objc public static func disable() {
        policy = .none
        DispatchQueue.main.async { dismissAll() }
    }

    /// Shows a toast for a completed call, if policy allows it.
    ///
    /// - Parameter statusCode: the HTTP status, or `nil` for a transport failure.
    @objc public static func showApiCall(
        method: String,
        path: String,
        statusCode: NSNumber?,
        durationMs: NSNumber?
    ) {
        let code = statusCode?.intValue
        let isError = code == nil || code! >= 400

        switch policy {
        case .none: return
        case .errorsOnly: if !isError { return }
        case .all: break
        }

        let badge = code.map(String.init) ?? "ERR"
        let accent = accentFor(code)
        var subtitle = code == nil ? "transport failure" : "completed"
        if let ms = durationMs?.intValue {
            subtitle += "  •  \(ms) ms"
        }

        onMain {
            show(badge: badge, title: "\(method) \(path)", subtitle: subtitle,
                 accent: accent, tab: "api")
        }
    }

    /// Shows a toast for a captured crash. Always shown when enabled.
    @objc public static func showCrash(errorType: String, fatal: Bool) {
        guard policy != .none else { return }
        onMain {
            show(
                badge: fatal ? "FATAL" : "WARN",
                title: errorType,
                subtitle: "tap to open the dashboard",
                accent: fatal ? errorColor : warn,
                tab: "crashes"
            )
        }
    }

    /// Mirrors `StackerTheme.statusColor` for the dark surface.
    private static func accentFor(_ statusCode: Int?) -> UIColor {
        guard let code = statusCode else { return errorColor }
        switch code {
        case 200..<300: return success
        case 300..<400: return redirect
        case 400..<500: return warn
        case 500...: return errorColor
        default: return neutral
        }
    }

    /// Builds and attaches the card. Main thread only.
    private static func show(
        badge: String,
        title: String,
        subtitle: String,
        accent: UIColor,
        tab: String
    ) {
        guard let window = keyWindow() else { return }

        let card = ToastCard(accent: accent, tab: tab)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = surface
        card.layer.cornerRadius = 10
        card.layer.borderWidth = 1
        card.layer.borderColor = accent.withAlphaComponent(0.55).cgColor
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.28
        card.layer.shadowRadius = 10
        card.layer.shadowOffset = CGSize(width: 0, height: 3)

        // Status badge.
        let badgeLabel = PaddedLabel()
        badgeLabel.text = badge
        badgeLabel.textColor = accent
        badgeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        badgeLabel.backgroundColor = accent.withAlphaComponent(0.16)
        badgeLabel.layer.cornerRadius = 4
        badgeLabel.clipsToBounds = true
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textAlignment = .left

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        subtitleLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.textAlignment = .left

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textColumn.axis = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 1

        let chevron = UILabel()
        chevron.text = "›"
        chevron.textColor = UIColor.white.withAlphaComponent(0.54)
        chevron.font = .systemFont(ofSize: 16, weight: .regular)

        let row = UIStackView(arrangedSubviews: [badgeLabel, textColumn, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false

        // The badge and chevron must hug their content while the text column
        // absorbs the remaining width. Without this, UIStackView distributes
        // space equally and the badge stretches across the card — verified on
        // a real native host before this was added.
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        textColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        card.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9),
        ])

        window.addSubview(card)

        // Stack upward from the bottom, newest lowest, like the Flutter column.
        let offset = CGFloat(liveToasts.count) * 58 + 12
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -8),
            card.bottomAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.bottomAnchor,
                constant: -offset
            ),
        ])

        liveToasts.append(card)
        while liveToasts.count > maxVisible, let oldest = liveToasts.first {
            dismiss(oldest)
        }

        card.alpha = 0
        UIView.animate(withDuration: 0.14) { card.alpha = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration) {
            dismiss(card)
        }
    }

    private static func dismiss(_ card: UIView) {
        guard let index = liveToasts.firstIndex(of: card) else { return }
        liveToasts.remove(at: index)
        UIView.animate(
            withDuration: 0.14,
            animations: { card.alpha = 0 },
            completion: { _ in card.removeFromSuperview() }
        )
    }

    private static func dismissAll() {
        liveToasts.forEach { card in
            card.removeFromSuperview()
        }
        liveToasts.removeAll()
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
            ?? scenes.first?.windows.first
    }

    private static func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}

/// The card view, which opens the dashboard when tapped.
private final class ToastCard: UIView {

    private let tab: String

    init(accent: UIColor, tab: String) {
        self.tab = tab
        super.init(frame: .zero)
        addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleTap))
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func handleTap() {
        removeFromSuperview()
        StackerDashboardPresenter.shared.present(initialTab: tab)
    }
}

/// A label with internal padding, for the status badge.
private final class PaddedLabel: UILabel {

    private let inset = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: inset))
    }

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(
            width: base.width + inset.left + inset.right,
            height: base.height + inset.top + inset.bottom
        )
    }
}
