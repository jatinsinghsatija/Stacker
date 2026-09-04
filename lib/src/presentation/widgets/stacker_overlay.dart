import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/stacker_config.dart';
import '../../core/service_locator.dart';
import '../../data/models/api_record.dart';
import '../../data/models/crash_record.dart';
import '../../data/repository/stacker_repository.dart';
import '../../stacker.dart';
import '../stacker_theme.dart';
import '../screens/dashboard_screen.dart';

/// Wraps the app to add the debug-only toast stack and dashboard bubble.
///
/// Place it as the `builder` of your [MaterialApp] so it sits above every
/// route but below the navigator's own overlays:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => StackerOverlay(child: child),
///   home: const HomePage(),
/// )
/// ```
///
/// In a release build (or whenever `Stacker.isEnabled` is false) this returns
/// [child] unchanged — no listeners, no timers, no extra widgets in the tree.
class StackerOverlay extends StatefulWidget {
  const StackerOverlay({required this.child, super.key});

  final Widget? child;

  @override
  State<StackerOverlay> createState() => _StackerOverlayState();
}

class _StackerOverlayState extends State<StackerOverlay> {
  static const int _maxVisibleToasts = 3;

  final List<_ToastEntry> _toasts = <_ToastEntry>[];
  StreamSubscription<ApiRecord>? _apiSubscription;
  StreamSubscription<CrashRecord>? _crashSubscription;

  /// Navigator that hosts the dashboard route.
  ///
  /// The overlay runs as `MaterialApp.builder`, above the app's own Navigator,
  /// so it cannot push onto it. A nested Navigator of its own means the
  /// dashboard can be opened from the bubble or a toast without the host app
  /// having to wire up a route.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Guards against pushing two dashboards on a double tap.
  bool _dashboardOpen = false;

  /// Bubble position as a fraction of the available area, so it stays sensible
  /// across rotation and window resizes.
  Alignment _bubbleAlignment = const Alignment(0.92, 0.62);

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _apiSubscription?.cancel();
    _crashSubscription?.cancel();
    for (final toast in _toasts) {
      toast.timer.cancel();
    }
    super.dispose();
  }

  void _subscribe() {
    if (!Stacker.isEnabled || !StackerLocator.isReady) return;
    final repository = StackerLocator.get<StackerRepository>();
    final config = StackerLocator.get<StackerConfig>();

    if (config.toastPolicy != ToastPolicy.never) {
      _apiSubscription = repository.completedApiStream.listen((record) {
        final isError = record.state == ApiCallState.failed || !record.isSuccess;
        if (config.toastPolicy == ToastPolicy.errorsOnly && !isError) return;
        _pushToast(_ToastData.fromApi(record));
      });
      // A crash is always worth surfacing, regardless of the API toast policy.
      _crashSubscription = repository.newCrashStream.listen(
        (record) => _pushToast(_ToastData.fromCrash(record)),
      );
    }
  }

  void _pushToast(_ToastData data) {
    if (!mounted) return;
    final config = StackerLocator.get<StackerConfig>();

    final entry = _ToastEntry(
      data: data,
      timer: Timer(config.toastDuration, () {}),
    );
    // Replace the placeholder timer with one that can reference `entry`.
    entry.timer.cancel();
    entry.timer = Timer(config.toastDuration, () => _removeToast(entry));

    setState(() {
      _toasts.add(entry);
      // Drop the oldest so a burst of calls cannot cover the whole screen.
      while (_toasts.length > _maxVisibleToasts) {
        _toasts.removeAt(0).timer.cancel();
      }
    });
  }

  void _removeToast(_ToastEntry entry) {
    if (!mounted) return;
    setState(() => _toasts.remove(entry));
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child ?? const SizedBox.shrink();
    if (!Stacker.isEnabled || !StackerLocator.isReady) return child;

    final config = StackerLocator.get<StackerConfig>();

    return Stack(
      children: <Widget>[
        // A nested Navigator whose initial route is the host app. The
        // dashboard is pushed on top of it, so the host app's own navigation
        // state is untouched and its back button still behaves normally.
        Navigator(
          key: _navigatorKey,
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            settings: settings,
            // No transition for the root: the host app must appear instantly,
            // exactly as it would without the overlay.
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, __, ___) => child,
          ),
        ),
        if (_toasts.isNotEmpty)
          Positioned(
            left: 8,
            right: 8,
            bottom: MediaQuery.of(context).padding.bottom + 12,
            child: IgnorePointer(
              // Ignore pointers on the column but not the cards themselves,
              // so a toast can be tapped while the rest stays pass-through.
              ignoring: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final toast in _toasts)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _ToastCard(
                        key: ValueKey<String>(toast.data.id),
                        data: toast.data,
                        onTap: () {
                          _removeToast(toast);
                          _openDashboard(context, toast.data.tab);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (config.showLauncherBubble)
          _DashboardBubble(
            alignment: _bubbleAlignment,
            onMoved: (alignment) =>
                setState(() => _bubbleAlignment = alignment),
            onTap: () => _openDashboard(context, DashboardTab.api),
          ),
      ],
    );
  }

  void _openDashboard(BuildContext context, DashboardTab tab) {
    // `StackerOverlay` is installed as `MaterialApp.builder`, which means its
    // BuildContext sits ABOVE the app's Navigator — so `Navigator.of(context)`
    // finds nothing here. The overlay therefore keeps its own navigator key
    // and pushes through that instead.
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    // Avoid stacking duplicate dashboards when the bubble is tapped twice.
    if (_dashboardOpen) return;
    _dashboardOpen = true;

    navigator
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => StackerDashboard(initialTab: tab),
            settings: const RouteSettings(name: StackerDashboard.routeName),
          ),
        )
        .whenComplete(() => _dashboardOpen = false);
  }
}

