import 'package:flutter/material.dart';

import '../core/stacker_config.dart';
import '../stacker.dart';
import 'stacker_theme.dart';
import 'screens/dashboard_screen.dart';

/// Dart entry point for the standalone dashboard engine.
///
/// A pure-native app has no Flutter UI of its own, so the dashboard runs in a
/// dedicated engine started by `StackerActivity` (Android) or
/// `StackerDashboardPresenter` (iOS). Both use this function as the entry
/// point, which is why it carries the `vm:entry-point` pragma — without it,
/// tree shaking would remove it from a release AOT build.
///
/// The initial route is `/stacker/<tab>`, set by the host, so the dashboard
/// opens directly on the tab the caller asked for.
@pragma('vm:entry-point')
Future<void> stackerDashboardMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A native host is responsible for its own debug gating, so capture is
  // forced on here: this engine only ever starts because the host explicitly
  // launched the dashboard.
  await Stacker.init(
    config: const StackerConfig(
      enabledOverride: true,
      // The dashboard is the whole UI here, so an in-app bubble and toasts
      // over the top of it would be redundant.
      showLauncherBubble: false,
      toastPolicy: ToastPolicy.never,
    ),
  );

  runApp(const StackerDashboardApp());
}

/// Root widget of the standalone dashboard engine.
class StackerDashboardApp extends StatelessWidget {
  const StackerDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final initialTab = _tabFromRoute(
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    );
    return MaterialApp(
      title: 'Stacker',
      debugShowCheckedModeBanner: false,
      theme: StackerTheme.themeFor(Brightness.light),
      darkTheme: StackerTheme.themeFor(Brightness.dark),
      home: StackerDashboard(initialTab: initialTab),
    );
  }

  /// Parses `/stacker/<tab>` into a [DashboardTab].
  static DashboardTab _tabFromRoute(String route) {
    final segments = Uri.tryParse(route)?.pathSegments ?? const <String>[];
    if (segments.length < 2) return DashboardTab.api;
    return DashboardTab.fromName(segments.last);
  }
}
