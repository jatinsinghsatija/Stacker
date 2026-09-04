import 'dart:async';
import 'dart:io' show ProcessInfo;

import 'package:flutter/foundation.dart';

import '../core/id_generator.dart';
import '../core/stacker_config.dart';
import '../data/models/leak_record.dart';
import '../data/repository/stacker_repository.dart';

/// An object being watched for retention, held only weakly.
class _Watch {
  _Watch({
    required this.reference,
    required this.objectType,
    required this.label,
    required this.registeredAt,
    required this.allocationStackTrace,
  });

  /// Weak so that the detector itself never keeps the object alive — holding a
  /// strong reference here would manufacture the very leak we are looking for.
  final WeakReference<Object> reference;
  final String objectType;
  final String? label;
  final DateTime registeredAt;
  final String? allocationStackTrace;

  DateTime? disposalExpectedAt;
  int checksSurvived = 0;
  bool reported = false;

  bool get isAlive => reference.target != null;
}

/// Detects retained Dart objects and unbounded resident-memory growth.
///
/// Two independent mechanisms, with deliberately different confidence levels:
///
/// **1. Retention tracking ([LeakKind.retainedObject], confirmed).**
/// [watch] stores a [WeakReference] to an object. The caller then declares,
/// via [expectDisposed], that the object should now be garbage. If the weak
/// target is *still* non-null after the configured retention window and
/// several check cycles, something is holding a strong reference to it. That is
/// a real leak, not a guess — the object is provably reachable when it should
/// not be. This is the same principle LeakCanary uses on Android.
///
/// **2. Resident-memory trend sampling ([LeakKind.growingHeap], suspected).**
/// [ProcessInfo.currentRss] is sampled on an interval. A run of consecutive
/// strictly-increasing samples that never falls back is reported as *suspected*
/// only, because a legitimate warming cache or image cache produces the same
/// shape.
///
/// ### What this deliberately does not do
/// It does not diff heap snapshots or walk retaining paths — that requires the
/// VM service protocol from outside the process, which is what Flutter DevTools
/// does. This detector tells you *that* an object leaked and where it was
/// allocated; use DevTools to find the full retaining chain.
class LeakDetector {
  LeakDetector({
    required StackerRepository repository,
    required StackerConfig config,
    required IdGenerator idGenerator,
    @visibleForTesting int Function()? rssProvider,
  })  : _repository = repository,
        _config = config,
        _ids = idGenerator,
        _readRss = rssProvider ?? _defaultRssProvider;

  /// Consecutive rising samples before growth is reported.
  static const int _growthSampleThreshold = 6;

  /// Minimum total growth across the window before reporting, so ordinary
  /// start-up allocation does not trigger a report.
  static const int _growthMinimumBytes = 24 * 1024 * 1024;

  /// How many check cycles a retained object must survive before it is
  /// reported. More than one cycle means a single delayed GC is not enough
  /// to produce a false positive.
  static const int _requiredChecksSurvived = 3;

  final StackerRepository _repository;
  final StackerConfig _config;
  final IdGenerator _ids;
  final int Function() _readRss;

  final List<_Watch> _watches = <_Watch>[];
  final List<int> _rssSamples = <int>[];

  Timer? _timer;
  bool _running = false;

  /// Whether sampling is currently active.
  bool get isRunning => _running;

  /// Number of objects currently being watched.
  @visibleForTesting
  int get watchCount => _watches.length;

  /// Most recent resident-memory samples, oldest first.
  List<int> get rssSamples => List<int>.unmodifiable(_rssSamples);

