import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/api_record.dart';
import '../models/crash_record.dart';
import '../models/leak_record.dart';

/// Bridge to the Android and iOS host implementations.
///
/// Two channels are used:
///  * a [MethodChannel] for calls Dart initiates (launch the dashboard,
///    toggle the launcher icon, ask whether the host is a debug build);
///  * an [EventChannel] for records the native interceptors push up.
class StackerPlatform {
  StackerPlatform({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ?? const MethodChannel(methodChannelName),
        _events = eventChannel ?? const EventChannel(eventChannelName);

  static const String methodChannelName = 'com.stacker/stacker';
  static const String eventChannelName = 'com.stacker/stacker_events';

  final MethodChannel _method;
  final EventChannel _events;

  /// Records pushed up by the native interceptors.
  ///
  /// The stream is `broadcast` on the native side; each event is a map with a
  /// `type` discriminator of `api`, `crash`, or `leak`.
  Stream<NativeRecordEvent> get nativeRecords {
    try {
      return _events
          .receiveBroadcastStream()
          .handleError(
            // A host that is absent or misbehaving must not tear down the
            // Dart-side subscription; capture from Dart keeps working.
            (Object error) => debugPrint('[Stacker] native stream: $error'),
          )
          .map(_parseEvent)
          .where((event) => event != null)
          .cast<NativeRecordEvent>();
    } on MissingPluginException {
      return const Stream<NativeRecordEvent>.empty();
    }
  }

  /// Reports the Dart-side capture state to the host so the native
  /// interceptors and the launcher icon can align with it.
  Future<void> setEnabled({required bool enabled}) async {
    await _invoke<void>('setEnabled', <String, Object?>{'enabled': enabled});
  }

  /// Enables or disables the separate dashboard launcher icon.
  ///
  /// On Android this toggles the `activity-alias` component state. On iOS
  /// there is no runtime equivalent, so the call is a no-op and the icon is
  /// controlled by the debug-only Info.plist entry described in the README.
  Future<void> setLauncherIconVisible({required bool visible}) async {
    await _invoke<void>(
      'setLauncherIconVisible',
      <String, Object?>{'visible': visible},
    );
  }

  /// Opens the native dashboard host activity / view controller.
  ///
  /// [initialTab] is one of `api`, `crashes`, or `leaks`.
  Future<void> openDashboard({String initialTab = 'api'}) async {
    await _invoke<void>(
      'openDashboard',
      <String, Object?>{'initialTab': initialTab},
    );
  }

  /// Whether the *host* app was built in debug mode.
  ///
  /// This differs from Dart's [kDebugMode] when Flutter is embedded as a
  /// module into a native app: the Flutter module can be built in release
  /// while the host app is debuggable, or vice versa. Returns `null` when the
  /// host does not answer, so the caller can fall back to [kDebugMode].
  Future<bool?> isHostDebugBuild() async {
    return _invoke<bool>('isHostDebugBuild');
  }

  /// Shows a native toast/snackbar for a completed call.
  ///
  /// Used when the Flutter UI is not mounted — for example a pure-native
  /// screen making OkHttp calls with no Flutter view on screen.
  Future<void> showNativeToast(String message) async {
    await _invoke<void>(
      'showNativeToast',
      <String, Object?>{'message': message},
    );
  }

  /// Asks the host for records captured before the Dart side attached.
  ///
  /// A native app may issue requests during startup, before the Flutter engine
  /// finishes warming up. The host buffers those and hands them over here so
  /// nothing is lost.
  Future<List<NativeRecordEvent>> drainBufferedRecords() async {
    final raw = await _invoke<List<Object?>>('drainBufferedRecords');
    if (raw == null) return const <NativeRecordEvent>[];
    return raw
        .map(_parseEvent)
        .whereType<NativeRecordEvent>()
        .toList(growable: false);
  }

  /// Invokes [name], swallowing the `MissingPluginException` that occurs when
  /// the library is used on a platform without a native implementation
  /// (unit tests, desktop, web). Capture keeps working; only the native
  /// extras are unavailable.
  /// How long to wait for the host before giving up on a call.
  ///
  /// A method channel with no handler on the other side never replies — it
  /// does not throw. In `flutter_test` there is no host at all, so without a
  /// timeout `Stacker.init` hangs until the test framework kills the run after
  /// ten minutes. That was a real defect: any app that called `Stacker.init`
  /// from its own widget test froze with no useful error.
  ///
  /// A real host answers these calls in single-digit milliseconds, so 2s is
  /// generous while still failing fast when nobody is listening.
  static const Duration _callTimeout = Duration(seconds: 2);

  Future<T?> _invoke<T>(String name, [Map<String, Object?>? args]) async {
    try {
      return await _method
          .invokeMethod<T>(name, args)
          .timeout(_callTimeout);
    } on MissingPluginException {
      // No native implementation: unit tests, desktop, web. Capture keeps
      // working; only the native extras are unavailable.
      return null;
    } on TimeoutException {
      // No host is listening. Silent by design — this is the normal case in a
      // widget test and must not spam the console on every call.
      return null;
    } on PlatformException catch (error) {
      debugPrint('[Stacker] platform call "$name" failed: ${error.message}');
      return null;
    }
  }

  static NativeRecordEvent? _parseEvent(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type']?.toString();
    final payload = raw['payload'];
    if (payload is! Map) return null;
    return switch (type) {
      'api' => NativeApiEvent(ApiRecord.fromNative(payload)),
      'crash' => NativeCrashEvent(CrashRecord.fromNative(payload)),
      'leak' => NativeLeakEvent(LeakRecord.fromNative(payload)),
      _ => null,
    };
  }
}

/// A record that came up from the native side.
sealed class NativeRecordEvent {
  const NativeRecordEvent();
}

class NativeApiEvent extends NativeRecordEvent {
  const NativeApiEvent(this.record);
  final ApiRecord record;
}

class NativeCrashEvent extends NativeRecordEvent {
  const NativeCrashEvent(this.record);
  final CrashRecord record;
}

class NativeLeakEvent extends NativeRecordEvent {
  const NativeLeakEvent(this.record);
  final LeakRecord record;
}
