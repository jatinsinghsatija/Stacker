import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';
import 'package:stacker_inspector/src/core/service_locator.dart';

/// Reproduces the exact wiring the README tells users to adopt:
/// `StackerOverlay` installed via `MaterialApp.builder`, with a page that
/// also calls `Stacker.openDashboard`.
///
/// Both entry points must reach the dashboard. A silent no-op here means a
/// user taps the bubble and nothing happens, which is exactly the bug this
/// file exists to prevent.
void main() {
  setUp(() async {
    await Stacker.init(
      config: const StackerConfig(enabledOverride: true),
    );
  });

  tearDown(() async {
    await Stacker.dispose();
    await StackerLocator.tearDown();
  });

  Widget buildApp() {
    return MaterialApp(
      builder: (context, child) => StackerOverlay(child: child),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            actions: <Widget>[
              IconButton(
                key: const Key('open-dashboard'),
                icon: const Icon(Icons.dashboard_outlined),
                onPressed: () => Stacker.openDashboard(context),
              ),
            ],
          ),
          body: const Center(child: Text('host app')),
        ),
      ),
    );
  }

  testWidgets('the overlay bubble opens the dashboard', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // The bubble is rendered by the overlay.
    final bubble = find.byIcon(Icons.layers_rounded);
    expect(bubble, findsOneWidget, reason: 'the bubble must be visible');

    await tester.tap(bubble);
    await tester.pumpAndSettle();

    expect(
      find.text('Stacker'),
      findsOneWidget,
      reason: 'tapping the bubble must push the dashboard, not silently no-op',
    );
    expect(find.text('Network'), findsOneWidget);
  });

  testWidgets('Stacker.openDashboard opens the dashboard', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-dashboard')));
    await tester.pumpAndSettle();

    expect(find.text('Stacker'), findsOneWidget);
    expect(find.text('Network'), findsOneWidget);
  });

  testWidgets('the dashboard can be popped back to the host app',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.layers_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Stacker'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('host app'), findsOneWidget);
  });

  testWidgets('the overlay renders the host app beneath it', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(
      find.text('host app'),
      findsOneWidget,
      reason: 'the overlay must not hide the app it wraps',
    );
  });
}
