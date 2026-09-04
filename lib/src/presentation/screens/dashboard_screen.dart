import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/service_locator.dart';
import '../blocs/api_list/api_list_bloc.dart';
import '../blocs/crash_list/crash_list_bloc.dart';
import '../blocs/leak_list/leak_list_bloc.dart';
import '../stacker_theme.dart';
import 'api_list_screen.dart';
import 'crash_list_screen.dart';
import 'leak_list_screen.dart';

/// Tabs of the dashboard.
enum DashboardTab {
  api('api', 'Network', Icons.swap_vert_rounded),
  crashes('crashes', 'Crashes', Icons.error_outline_rounded),
  leaks('leaks', 'Memory', Icons.memory_rounded);

  const DashboardTab(this.channelName, this.label, this.icon);

  /// Identifier used across the method channel.
  final String channelName;
  final String label;
  final IconData icon;

  /// Parses a channel identifier, defaulting to [DashboardTab.api].
  static DashboardTab fromName(String? name) {
    return DashboardTab.values.firstWhere(
      (tab) => tab.channelName == name,
      orElse: () => DashboardTab.api,
    );
  }
}

/// The Stacker inspector dashboard.
///
/// Provides its own [Theme] and its own three BLoCs, so it can be pushed onto
/// any navigator — or hosted as the root widget of a native activity — without
/// depending on anything the host app has set up.
class StackerDashboard extends StatefulWidget {
  const StackerDashboard({this.initialTab = DashboardTab.api, super.key});

  /// Route name used when Stacker pushes the dashboard itself.
  static const String routeName = '/stacker';

  final DashboardTab initialTab;

  @override
  State<StackerDashboard> createState() => _StackerDashboardState();
}

class _StackerDashboardState extends State<StackerDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: DashboardTab.values.length,
      initialIndex: widget.initialTab.index,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Guard against being shown before init, which would throw in the locator.
    if (!StackerLocator.isReady) {
      return const _DashboardUnavailable();
    }

    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<ApiListBloc>(
          create: (_) => StackerLocator.get<ApiListBloc>()
            ..add(const ApiListSubscriptionRequested()),
        ),
        BlocProvider<CrashListBloc>(
          create: (_) => StackerLocator.get<CrashListBloc>()
            ..add(const CrashListSubscriptionRequested()),
        ),
        BlocProvider<LeakListBloc>(
          create: (_) => StackerLocator.get<LeakListBloc>()
            ..add(const LeakListSubscriptionRequested()),
        ),
      ],
      child: Theme(
        data: StackerTheme.themeFor(Theme.of(context).brightness),
        child: Builder(
          // A nested Builder so the Scaffold reads the Stacker theme rather
          // than the host app's.
          builder: (themedContext) => Scaffold(
            appBar: AppBar(
              title: const Text('Stacker'),
              titleTextStyle: Theme.of(themedContext)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear the current tab',
                  onPressed: () => _clearCurrentTab(themedContext),
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                tabs: <Widget>[
                  for (final tab in DashboardTab.values)
                    Tab(
                      icon: Icon(tab.icon, size: 18),
                      child: _TabLabel(tab: tab),
                    ),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: const <Widget>[
                ApiListScreen(),
                CrashListScreen(),
                LeakListScreen(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _clearCurrentTab(BuildContext context) {
    final tab = DashboardTab.values[_tabController.index];
    switch (tab) {
      case DashboardTab.api:
        context.read<ApiListBloc>().add(const ApiListCleared());
      case DashboardTab.crashes:
        context.read<CrashListBloc>().add(const CrashListCleared());
      case DashboardTab.leaks:
        context.read<LeakListBloc>().add(const LeakListCleared());
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cleared ${tab.label.toLowerCase()}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Tab label with a live count, so a problem is visible without switching tabs.
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.tab});

  final DashboardTab tab;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      DashboardTab.api => BlocBuilder<ApiListBloc, ApiListState>(
          buildWhen: (previous, current) =>
              previous.records.length != current.records.length,
          builder: (context, state) =>
              _label(tab.label, state.records.length),
        ),
      DashboardTab.crashes => BlocBuilder<CrashListBloc, CrashListState>(
          buildWhen: (previous, current) =>
              previous.records.length != current.records.length,
          builder: (context, state) =>
              _label(tab.label, state.records.length),
        ),
      DashboardTab.leaks => BlocBuilder<LeakListBloc, LeakListState>(
          buildWhen: (previous, current) =>
              previous.records.length != current.records.length,
          builder: (context, state) =>
              _label(tab.label, state.records.length),
        ),
    };
  }

  Widget _label(String text, int count) =>
      Text(count == 0 ? text : '$text ($count)');
}

/// Shown when the dashboard is opened without Stacker being initialised.
class _DashboardUnavailable extends StatelessWidget {
  const _DashboardUnavailable();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: StackerTheme.themeFor(Theme.of(context).brightness),
      child: Scaffold(
        appBar: AppBar(title: const Text('Stacker')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.visibility_off_outlined, size: 52),
                SizedBox(height: 14),
                Text(
                  'Stacker is not capturing',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  'Capture is disabled in release builds. Call Stacker.init() '
                  'from a debug build, or set StackerConfig.enabledOverride '
                  'if you intentionally need capture here.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