/// A toast currently on screen, with the timer that will retire it.
class _ToastEntry {
  _ToastEntry({required this.data, required this.timer});

  final _ToastData data;
  Timer timer;
}

/// Content of one toast.
class _ToastData {
  const _ToastData({
    required this.id,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.tab,
  });

  final String id;

  /// Status code or severity shown at the left edge.
  final String leading;
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final DashboardTab tab;

  /// Builds toast content from a completed API call.
  ///
  /// The status code and endpoint are the two things worth seeing without
  /// opening the dashboard, so they get the primary line.
  factory _ToastData.fromApi(ApiRecord record) {
    final code = record.state == ApiCallState.failed && record.statusCode == null
        ? 'ERR'
        : record.statusCode?.toString() ?? '—';
    final duration = record.duration;
    return _ToastData(
      id: record.id,
      leading: code,
      title: '${record.method} ${record.path}',
      subtitle: <String>[
        record.host,
        if (duration != null) '${duration.inMilliseconds} ms',
      ].where((part) => part.isNotEmpty).join('  •  '),
      // Resolved against a fixed brightness because the toast card paints its
      // own dark surface regardless of the host app's theme.
      color: StackerTheme.recordColor(record, Brightness.dark),
      icon: record.state == ApiCallState.failed
          ? Icons.cloud_off_rounded
          : Icons.swap_vert_rounded,
      tab: DashboardTab.api,
    );
  }

  /// Builds toast content from a crash.
  factory _ToastData.fromCrash(CrashRecord record) {
    return _ToastData(
      id: record.id,
      leading: record.severity == CrashSeverity.fatal ? 'FATAL' : 'WARN',
      title: record.errorType,
      subtitle: record.title,
      color: StackerTheme.severityColor(record.severity, Brightness.dark),
      icon: Icons.error_outline_rounded,
      tab: DashboardTab.crashes,
    );
  }
}

/// The toast card itself.
class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.data, required this.onTap, super.key});

  final _ToastData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xF01B2029),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: data.color.withValues(alpha: 0.55)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Icon(data.icon, size: 16, color: data.color),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  data.leading,
                  style: StackerTheme.monospace(
                    fontSize: 11,
                    color: data.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StackerTheme.monospace(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (data.subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 1),
                      Text(
                        data.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StackerTheme.monospace(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The draggable in-app button that opens the dashboard.
class _DashboardBubble extends StatelessWidget {
  const _DashboardBubble({
    required this.alignment,
    required this.onMoved,
    required this.onTap,
  });

  final Alignment alignment;
  final ValueChanged<Alignment> onMoved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: alignment,
          child: GestureDetector(
            onPanUpdate: (details) {
              // Convert the pixel delta into alignment space, where the full
              // width spans -1 to 1, hence the factor of two.
              final dx = details.delta.dx / (constraints.maxWidth / 2);
              final dy = details.delta.dy / (constraints.maxHeight / 2);
              onMoved(
                Alignment(
                  (alignment.x + dx).clamp(-1.0, 1.0),
                  (alignment.y + dy).clamp(-1.0, 1.0),
                ),
              );
            },
            child: Material(
              color: StackerTheme.accent,
              shape: const CircleBorder(),
              elevation: 6,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(
                    Icons.layers_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
