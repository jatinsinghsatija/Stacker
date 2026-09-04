import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';

ApiRecord _record(String id, {ApiCallState state = ApiCallState.pending}) {
  return ApiRecord(
    id: id,
    method: 'GET',
    url: 'https://api.example.com/v1/users?page=1',
    requestTime: DateTime(2026, 9, 3, 10, 30),
    state: state,
    statusCode: state == ApiCallState.complete ? 200 : null,
  );
}

CrashRecord _crash(String id) {
  return CrashRecord(
    id: id,
    timestamp: DateTime(2026, 9, 3, 10, 30),
    error: 'StateError: something broke',
    source: CrashSource.manual,
  );
}

LeakRecord _leak(String id) {
  return LeakRecord(
    id: id,
    detectedAt: DateTime(2026, 9, 3, 10, 30),
    objectType: 'MyController',
    kind: LeakKind.retainedObject,
  );
}

void main() {
  late InMemoryStackerRepository repository;

  setUp(() {
    repository = InMemoryStackerRepository(
      const StackerConfig(
        maxApiRecords: 3,
        maxCrashRecords: 3,
        maxLeakRecords: 3,
      ),
    );
  });

  tearDown(() async => repository.dispose());

  group('API records', () {
    test('returns records newest first', () {
      repository
        ..addApiRecord(_record('a'))
        ..addApiRecord(_record('b'))
        ..addApiRecord(_record('c'));

      expect(
        repository.apiRecords.map((record) => record.id),
        <String>['c', 'b', 'a'],
        reason: 'the dashboard shows the freshest call on top',
      );
    });

    test('honours the configured capacity', () {
      for (final id in <String>['a', 'b', 'c', 'd', 'e']) {
        repository.addApiRecord(_record(id));
      }

      expect(repository.apiRecords, hasLength(3));
      expect(
        repository.apiRecords.map((record) => record.id),
        <String>['e', 'd', 'c'],
      );
    });

    test('updateApiRecord replaces the pending entry in place', () {
      repository
        ..addApiRecord(_record('a'))
        ..addApiRecord(_record('b'));

      final completed = _record('a').copyWith(
        state: ApiCallState.complete,
        statusCode: 201,
        responseTime: DateTime(2026, 9, 3, 10, 30, 1),
      );
      repository.updateApiRecord(completed);

      expect(repository.apiRecords, hasLength(2));
      final updated = repository.findApiRecord('a');
      expect(updated!.statusCode, 201);
      expect(updated.state, ApiCallState.complete);
      // Position preserved: 'b' is still the newest.
      expect(repository.apiRecords.first.id, 'b');
    });

    test('updateApiRecord inserts when the record is unknown', () {
      repository.updateApiRecord(
        _record('native-1', state: ApiCallState.complete),
      );

      expect(repository.apiRecords, hasLength(1));
      expect(repository.findApiRecord('native-1'), isNotNull);
    });

    test('findApiRecord returns null for a missing id', () {
      expect(repository.findApiRecord('nope'), isNull);
    });

    test('apiStream emits the full list on each change', () async {
      final emissions = <int>[];
      final subscription =
          repository.apiStream.listen((records) => emissions.add(records.length));

      repository
        ..addApiRecord(_record('a'))
        ..addApiRecord(_record('b'));
      await Future<void>.delayed(Duration.zero);

      expect(emissions, <int>[1, 2]);
      await subscription.cancel();
    });

    test('completedApiStream emits only finished calls', () async {
      final completed = <String>[];
      final subscription = repository.completedApiStream
          .listen((record) => completed.add(record.id));

      repository
        ..addApiRecord(_record('pending'))
        ..addApiRecord(_record('done', state: ApiCallState.complete));
      await Future<void>.delayed(Duration.zero);

      expect(
        completed,
        <String>['done'],
        reason: 'a toast must not fire for an in-flight request',
      );
      await subscription.cancel();
    });

    test('completedApiStream fires when a pending call completes', () async {
      final completed = <String>[];
      final subscription = repository.completedApiStream
          .listen((record) => completed.add(record.id));

      repository.addApiRecord(_record('a'));
      repository.updateApiRecord(
        _record('a').copyWith(state: ApiCallState.complete, statusCode: 200),
      );
      await Future<void>.delayed(Duration.zero);

      expect(completed, <String>['a']);
      await subscription.cancel();
    });

    test('clearApiRecords empties the list and emits', () async {
      repository.addApiRecord(_record('a'));

      final emissions = <int>[];
      final subscription =
          repository.apiStream.listen((records) => emissions.add(records.length));

      repository.clearApiRecords();
      await Future<void>.delayed(Duration.zero);

      expect(repository.apiRecords, isEmpty);
      expect(emissions, <int>[0]);
      await subscription.cancel();
    });
  });

  group('crashes and leaks', () {
    test('stores crashes newest first within capacity', () {
      for (final id in <String>['a', 'b', 'c', 'd']) {
        repository.addCrash(_crash(id));
      }

      expect(repository.crashRecords, hasLength(3));
      expect(repository.crashRecords.first.id, 'd');
    });

    test('newCrashStream emits each crash', () async {
      final seen = <String>[];
      final subscription =
          repository.newCrashStream.listen((record) => seen.add(record.id));

      repository.addCrash(_crash('a'));
      await Future<void>.delayed(Duration.zero);

      expect(seen, <String>['a']);
      await subscription.cancel();
    });

    test('stores leaks newest first within capacity', () {
      for (final id in <String>['a', 'b', 'c', 'd']) {
        repository.addLeak(_leak(id));
      }

      expect(repository.leakRecords, hasLength(3));
      expect(repository.leakRecords.first.id, 'd');
    });

    test('clearAll empties every buffer', () {
      repository
        ..addApiRecord(_record('a'))
        ..addCrash(_crash('b'))
        ..addLeak(_leak('c'))
        ..clearAll();

      expect(repository.apiRecords, isEmpty);
      expect(repository.crashRecords, isEmpty);
      expect(repository.leakRecords, isEmpty);
    });
  });

  group('after dispose', () {
    test('ignores further writes instead of throwing', () async {
      await repository.dispose();

      // A late-arriving native event must not crash the app.
      expect(() => repository.addApiRecord(_record('a')), returnsNormally);
      expect(() => repository.addCrash(_crash('b')), returnsNormally);
      expect(() => repository.addLeak(_leak('c')), returnsNormally);
      expect(repository.apiRecords, isEmpty);
    });

    test('dispose is idempotent', () async {
      await repository.dispose();
      await expectLater(repository.dispose(), completes);
    });
  });
}
