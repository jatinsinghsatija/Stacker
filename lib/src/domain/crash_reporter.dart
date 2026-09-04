import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/id_generator.dart';
import '../data/models/crash_record.dart';
import '../data/repository/stacker_repository.dart';

/// Captures uncaught Flutter and Dart errors into the repository.
///
/// Three hooks are installed, covering the three ways an error can escape:
///
///  * [FlutterError.onError] — synchronous errors inside the framework
///    (build, layout, paint, gesture callbacks);
///  * [ui.PlatformDispatcher.onError] — uncaught asynchronous Dart errors
///    that would otherwise only reach the console;
///  * [Isolate.addErrorListener] — errors raised on the current isolate that
///    bypass both of the above.
///
/// Any handler already installed is chained, so installing Stacker does not
/// silence Crashlytics, Sentry, or the default red-screen reporter.
class CrashReporter {
  CrashReporter({
    required StackerRepository repository,
    required IdGenerator idGenerator,
  })  : _repository = repository,
        _ids = idGenerator;

  final StackerRepository _repository;
  final IdGenerator _ids;

  FlutterExceptionHandler? _previousFlutterHandler;
  ui.ErrorCallback? _previousDispatcherHandler;
  RawReceivePort? _isolateErrorPort;
  bool _installed = false;

  /// Whether the handlers are currently installed.
  bool get isInstalled => _installed;

  /// Installs the error handlers. Safe to call more than once.
  void install() {
    if (_installed) return;
    _installed = true;

    _previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _recordFlutterError(details);
      // Preserve existing behaviour: other reporters and the red screen still run.
      _previousFlutterHandler?.call(details);
    };

    _previousDispatcherHandler = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _recordDartError(error, stack);
      // `true` means handled. Defer to the previous handler's verdict when one
      // exists so we do not change whether the process is torn down.
      return _previousDispatcherHandler?.call(error, stack) ?? false;
    };

    _installErrorPort();
  }

  /// Restores the handlers that were in place before [install].
  void uninstall() {
    if (!_installed) return;
    _installed = false;
    FlutterError.onError = _previousFlutterHandler;
    ui.PlatformDispatcher.instance.onError = _previousDispatcherHandler;
    _isolateErrorPort?.close();
    _isolateErrorPort = null;
  }

  /// Records a caught error explicitly.
  ///
  /// Use this in a `catch` block for a failure the app recovers from but that
  /// is still worth seeing in the dashboard.
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? context,
    Map<String, String> metadata = const <String, String>{},
  }) {
    _repository.addCrash(
      CrashRecord(
        id: _ids.next('crash'),
        timestamp: DateTime.now(),
        error: error.toString(),
        stackTrace: stackTrace?.toString(),
        source: CrashSource.manual,
        severity: fatal ? CrashSeverity.fatal : CrashSeverity.nonFatal,
        context: context,
        metadata: metadata,
        isolateName: Isolate.current.debugName,
      ),
    );
  }

  /// Records a crash that arrived from the native side.
  void recordNative(CrashRecord record) => _repository.addCrash(record);

  void _recordFlutterError(FlutterErrorDetails details) {
    _repository.addCrash(
      CrashRecord(
        id: _ids.next('crash'),
        timestamp: DateTime.now(),
        error: details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
        source: CrashSource.flutterFramework,
        // A framework error does not terminate the process in release; it is
        // reported as fatal only when the framework itself says it is.
        severity: details.silent ? CrashSeverity.nonFatal : CrashSeverity.fatal,
        library: details.library,
        context: details.context?.toDescription(),
        isolateName: Isolate.current.debugName,
      ),
    );
  }

  void _recordDartError(Object error, StackTrace stack) {
    _repository.addCrash(
      CrashRecord(
        id: _ids.next('crash'),
        timestamp: DateTime.now(),
        error: error.toString(),
        stackTrace: stack.toString(),
        source: CrashSource.dartUncaught,
        severity: CrashSeverity.fatal,
        isolateName: Isolate.current.debugName,
      ),
    );
  }

  void _installErrorPort() {
    final port = RawReceivePort((dynamic message) {
      // Isolate error messages arrive as a two-element list of strings.
      if (message is! List || message.length < 2) return;
      final error = message[0]?.toString() ?? 'Unknown isolate error';
      final stack = message[1]?.toString();
      _repository.addCrash(
        CrashRecord(
          id: _ids.next('crash'),
          timestamp: DateTime.now(),
          error: error,
          stackTrace: stack,
          source: CrashSource.dartUncaught,
          severity: CrashSeverity.fatal,
          context: 'Uncaught error on isolate',
          isolateName: Isolate.current.debugName,
        ),
      );
    });
    _isolateErrorPort = port;
    Isolate.current.addErrorListener(port.sendPort);
  }
}
