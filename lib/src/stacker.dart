import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/id_generator.dart';
import 'core/stacker_config.dart';
import 'core/redactor.dart';
import 'core/service_locator.dart';
import 'data/models/api_record.dart';
import 'data/models/crash_record.dart';
import 'data/models/leak_record.dart';
import 'data/repository/stacker_repository.dart';
import 'data/sources/stacker_platform.dart';
import 'domain/crash_reporter.dart';
import 'domain/leak_detector.dart';
import 'interceptors/stacker_dio_interceptor.dart';
import 'interceptors/stacker_http_client.dart';
import 'presentation/screens/dashboard_screen.dart';

/// Entry point for the Stacker debug inspector.
///
/// Initialise once, as early as possible:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Stacker.init();
///   runApp(const MyApp());
/// }
/// ```
///
/// ## Release behaviour
///
/// Capture is gated on [kDebugMode] (plus the host's own debug flag, when the
/// Flutter engine is embedded in a native app). In a release build [init]
/// returns immediately without registering anything: no handlers are
/// installed, no timers run, and the interceptors become no-ops. Nothing needs
/// to be stripped from the call sites for a production build to be clean.
///
/// Override that gate with [StackerConfig.enabledOverride] only if you have
/// read the security note in the README.
abstract final class Stacker {
  static StackerConfig _config = const StackerConfig();
  static bool _enabled = false;
  static bool _initialised = false;
  static StreamSubscription<NativeRecordEvent>? _nativeSubscription;

  /// The active configuration.
  static StackerConfig get config => _config;

  /// Whether capture is currently active.
  ///
  /// `false` in release builds unless explicitly overridden. Guard any
  /// expensive debug-only work behind this rather than behind [kDebugMode],
  /// so an override is respected.
  static bool get isEnabled => _enabled;

  /// Whether [init] has run.
  static bool get isInitialised => _initialised;

  /// Initialises the library.
  ///
  /// Safe to call in a release build — it becomes a no-op. Calling it twice
  /// tears the first instance down before rebuilding, so hot restart works.
  static Future<void> init({StackerConfig config = const StackerConfig()}) async {
    _config = config;

    // Determine whether to capture. The host's flag wins when it is available,
    // because an embedded Flutter module's own build mode can differ from the
    // native app's.
    final override = config.enabledOverride;
    if (override != null) {
      _enabled = override;
    } else {
      final hostDebug = await StackerPlatform().isHostDebugBuild();
      _enabled = hostDebug ?? kDebugMode;
    }

    if (!_enabled) {
      // Leave the container empty so the interceptors resolve to no-ops.
      _initialised = true;
      return;
    }

    await StackerLocator.setUp(config);
    _initialised = true;

    // Let the interceptors find the container lazily, avoiding an import cycle.
    StackerHttpClient.bindGlobals(
      repository: () => StackerLocator.instance
          .isRegistered<StackerRepository>()
          ? StackerLocator.get<StackerRepository>()
          : null,
      redactor: () => StackerLocator.instance.isRegistered<Redactor>()
          ? StackerLocator.get<Redactor>()
          : null,
      idGenerator: () => StackerLocator.instance.isRegistered<IdGenerator>()
          ? StackerLocator.get<IdGenerator>()
          : null,
    );

    if (config.captureCrashes) {
      StackerLocator.get<CrashReporter>().install();
    }
    if (config.detectLeaks) {
      StackerLocator.get<LeakDetector>().start();
    }

    final platform = StackerLocator.get<StackerPlatform>();
    await platform.setEnabled(enabled: true);
    await platform.setLauncherIconVisible(visible: true);
    _listenToNative(platform);
    await _drainNativeBacklog(platform);
  }

  /// Tears the library down, restoring the previous error handlers.
  ///
  /// Rarely needed in an app; used by tests and by hosts that embed Flutter
  /// transiently and want the engine to shut down cleanly.
  static Future<void> dispose() async {
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    if (_enabled && StackerLocator.isReady) {
      await StackerLocator.get<StackerPlatform>().setEnabled(enabled: false);
      await StackerLocator.tearDown();
    }
    StackerHttpClient.unbindGlobals();
    unbindInterceptorDependencies();
    _enabled = false;
    _initialised = false;
  }

  // -------------------------------------------------------------------------
  // Reading captured data
  // -------------------------------------------------------------------------

