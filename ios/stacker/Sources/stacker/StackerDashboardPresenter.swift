import Flutter
import UIKit

/// Presents the Stacker dashboard from native iOS code.
///
/// This is the iOS counterpart to `StackerActivity` on Android: it lets a
/// pure-native app open the dashboard without having a Flutter UI of its own.
///
/// ```swift
/// StackerDashboardPresenter.shared.present(initialTab: "crashes")
/// ```
///
/// A dedicated `FlutterEngine` is cached and reused, so records survive
/// closing and reopening the dashboard — dropping the engine would discard
/// exactly the data the user came to inspect.
@objc public final class StackerDashboardPresenter: NSObject {

    /// The shared presenter.
    @objc public static let shared = StackerDashboardPresenter()

    /// Dart entry point annotated with `@pragma('vm:entry-point')`.
    private static let dartEntrypoint = "stackerDashboardMain"

    private var engine: FlutterEngine?
    private weak var presentedController: UIViewController?

    private override init() {
        super.init()
    }

    /// Starts the dashboard engine without showing anything.
    ///
    /// Optional. Call during launch in a debug build if the roughly
    /// one-second cold start of a Flutter engine is noticeable.
    @objc public func warmUp() {
        _ = ensureEngine(initialRoute: "/stacker/api")
    }

    /// Presents the dashboard modally.
    ///
    /// - Parameters:
    ///   - initialTab: `api`, `crashes`, or `leaks`.
    ///   - presenter: the controller to present from. Defaults to the
    ///     top-most controller of the active window.
    @objc public func present(
        initialTab: String = "api",
        from presenter: UIViewController? = nil
    ) {
        guard let host = presenter ?? Self.topViewController() else {
            NSLog("[Stacker] No view controller available to present from")
            return
        }

        // Presenting twice would stack two dashboards over each other.
        if let existing = presentedController, existing.presentingViewController != nil {
            return
        }

        let engine = ensureEngine(initialRoute: "/stacker/\(initialTab)")
        let controller = FlutterViewController(
            engine: engine,
            nibName: nil,
            bundle: nil
        )
        controller.modalPresentationStyle = .fullScreen

        // The dashboard has its own app bar but no way back to the host app,
        // so a native Close button is layered on top.
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.layer.cornerRadius = 15
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(
            self,
            action: #selector(dismissDashboard),
            for: .touchUpInside
        )
        controller.view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(
                equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor,
                constant: -12
            ),
            closeButton.bottomAnchor.constraint(
                equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor,
                constant: -16
            ),
            closeButton.widthAnchor.constraint(equalToConstant: 74),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        presentedController = controller
        host.present(controller, animated: true)
    }

    /// Dismisses the dashboard if it is showing.
    @objc public func dismissDashboard() {
        presentedController?.dismiss(animated: true)
        presentedController = nil
    }

    /// Returns the cached engine, starting it on first use.
    ///
    /// The initial route can only be set before the engine runs, so a later
    /// call with a different tab reuses the engine and opens on its original
    /// tab. The dashboard's own tab bar covers navigating from there.
    private func ensureEngine(initialRoute: String) -> FlutterEngine {
        if let engine {
            return engine
        }
        let newEngine = FlutterEngine(name: "stacker_dashboard_engine")
        newEngine.run(
            withEntrypoint: Self.dartEntrypoint,
            initialRoute: initialRoute
        )
        // Register the plugin so the dashboard engine can talk to the host.
        StackerPlugin.register(
            with: newEngine.registrar(forPlugin: "StackerPlugin")!
        )
        engine = newEngine
        return newEngine
    }

    /// Finds the top-most view controller of the active window.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
            ?? scenes.first?.windows.first

        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
