package com.stacker.stacker

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.lang.ref.WeakReference

/**
 * Shows a per-call toast in a **native** host app, styled to match the Flutter
 * dashboard.
 *
 * In a Flutter app the toast stack is drawn by `StackerOverlay`. A native host
 * has no Flutter widget tree on screen — the engine only runs while the
 * dashboard activity is open — so that overlay can never appear.
 *
 * A platform [android.widget.Toast] was the obvious shortcut, but it looks
 * nothing like the Flutter version: a grey system pill with the system font,
 * no status colour, and not tappable. Since the same developer may see both on
 * the same project, the two must be visually the same component. This draws a
 * custom view into the foreground activity's content root instead, reusing the
 * exact colours, radii, and type scale from `StackerTheme` and `_ToastCard`.
 *
 * Enabled via [StackerAndroid.enable]; a no-op until then.
 */
object StackerToast {

    /** Toast policy, mirroring `ToastPolicy` on the Dart side. */
    enum class Policy {
        /** A toast for every completed call. */
        ALL,

        /** Only non-2xx responses and transport failures. */
        ERRORS_ONLY,

        /** No toasts. */
        NONE,
    }

    // Design tokens copied from StackerTheme so the two stay identical.
    // The card paints its own dark surface, so the *dark* variant of each
    // status colour is the correct one regardless of the host's theme.
    private const val SURFACE = 0xF01B2029.toInt()
    private const val SUCCESS = 0xFF4ADE80.toInt()
    private const val REDIRECT = 0xFFA78BFA.toInt()
    private const val WARN = 0xFFFBBF24.toInt()
    private const val ERROR = 0xFFF87171.toInt()
    private const val NEUTRAL = 0xFF94A3B8.toInt()

    /** How long a toast stays on screen, matching the Flutter default. */
    private const val VISIBLE_MS = 3_000L

    /** Bursts are coalesced so parallel requests cannot cover the screen. */
    private const val MAX_VISIBLE = 3

    private val mainHandler = Handler(Looper.getMainLooper())

    @SuppressLint("StaticFieldLeak")
    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var policy: Policy = Policy.NONE

    /**
     * The activity currently in the foreground.
     *
     * Weak so a backgrounded activity is never retained — this class outlives
     * every activity in the process.
     */
    private var currentActivity: WeakReference<Activity>? = null

    private val liveToasts = mutableListOf<View>()

    /** Whether toasts are currently enabled. */
    @JvmStatic
    val isEnabled: Boolean
        get() = policy != Policy.NONE && appContext != null

    /** Configures the emitter. Called by [StackerAndroid.enable]. */
    fun configure(context: Context, policy: Policy) {
        val app = context.applicationContext
        this.appContext = app
        this.policy = policy

        // The toast has to be added to whichever activity is in front, so the
        // lifecycle is tracked rather than requiring the host to pass one in.
        if (app is Application) {
            app.unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
            app.registerActivityLifecycleCallbacks(lifecycleCallbacks)
        }
    }

    /** Turns toasts off and releases every reference. */
    fun disable() {
        policy = Policy.NONE
        (appContext as? Application)?.unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
        mainHandler.post { dismissAll() }
        appContext = null
        currentActivity = null
    }

    /**
     * Shows a toast for a completed call, if policy allows it.
     *
     * @param statusCode the HTTP status, or `null` for a transport failure.
     */
    fun showApiCall(method: String, path: String, statusCode: Int?, durationMs: Long?) {
        val isError = statusCode == null || statusCode >= 400
        when (policy) {
            Policy.NONE -> return
            Policy.ERRORS_ONLY -> if (!isError) return
            Policy.ALL -> Unit
        }

        val badge = statusCode?.toString() ?: "ERR"
        val accent = accentFor(statusCode)
        val subtitle = buildString {
            append(if (statusCode == null) "transport failure" else "completed")
            durationMs?.let { append("  •  ${it} ms") }
        }

        post { show(badge, "$method $path", subtitle, accent, "api") }
    }

    /** Shows a toast for a captured crash. Always shown when enabled. */
    fun showCrash(errorType: String, fatal: Boolean) {
        if (policy == Policy.NONE) return
        val badge = if (fatal) "FATAL" else "WARN"
        val accent = if (fatal) ERROR else WARN
        post { show(badge, errorType, "tap to open the dashboard", accent, "crashes") }
    }

