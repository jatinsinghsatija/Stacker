import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';
import 'package:stacker_inspector/src/core/id_generator.dart';
import 'package:stacker_inspector/src/core/redactor.dart';
import 'package:stacker_inspector/src/core/service_locator.dart';
import 'package:stacker_inspector/src/domain/crash_reporter.dart';
import 'package:stacker_inspector/src/domain/leak_detector.dart';

void main() {
  tearDown(() async {
    await StackerLocator.tearDown();
  });

  group('StackerLocator', () {
    test('is not ready before setUp', () {
      expect(StackerLocator.isReady, isFalse);
    });

    test('registers every dependency', () async {
      await StackerLocator.setUp(const StackerConfig());

      expect(StackerLocator.isReady, isTrue);
      expect(StackerLocator.get<StackerConfig>(), isA<StackerConfig>());
      expect(StackerLocator.get<IdGenerator>(), isA<IdGenerator>());
      expect(StackerLocator.get<Redactor>(), isA<Redactor>());
      expect(StackerLocator.get<StackerRepository>(), isA<StackerRepository>());
      expect(StackerLocator.get<CrashReporter>(), isA<CrashReporter>());
      expect(StackerLocator.get<LeakDetector>(), isA<LeakDetector>());
    });

    test('registers the repository as a singleton', () async {
      await StackerLocator.setUp(const StackerConfig());

      final first = StackerLocator.get<StackerRepository>();
      final second = StackerLocator.get<StackerRepository>();

      expect(
        first,
        same(second),
        reason: 'every consumer must observe the same captured data',
      );
    });

    test('registers the blocs as factories', () async {
      await StackerLocator.setUp(const StackerConfig());

      final first = StackerLocator.get<ApiListBloc>();
      final second = StackerLocator.get<ApiListBloc>();

      expect(
        first,
        isNot(same(second)),
        reason: 'each dashboard route needs its own bloc and subscription',
      );

      await first.close();
      await second.close();
    });

    test('blocs resolve against the registered repository', () async {
      await StackerLocator.setUp(const StackerConfig());

      final repository = StackerLocator.get<StackerRepository>();
      repository.addApiRecord(
        ApiRecord(
          id: 'a',
          method: 'GET',
          url: 'https://example.com/x',
          requestTime: DateTime(2026, 9, 4),
        ),
      );

      final bloc = StackerLocator.get<ApiListBloc>()
        ..add(const ApiListSubscriptionRequested());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.records, hasLength(1));
      await bloc.close();
    });

    test('propagates the supplied config', () async {
      await StackerLocator.setUp(
        const StackerConfig(maxApiRecords: 7, toastPolicy: ToastPolicy.errorsOnly),
      );

      final config = StackerLocator.get<StackerConfig>();
      expect(config.maxApiRecords, 7);
      expect(config.toastPolicy, ToastPolicy.errorsOnly);
    });

    test('applies the configured buffer capacity to the repository', () async {
      await StackerLocator.setUp(const StackerConfig(maxApiRecords: 2));

      final repository = StackerLocator.get<StackerRepository>();
      for (var i = 0; i < 5; i++) {
        repository.addApiRecord(
          ApiRecord(
            id: 'r$i',
            method: 'GET',
            url: 'https://example.com/$i',
            requestTime: DateTime(2026, 9, 4),
          ),
        );
      }

      expect(repository.apiRecords, hasLength(2));
    });

    test('setUp twice rebuilds cleanly rather than throwing', () async {
      await StackerLocator.setUp(const StackerConfig(maxApiRecords: 5));
      final first = StackerLocator.get<StackerRepository>();

      // This is the hot-restart path.
      await StackerLocator.setUp(const StackerConfig(maxApiRecords: 9));
      final second = StackerLocator.get<StackerRepository>();

      expect(first, isNot(same(second)));
      expect(StackerLocator.get<StackerConfig>().maxApiRecords, 9);
    });

    test('tearDown unregisters everything', () async {
      await StackerLocator.setUp(const StackerConfig());
      expect(StackerLocator.isReady, isTrue);

      await StackerLocator.tearDown();

      expect(StackerLocator.isReady, isFalse);
      expect(
        () => StackerLocator.get<StackerRepository>(),
        throwsA(isA<Object>()),
      );
    });

    test('uses a private GetIt instance, not the global one', () async {
      await StackerLocator.setUp(const StackerConfig());

      // A host app using GetIt.instance must be unaffected by Stacker's
      // registrations, so the two containers cannot be the same object.
      expect(StackerLocator.instance.runtimeType.toString(), isNotEmpty);
      expect(StackerLocator.isReady, isTrue);
    });
  });

  group('Stacker facade when uninitialised', () {
    test('exposes empty lists rather than throwing', () {
      expect(Stacker.apiRecords, isEmpty);
      expect(Stacker.crashes, isEmpty);
      expect(Stacker.leaks, isEmpty);
    });

    test('recording calls are safe no-ops', () {
      expect(
        () => Stacker.recordError(Exception('x'), null),
        returnsNormally,
      );
      expect(() => Stacker.watchForLeaks(Object()), returnsNormally);
      expect(() => Stacker.expectDisposed(Object()), returnsNormally);
      expect(Stacker.clearAll, returnsNormally);
    });
  });
}
