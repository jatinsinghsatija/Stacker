import 'package:equatable/equatable.dart';

import '../../../data/models/api_record.dart';

/// Events accepted by `ApiListBloc`.
sealed class ApiListEvent extends Equatable {
  const ApiListEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Subscribes to the repository and emits the current list.
final class ApiListSubscriptionRequested extends ApiListEvent {
  const ApiListSubscriptionRequested();
}

/// Internal: the repository pushed a new list.
final class ApiListUpdated extends ApiListEvent {
  const ApiListUpdated(this.records);

  final List<ApiRecord> records;

  @override
  List<Object?> get props => <Object?>[records];
}

/// Applies a free-text search across method, URL, and status code.
final class ApiListSearchChanged extends ApiListEvent {
  const ApiListSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => <Object?>[query];
}

/// Filters by status-code class.
final class ApiListFilterChanged extends ApiListEvent {
  const ApiListFilterChanged(this.filter);

  final ApiListFilter filter;

  @override
  List<Object?> get props => <Object?>[filter];
}

/// Empties the API buffer.
final class ApiListCleared extends ApiListEvent {
  const ApiListCleared();
}

/// Which subset of calls the list shows.
enum ApiListFilter {
  all('All'),
  success('2xx'),
  redirect('3xx'),
  clientError('4xx'),
  serverError('5xx'),
  failed('Failed'),
  pending('Pending');

  const ApiListFilter(this.label);

  /// Short label shown on the filter chip.
  final String label;
}
