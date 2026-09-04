package com.stacker.stacker

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.widget.Toast
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android host side of the Stacker plugin.
 *
 * Serves three roles:
 *  * answers the Dart-initiated method calls (debug detection, launcher icon
 *    toggling, opening the dashboard, native toasts);
 *  * streams records captured by the native interceptors up to Dart via an
 *    event channel;
 *  * keeps [StackerBridge] in step with whether Dart is capturing.
 */
class StackerPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    EventChannel.StreamHandler {

    private companion object {
        const val METHOD_CHANNEL = "com.stacker/stacker"
        const val EVENT_CHANNEL = "com.stacker/stacker_events"

        /**
         * Fully qualified name of the launcher alias declared in the host
         * manifest. Toggling this component is what shows and hides the
         * separate dashboard icon.
         */
        const val LAUNCHER_ALIAS = "com.stacker.stacker.StackerLauncherAlias"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var applicationContext: Context

    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    // -- FlutterPlugin --------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        StackerBridge.detachSink()
    }

    // -- ActivityAware --------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    // -- EventChannel.StreamHandler -------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (events != null) {
            StackerBridge.attachSink { event -> events.success(event) }
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        StackerBridge.detachSink()
    }

    // -- MethodCallHandler ----------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isHostDebugBuild" -> result.success(isDebuggable())

            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                StackerBridge.setEnabled(enabled)
                if (enabled) {
                    // A native app benefits from crash capture even when it
                    // never calls install() itself.
                    StackerCrashHandler.install()
                }
                result.success(null)
            }

            "setLauncherIconVisible" -> {
                val visible = call.argument<Boolean>("visible") ?: false
                result.success(setLauncherIconVisible(visible))
            }

            "openDashboard" -> {
                val tab = call.argument<String>("initialTab") ?: "api"
                val host = activity ?: applicationContext
                runCatching { StackerActivity.launch(host, tab) }
                    .onSuccess { result.success(null) }
                    .onFailure { error ->
                        result.error(
                            "OPEN_DASHBOARD_FAILED",
                            error.message,
                            null,
                        )
                    }
            }

            "showNativeToast" -> {
                val message = call.argument<String>("message") ?: ""
                if (message.isNotEmpty()) {
                    Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT)
                        .show()
                }
                result.success(null)
            }

            "drainBufferedRecords" -> result.success(StackerBridge.drainBuffer())

            else -> result.notImplemented()
        }
    }

    /**
     * Whether the *host application* is debuggable.
     *
     * Read from the manifest flag rather than `BuildConfig.DEBUG`, because
     * this library's own build type says nothing about the app embedding it —
     * a release-built AAR is routinely consumed by a debug app.
     */
    private fun isDebuggable(): Boolean {
        return (applicationContext.applicationInfo.flags and
            ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    /**
     * Enables or disables the launcher alias, which adds or removes the
     * separate dashboard icon from the launcher.
     *
     * Returns `false` when the host manifest does not declare the alias — an
     * app that only wants the in-app bubble can skip that manifest entry, and
     * this is not an error.
     */
    private fun setLauncherIconVisible(visible: Boolean): Boolean {
        // Never expose the icon in a release build, even if asked. A debug
        // inspector on a shipped app is a data-disclosure problem.
        if (visible && !isDebuggable()) return false

        val component = ComponentName(applicationContext.packageName, LAUNCHER_ALIAS)
        val newState = if (visible) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        return runCatching {
            applicationContext.packageManager.setComponentEnabledSetting(
                component,
                newState,
                PackageManager.DONT_KILL_APP,
            )
            true
        }.getOrDefault(false)
    }
}
