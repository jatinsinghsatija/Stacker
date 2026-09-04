import UIKit

/// Zero-configuration entry points to the dashboard for native iOS hosts.
///
/// iOS cannot do what Stacker does on Android. There is no equivalent of an
/// `activity-alias`, so a library cannot add a second home-screen icon: the
/// only supported mechanism is `setAlternateIconName`, which swaps the app's
/// *own* icon and shows a system alert every time it is called. That is
/// unusable for a debug tool.
///
/// Instead this gives a native host two ways in, both enabled with one call:
///
///  * **Shake the device** — the standard iOS debug-menu gesture. Works from
///    any screen, including ones with no Stacker UI on them.
///  * **A floating bubble** — a draggable button pinned above the app's own
///    UI, mirroring what `StackerOverlay` provides inside Flutter.
///
/// ```swift
/// #if DEBUG
/// StackerAutoAttach.enable()
/// #endif
/// ```
///
/// Everything here is a no-op unless `StackerBridge.shared.isEnabled` is
/// `true`, so leaving the call in a release build costs nothing — though
/// wrapping it in `#if DEBUG` is still the clearer habit.
@objc public final class StackerAutoAttach: NSObject {

    /// Whether [enable] has run.
    @objc public private(set) static var isEnabled = false

    private static var bubble: StackerBubbleWindow?

    /// Installs the shake gesture and, unless disabled, the floating bubble.
    ///
    /// - Parameter showBubble: pass `false` for the shake gesture only, when
    ///   a persistent on-screen button would get in the way of UI work.
    @objc public static func enable(showBubble: Bool = true) {
        guard !isEnabled else { return }
        isEnabled = true

        // Capture is on for the whole process from here, which is what lets
        // StackerURLProtocol and StackerCrashHandler start recording.
        StackerBridge.shared.setEnabled(true)
        StackerURLProtocol.registerGlobally()

        UIWindow.stackerInstallShakeHook()

        if showBubble {
            // Deferred to the next runloop turn: at the point a host calls
            // this from `didFinishLaunchingWithOptions`, no window is key yet
            // and the bubble would have nothing to attach to.
            DispatchQueue.main.async {
                bubble = StackerBubbleWindow()
                bubble?.show()
            }
        }
    }

    /// Removes the bubble and stops the shake gesture opening the dashboard.
    @objc public static func disable() {
        guard isEnabled else { return }
        isEnabled = false
        bubble?.hide()
        bubble = nil
        StackerURLProtocol.unregisterGlobally()
        StackerBridge.shared.setEnabled(false)
    }

    /// Opens the dashboard. Safe to call from anywhere, on any thread.
    @objc public static func openDashboard(initialTab: String = "api") {
        DispatchQueue.main.async {
            StackerDashboardPresenter.shared.present(initialTab: initialTab)
        }
    }
}

// MARK: - Shake gesture

extension UIWindow {

    private static var stackerShakeInstalled = false

    /// Swizzles `motionEnded` so a shake anywhere in the app opens the
    /// dashboard.
    ///
    /// Swizzling is confined to this single, stable UIKit method rather than
    /// anything in `URLSession`, and the original implementation is always
    /// invoked afterwards — so an app that already handles shake (many do,
    /// for their own debug menus) keeps working.
    static func stackerInstallShakeHook() {
        guard !stackerShakeInstalled else { return }
        stackerShakeInstalled = true

        let original = #selector(UIResponder.motionEnded(_:with:))
        let swizzled = #selector(UIWindow.stacker_motionEnded(_:with:))

        guard
            let originalMethod = class_getInstanceMethod(UIWindow.self, original),
            let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzled)
        else {
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    @objc private func stacker_motionEnded(
        _ motion: UIEvent.EventSubtype,
        with event: UIEvent?
    ) {
        if motion == .motionShake, StackerBridge.shared.isEnabled {
            StackerDashboardPresenter.shared.present(initialTab: "api")
        }
        // Because the implementations were exchanged, this call now reaches
        // the *original* motionEnded — the host's own shake handling still runs.
        stacker_motionEnded(motion, with: event)
    }
}

// MARK: - Floating bubble

/// A borderless always-on-top window holding the draggable dashboard button.
///
/// A separate `UIWindow` rather than a subview of the app's own hierarchy, so
/// the button survives the host pushing, presenting, and replacing view
/// controllers, and never appears in the host's own view debugging.
final class StackerBubbleWindow: UIWindow {

    private let button = UIButton(type: .custom)
    private var dragOffset: CGPoint = .zero

    init() {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
        {
            super.init(windowScene: scene)
        } else {
            super.init(frame: UIScreen.main.bounds)
        }
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func configure() {
        // Sized to the button only. A full-screen window would swallow every
        // touch in the host app.
        frame = CGRect(x: UIScreen.main.bounds.width - 74, y: 160, width: 56, height: 56)
        windowLevel = .alert + 1
        backgroundColor = .clear
        isHidden = true

        // A window needs a root controller or UIKit logs a warning and
        // rotation behaves oddly.
        let host = UIViewController()
        host.view.backgroundColor = .clear
        rootViewController = host

        button.frame = bounds
        button.backgroundColor = UIColor(red: 0.16, green: 0.38, blue: 1.0, alpha: 1.0)
        button.layer.cornerRadius = 28
        button.setTitle("≡", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 26, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowRadius = 6
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.addTarget(self, action: #selector(openDashboard), for: .touchUpInside)
        button.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        )
        host.view.addSubview(button)
    }

    func show() {
        isHidden = false
    }

    func hide() {
        isHidden = true
    }

    @objc private func openDashboard() {
        StackerDashboardPresenter.shared.present(initialTab: "api")
    }

    @objc private func handleDrag(_ gesture: UIPanGestureRecognizer) {
        guard let screen = windowScene?.screen ?? UIScreen.main as UIScreen? else { return }
        let translation = gesture.translation(in: nil)

        var newOrigin = CGPoint(
            x: frame.origin.x + translation.x,
            y: frame.origin.y + translation.y
        )
        // Clamp so the bubble can never be dragged off-screen and stranded.
        newOrigin.x = min(max(0, newOrigin.x), screen.bounds.width - frame.width)
        newOrigin.y = min(max(0, newOrigin.y), screen.bounds.height - frame.height)

        frame.origin = newOrigin
        gesture.setTranslation(.zero, in: nil)
    }

    /// Only the button itself is interactive; every other point falls through
    /// to the app underneath.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        button.frame.contains(point)
    }
}