  /// Starts the periodic check. Safe to call more than once.
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(_config.memorySampleInterval, (_) => _tick());
  }

  /// Stops the periodic check and clears pending watches.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _watches.clear();
    _rssSamples.clear();
  }

  /// Registers [object] to be watched for retention.
  ///
  /// Call this where the object is created — in `initState`, a BLoC
  /// constructor, or a controller factory. Only a weak reference is kept, so
  /// watching an object never prevents it from being collected and calling
  /// this on a hot path is cheap.
  ///
  /// [label] distinguishes multiple live instances of the same type.
  void watch(Object object, {String? label}) {
    if (!_config.detectLeaks) return;
    _watches.add(
      _Watch(
        reference: WeakReference<Object>(object),
        objectType: object.runtimeType.toString(),
        label: label,
        registeredAt: DateTime.now(),
        // Captured at registration so the dashboard can show the allocation
        // site; the trace is cheap to take and only kept in debug.
        allocationStackTrace: kDebugMode ? _trimmedTrace() : null,
      ),
    );
  }

  /// Declares that [object] should now be eligible for garbage collection.
  ///
  /// Call this from `dispose()`, `close()`, or wherever the object's lifecycle
  /// ends. If the object is still reachable after
  /// [StackerConfig.leakRetentionWindow] and [_requiredChecksSurvived] check
  /// cycles, a confirmed leak is recorded.
  void expectDisposed(Object object) {
    if (!_config.detectLeaks) return;
    final now = DateTime.now();
    for (final watch in _watches) {
      if (identical(watch.reference.target, object)) {
        watch.disposalExpectedAt = now;
        watch.checksSurvived = 0;
        return;
      }
    }
    // Not previously watched — start watching now so a late call still works.
    watch(object);
    _watches.last.disposalExpectedAt = now;
  }

  /// Reports a leak observed by the caller or by native tooling.
  void report(LeakRecord record) => _repository.addLeak(record);

  /// Runs one detection cycle immediately, outside the timer.
  @visibleForTesting
  void checkNow() => _tick();

  void _tick() {
    _checkRetainedObjects();
    _sampleMemory();
  }

  void _checkRetainedObjects() {
    final now = DateTime.now();
    final resolved = <_Watch>[];

    for (final watch in _watches) {
      if (!watch.isAlive) {
        // Collected as expected — nothing to report, stop tracking it.
        resolved.add(watch);
        continue;
      }

      final expectedAt = watch.disposalExpectedAt;
      if (expectedAt == null) {
        // Still in normal use; no expectation has been declared yet.
        continue;
      }

      final retainedFor = now.difference(expectedAt);
      if (retainedFor < _config.leakRetentionWindow) continue;

      watch.checksSurvived++;
      if (watch.checksSurvived < _requiredChecksSurvived) continue;

      if (!watch.reported) {
        watch.reported = true;
        _repository.addLeak(
          LeakRecord(
            id: _ids.next('leak'),
            detectedAt: now,
            objectType: watch.objectType,
            label: watch.label,
            kind: LeakKind.retainedObject,
            confidence: LeakConfidence.confirmed,
            allocatedAt: watch.registeredAt,
            retainedForMs: retainedFor.inMilliseconds,
            gcCyclesSurvived: watch.checksSurvived,
            rssBytes: _safeRss(),
            details:
                '${watch.objectType} was still reachable '
                '${retainedFor.inMilliseconds} ms after it was expected to be '
                'disposed, across ${watch.checksSurvived} checks. Something is '
                'holding a strong reference to it — a common cause is a stream '
                'subscription, timer, animation controller, or listener that '
                'was never cancelled. Open Flutter DevTools › Memory and take '
                'a heap snapshot to see the full retaining path.',
            allocationStackTrace: watch.allocationStackTrace,
          ),
        );
      }
      resolved.add(watch);
    }

    for (final watch in resolved) {
      _watches.remove(watch);
    }
  }

  void _sampleMemory() {
    final rss = _safeRss();
    if (rss == null) return;

    _rssSamples.add(rss);
    // Keep one extra sample so a full window can be evaluated after trimming.
    final maxSamples = _growthSampleThreshold + 1;
    while (_rssSamples.length > maxSamples) {
      _rssSamples.removeAt(0);
    }

    if (_rssSamples.length < _growthSampleThreshold) return;

    final window = _rssSamples.sublist(
      _rssSamples.length - _growthSampleThreshold,
    );
    var strictlyRising = true;
    for (var i = 1; i < window.length; i++) {
      if (window[i] <= window[i - 1]) {
        strictlyRising = false;
        break;
      }
    }
    if (!strictlyRising) return;

    final delta = window.last - window.first;
    if (delta < _growthMinimumBytes) return;

    _repository.addLeak(
      LeakRecord(
        id: _ids.next('leak'),
        detectedAt: DateTime.now(),
        objectType: 'Process resident memory',
        kind: LeakKind.growingHeap,
        confidence: LeakConfidence.suspected,
        rssBytes: window.last,
        rssDeltaBytes: delta,
        details:
            'Resident memory rose across $_growthSampleThreshold consecutive '
            'samples without falling back, gaining '
            '${LeakRecord.formatBytes(delta)} in total. This can be a real '
            'leak, but a warming image or response cache produces the same '
            'shape — confirm with a heap snapshot before treating it as a bug.',
      ),
    );

    // Reset so the same rise is not reported again on the next tick.
    _rssSamples.clear();
  }

  int? _safeRss() {
    try {
      return _readRss();
    } on Object {
      // Not available on every platform (notably web); trend detection is
      // simply skipped there while retention tracking keeps working.
      return null;
    }
  }

  static int _defaultRssProvider() => ProcessInfo.currentRss;

  /// Drops the frames belonging to Stacker itself so the reported trace
  /// starts at the caller's allocation site.
  static String _trimmedTrace() {
    final lines = StackTrace.current.toString().split('\n');
    final filtered = lines
        .where((line) => !line.contains('package:stacker_inspector/src/domain/leak_detector.dart'))
        .take(16)
        .toList();
    return filtered.join('\n');
  }
}
