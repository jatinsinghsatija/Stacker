import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/api_record.dart';
import '../blocs/api_list/api_list_bloc.dart';
import '../stacker_theme.dart';
import '../widgets/common.dart';

/// Full detail for one captured API call.
///
/// Reads the record out of the bloc's state by id rather than taking the
/// record as a value, so a pending call updates in place while the detail
/// screen is open instead of showing a stale snapshot.
class ApiDetailScreen extends StatelessWidget {
  const ApiDetailScreen({required this.recordId, super.key});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: StackerTheme.themeFor(Theme.of(context).brightness),
      child: BlocBuilder<ApiListBloc, ApiListState>(
        builder: (context, state) {
          final record = state.records
              .where((candidate) => candidate.id == recordId)
              .firstOrNull;

          if (record == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Call detail')),
              body: const StackerEmptyState(
                icon: Icons.help_outline_rounded,
                title: 'This call is no longer in the buffer',
                message:
                    'The buffer keeps a fixed number of calls and this one has '
                    'been evicted by newer traffic.',
              ),
            );
          }

          return _DetailScaffold(record: record);
        },
      ),
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.record});

  final ApiRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor =
        StackerTheme.recordColor(record, theme.brightness);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${record.method} ${record.path}',
          style: StackerTheme.monospace(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.terminal_rounded),
            tooltip: 'Copy as cURL',
            onPressed: () => copyToClipboard(
              context,
              record.toCurl(),
              message: 'cURL command copied',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_rounded),
            tooltip: 'Copy full report',
            onPressed: () => copyToClipboard(
              context,
              record.toReport(),
              message: 'Full report copied',
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          _SummaryCard(record: record, statusColor: statusColor),
          const SizedBox(height: 10),
          if (record.statusInfo != null) ...<Widget>[
            _StatusMeaningCard(record: record, statusColor: statusColor),
            const SizedBox(height: 10),
          ],
          if (record.errorMessage != null) ...<Widget>[
            _ErrorCard(record: record),
            const SizedBox(height: 10),
          ],
          StackerSection(
            title: 'Request headers',
            subtitle: '${record.requestHeaders.length} sent',
            trailing: _CopyMapButton(map: record.requestHeaders),
            child: StackerKeyValueTable(
              entries: record.requestHeaders,
              emptyLabel: 'No request headers',
            ),
          ),
          const SizedBox(height: 8),
          StackerSection(
            title: 'Query parameters',
            subtitle: '${record.queryParameters.length} in the URL',
            trailing: _CopyMapButton(map: record.queryParameters),
            child: StackerKeyValueTable(
              entries: record.queryParameters,
              emptyLabel: 'No query parameters',
            ),
          ),
          const SizedBox(height: 8),
          StackerSection(
            title: 'Path parameters',
            subtitle: record.pathParameters.isEmpty
                ? 'Pass them via the stacker.pathParameters extra'
                : '${record.pathParameters.length} supplied',
            initiallyExpanded: record.pathParameters.isNotEmpty,
            child: StackerKeyValueTable(
              entries: record.pathParameters,
              emptyLabel: 'No path parameters recorded',
            ),
          ),
          const SizedBox(height: 8),
          StackerSection(
            title: 'Request body',
            subtitle: record.requestContentType ?? 'No content type',
            initiallyExpanded: record.requestBody != null,
            child: StackerCodeBlock(
              content: ApiRecord.prettyPrint(record.requestBody),
              emptyLabel: 'No request body',
            ),
          ),
          const SizedBox(height: 8),
          StackerSection(
            title: 'Response headers',
            subtitle: '${record.responseHeaders.length} received',
            trailing: _CopyMapButton(map: record.responseHeaders),
            child: StackerKeyValueTable(
              entries: record.responseHeaders,
              emptyLabel: 'No response headers',
            ),
          ),
          const SizedBox(height: 8),
          StackerSection(
            title: 'Response body',
            subtitle: record.responseContentType ?? 'No content type',
            initiallyExpanded: record.responseBody != null,
            child: StackerCodeBlock(
              content: ApiRecord.prettyPrint(record.responseBody),
              emptyLabel: record.state == ApiCallState.pending
                  ? 'Waiting for the response…'
                  : 'No response body',
            ),
          ),
          const SizedBox(height: 8),
          StackerSection(
            title: 'Full URL',
            initiallyExpanded: false,
            child: StackerCodeBlock(content: record.url),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Top card with the status, timings, and sizes.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.record, required this.statusColor});

  final ApiRecord record;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                StackerBadge(
                  label: record.method,
                  color: StackerTheme.methodColor(
                    record.method,
                    theme.brightness,
                  ),
                ),
                const SizedBox(width: 6),
                StackerBadge(
                  label: switch (record.state) {
                    ApiCallState.pending => 'PENDING',
                    ApiCallState.failed =>
                      record.statusCode?.toString() ?? 'FAILED',
                    ApiCallState.complete =>
                      record.statusCode?.toString() ?? 'DONE',
                  },
                  color: statusColor,
                ),
                const Spacer(),
                StackerBadge(
                  label: record.origin.name.toUpperCase(),
                  color: theme.disabledColor,
                  icon: switch (record.origin) {
                    CaptureOrigin.android => Icons.android_rounded,
                    CaptureOrigin.ios => Icons.phone_iphone_rounded,
                    CaptureOrigin.dart => Icons.flutter_dash_rounded,
                    CaptureOrigin.manual => Icons.edit_rounded,
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              record.url,
              style: StackerTheme.monospace(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 22,
              runSpacing: 10,
              children: <Widget>[
                _Metric(
                  label: 'Sent',
                  value: formatClockTime(record.requestTime),
                ),
                _Metric(
                  label: 'Received',
                  value: record.responseTime == null
                      ? '—'
                      : formatClockTime(record.responseTime!),
                ),
                _Metric(
                  label: 'Duration',
                  value: record.duration == null
                      ? '—'
                      : formatDuration(record.duration!),
                ),
                _Metric(
                  label: 'Request size',
                  value: formatBytes(record.requestSizeBytes),
                ),
                _Metric(
                  label: 'Response size',
                  value: formatBytes(record.responseSizeBytes),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Full timestamp: ${formatFullTimestamp(record.requestTime)}',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card explaining what the status code means.
class _StatusMeaningCard extends StatelessWidget {
  const _StatusMeaningCard({
    required this.record,
    required this.statusColor,
  });

  final ApiRecord record;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = record.statusInfo!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.info_outline_rounded, size: 16, color: statusColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    info.code == -1
                        ? info.reasonPhrase
                        : '${info.code} ${info.reasonPhrase}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(info.meaning, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// Card shown when the call failed at the transport level.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.record});

  final ApiRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = StackerTheme.statusColor(500, theme.brightness);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.error_outline_rounded, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  record.errorType ?? 'Error',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              record.errorMessage ?? '',
              style: StackerTheme.monospace(fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 9,
            letterSpacing: 0.6,
            color: theme.textTheme.bodySmall?.color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: StackerTheme.monospace(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Copies a header or parameter map as `key: value` lines.
class _CopyMapButton extends StatelessWidget {
  const _CopyMapButton({required this.map});

  final Map<String, String> map;

  @override
  Widget build(BuildContext context) {
    if (map.isEmpty) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.copy_rounded, size: 15),
      tooltip: 'Copy',
      visualDensity: VisualDensity.compact,
      onPressed: () => copyToClipboard(
        context,
        map.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n'),
      ),
    );
  }
}