    /** Mirrors `StackerTheme.statusColor` for the dark surface. */
    private fun accentFor(statusCode: Int?): Int = when {
        statusCode == null -> ERROR
        statusCode in 200..299 -> SUCCESS
        statusCode in 300..399 -> REDIRECT
        statusCode in 400..499 -> WARN
        statusCode >= 500 -> ERROR
        else -> NEUTRAL
    }

    /**
     * Builds and attaches the card. Main thread only.
     *
     * Laid out to match `_ToastCard`: a rounded dark surface with a 1px accent
     * border, a tinted status badge, a monospace title, and a muted subtitle.
     */
    private fun show(
        badge: String,
        title: String,
        subtitle: String,
        accent: Int,
        tab: String,
    ) {
        val activity = currentActivity?.get() ?: return
        if (activity.isFinishing || activity.isDestroyed) return
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return

        val density = activity.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val card = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(9), dp(12), dp(9))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(10).toFloat()
                setColor(SURFACE)
                // 0.55 alpha on the accent, as in the Flutter card.
                setStroke(dp(1), Color.argb(140, Color.red(accent), Color.green(accent), Color.blue(accent)))
            }
            elevation = dp(6).toFloat()
            isClickable = true
            setOnClickListener {
                dismiss(this)
                StackerActivity.launch(activity, tab)
            }
        }

        card.addView(
            TextView(activity).apply {
                text = badge
                setTextColor(accent)
                typeface = Typeface.MONOSPACE
                setTypeface(typeface, Typeface.BOLD)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                setPadding(dp(6), dp(2), dp(6), dp(2))
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(4).toFloat()
                    // 0.16 alpha tint behind the badge.
                    setColor(Color.argb(41, Color.red(accent), Color.green(accent), Color.blue(accent)))
                }
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )

        val textColumn = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(9), 0, dp(4), 0)
        }
        textColumn.addView(
            TextView(activity).apply {
                text = title
                setTextColor(Color.WHITE)
                typeface = Typeface.MONOSPACE
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            },
        )
        if (subtitle.isNotEmpty()) {
            textColumn.addView(
                TextView(activity).apply {
                    text = subtitle
                    setTextColor(Color.argb(179, 255, 255, 255))
                    typeface = Typeface.MONOSPACE
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                },
            )
        }
        card.addView(
            textColumn,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )

        card.addView(
            TextView(activity).apply {
                text = "›"
                setTextColor(Color.argb(138, 255, 255, 255))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            },
        )

        // Stack upward from the bottom, newest lowest, like the Flutter column.
        val params = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply {
            gravity = Gravity.BOTTOM
            leftMargin = dp(8)
            rightMargin = dp(8)
            bottomMargin = dp(12) + liveToasts.size * dp(58)
        }

        root.addView(card, params)
        liveToasts.add(card)

        while (liveToasts.size > MAX_VISIBLE) {
            dismiss(liveToasts.first())
        }

        card.alpha = 0f
        card.animate().alpha(1f).setDuration(140).start()
        mainHandler.postDelayed({ dismiss(card) }, VISIBLE_MS)
    }

    private fun dismiss(card: View) {
        if (!liveToasts.remove(card)) return
        card.animate().alpha(0f).setDuration(140).withEndAction {
            (card.parent as? ViewGroup)?.removeView(card)
        }.start()
    }

    private fun dismissAll() {
        liveToasts.toList().forEach { dismiss(it) }
    }

    private fun post(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post(action)
        }
    }

    /**
     * Tracks the foreground activity.
     *
     * The dashboard activity is skipped: it draws its own Flutter UI and a
     * toast on top of it would be redundant, exactly as `showLauncherBubble`
     * and `toastPolicy` are disabled in the dashboard's own engine.
     */
    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(activity: Activity) {
            if (activity is StackerActivity) return
            currentActivity = WeakReference(activity)
        }

        override fun onActivityPaused(activity: Activity) {
            if (currentActivity?.get() === activity) {
                dismissAll()
                currentActivity = null
            }
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
        override fun onActivityStarted(activity: Activity) = Unit
        override fun onActivityStopped(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }
}
