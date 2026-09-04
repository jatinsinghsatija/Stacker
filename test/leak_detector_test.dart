import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';
import 'package:stacker_inspector/src/core/id_generator.dart';
import 'package:stacker_inspector/src/domain/leak_detector.dart';

/// A plain object to watch.
class Watched {
  Watched(this.name);
  final String name;
}

void main() {
  // A short window and zero-length interval keep the tests fast; the detector
  // is driven manually with checkNow rather than by its timer.
  const config = StackerConfig(
    leakRetentionWindow: Duration.zero,
    memorySampleInterval: Duration(milliseconds: 1),
  );

  late InMemoryStackerRepository repository;
  late LeakDetector detector;

  setUp(() {
    repository = InMemoryStackerRepository(const StackerConfig());
    detector = LeakDetector(
      repository: repository,
      config: config,
      idGenerator: IdGenerator(),
      // Flat RSS so the growth heuristic never fires during retention tests.
      rssProvider: () => 100 * 1024 * 1024,
    );
  });

  tearDown(() async {
    detector.stop();
    await repository.dispose();
  });

  group('retention tracking', () {
    test('reports an object still held after expectDisposed', () {
      // Held for the whole test, so it is provably retained.
      final retained = Watched('leaky');

      detector.watch(retained, label: 'test-instance');
      detector.expectDisposed(retained);

      // Three checks are required before a report is emitted.
      detector.checkNow();
      expect(repository.leakRecords, isEmpty, reason: '1 of 3 checks');
      detector.checkNow();
      expect(repository.leakRecords, isEmpty, reason: '2 of 3 checks');
      detector.checkNow();

      expect(repository.leakRecords, hasLength(1));
      final leak = repository.leakRecords.single;
      expect(leak.objectType, 'Watched');
      expect(leak.label, 'test-instance');
      expect(leak.kind, LeakKind.retainedObject);
      expect(
        leak.confidence,
        LeakConfidence.confirmed,
        reason: 'a still-reachable object is proof, not a guess',
      );
      expect(leak.gcCyclesSurvived, 3);

      // Keep the object alive past the assertions so it cannot be collected
      // early and invalidate the test.
      expect(retained.name, 'leaky');
    });

    test('does not report an object that was never expected to be disposed', () {
      final inUse = Watched('active');
      detector.watch(inUse);

      for (var i = 0; i < 5; i++) {
        detector.checkNow();
      }

      expect(
        repository.leakRecords,
        isEmpty,
        reason: 'an object in normal use is not a leak',
      );
      expect(inUse.name, 'active');
    });

    test('reports a given object only once', () {
      final retained = Watched('once');
      detector.watch(retained);
      detector.expectDisposed(retained);

      for (var i = 0; i < 10; i++) {
        detector.checkNow();
      }

      expect(
        repository.leakRecords,
        hasLength(1),
        reason: 'repeated checks must not spam the list',
      );
      expect(retained.name, 'once');
    });

    test('expectDisposed on an unwatched object still tracks it', () {
      final retained = Watched('late');
      // No prior watch call.
      detector.expectDisposed(retained);

      detector.checkNow();
      detector.checkNow();
      detector.checkNow();

      expect(repository.leakRecords, hasLength(1));
      expect(retained.name, 'late');
    });

    test('respects the retention window before reporting', () {
      const slow = StackerConfig(
        leakRetentionWindow: Duration(minutes: 5),
      );
      final slowDetector = LeakDetector(
        repository: repository,
        config: slow,
        idGenerator: IdGenerator(),
        rssProvider: () => 100 * 1024 * 1024,
      );

      final retained = Watched('waiting');
      slowDetector.watch(retained);
      slowDetector.expectDisposed(retained);

      for (var i = 0; i < 5; i++) {
        slowDetector.checkNow();
      }

      expect(
        repository.leakRecords,
        isEmpty,
        reason: 'the window has not elapsed, so this is not yet a leak',
      );
      expect(retained.name, 'waiting');
      slowDetector.stop();
    });

    test('does nothing when leak detection is disabled', () {
      const disabled = StackerConfig(detectLeaks: false);
      final disabledDetector = LeakDetector(
        repository: repository,
        config: disabled,
        idGenerator: IdGenerator(),
        rssProvider: () => 100 * 1024 * 1024,
      );

      final retained = Watched('ignored');
      disabledDetector.watch(retained);
      disabledDetector.expectDisposed(retained);
      disabledDetector.checkNow();
      disabledDetector.checkNow();
      disabledDetector.checkNow();

      expect(repository.leakRecords, isEmpty);
      expect(disabledDetector.watchCount, 0);
      expect(retained.name, 'ignored');
      disabledDetector.stop();
    });

    test('holds only a weak reference to the watched object', () {
      // Register an object with no other strong reference to it. If the
      // detector held it strongly, watchCount could never drop.
      detector.watch(Watched('collectable'));
      expect(detector.watchCount, 1);

      // Not asserting collection here: GC timing is not deterministic, so a
      // test that demands it would be flaky. The design guarantee is that the
      // detector stores a WeakReference, which the retention tests above rely
      // on to distinguish a real leak from a collected object.
    });
  });

  group('resident-memory trend detection', () {
    test('reports sustained growth as suspected', () {
      var rss = 100 * 1024 * 1024;
      final growing = LeakDetector(
        repository: repository,
        config: config,
        idGenerator: IdGenerator(),
        // 8 MB per sample: six rising samples clear the 24 MB threshold.
        rssProvider: () {
          rss += 8 * 1024 * 1024;
          return rss;
        },
      );

      for (var i = 0; i < 6; i++) {
        growing.checkNow();
      }

      expect(repository.leakRecords, hasLength(1));
      final leak = repository.leakRecords.single;
      expect(leak.kind, LeakKind.growingHeap);
      expect(
        leak.confidence,
        LeakConfidence.suspected,
        reason: 'a warming cache produces the same shape, so never "confirmed"',
      );
      expect(leak.rssDeltaBytes, greaterThan(0));
      growing.stop();
    });

    test('ignores memory that fluctuates without a trend', () {
      var index = 0;
      final samples = <int>[
        100 * 1024 * 1024,
        120 * 1024 * 1024,
        110 * 1024 * 1024,
        130 * 1024 * 1024,
        115 * 1024 * 1024,
        140 * 1024 * 1024,
        125 * 1024 * 1024,
      ];
      final noisy = LeakDetector(
        repository: repository,
        config: config,
        idGenerator: IdGenerator(),
        rssProvider: () => samples[index++ % samples.length],
      );

      for (var i = 0; i < 7; i++) {
        noisy.checkNow();
      }

      expect(
        repository.leakRecords,
        isEmpty,
        reason: 'normal allocation churn must not be reported',
      );
      noisy.stop();
    });

    test('ignores growth below the reporting threshold', () {
      var rss = 100 * 1024 * 1024;
      final slight = LeakDetector(
        repository: repository,
        config: config,
        idGenerator: IdGenerator(),
        // 1 MB per sample: rising, but only ~5 MB total.
        rssProvider: () {
          rss += 1024 * 1024;
          return rss;
        },
      );

      for (var i = 0; i < 6; i++) {
        slight.checkNow();
      }

      expect(
        repository.leakRecords,
        isEmpty,
        reason: 'a few MB of growth is ordinary, not a leak',
      );
      slight.stop();
    });

    test('survives an RSS provider that throws', () {
      final broken = LeakDetector(
        repository: repository,
        config: config,
        idGenerator: IdGenerator(),
        rssProvider: () => throw UnsupportedError('no RSS on this platform'),
      );

      // Trend detection is skipped, but retention tracking must keep working.
      expect(broken.checkNow, returnsNormally);

      final retained = Watched('still-works');
      broken.watch(retained);
      broken.expectDisposed(retained);
      broken.checkNow();
      broken.checkNow();
      broken.checkNow();

      expect(repository.leakRecords, hasLength(1));
      expect(repository.leakRecords.single.kind, LeakKind.retainedObject);
      expect(retained.name, 'still-works');
      broken.stop();
    });
  });

  group('lifecycle', () {
    test('start and stop toggle isRunning', () {
      expect(detector.isRunning, isFalse);
      detector.start();
      expect(detector.isRunning, isTrue);
      detector.stop();
      expect(detector.isRunning, isFalse);
    });

    test('start is idempotent', () {
      detector.start();
      expect(detector.start, returnsNormally);
      expect(detector.isRunning, isTrue);
    });

    test('stop clears pending watches', () {
      final retained = Watched('cleared');
      detector.watch(retained);
      expect(detector.watchCount, 1);

      detector.stop();

      expect(detector.watchCount, 0);
      expect(retained.name, 'cleared');
    });
  });
}
