import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/api_record.dart';
import '../blocs/api_list/api_list_bloc.dart';
import '../stacker_theme.dart';
import '../widgets/common.dart';
import 'api_detail_screen.dart';

/// Lists every captured API call, newest first.
class ApiListScreen extends StatelessWidget {
  const ApiListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ApiListBloc, ApiListState>(
      builder: (context, state) {
        final records = state.visibleRecords;
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search URL, method, or status',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (value) => context
                    .read<ApiListBloc>()
                    .add(ApiListSearchChanged(value)),
              ),
            ),
            StackerFilterBar<ApiListFilter>(
              values: ApiListFilter.values,
              selected: state.filter,
              labelOf: (filter) => filter.label,
              onSelected: (filter) => context
                  .read<ApiListBloc>()
                  .add(ApiListFilterChanged(filter)),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: records.isEmpty
                  ? StackerEmptyState(
                      icon: state.isFiltered
                          ? Icons.filter_alt_off_outlined
                          : Icons.wifi_tethering_rounded,
                      title: state.isFiltered
                          ? 'No calls match this filter'
                          : 'No API calls captured yet',
                      message: state.isFiltered
                          ? 'Clear the search or filter to see all '
                              '${state.records.length} captured calls.'
                          : 'Attach StackerDioInterceptor to your Dio '
                              'instance, or wrap your http.Client in '
                              'StackerHttpClient, then make a request.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: records.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _ApiRow(record: records[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// One row in the API call list.
class _ApiRow extends StatelessWidget {
  const _ApiRow({required this.record});

  final ApiRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = StackerTheme.recordColor(record, theme.brightness);
    final methodColor =
        StackerTheme.methodColor(record.method, theme.brightness);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      // `mainAxisSize: min` plus a tight leading box: ListTile gives its
      // leading widget a bounded height, so a Column sized to its natural
      // height overflows once the text scale grows.
      leading: SizedBox(
        width: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _statusLabel,
              maxLines: 1,
              style: StackerTheme.monospace(
                fontSize: 14,
                color: color,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            Text(
              record.method,
              maxLines: 1,
              style: StackerTheme.monospace(
                fontSize: 10,
                color: methodColor,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
      title: Text(
        record.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: StackerTheme.monospace(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                record.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatClockTime(record.requestTime),
              style: StackerTheme.monospace(
                fontSize: 10,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (record.duration != null)
            Text(
              formatDuration(record.duration!),
              maxLines: 1,
              style: StackerTheme.monospace(fontSize: 11, height: 1.2),
            )
          else
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
          Text(
            formatBytes(
              record.totalSizeBytes == 0 ? null : record.totalSizeBytes,
            ),
            maxLines: 1,
            style: StackerTheme.monospace(
              fontSize: 10,
              height: 1.2,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
      onTap: () {
        // The detail screen watches the same bloc so a pending call updates
        // live while it is open. The pushed route is a sibling of the
        // dashboard, not a descendant, so the bloc must be handed across
        // explicitly — `BlocProvider.value` reuses the instance rather than
        // creating (and later closing) a second one.
        final bloc = context.read<ApiListBloc>();
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => BlocProvider<ApiListBloc>.value(
              value: bloc,
              child: ApiDetailScreen(recordId: record.id),
            ),
          ),
        );
      },
    );
  }

  String get _statusLabel => switch (record.state) {
        ApiCallState.pending => '···',
        ApiCallState.failed => record.statusCode?.toString() ?? '!',
        ApiCallState.complete => record.statusCode?.toString() ?? '?',
      };
}
