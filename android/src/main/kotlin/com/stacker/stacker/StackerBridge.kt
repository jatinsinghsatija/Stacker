package com.stacker.stacker

import android.os.Handler
import android.os.Looper
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Process-wide funnel between the native interceptors and the Flutter engine.
 *
 * The native side has no direct handle on the Dart isolate, and the engine may
 * not even be running when an OkHttp call happens — a native app can issue
 * requests during startup, long before any Flutter view is attached. So records
 * go here first:
 *
 *  * when the event sink is attached, they are forwarded straight through;
 *  * when it is not, they are buffered (bounded, oldest evicted) and handed
 *    over the moment Dart calls `drainBufferedRecords`.
 *
 * Everything is synchronised on [lock] because interceptors run on arbitrary
 * OkHttp dispatcher threads while the sink is only safe to touch on the main
 * thread.
 */
internal object StackerBridge {

    /** Maximum records held while no sink is attached. */
    private const val MAX_BUFFERED = 200

    private val lock = Any()
    private val buffer = ArrayDeque<Map<String, Any?>>()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Set by the plugin while the Dart event channel is listening. */
    @Volatile
    private var sink: ((Map<String, Any?>) -> Unit)? = null

    /**
     * Whether capture is on.
     *
     * Defaults to `false` so an interceptor left in a release build costs
     * nothing until Dart explicitly enables it — and Dart only does that in a
     * debug build.
     */
    private val enabled = AtomicBoolean(false)

    /** Whether the native interceptors should record. */
    val isEnabled: Boolean
        get() = enabled.get()

    fun setEnabled(value: Boolean) {
        enabled.set(value)
        if (!value) {
            synchronized(lock) { buffer.clear() }
        }
    }

    /** Attaches the Dart event sink and flushes anything buffered. */
    fun attachSink(newSink: (Map<String, Any?>) -> Unit) {
        val pending: List<Map<String, Any?>>
        synchronized(lock) {
            sink = newSink
            pending = buffer.toList()
            buffer.clear()
        }
        pending.forEach { event -> post(newSink, event) }
    }

    fun detachSink() {
        synchronized(lock) { sink = null }
    }

    /** Hands over and clears the buffer, for the Dart-side drain call. */
    fun drainBuffer(): List<Map<String, Any?>> = synchronized(lock) {
        val copy = buffer.toList()
        buffer.clear()
        copy
    }

    /** Reports a captured API call. */
    fun sendApi(payload: Map<String, Any?>) = send("api", payload)

    /** Reports a captured crash. */
    fun sendCrash(payload: Map<String, Any?>) = send("crash", payload)

    /** Reports a captured leak. */
    fun sendLeak(payload: Map<String, Any?>) = send("leak", payload)

    private fun send(type: String, payload: Map<String, Any?>) {
        if (!isEnabled) return
        val event = mapOf("type" to type, "payload" to payload)
        val current = sink
        if (current != null) {
            post(current, event)
            return
        }
        synchronized(lock) {
            // Re-check: the sink may have attached between the read and here.
            val recheck = sink
            if (recheck != null) {
                post(recheck, event)
                return
            }
            while (buffer.size >= MAX_BUFFERED) {
                buffer.pollFirst()
            }
            buffer.addLast(event)
        }
    }

    /** Event sinks must be called on the main thread. */
    private fun post(target: (Map<String, Any?>) -> Unit, event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            target(event)
        } else {
            mainHandler.post { target(event) }
        }
    }
}
