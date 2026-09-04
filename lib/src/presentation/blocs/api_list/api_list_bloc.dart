import 'package:bloc/bloc.dart';

import '../../../data/repository/stacker_repository.dart';
import 'api_list_event.dart';
import 'api_list_state.dart';

export 'api_list_event.dart';
export 'api_list_state.dart';

/// Drives the API call list screen.
///
/// The bloc owns no data of its own: the repository is the single source of
/// truth and the bloc mirrors it, layering search and filter on top. Filtering
/// lives in [ApiListState.visibleRecords] rather than in the bloc so the
/// unfiltered list survives a filter change and no data is lost.
class ApiListBloc extends Bloc<ApiListEvent, ApiListState> {
  ApiListBloc({required StackerRepository repository})
      : _repository = repository,
        super(const ApiListState()) {
    on<ApiListSubscriptionRequested>(_onSubscriptionRequested);
    on<ApiListUpdated>(_onUpdated);
    on<ApiListSearchChanged>(_onSearchChanged);
    on<ApiListFilterChanged>(_onFilterChanged);
    on<ApiListCleared>(_onCleared);
  }

  final StackerRepository _repository;

  Future<void> _onSubscriptionRequested(
    ApiListSubscriptionRequested event,
    Emitter<ApiListState> emit,
  ) async {
    emit(
      state.copyWith(
        status: ApiListStatus.ready,
        records: _repository.apiRecords,
      ),
    );
    // `emit.forEach` ties the subscription to the bloc's lifetime, so it is
    // cancelled automatically on close without a manual StreamSubscription.
    await emit.forEach(
      _repository.apiStream,
      onData: (records) => state.copyWith(records: records),
    );
  }

  void _onUpdated(ApiListUpdated event, Emitter<ApiListState> emit) {
    emit(state.copyWith(records: event.records));
  }

  void _onSearchChanged(
    ApiListSearchChanged event,
    Emitter<ApiListState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  void _onFilterChanged(
    ApiListFilterChanged event,
    Emitter<ApiListState> emit,
  ) {
    emit(state.copyWith(filter: event.filter));
  }

  void _onCleared(ApiListCleared event, Emitter<ApiListState> emit) {
    _repository.clearApiRecords();
    emit(state.copyWith(records: const []));
  }
}
