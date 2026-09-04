import Foundation

/// Captures uncaught Objective-C exceptions and fatal signals on iOS.
///
/// Install once, early in `application(_:didFinishLaunchingWithOptions:)`:
///
/// ```swift
/// StackerCrashHandler.install()
/// ```
///
/// ## What is captured
///
/// * **`NSException`** — an uncaught Objective-C exception, via
///   `NSSetUncaughtExceptionHandler`. Full call stack included.
/// * **Fatal signals** — `SIGABRT`, `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`,
///   `SIGTRAP`, via `sigaction`. These cover a Swift `fatalError`, a forced
///   unwrap of `nil`, and an array-bounds trap.
///
/// ## Honest limitations
///
/// Read this before relying on it as a crash reporter:
///
/// 1. **A signal handler must only call async-signal-safe functions.** Sending
///    a record over a Flutter method channel is emphatically not one of them.
///    So the signal path records a minimal payload and, if the Flutter engine
///    happens to still be alive, forwards it — but the process is already
///    dying and delivery is not guaranteed.
/// 2. **Records are in-memory only.** They do not survive the crash. Reopening
///    the app shows an empty crash list.
/// 3. **Installing a handler conflicts with Crashlytics, Sentry, and Bugsnag.**
///    Those SDKs install their own handlers; whichever installs last wins for
///    the signal path. This class chains to a previously installed
///    `NSException` handler, but POSIX signal chaining is inherently lossy.
///
/// **Recommendation:** if the app already uses a real crash reporter, do not
/// call [install]. Use `StackerCrashHandler.recordNonFatal(_:)` for handled
/// errors instead, and let the dedicated SDK own fatal crashes. Stacker's
/// crash tab is then a live view of Flutter-side errors during a debug
/// session, which is what it is genuinely good at.
@objc public final class StackerCrashHandler: NSObject {

    private static var previousExceptionHandler:
        (@convention(c) (NSException) -> Void)?
    private static var installed = false
    private static let signals: [Int32] = [
        SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP,
    ]

    /// Whether [install] has run.
    @objc public static var isInstalled: Bool { installed }

    /// Installs the exception and signal handlers. Safe to call twice.
    ///
    /// See the type documentation for why you may not want to call this at all
    /// when another crash reporter is present.
    @objc public static func install() {
        guard !installed else { return }
        installed = true

        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            StackerCrashHandler.report(exception: exception)
            // Preserve any existing reporter's handler.
            StackerCrashHandler.previousExceptionHandler?(exception)
        }

        for signalValue in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { received in
                StackerCrashHandler.report(signal: received)
                // Restore the default action and re-raise so the OS still
                // produces its normal crash report and the process dies as
                // it otherwise would.
                signal(received, SIG_DFL)
                raise(received)
            }
            sigemptyset(&action.sa_mask)
            action.sa_flags = 0
            sigaction(signalValue, &action, nil)
        }
    }

    /// Restores the default handlers.
    @objc public static func uninstall() {
        guard installed else { return }
        installed = false
        NSSetUncaughtExceptionHandler(previousExceptionHandler)
        previousExceptionHandler = nil
        for signalValue in signals {
            signal(signalValue, SIG_DFL)
        }
    }

    /// Records a caught error the app recovered from.
    ///
    /// This path is fully reliable — it runs on a healthy process — and is the
    /// recommended way to use this class.
    @objc public static func recordNonFatal(
        _ error: Error,
        context: String? = nil,
        metadata: [String: String] = [:]
    ) {
        guard StackerBridge.shared.isEnabled else { return }
        let nsError = error as NSError
        var payload: [String: Any] = [
            "id": "ios-crash-\(UUID().uuidString)",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "error": "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)",
            "stackTrace": Thread.callStackSymbols.joined(separator: "\n"),
            "source": "iosNative",
            "severity": "nonFatal",
            "metadata": metadata,
        ]
        if let context {
            payload["context"] = context
        }
        StackerBridge.shared.sendCrash(payload)
    }

    private static func report(exception: NSException) {
        guard StackerBridge.shared.isEnabled else { return }
        let name = exception.name.rawValue
        let reason = exception.reason ?? ""
        StackerBridge.shared.sendCrash([
            "id": "ios-crash-\(UUID().uuidString)",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "error": "\(name): \(reason)",
            "stackTrace": exception.callStackSymbols.joined(separator: "\n"),
            "source": "iosNative",
            "severity": "fatal",
            "context": "Uncaught NSException",
        ])
    }

    /// Signal path. Deliberately minimal — see the type documentation.
    private static func report(signal received: Int32) {
        guard StackerBridge.shared.isEnabled else { return }
        let name = signalName(received)
        StackerBridge.shared.sendCrash([
            "id": "ios-signal-\(received)-\(Int(Date().timeIntervalSince1970 * 1000))",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "error": "Fatal signal \(received) (\(name))",
            "stackTrace": Thread.callStackSymbols.joined(separator: "\n"),
            "source": "iosNative",
            "severity": "fatal",
            "context": "Fatal signal — delivery to the dashboard is best-effort "
                + "because the process is terminating",
        ])
    }

    private static func signalName(_ value: Int32) -> String {
        switch value {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS: return "SIGBUS"
        case SIGILL: return "SIGILL"
        case SIGFPE: return "SIGFPE"
        case SIGTRAP: return "SIGTRAP"
        default: return "UNKNOWN"
        }
    }
}
