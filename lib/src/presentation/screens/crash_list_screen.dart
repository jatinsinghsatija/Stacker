import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/crash_record.dart';
import '../blocs/crash_list/crash_list_bloc.dart';
import '../stacker_theme.dart';
import '../widgets/common.dart';

/// Lists captured crashes and uncaught errors, newest first.
class CrashListScreen extends StatelessWidget {
  const CrashListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CrashListBloc, CrashListState>(
      builder: (context, state) {
        final records = state.visibleRecords;
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search error text or stack trace',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (value) => context
                    .read<CrashListBloc>()
                    .add(CrashListSearchChanged(value)),
              ),
            ),
            StackerFilterBar<CrashListFilter>(
              values: CrashListFilter.values,
              selected: state.filter,
              labelOf: (filter) => filter.label,
              onSelected: (filter) => context
                  .read<CrashListBloc>()
                  .add(CrashListFilterChanged(filter)),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: records.isEmpty
                  ? const StackerEmptyState(
                      icon: Icons.verified_outlined,
                      title: 'No crashes captured',
                      message:
                          'Uncaught Flutter and Dart errors appear here with a '
                          'timestamp and stack trace as soon as they occur.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: records.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _CrashRow(record: records[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CrashRow extends StatelessWidget {
  const _CrashRow({required this.record});

  final CrashRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        StackerTheme.severityColor(record.severity, theme.brightness);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Icon(
        record.severity == CrashSeverity.fatal
            ? Icons.dangerous_rounded
            : Icons.warning_amber_rounded,
        color: color,
        size: 22,
      ),
      title: Text(
        record.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: StackerTheme.monospace(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: <Widget>[
            StackerBadge(label: record.errorType, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                record.source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ),
            Text(
              formatClockTime(record.timestamp),
              style: StackerTheme.monospace(
                fontSize: 10,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _CrashDetailScreen(record: record),
        ),
      ),
    );
  }
}

/// Full detail for one crash.
class _CrashDetailScreen extends StatelessWidget {
  const _CrashDetailScreen({required this.record});

  final CrashRecord record;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: StackerTheme.themeFor(Theme.of(context).brightness),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final color =
              StackerTheme.severityColor(record.severity, theme.brightness);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Crash detail'),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.copy_all_rounded),
                  tooltip: 'Copy full report',
                  onPressed: () => copyToClipboard(
                    context,
                    record.toReport(),
                    message: 'Crash report copied',
                  ),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            StackerBadge(
                              label: record.severity.name.toUpperCase(),
                              color: color,
                            ),
                            const SizedBox(width: 6),
                            StackerBadge(
                              label: record.source.name,
                              color: theme.disabledColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          record.error,
                          style: StackerTheme.monospace(
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: 'Timestamp',
                          value: formatFullTimestamp(record.timestamp),
                        ),
                        if (record.library != null)
                          _DetailRow(
                            label: 'Library',
                            value: record.library!,
                          ),
                        if (record.context != null)
                          _DetailRow(
                            label: 'Context',
                            value: record.context!,
                          ),
                        if (record.isolateName != null)
                          _DetailRow(
                            label: 'Isolate',
                            value: record.isolateName!,
                          ),
                      ],
                    ),
                  ),
                ),
                if (record.metadata.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  StackerSection(
                    title: 'Metadata',
                    child: StackerKeyValueTable(entries: record.metadata),
                  ),
                ],
                const SizedBox(height: 10),
                StackerSection(
                  title: 'Stack trace',
                  subtitle: record.topFrame,
                  child: StackerCodeBlock(
                    content: record.stackTrace ?? '',
                    emptyLabel: 'No stack trace was captured',
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 0.5,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: StackerTheme.monospace(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
