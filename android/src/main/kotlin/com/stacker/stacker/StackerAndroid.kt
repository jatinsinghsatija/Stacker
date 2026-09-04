package com.stacker.stacker

import android.content.Context

/**
 * One-call setup for a **native Android** host app.
 *
 * Without this, a native host had to know to call three separate things —
 * `StackerCrashHandler.install()`, `StackerActivity.warmUp()`, and to add the
 * OkHttp interceptor — and even then got no per-call toasts, because those are
 * drawn by a Flutter widget that a native app never mounts.
 *
 * ```kotlin
 * class MyApplication : Application() {
 *     override fun onCreate() {
 *         super.onCreate()
 *         if (BuildConfig.DEBUG) {
 *             StackerAndroid.enable(this)
 *         }
 *     }
 * }
 * ```
 *
 * You still add the interceptor to your own `OkHttpClient`, because Stacker
 * cannot reach a client it did not build:
 *
 * ```kotlin
 * OkHttpClient.Builder()
 *     .addInterceptor(StackerOkHttpInterceptor())
 *     .build()
 * ```
 *
 * This is the native counterpart of `StackerAutoAttach.enable()` on iOS and of
 * `Stacker.init()` plus `StackerOverlay` in Flutter.
 */
object StackerAndroid {

    /** Whether [enable] has run. */
    @Volatile
    @JvmStatic
    var isEnabled: Boolean = false
        private set

    /**
     * Turns capture on and configures the debug affordances.
     *
     * @param context any context; the application context is retained.
     * @param toastPolicy which completed calls raise a toast. Defaults to
     *   [StackerToast.Policy.ALL] so a native integrator sees immediate
     *   feedback that capture is working — the single most common "is this
     *   even wired up?" question.
     * @param installCrashHandler whether to hook
     *   `Thread.setDefaultUncaughtExceptionHandler`. Pass `false` if you use
     *   Crashlytics, Sentry, or Bugsnag; see [StackerCrashHandler] for why.
     * @param warmUpDashboard whether to start the dashboard's Flutter engine
     *   eagerly. Costs ~1s of background work at launch and makes the first
     *   dashboard open instant.
     */
    @JvmStatic
    @JvmOverloads
    fun enable(
        context: Context,
        toastPolicy: StackerToast.Policy = StackerToast.Policy.ALL,
        installCrashHandler: Boolean = true,
        warmUpDashboard: Boolean = true,
    ) {
        if (isEnabled) return
        isEnabled = true

        // Capture must be on before any interceptor runs, or early requests
        // are silently dropped.
        StackerBridge.setEnabled(true)

        StackerToast.configure(context, toastPolicy)

        if (installCrashHandler) {
            StackerCrashHandler.install()
        }
        if (warmUpDashboard) {
            // Failure here is not fatal: the dashboard simply takes ~1s longer
            // to open the first time. Capture is unaffected, so this must not
            // bring down the host's Application.onCreate.
            runCatching { StackerActivity.warmUp(context) }
        }
    }

    /** Turns capture and toasts off, and restores the crash handler. */
    @JvmStatic
    fun disable() {
        if (!isEnabled) return
        isEnabled = false
        StackerToast.disable()
        StackerCrashHandler.uninstall()
        StackerBridge.setEnabled(false)
    }

    /** Opens the dashboard. Equivalent to tapping the launcher icon. */
    @JvmStatic
    @JvmOverloads
    fun openDashboard(context: Context, initialTab: String = "api") {
        StackerActivity.launch(context, initialTab)
    }
}
