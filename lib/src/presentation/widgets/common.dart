import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stacker_theme.dart';

/// A small rounded label, used for status codes, methods, and severities.
class StackerBadge extends StatelessWidget {
  const StackerBadge({
    required this.label,
    required this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: StackerTheme.monospace(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled, collapsible section used throughout the detail screens.
class StackerSection extends StatelessWidget {
  const StackerSection({
    required this.title,
    required this.child,
    this.subtitle,
    this.initiallyExpanded = true,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool initiallyExpanded;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Theme(
        // Remove the default divider lines so the card border is the only edge.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          subtitle: subtitle == null
              ? null
              : Text(subtitle!, style: theme.textTheme.bodySmall),
          children: <Widget>[child],
        ),
      ),
    );
  }
}

/// Renders a map as aligned, copyable key/value rows.
class StackerKeyValueTable extends StatelessWidget {
  const StackerKeyValueTable({
    required this.entries,
    this.emptyLabel = 'None',
    super.key,
  });

  final Map<String, String> entries;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          emptyLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.disabledColor,
          ),
        ),
      );
    }

    final sortedKeys = entries.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final key in sortedKeys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: SelectableText.rich(
              TextSpan(
                children: <TextSpan>[
                  TextSpan(
                    text: '$key: ',
                    style: StackerTheme.monospace(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  TextSpan(
                    text: entries[key] ?? '',
                    style: StackerTheme.monospace(
                      fontSize: 12,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A selectable monospaced code block with a copy button.
class StackerCodeBlock extends StatelessWidget {
  const StackerCodeBlock({
    required this.content,
    this.emptyLabel = 'Empty',
    this.maxLines,
    super.key,
  });

  final String content;
  final String emptyLabel;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (content.trim().isEmpty) {
      return Text(
        emptyLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.disabledColor,
        ),
      );
    }

    return Stack(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 44, 12),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.35)
                : const Color(0xFFF1F3F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            content,
            maxLines: maxLines,
            style: StackerTheme.monospace(fontSize: 12, height: 1.45),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            onPressed: () => copyToClipboard(context, content),
          ),
        ),
      ],
    );
  }
}

/// Placeholder shown when a list has no rows.
class StackerEmptyState extends StatelessWidget {
  const StackerEmptyState({
    required this.icon,
    required this.title,
    this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 52, color: theme.disabledColor),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A horizontal row of single-select filter chips.
class StackerFilterBar<T> extends StatelessWidget {
  const StackerFilterBar({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(labelOf(value)),
                selected: value == selected,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12),
                onSelected: (_) => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }
}

/// Copies [text] to the clipboard and confirms with a snackbar.
Future<void> copyToClipboard(
  BuildContext context,
  String text, {
  String message = 'Copied to clipboard',
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

String _pad2(int value) => value.toString().padLeft(2, '0');

String _pad3(int value) => value.toString().padLeft(3, '0');

/// Formats a timestamp as `HH:mm:ss.mmm`, the precision a debugger needs.
String formatClockTime(DateTime time) {
  return '${_pad2(time.hour)}:${_pad2(time.minute)}:${_pad2(time.second)}'
      '.${_pad3(time.millisecond)}';
}

/// Formats a timestamp as `yyyy-MM-dd HH:mm:ss.mmm`.
String formatFullTimestamp(DateTime time) {
  return '${time.year}-${_pad2(time.month)}-${_pad2(time.day)} '
      '${formatClockTime(time)}';
}

/// Formats a duration for display, switching units for readability.
String formatDuration(Duration duration) {
  final ms = duration.inMilliseconds;
  if (ms < 1000) return '$ms ms';
  return '${(ms / 1000).toStringAsFixed(2)} s';
}

/// Formats a byte count using binary units.
String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(1)} ${units[index]}';
}
