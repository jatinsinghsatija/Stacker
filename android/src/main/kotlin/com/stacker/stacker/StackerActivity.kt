package com.stacker.stacker

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Hosts the Stacker dashboard as a standalone Android activity.
 *
 * This is what the debug launcher icon opens, and what an explicit intent from
 * anywhere in a native app targets. It runs its own cached Flutter engine
 * whose entry point is `stackerDashboardMain`, so a pure-native app can show
 * the dashboard without having a Flutter UI of its own.
 *
 * Launch it with [intent] or [launch] rather than constructing the intent by
 * hand, so the extras stay in one place.
 */
class StackerActivity : FlutterActivity() {

    companion object {
        /** Extra naming the tab to open: `api`, `crashes`, or `leaks`. */
        const val EXTRA_INITIAL_TAB = "com.stacker.INITIAL_TAB"

        /** Id under which the dashboard engine is cached across launches. */
        const val ENGINE_ID = "stacker_dashboard_engine"

        /** Dart entry point annotated with `@pragma('vm:entry-point')`. */
        private const val DART_ENTRYPOINT = "stackerDashboardMain"

        /**
         * Builds an intent that opens the dashboard.
         *
         * ```kotlin
         * startActivity(StackerActivity.intent(this, "crashes"))
         * ```
         */
        @JvmStatic
        @JvmOverloads
        fun intent(context: Context, initialTab: String = "api"): Intent {
            return Intent(context, StackerActivity::class.java)
                .putExtra(EXTRA_INITIAL_TAB, initialTab)
        }

        /** Starts the dashboard activity. */
        @JvmStatic
        @JvmOverloads
        fun launch(context: Context, initialTab: String = "api") {
            val launchIntent = intent(context, initialTab).apply {
                // Needed when launching from a non-activity context, e.g. a
                // service or an Application subclass.
                if (context !is android.app.Activity) {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            }
            context.startActivity(launchIntent)
        }

        /**
         * Warms the dashboard engine so the first launch is not slow.
         *
         * Optional. Call from `Application.onCreate` in a debug build if the
         * roughly one-second cold start of the Flutter engine is noticeable.
         */
        @JvmStatic
        fun warmUp(context: Context) {
            if (FlutterEngineCache.getInstance().get(ENGINE_ID) != null) return
            val engine = FlutterEngine(context.applicationContext)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    io.flutter.FlutterInjector.instance()
                        .flutterLoader()
                        .findAppBundlePath(),
                    DART_ENTRYPOINT,
                ),
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Warm the engine before super.onCreate so getCachedEngineId finds it.
        warmUp(this)
        super.onCreate(savedInstanceState)
    }

    override fun getCachedEngineId(): String = ENGINE_ID

    /**
     * Keep the engine alive between launches.
     *
     * Destroying it would drop every buffered record, which is exactly the
     * data the user came to look at.
     */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun getInitialRoute(): String {
        val tab = intent.getStringExtra(EXTRA_INITIAL_TAB) ?: "api"
        return "/stacker/$tab"
    }
}
