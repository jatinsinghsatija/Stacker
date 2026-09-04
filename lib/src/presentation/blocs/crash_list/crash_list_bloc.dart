import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../data/models/crash_record.dart';
import '../../../data/repository/stacker_repository.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Events accepted by [CrashListBloc].
sealed class CrashListEvent extends Equatable {
  const CrashListEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Subscribes to the repository and emits the current list.
final class CrashListSubscriptionRequested extends CrashListEvent {
  const CrashListSubscriptionRequested();
}

/// Applies a free-text search across the error text and stack trace.
final class CrashListSearchChanged extends CrashListEvent {
  const CrashListSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => <Object?>[query];
}

/// Filters by severity.
final class CrashListFilterChanged extends CrashListEvent {
  const CrashListFilterChanged(this.filter);

  final CrashListFilter filter;

  @override
  List<Object?> get props => <Object?>[filter];
}

/// Empties the crash buffer.
final class CrashListCleared extends CrashListEvent {
  const CrashListCleared();
}

/// Which subset of crashes the list shows.
enum CrashListFilter {
  all('All'),
  fatal('Fatal'),
  nonFatal('Non-fatal');

  const CrashListFilter(this.label);

  final String label;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum CrashListStatus { initial, ready }

/// State of [CrashListBloc].
final class CrashListState extends Equatable {
  const CrashListState({
    this.status = CrashListStatus.initial,
    this.records = const <CrashRecord>[],
    this.query = '',
    this.filter = CrashListFilter.all,
  });

  final CrashListStatus status;

  /// Every captured crash, newest first, before filtering.
  final List<CrashRecord> records;

  final String query;
  final CrashListFilter filter;

  /// Records matching both [filter] and [query].
  List<CrashRecord> get visibleRecords {
    final needle = query.trim().toLowerCase();
    return records.where((record) {
      final severityOk = switch (filter) {
        CrashListFilter.all => true,
        CrashListFilter.fatal => record.severity == CrashSeverity.fatal,
        CrashListFilter.nonFatal => record.severity == CrashSeverity.nonFatal,
      };
      if (!severityOk) return false;
      if (needle.isEmpty) return true;
      return record.error.toLowerCase().contains(needle) ||
          (record.stackTrace?.toLowerCase().contains(needle) ?? false) ||
          (record.library?.toLowerCase().contains(needle) ?? false);
    }).toList(growable: false);
  }

  /// Count of fatal entries, shown on the tab badge.
  int get fatalCount => records
      .where((record) => record.severity == CrashSeverity.fatal)
      .length;

  CrashListState copyWith({
    CrashListStatus? status,
    List<CrashRecord>? records,
    String? query,
    CrashListFilter? filter,
  }) {
    return CrashListState(
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

/// Drives the crash list screen.
class CrashListBloc extends Bloc<CrashListEvent, CrashListState> {
  CrashListBloc({required StackerRepository repository})
      : _repository = repository,
        super(const CrashListState()) {
    on<CrashListSubscriptionRequested>(_onSubscriptionRequested);
    on<CrashListSearchChanged>(_onSearchChanged);
    on<CrashListFilterChanged>(_onFilterChanged);
    on<CrashListCleared>(_onCleared);
  }

  final StackerRepository _repository;

  Future<void> _onSubscriptionRequested(
    CrashListSubscriptionRequested event,
    Emitter<CrashListState> emit,
  ) async {
    emit(
      state.copyWith(
        status: CrashListStatus.ready,
        records: _repository.crashRecords,
      ),
    );
    await emit.forEach(
      _repository.crashStream,
      onData: (records) => state.copyWith(records: records),
    );
  }

  void _onSearchChanged(
    CrashListSearchChanged event,
    Emitter<CrashListState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  void _onFilterChanged(
    CrashListFilterChanged event,
    Emitter<CrashListState> emit,
  ) {
    emit(state.copyWith(filter: event.filter));
  }

  void _onCleared(CrashListCleared event, Emitter<CrashListState> emit) {
    _repository.clearCrashes();
    emit(state.copyWith(records: const []));
  }
}
