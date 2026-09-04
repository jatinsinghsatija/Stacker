package com.stacker.stacker

import java.io.PrintWriter
import java.io.StringWriter
import java.util.UUID

/**
 * Captures uncaught JVM exceptions into the Stacker dashboard.
 *
 * A native Android app installs this once, typically in `Application.onCreate`:
 *
 * ```kotlin
 * StackerCrashHandler.install()
 * ```
 *
 * The previously installed handler is always invoked afterwards, so the
 * platform's default "app has stopped" dialog, Crashlytics, and any other
 * reporter keep working exactly as before.
 *
 * ### An honest caveat
 *
 * When an uncaught exception reaches this handler, the process is about to be
 * torn down. The record is forwarded to the Flutter engine on a best-effort
 * basis, so a crash on a background thread with the dashboard already open is
 * usually delivered — but a crash during startup, before the engine attaches,
 * generally is not: the buffer lives in the dying process. Records are held in
 * memory only and do not survive the crash. For post-mortem crash reporting
 * that survives a restart, use Crashlytics or Play Console alongside Stacker.
 */
object StackerCrashHandler {

    private var previous: Thread.UncaughtExceptionHandler? = null

    @Volatile
    private var installed = false

    /** Whether [install] has run. */
    @JvmStatic
    val isInstalled: Boolean
        get() = installed

    /** Installs the handler. Safe to call more than once. */
    @JvmStatic
    @Synchronized
    fun install() {
        if (installed) return
        installed = true
        previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            report(thread, throwable)
            // Preserve the existing crash pipeline.
            previous?.uncaughtException(thread, throwable)
        }
    }

    /** Restores the handler that was in place before [install]. */
    @JvmStatic
    @Synchronized
    fun uninstall() {
        if (!installed) return
        installed = false
        Thread.setDefaultUncaughtExceptionHandler(previous)
        previous = null
    }

    /**
     * Records a caught exception the app recovered from.
     *
     * @param context what the app was doing, shown in the dashboard.
     */
    @JvmStatic
    @JvmOverloads
    fun recordNonFatal(
        throwable: Throwable,
        context: String? = null,
        metadata: Map<String, String> = emptyMap(),
    ) {
        if (!StackerBridge.isEnabled) return
        runCatching {
            StackerBridge.sendCrash(
                payloadOf(
                    throwable = throwable,
                    threadName = Thread.currentThread().name,
                    severity = "nonFatal",
                    context = context,
                    metadata = metadata,
                ),
            )
        }
    }

    private fun report(thread: Thread, throwable: Throwable) {
        if (!StackerBridge.isEnabled) return
        runCatching {
            StackerBridge.sendCrash(
                payloadOf(
                    throwable = throwable,
                    threadName = thread.name,
                    severity = "fatal",
                    context = "Uncaught exception on thread ${thread.name}",
                    metadata = emptyMap(),
                ),
            )
        }
    }

    private fun payloadOf(
        throwable: Throwable,
        threadName: String,
        severity: String,
        context: String?,
        metadata: Map<String, String>,
    ): Map<String, Any?> = buildMap {
        put("id", "android-crash-${UUID.randomUUID()}")
        put("timestamp", System.currentTimeMillis())
        put("error", "${throwable.javaClass.name}: ${throwable.message ?: ""}".trim())
        put("stackTrace", stackTraceOf(throwable))
        put("source", "androidNative")
        put("severity", severity)
        put("isolateName", threadName)
        put("context", context)
        put("metadata", metadata)
    }

    private fun stackTraceOf(throwable: Throwable): String {
        val writer = StringWriter()
        PrintWriter(writer).use { printer ->
            // printStackTrace includes the full "Caused by" chain.
            throwable.printStackTrace(printer)
        }
        return writer.toString()
    }
}
