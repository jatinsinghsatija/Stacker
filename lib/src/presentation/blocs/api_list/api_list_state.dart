import 'package:equatable/equatable.dart';

import '../../../core/http_status.dart';
import '../../../data/models/api_record.dart';
import 'api_list_event.dart';

/// Loading lifecycle of the API list.
enum ApiListStatus { initial, ready }

/// State of `ApiListBloc`.
final class ApiListState extends Equatable {
  const ApiListState({
    this.status = ApiListStatus.initial,
    this.records = const <ApiRecord>[],
    this.query = '',
    this.filter = ApiListFilter.all,
  });

  final ApiListStatus status;

  /// Every captured record, newest first, before filtering.
  final List<ApiRecord> records;

  final String query;
  final ApiListFilter filter;

  /// Records matching both [filter] and [query].
  List<ApiRecord> get visibleRecords {
    final needle = query.trim().toLowerCase();
    return records.where((record) {
      if (!_matchesFilter(record)) return false;
      if (needle.isEmpty) return true;
      return record.url.toLowerCase().contains(needle) ||
          record.method.toLowerCase().contains(needle) ||
          (record.statusCode?.toString().contains(needle) ?? false) ||
          (record.statusInfo?.reasonPhrase.toLowerCase().contains(needle) ??
              false);
    }).toList(growable: false);
  }

  /// Whether any filter or search term is narrowing the list.
  bool get isFiltered => query.trim().isNotEmpty || filter != ApiListFilter.all;

  /// Count of calls that genuinely went wrong.
  ///
  /// A 3xx is deliberately excluded: a redirect is normal traffic, and
  /// counting it as an error would inflate the badge on every app that
  /// follows one.
  int get errorCount => records.where((record) {
        if (record.state == ApiCallState.failed) return true;
        final code = record.statusCode;
        if (code == null) return false;
        final statusClass = HttpStatus.classOf(code);
        return statusClass == HttpStatusClass.clientError ||
            statusClass == HttpStatusClass.serverError;
      }).length;

  bool _matchesFilter(ApiRecord record) {
    return switch (filter) {
      ApiListFilter.all => true,
      ApiListFilter.pending => record.state == ApiCallState.pending,
      ApiListFilter.failed => record.state == ApiCallState.failed,
      ApiListFilter.success => _isClass(record, HttpStatusClass.success),
      ApiListFilter.redirect => _isClass(record, HttpStatusClass.redirection),
      ApiListFilter.clientError =>
        _isClass(record, HttpStatusClass.clientError),
      ApiListFilter.serverError =>
        _isClass(record, HttpStatusClass.serverError),
    };
  }

  static bool _isClass(ApiRecord record, HttpStatusClass expected) {
    final code = record.statusCode;
    if (code == null) return false;
    return HttpStatus.classOf(code) == expected;
  }

  ApiListState copyWith({
    ApiListStatus? status,
    List<ApiRecord>? records,
    String? query,
    ApiListFilter? filter,
  }) {
    return ApiListState(
      status: status ?? this.status,
      records: records ?? this.records,
      query: query ?? this.query,
      filter: filter ?? this.filter,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, records, query, filter];
}
