import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';

ApiRecord _record({
  required String id,
  int? statusCode,
  ApiCallState state = ApiCallState.complete,
  String url = 'https://api.example.com/v1/users',
  String method = 'GET',
}) {
  return ApiRecord(
    id: id,
    method: method,
    url: url,
    requestTime: DateTime(2026, 9, 3, 10, 30),
    responseTime: DateTime(2026, 9, 3, 10, 30, 1),
    state: state,
    statusCode: statusCode,
  );
}

void main() {
  late InMemoryStackerRepository repository;

  setUp(() {
    repository = InMemoryStackerRepository(const StackerConfig());
  });

  tearDown(() async => repository.dispose());

  group('ApiListBloc', () {
    test('starts in the initial state with no records', () {
      final bloc = ApiListBloc(repository: repository);
      expect(bloc.state.status, ApiListStatus.initial);
      expect(bloc.state.records, isEmpty);
      expect(bloc.state.filter, ApiListFilter.all);
      bloc.close();
    });

    blocTest<ApiListBloc, ApiListState>(
      'becomes ready and loads existing records on subscription',
      setUp: () {
        repository.addApiRecord(_record(id: 'a', statusCode: 200));
      },
      build: () => ApiListBloc(repository: repository),
      act: (bloc) => bloc.add(const ApiListSubscriptionRequested()),
      expect: () => <Matcher>[
        isA<ApiListState>()
            .having((state) => state.status, 'status', ApiListStatus.ready)
            .having((state) => state.records, 'records', hasLength(1)),
      ],
    );

    blocTest<ApiListBloc, ApiListState>(
      'emits again when the repository receives a new record',
      build: () => ApiListBloc(repository: repository),
      act: (bloc) async {
        bloc.add(const ApiListSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        repository.addApiRecord(_record(id: 'a', statusCode: 200));
        await Future<void>.delayed(Duration.zero);
        repository.addApiRecord(_record(id: 'b', statusCode: 404));
      },
      expect: () => <Matcher>[
        isA<ApiListState>().having((s) => s.records, 'records', isEmpty),
        isA<ApiListState>().having((s) => s.records, 'records', hasLength(1)),
        isA<ApiListState>().having((s) => s.records, 'records', hasLength(2)),
      ],
    );

    blocTest<ApiListBloc, ApiListState>(
      'stores the search query',
      build: () => ApiListBloc(repository: repository),
      act: (bloc) => bloc.add(const ApiListSearchChanged('users')),
      expect: () => <Matcher>[
        isA<ApiListState>().having((state) => state.query, 'query', 'users'),
      ],
    );

    blocTest<ApiListBloc, ApiListState>(
      'stores the selected filter',
      build: () => ApiListBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const ApiListFilterChanged(ApiListFilter.serverError)),
      expect: () => <Matcher>[
        isA<ApiListState>().having(
          (state) => state.filter,
          'filter',
          ApiListFilter.serverError,
        ),
      ],
    );

    blocTest<ApiListBloc, ApiListState>(
      'clears the repository on ApiListCleared',
      setUp: () {
        repository.addApiRecord(_record(id: 'a', statusCode: 200));
      },
      build: () => ApiListBloc(repository: repository),
      act: (bloc) => bloc.add(const ApiListCleared()),
      verify: (_) {
        expect(repository.apiRecords, isEmpty);
      },
    );
  });

  group('ApiListState.visibleRecords', () {
    final records = <ApiRecord>[
      _record(id: 'ok', statusCode: 200),
      _record(id: 'redirect', statusCode: 301),
      _record(id: 'missing', statusCode: 404, url: 'https://api.example.com/v1/orders'),
      _record(id: 'boom', statusCode: 500),
      _record(id: 'pending', state: ApiCallState.pending),
      _record(id: 'failed', state: ApiCallState.failed),
    ];

    test('returns everything with the default filter', () {
      final state = ApiListState(records: records);
      expect(state.visibleRecords, hasLength(6));
      expect(state.isFiltered, isFalse);
    });

    test('filters by status class', () {
      expect(
        ApiListState(records: records, filter: ApiListFilter.success)
            .visibleRecords
            .map((record) => record.id),
        <String>['ok'],
      );
      expect(
        ApiListState(records: records, filter: ApiListFilter.redirect)
            .visibleRecords
            .map((record) => record.id),
        <String>['redirect'],
      );
      expect(
        ApiListState(records: records, filter: ApiListFilter.clientError)
            .visibleRecords
            .map((record) => record.id),
        <String>['missing'],
      );
      expect(
        ApiListState(records: records, filter: ApiListFilter.serverError)
            .visibleRecords
            .map((record) => record.id),
        <String>['boom'],
      );
    });

    test('filters by lifecycle state', () {
      expect(
        ApiListState(records: records, filter: ApiListFilter.pending)
            .visibleRecords
            .map((record) => record.id),
        <String>['pending'],
      );
      expect(
        ApiListState(records: records, filter: ApiListFilter.failed)
            .visibleRecords
            .map((record) => record.id),
        <String>['failed'],
      );
    });

    test('searches the URL case-insensitively', () {
      final state = ApiListState(records: records, query: 'ORDERS');
      expect(state.visibleRecords.map((record) => record.id), <String>['missing']);
      expect(state.isFiltered, isTrue);
    });

    test('searches by status code', () {
      final state = ApiListState(records: records, query: '500');
      expect(state.visibleRecords.map((record) => record.id), <String>['boom']);
    });

    test('searches by reason phrase', () {
      final state = ApiListState(records: records, query: 'not found');
      expect(state.visibleRecords.map((record) => record.id), <String>['missing']);
    });

    test('combines filter and search', () {
      final state = ApiListState(
        records: records,
        filter: ApiListFilter.clientError,
        query: 'orders',
      );
      expect(state.visibleRecords, hasLength(1));

      final noMatch = ApiListState(
        records: records,
        filter: ApiListFilter.success,
        query: 'orders',
      );
      expect(noMatch.visibleRecords, isEmpty);
    });

    test('counts non-2xx outcomes as errors', () {
      // 301 is not an error; 404, 500 and the failed call are.
      expect(ApiListState(records: records).errorCount, 3);
    });

    test('trims a whitespace-only query', () {
      final state = ApiListState(records: records, query: '   ');
      expect(state.visibleRecords, hasLength(6));
      expect(state.isFiltered, isFalse);
    });
  });
}
