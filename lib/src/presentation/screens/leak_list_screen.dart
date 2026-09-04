import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/leak_record.dart';
import '../blocs/leak_list/leak_list_bloc.dart';
import '../stacker_theme.dart';
import '../widgets/common.dart';

/// Lists detected memory leaks, newest first.
class LeakListScreen extends StatelessWidget {
  const LeakListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LeakListBloc, LeakListState>(
      builder: (context, state) {
        final records = state.visibleRecords;
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search object type or details',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (value) => context
                    .read<LeakListBloc>()
                    .add(LeakListSearchChanged(value)),
              ),
            ),
            StackerFilterBar<LeakListFilter>(
              values: LeakListFilter.values,
              selected: state.filter,
              labelOf: (filter) => filter.label,
              onSelected: (filter) => context
                  .read<LeakListBloc>()
                  .add(LeakListFilterChanged(filter)),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: records.isEmpty
                  ? const StackerEmptyState(
                      icon: Icons.eco_outlined,
                      title: 'No leaks detected',
                      message:
                          'Call Stacker.watchForLeaks(obj) where an object is '
                          'created and Stacker.expectDisposed(obj) in its '
                          'dispose(). Anything still reachable afterwards is '
                          'reported here.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: records.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _LeakRow(record: records[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LeakRow extends StatelessWidget {
  const _LeakRow({required this.record});

  final LeakRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        StackerTheme.confidenceColor(record.confidence, theme.brightness);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Icon(
        switch (record.kind) {
          LeakKind.retainedObject => Icons.link_rounded,
          LeakKind.growingHeap => Icons.trending_up_rounded,
          LeakKind.nativeReport => Icons.phone_android_rounded,
        },
        color: color,
        size: 22,
      ),
      title: Text(
        record.title,
        maxLines: 1,
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
            StackerBadge(
              label: record.confidence.name.toUpperCase(),
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                record.retainedForMs != null
                    ? 'retained ${record.retainedForMs} ms'
                    : record.rssDeltaBytes != null
                        ? '+${LeakRecord.formatBytes(record.rssDeltaBytes!)}'
                        : record.kind.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ),
            Text(
              formatClockTime(record.detectedAt),
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
          builder: (_) => _LeakDetailScreen(record: record),
        ),
      ),
    );
  }
}

/// Full detail for one detected leak.
class _LeakDetailScreen extends StatelessWidget {
  const _LeakDetailScreen({required this.record});

  final LeakRecord record;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: StackerTheme.themeFor(Theme.of(context).brightness),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final color = StackerTheme.confidenceColor(
            record.confidence,
            theme.brightness,
          );
          return Scaffold(
            appBar: AppBar(
              title: const Text('Leak detail'),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.copy_all_rounded),
                  tooltip: 'Copy full report',
                  onPressed: () => copyToClipboard(
                    context,
                    record.toReport(),
                    message: 'Leak report copied',
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
                              label: record.confidence.name.toUpperCase(),
                              color: color,
                            ),
                            const SizedBox(width: 6),
                            StackerBadge(
                              label: record.kind.name,
                              color: theme.disabledColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          record.title,
                          style: StackerTheme.monospace(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        _LeakMetric(
                          label: 'Detected',
                          value: formatFullTimestamp(record.detectedAt),
                        ),
                        if (record.allocatedAt != null)
                          _LeakMetric(
                            label: 'Registered',
                            value: formatFullTimestamp(record.allocatedAt!),
                          ),
                        if (record.retainedForMs != null)
                          _LeakMetric(
                            label: 'Retained for',
                            value: '${record.retainedForMs} ms past disposal',
                          ),
                        if (record.gcCyclesSurvived != null)
                          _LeakMetric(
                            label: 'Checks survived',
                            value: '${record.gcCyclesSurvived}',
                          ),
                        if (record.rssBytes != null)
                          _LeakMetric(
                            label: 'Resident memory',
                            value: LeakRecord.formatBytes(record.rssBytes!),
                          ),
                        if (record.rssDeltaBytes != null)
                          _LeakMetric(
                            label: 'Memory change',
                            value:
                                '${record.rssDeltaBytes! >= 0 ? '+' : '-'}'
                                '${LeakRecord.formatBytes(record.rssDeltaBytes!.abs())}',
                          ),
                      ],
                    ),
                  ),
                ),
                if (record.details != null) ...<Widget>[
                  const SizedBox(height: 10),
                  StackerSection(
                    title: 'What this means',
                    child: Text(
                      record.details!,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                StackerSection(
                  title: 'Allocation stack trace',
                  subtitle: 'Where the watched object was registered',
                  initiallyExpanded: record.allocationStackTrace != null,
                  child: StackerCodeBlock(
                    content: record.allocationStackTrace ?? '',
                    emptyLabel:
                        'No allocation trace. Traces are only captured in '
                        'debug builds.',
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

class _LeakMetric extends StatelessWidget {
  const _LeakMetric({required this.label, required this.value});

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
            width: 116,
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
