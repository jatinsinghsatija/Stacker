import Foundation

/// Process-wide funnel between the native capture points and the Flutter engine.
///
/// The native side has no direct handle on the Dart isolate, and the engine may
/// not be running at all when a `URLSession` call happens — a native app can
/// issue requests during launch, long before any Flutter view exists. So
/// records go here first:
///
///  * when the event sink is attached, they are forwarded straight through;
///  * when it is not, they are buffered (bounded, oldest evicted) and handed
///    over when Dart calls `drainBufferedRecords`.
///
/// All mutable state is guarded by a serial queue, because capture happens on
/// arbitrary `URLSession` delegate queues while the sink is only safe to touch
/// on the main thread.
@objc public final class StackerBridge: NSObject {

    /// The shared instance. Capture points and the plugin both use this.
    @objc public static let shared = StackerBridge()

    /// Maximum records held while no sink is attached.
    private static let maxBuffered = 200

    private let queue = DispatchQueue(label: "com.stacker.bridge")
    private var buffer: [[String: Any]] = []
    private var sink: (([String: Any]) -> Void)?

    /// Whether capture is on.
    ///
    /// Defaults to `false` so a capture point left in a release build costs
    /// nothing until Dart explicitly enables it — and Dart only does that for
    /// a debug build.
    private var enabledStorage = false

    private override init() {
        super.init()
    }

    /// Whether the native capture points should record.
    @objc public var isEnabled: Bool {
        queue.sync { enabledStorage }
    }

    @objc public func setEnabled(_ value: Bool) {
        queue.sync {
            enabledStorage = value
            if !value {
                buffer.removeAll()
            }
        }
    }

    /// Attaches the Dart event sink and flushes anything buffered.
    func attachSink(_ newSink: @escaping ([String: Any]) -> Void) {
        let pending: [[String: Any]] = queue.sync {
            sink = newSink
            let copy = buffer
            buffer.removeAll()
            return copy
        }
        for event in pending {
            deliver(event, to: newSink)
        }
    }

    func detachSink() {
        queue.sync { sink = nil }
    }

    /// Hands over and clears the buffer, for the Dart-side drain call.
    func drainBuffer() -> [[String: Any]] {
        queue.sync {
            let copy = buffer
            buffer.removeAll()
            return copy
        }
    }

    /// Reports a captured API call.
    @objc public func sendApi(_ payload: [String: Any]) {
        send(type: "api", payload: payload)
    }

    /// Reports a captured crash.
    @objc public func sendCrash(_ payload: [String: Any]) {
        send(type: "crash", payload: payload)
    }

    /// Reports a captured leak.
    @objc public func sendLeak(_ payload: [String: Any]) {
        send(type: "leak", payload: payload)
    }

    private func send(type: String, payload: [String: Any]) {
        let event: [String: Any] = ["type": type, "payload": payload]
        var target: (([String: Any]) -> Void)?

        queue.sync {
            guard enabledStorage else { return }
            if let current = sink {
                target = current
            } else {
                while buffer.count >= Self.maxBuffered {
                    buffer.removeFirst()
                }
                buffer.append(event)
            }
        }

        if let target {
            deliver(event, to: target)
        }
    }

    /// Event sinks must be called on the main thread.
    private func deliver(
        _ event: [String: Any],
        to target: @escaping ([String: Any]) -> Void
    ) {
        if Thread.isMainThread {
            target(event)
        } else {
            DispatchQueue.main.async { target(event) }
        }
    }
}
