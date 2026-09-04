import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';
import 'package:stacker_inspector/src/core/id_generator.dart';
import 'package:stacker_inspector/src/domain/crash_reporter.dart';

void main() {
  late InMemoryStackerRepository repository;
  late CrashReporter reporter;

  setUp(() {
    repository = InMemoryStackerRepository(const StackerConfig());
    reporter = CrashReporter(
      repository: repository,
      idGenerator: IdGenerator(),
    );
  });

  tearDown(() async {
    reporter.uninstall();
    await repository.dispose();
  });

  group('recordError', () {
    test('records a caught error as non-fatal by default', () {
      reporter.recordError(
        StateError('cart total went negative'),
        StackTrace.current,
      );

      expect(repository.crashRecords, hasLength(1));
      final crash = repository.crashRecords.single;
      expect(crash.error, contains('cart total went negative'));
      expect(crash.severity, CrashSeverity.nonFatal);
      expect(crash.source, CrashSource.manual);
      expect(crash.stackTrace, isNotNull);
      expect(crash.timestamp, isNotNull);
    });

    test('records context and metadata', () {
      reporter.recordError(
        Exception('boom'),
        null,
        fatal: true,
        context: 'During checkout',
        metadata: <String, String>{'orderId': 'A-1'},
      );

      final crash = repository.crashRecords.single;
      expect(crash.severity, CrashSeverity.fatal);
      expect(crash.context, 'During checkout');
      expect(crash.metadata['orderId'], 'A-1');
    });

    test('handles a null stack trace', () {
      reporter.recordError(Exception('no trace'), null);
      expect(repository.crashRecords.single.stackTrace, isNull);
    });
  });

  group('Flutter error capture', () {
    test('records a framework error and chains to the previous handler', () {
      final previousCalls = <FlutterErrorDetails>[];
      final original = FlutterError.onError;
      FlutterError.onError = previousCalls.add;

      reporter.install();
      addTearDown(() => FlutterError.onError = original);

      final details = FlutterErrorDetails(
        exception: ArgumentError('bad widget argument'),
        stack: StackTrace.current,
        library: 'widgets library',
        context: ErrorDescription('building MyWidget'),
      );
      FlutterError.onError!(details);

      expect(repository.crashRecords, hasLength(1));
      final crash = repository.crashRecords.single;
      expect(crash.error, contains('bad widget argument'));
      expect(crash.source, CrashSource.flutterFramework);
      expect(crash.library, 'widgets library');
      expect(crash.context, contains('MyWidget'));

      expect(
        previousCalls,
        hasLength(1),
        reason: 'installing Stacker must not silence Crashlytics or Sentry',
      );
    });

    test('marks a silent framework error as non-fatal', () {
      final original = FlutterError.onError;
      reporter.install();
      addTearDown(() => FlutterError.onError = original);

      FlutterError.onError!(
        FlutterErrorDetails(
          exception: Exception('quiet'),
          silent: true,
        ),
      );

      expect(repository.crashRecords.single.severity, CrashSeverity.nonFatal);
    });
  });

  group('lifecycle', () {
    test('install sets isInstalled and is idempotent', () {
      final original = FlutterError.onError;
      addTearDown(() => FlutterError.onError = original);

      expect(reporter.isInstalled, isFalse);
      reporter.install();
      expect(reporter.isInstalled, isTrue);

      final handlerAfterFirst = FlutterError.onError;
      reporter.install();
      expect(
        FlutterError.onError,
        same(handlerAfterFirst),
        reason: 'a second install must not wrap the handler twice',
      );
    });

    test('uninstall restores the original handler', () {
      final original = FlutterError.onError;

      reporter.install();
      expect(FlutterError.onError, isNot(same(original)));

      reporter.uninstall();
      expect(FlutterError.onError, same(original));
      expect(reporter.isInstalled, isFalse);
    });
  });

  group('CrashRecord derived fields', () {
    test('extracts the error type from the conventional prefix', () {
      final record = CrashRecord(
        id: 'c1',
        timestamp: DateTime(2026, 9, 4),
        error: 'StateError: something went wrong',
        source: CrashSource.manual,
      );
      expect(record.errorType, 'StateError');
      expect(record.title, 'StateError: something went wrong');
    });

    test('falls back to a generic type when there is no prefix', () {
      final record = CrashRecord(
        id: 'c1',
        timestamp: DateTime(2026, 9, 4),
        error: 'just a message',
        source: CrashSource.manual,
      );
      expect(record.errorType, 'Error');
    });

    test('topFrame skips framework noise in favour of app code', () {
      final record = CrashRecord(
        id: 'c1',
        timestamp: DateTime(2026, 9, 4),
        error: 'Exception: x',
        source: CrashSource.manual,
        stackTrace: '#0      dart:async/zone.dart 1234\n'
            '#1      package:flutter/src/widgets/framework.dart 99\n'
            '#2      MyApp.build (package:myapp/main.dart:42)',
      );

      expect(record.topFrame, contains('package:myapp/main.dart'));
    });

    test('topFrame is null without a stack trace', () {
      final record = CrashRecord(
        id: 'c1',
        timestamp: DateTime(2026, 9, 4),
        error: 'Exception: x',
        source: CrashSource.manual,
      );
      expect(record.topFrame, isNull);
    });

    test('toReport includes the timestamp, error, and trace', () {
      final record = CrashRecord(
        id: 'c1',
        timestamp: DateTime(2026, 9, 4, 12, 30),
        error: 'StateError: bad',
        source: CrashSource.dartUncaught,
        stackTrace: '#0 main',
        metadata: <String, String>{'screen': 'Cart'},
      );

      final report = record.toReport();
      expect(report, contains('FATAL'));
      expect(report, contains('2026-09-04'));
      expect(report, contains('StateError: bad'));
      expect(report, contains('#0 main'));
      expect(report, contains('screen: Cart'));
    });
  });

  group('native crash parsing', () {
    test('builds a record from a native payload', () {
      final record = CrashRecord.fromNative(<dynamic, dynamic>{
        'id': 'android-crash-1',
        'timestamp': DateTime(2026, 9, 4).millisecondsSinceEpoch,
        'error': 'java.lang.NullPointerException: oops',
        'stackTrace': 'at com.example.Foo.bar(Foo.java:10)',
        'source': 'androidNative',
        'severity': 'fatal',
        'isolateName': 'main',
      });

      expect(record.id, 'android-crash-1');
      expect(record.source, CrashSource.androidNative);
      expect(record.severity, CrashSeverity.fatal);
      expect(record.errorType, 'java.lang.NullPointerException');
    });

    test('degrades gracefully on a malformed payload', () {
      final record = CrashRecord.fromNative(<dynamic, dynamic>{});

      expect(record.id, isNotEmpty);
      expect(record.error, 'Unknown native error');
      expect(record.source, CrashSource.manual);
    });
  });
}