  /// Captured API calls, newest first. Empty when disabled.
  static List<ApiRecord> get apiRecords =>
      _enabled && StackerLocator.isReady
          ? StackerLocator.get<StackerRepository>().apiRecords
          : const <ApiRecord>[];

  /// Captured crashes, newest first. Empty when disabled.
  static List<CrashRecord> get crashes => _enabled && StackerLocator.isReady
      ? StackerLocator.get<StackerRepository>().crashRecords
      : const <CrashRecord>[];

  /// Detected leaks, newest first. Empty when disabled.
  static List<LeakRecord> get leaks => _enabled && StackerLocator.isReady
      ? StackerLocator.get<StackerRepository>().leakRecords
      : const <LeakRecord>[];

  // -------------------------------------------------------------------------
  // Recording
  // -------------------------------------------------------------------------

  /// Records a caught error that the app recovered from.
  static void recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? context,
    Map<String, String> metadata = const <String, String>{},
  }) {
    if (!_enabled || !StackerLocator.isReady) return;
    StackerLocator.get<CrashReporter>().recordError(
      error,
      stackTrace,
      fatal: fatal,
      context: context,
      metadata: metadata,
    );
  }

  /// Records an API call captured outside the provided interceptors.
  static void recordApiCall(ApiRecord record) {
    if (!_enabled || !StackerLocator.isReady) return;
    StackerLocator.get<StackerRepository>().addApiRecord(record);
  }

  /// Starts watching [object] for retention.
  ///
  /// Pair with [expectDisposed] at the end of the object's life. See
  /// [LeakDetector] for exactly what is and is not detected.
  static void watchForLeaks(Object object, {String? label}) {
    if (!_enabled || !StackerLocator.isReady) return;
    StackerLocator.get<LeakDetector>().watch(object, label: label);
  }

  /// Declares that [object] should now be collectable.
  static void expectDisposed(Object object) {
    if (!_enabled || !StackerLocator.isReady) return;
    StackerLocator.get<LeakDetector>().expectDisposed(object);
  }

  /// Clears every buffer.
  static void clearAll() {
    if (!_enabled || !StackerLocator.isReady) return;
    StackerLocator.get<StackerRepository>().clearAll();
  }

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  /// Pushes the dashboard onto [context]'s navigator.
  ///
  /// No-op when disabled, so a debug menu item wired to this is safe to leave
  /// in a release build.
  static Future<void> openDashboard(
    BuildContext context, {
    DashboardTab initialTab = DashboardTab.api,
  }) {
    if (!_enabled || !StackerLocator.isReady) return Future<void>.value();
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StackerDashboard(initialTab: initialTab),
        settings: const RouteSettings(name: StackerDashboard.routeName),
      ),
    );
  }

  /// Opens the dashboard in a native host activity or view controller.
  ///
  /// This is the path a pure-native app uses: it does not need a Flutter
  /// `BuildContext`. On Android it starts `StackerActivity`; on iOS it
  /// presents the Flutter view controller. See the README for the intent and
  /// `StackerLauncher` details.
  static Future<void> openNativeDashboard({
    DashboardTab initialTab = DashboardTab.api,
  }) async {
    if (!_enabled) return;
    await StackerPlatform().openDashboard(initialTab: initialTab.channelName);
  }

  // -------------------------------------------------------------------------
  // Native bridge
  // -------------------------------------------------------------------------

  static void _listenToNative(StackerPlatform platform) {
    _nativeSubscription?.cancel();
    _nativeSubscription = platform.nativeRecords.listen(
      _handleNativeEvent,
      onError: (Object error) {
        debugPrint('[Stacker] native event stream error: $error');
      },
      cancelOnError: false,
    );
  }

  static Future<void> _drainNativeBacklog(StackerPlatform platform) async {
    final buffered = await platform.drainBufferedRecords();
    for (final event in buffered) {
      _handleNativeEvent(event);
    }
  }

  static void _handleNativeEvent(NativeRecordEvent event) {
    if (!StackerLocator.isReady) return;
    final repository = StackerLocator.get<StackerRepository>();
    switch (event) {
      case NativeApiEvent(:final record):
        // Native interceptors may report a request and its response as two
        // messages sharing an id, so route through update to merge them.
        repository.updateApiRecord(record);
      case NativeCrashEvent(:final record):
        repository.addCrash(record);
      case NativeLeakEvent(:final record):
        repository.addLeak(record);
    }
  }
}
