import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../data/models/leak_record.dart';
import '../../../data/repository/stacker_repository.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Events accepted by [LeakListBloc].
sealed class LeakListEvent extends Equatable {
  const LeakListEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Subscribes to the repository and emits the current list.
final class LeakListSubscriptionRequested extends LeakListEvent {
  const LeakListSubscriptionRequested();
}

/// Applies a free-text search across the object type and details.
final class LeakListSearchChanged extends LeakListEvent {
  const LeakListSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => <Object?>[query];
}

/// Filters by confidence level.
final class LeakListFilterChanged extends LeakListEvent {
  const LeakListFilterChanged(this.filter);

  final LeakListFilter filter;

  @override
  List<Object?> get props => <Object?>[filter];
}

/// Empties the leak buffer.
final class LeakListCleared extends LeakListEvent {
  const LeakListCleared();
}

/// Which subset of leaks the list shows.
enum LeakListFilter {
  all('All'),
  confirmed('Confirmed'),
  suspected('Suspected');

  const LeakListFilter(this.label);

  final String label;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum LeakListStatus { initial, ready }

/// State of [LeakListBloc].
final class LeakListState extends Equatable {
  const LeakListState({
    this.status = LeakListStatus.initial,
    this.records = const <LeakRecord>[],
    this.query = '',
    this.filter = LeakListFilter.all,
  });

  final LeakListStatus status;

  /// Every detected leak, newest first, before filtering.
  final List<LeakRecord> records;

  final String query;
  final LeakListFilter filter;

  /// Records matching both [filter] and [query].
  List<LeakRecord> get visibleRecords {
    final needle = query.trim().toLowerCase();
    return records.where((record) {
      final confidenceOk = switch (filter) {
        LeakListFilter.all => true,
        LeakListFilter.confirmed =>
          record.confidence == LeakConfidence.confirmed,
        LeakListFilter.suspected =>
          record.confidence == LeakConfidence.suspected,
      };
      if (!confidenceOk) return false;
      if (needle.isEmpty) return true;
      return record.objectType.toLowerCase().contains(needle) ||
          (record.label?.toLowerCase().contains(needle) ?? false) ||
          (record.details?.toLowerCase().contains(needle) ?? false);
    }).toList(growable: false);
  }

  /// Count of confirmed leaks, shown on the tab badge.
  int get confirmedCount => records
      .where((record) => record.confidence == LeakConfidence.confirmed)
      .length;

  LeakListState copyWith({
    LeakListStatus? status,
    List<LeakRecord>? records,
    String? query,
    LeakListFilter? filter,
  }) {
    return LeakListState(
      status: status ?? this.status,
      records: records ?? this.records,
      query: query ?? this.query,
      filter: filter ?? this.filter,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, records, query, filter];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

/// Drives the memory-leak list screen.
class LeakListBloc extends Bloc<LeakListEvent, LeakListState> {
  LeakListBloc({required StackerRepository repository})
      : _repository = repository,
        super(const LeakListState()) {
    on<LeakListSubscriptionRequested>(_onSubscriptionRequested);
    on<LeakListSearchChanged>(_onSearchChanged);
    on<LeakListFilterChanged>(_onFilterChanged);
    on<LeakListCleared>(_onCleared);
  }

  final StackerRepository _repository;

  Future<void> _onSubscriptionRequested(
    LeakListSubscriptionRequested event,
    Emitter<LeakListState> emit,
  ) async {
    emit(
      state.copyWith(
        status: LeakListStatus.ready,
        records: _repository.leakRecords,
      ),
    );
    await emit.forEach(
      _repository.leakStream,
      onData: (records) => state.copyWith(records: records),
    );
  }

  void _onSearchChanged(
    LeakListSearchChanged event,
    Emitter<LeakListState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  void _onFilterChanged(
    LeakListFilterChanged event,
    Emitter<LeakListState> emit,
  ) {
    emit(state.copyWith(filter: event.filter));
  }

  void _onCleared(LeakListCleared event, Emitter<LeakListState> emit) {
    _repository.clearLeaks();
    emit(state.copyWith(records: const []));
  }
}
