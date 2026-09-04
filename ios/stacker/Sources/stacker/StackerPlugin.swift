import Flutter
import UIKit

/// iOS host side of the Stacker plugin.
///
/// Serves three roles:
///  * answers the Dart-initiated method calls (debug detection, opening the
///    dashboard, native toasts);
///  * streams records captured by the native capture points up to Dart via an
///    event channel;
///  * keeps `StackerBridge` in step with whether Dart is capturing.
public class StackerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private static let methodChannelName = "com.stacker/stacker"
    private static let eventChannelName = "com.stacker/stacker_events"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = StackerPlugin()

        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - FlutterPlugin

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "isHostDebugBuild":
            result(Self.isDebugBuild())

        case "setEnabled":
            let arguments = call.arguments as? [String: Any]
            let enabled = arguments?["enabled"] as? Bool ?? false
            StackerBridge.shared.setEnabled(enabled)
            result(nil)

        case "setLauncherIconVisible":
            // iOS has no runtime equivalent of Android's activity-alias
            // toggling. An alternate app icon is declared in Info.plist and
            // can only be swapped with setAlternateIconName, which shows a
            // system alert every time — unusable for a debug tool. The README
            // documents the debug-only Info.plist approach instead.
            result(false)

        case "openDashboard":
            let arguments = call.arguments as? [String: Any]
            let tab = arguments?["initialTab"] as? String ?? "api"
            DispatchQueue.main.async {
                StackerDashboardPresenter.shared.present(initialTab: tab)
            }
            result(nil)

        case "showNativeToast":
            let arguments = call.arguments as? [String: Any]
            let message = arguments?["message"] as? String ?? ""
            if !message.isEmpty {
                DispatchQueue.main.async {
                    Self.showToast(message)
                }
            }
            result(nil)

        case "drainBufferedRecords":
            result(StackerBridge.shared.drainBuffer())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        StackerBridge.shared.attachSink { event in
            events(event)
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        StackerBridge.shared.detachSink()
        return nil
    }

    // MARK: - Helpers

    /// Whether this is a debug build.
    ///
    /// `DEBUG` is defined by the Xcode Debug configuration. Because the plugin
    /// compiles as part of the host app's build on iOS (unlike Android's
    /// prebuilt AAR), this correctly reflects the *host's* configuration.
    private static func isDebugBuild() -> Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }

    /// Shows a brief Android-style toast.
    ///
    /// iOS has no toast primitive, so this is a self-dismissing label pinned
    /// near the bottom of the key window.
    private static func showToast(_ message: String) {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        guard let window = scenes
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
        else {
            return
        }

        let label = PaddedLabel()
        label.text = message
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        label.numberOfLines = 2
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false

        window.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            label.bottomAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            ),
            label.leadingAnchor.constraint(
                greaterThanOrEqualTo: window.leadingAnchor,
                constant: 16
            ),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: window.trailingAnchor,
                constant: -16
            ),
        ])

        UIView.animate(
            withDuration: 0.2,
            delay: 2.4,
            options: [],
            animations: { label.alpha = 0 },
            completion: { _ in label.removeFromSuperview() }
        )
    }
}

/// A label with internal padding, so the toast text is not flush to its edges.
private final class PaddedLabel: UILabel {

    private let inset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

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
