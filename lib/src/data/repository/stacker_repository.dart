import 'dart:async';

import '../../core/stacker_config.dart';
import '../models/api_record.dart';
import '../models/crash_record.dart';
import '../models/leak_record.dart';
import 'ring_buffer.dart';

/// Contract for the record store, so the BLoCs can be tested against a fake.
abstract interface class StackerRepository {
  /// API calls, newest first.
  List<ApiRecord> get apiRecords;

  /// Crashes, newest first.
  List<CrashRecord> get crashRecords;

  /// Leaks, newest first.
  List<LeakRecord> get leakRecords;

  /// Emits the full API list whenever it changes.
  Stream<List<ApiRecord>> get apiStream;

  /// Emits the full crash list whenever it changes.
  Stream<List<CrashRecord>> get crashStream;

  /// Emits the full leak list whenever it changes.
  Stream<List<LeakRecord>> get leakStream;

  /// Emits each API record as it completes, for the toast overlay.
  Stream<ApiRecord> get completedApiStream;

  /// Emits each crash as it is captured, for the toast overlay.
  Stream<CrashRecord> get newCrashStream;

  /// Records a new outgoing request.
  void addApiRecord(ApiRecord record);

  /// Updates an existing record in place, keyed by [ApiRecord.id].
  ///
  /// Falls back to inserting when no record with that id exists, which happens
  /// when a native interceptor reports a completed call in a single message.
  void updateApiRecord(ApiRecord record);

  void addCrash(CrashRecord record);
  void addLeak(LeakRecord record);

  ApiRecord? findApiRecord(String id);
  CrashRecord? findCrash(String id);
  LeakRecord? findLeak(String id);

  void clearApiRecords();
  void clearCrashes();
  void clearLeaks();
  void clearAll();

  /// Releases the streams. Call only when tearing the library down.
  Future<void> dispose();
}

/// In-memory [StackerRepository] backed by three [RingBuffer]s.
///
/// Records live only for the process lifetime; nothing touches disk, so the
/// library needs no storage permission and cannot leave captured tokens behind
/// on the device after the app exits.
class InMemoryStackerRepository implements StackerRepository {
  InMemoryStackerRepository(StackerConfig config)
      : _apiBuffer = RingBuffer<ApiRecord>(config.maxApiRecords),
        _crashBuffer = RingBuffer<CrashRecord>(config.maxCrashRecords),
        _leakBuffer = RingBuffer<LeakRecord>(config.maxLeakRecords);

  final RingBuffer<ApiRecord> _apiBuffer;
  final RingBuffer<CrashRecord> _crashBuffer;
  final RingBuffer<LeakRecord> _leakBuffer;

  final StreamController<List<ApiRecord>> _apiController =
      StreamController<List<ApiRecord>>.broadcast();
  final StreamController<List<CrashRecord>> _crashController =
      StreamController<List<CrashRecord>>.broadcast();
  final StreamController<List<LeakRecord>> _leakController =
      StreamController<List<LeakRecord>>.broadcast();
  final StreamController<ApiRecord> _completedApiController =
      StreamController<ApiRecord>.broadcast();
  final StreamController<CrashRecord> _newCrashController =
      StreamController<CrashRecord>.broadcast();

  bool _disposed = false;

  @override
  List<ApiRecord> get apiRecords => _apiBuffer.reversed;

  @override
  List<CrashRecord> get crashRecords => _crashBuffer.reversed;

  @override
  List<LeakRecord> get leakRecords => _leakBuffer.reversed;

  @override
  Stream<List<ApiRecord>> get apiStream => _apiController.stream;

  @override
  Stream<List<CrashRecord>> get crashStream => _crashController.stream;

  @override
  Stream<List<LeakRecord>> get leakStream => _leakController.stream;

  @override
  Stream<ApiRecord> get completedApiStream => _completedApiController.stream;

  @override
  Stream<CrashRecord> get newCrashStream => _newCrashController.stream;

  @override
  void addApiRecord(ApiRecord record) {
    if (_disposed) return;
    _apiBuffer.add(record);
    _emitApi();
    if (record.state != ApiCallState.pending) {
      _completedApiController.add(record);
    }
  }

  @override
  void updateApiRecord(ApiRecord record) {
    if (_disposed) return;
    final replaced = _apiBuffer.replaceWhere(
      (existing) => existing.id == record.id,
      record,
    );
    if (!replaced) {
      // The pending entry was already evicted, or the call arrived complete.
      _apiBuffer.add(record);
    }
    _emitApi();
    if (record.state != ApiCallState.pending) {
      _completedApiController.add(record);
    }
  }

  @override
  void addCrash(CrashRecord record) {
    if (_disposed) return;
    _crashBuffer.add(record);
    _crashController.add(crashRecords);
    _newCrashController.add(record);
  }

  @override
  void addLeak(LeakRecord record) {
    if (_disposed) return;
    _leakBuffer.add(record);
    _leakController.add(leakRecords);
  }

  @override
  ApiRecord? findApiRecord(String id) =>
      _apiBuffer.firstWhereOrNull((record) => record.id == id);

  @override
  CrashRecord? findCrash(String id) =>
      _crashBuffer.firstWhereOrNull((record) => record.id == id);

  @override
  LeakRecord? findLeak(String id) =>
      _leakBuffer.firstWhereOrNull((record) => record.id == id);

  @override
  void clearApiRecords() {
    if (_disposed) return;
    _apiBuffer.clear();
    _emitApi();
  }

  @override
  void clearCrashes() {
    if (_disposed) return;
    _crashBuffer.clear();
    _crashController.add(crashRecords);
  }

  @override
  void clearLeaks() {
    if (_disposed) return;
    _leakBuffer.clear();
    _leakController.add(leakRecords);
  }

  @override
  void clearAll() {
    clearApiRecords();
    clearCrashes();
    clearLeaks();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait<void>([
      _apiController.close(),
      _crashController.close(),
      _leakController.close(),
      _completedApiController.close(),
      _newCrashController.close(),
    ]);
  }

  void _emitApi() => _apiController.add(apiRecords);
}
