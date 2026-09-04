import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';
import 'package:stacker_inspector/src/core/service_locator.dart';

ApiRecord _record({
  required String id,
  required int statusCode,
  String path = '/v1/users',
  String method = 'GET',
}) {
  return ApiRecord(
    id: id,
    method: method,
    url: 'https://api.example.com$path',
    requestTime: DateTime(2026, 9, 4, 10, 30),
    responseTime: DateTime(2026, 9, 4, 10, 30, 0, 250),
    state: ApiCallState.complete,
    statusCode: statusCode,
    requestHeaders: const <String, String>{'X-Request-Id': 'req-1'},
    queryParameters: const <String, String>{'page': '2'},
    responseHeaders: const <String, String>{'content-type': 'application/json'},
    responseBody: '{"ok":true}',
  );
}

void main() {
  late StackerRepository repository;

  setUp(() async {
    await StackerLocator.setUp(const StackerConfig());
    repository = StackerLocator.get<StackerRepository>();
  });

  tearDown(() async {
    await StackerLocator.tearDown();
  });

  Future<void> pumpDashboard(
    WidgetTester tester, {
    DashboardTab tab = DashboardTab.api,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: StackerDashboard(initialTab: tab)),
    );
    await tester.pumpAndSettle();
  }

  group('dashboard shell', () {
    testWidgets('shows the three tabs', (tester) async {
      await pumpDashboard(tester);

      expect(find.text('Stacker'), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Crashes'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);
    });

    testWidgets('shows a live count on the tab label', (tester) async {
      repository
        ..addApiRecord(_record(id: 'a', statusCode: 200))
        ..addApiRecord(_record(id: 'b', statusCode: 404));

      await pumpDashboard(tester);

      expect(find.text('Network (2)'), findsOneWidget);
    });

    testWidgets('opens on the requested tab', (tester) async {
      await pumpDashboard(tester, tab: DashboardTab.crashes);

      expect(find.text('No crashes captured'), findsOneWidget);
    });
  });

  group('API list', () {
    testWidgets('shows an empty state with integration guidance', (tester) async {
      await pumpDashboard(tester);

      expect(find.text('No API calls captured yet'), findsOneWidget);
      expect(find.textContaining('StackerDioInterceptor'), findsOneWidget);
    });

    testWidgets('lists a captured call with its status and endpoint',
        (tester) async {
      repository.addApiRecord(_record(id: 'a', statusCode: 200));

      await pumpDashboard(tester);

      expect(find.text('200'), findsOneWidget);
      expect(find.text('GET'), findsOneWidget);
      expect(find.text('/v1/users'), findsOneWidget);
      expect(find.text('api.example.com'), findsOneWidget);
    });

    testWidgets('shows the newest call first', (tester) async {
      repository
        ..addApiRecord(_record(id: 'old', statusCode: 200, path: '/old'))
        ..addApiRecord(_record(id: 'new', statusCode: 201, path: '/new'));

      await pumpDashboard(tester);

      final oldY = tester.getCenter(find.text('/old')).dy;
      final newY = tester.getCenter(find.text('/new')).dy;
      expect(newY, lessThan(oldY));
    });

    testWidgets('filters by status class', (tester) async {
      repository
        ..addApiRecord(_record(id: 'ok', statusCode: 200, path: '/ok'))
        ..addApiRecord(_record(id: 'bad', statusCode: 500, path: '/bad'));

      await pumpDashboard(tester);
      expect(find.text('/ok'), findsOneWidget);
      expect(find.text('/bad'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, '5xx'));
      await tester.pumpAndSettle();

      expect(find.text('/bad'), findsOneWidget);
      expect(find.text('/ok'), findsNothing);
    });

    testWidgets('searches by endpoint', (tester) async {
      repository
        ..addApiRecord(_record(id: 'a', statusCode: 200, path: '/users'))
        ..addApiRecord(_record(id: 'b', statusCode: 200, path: '/orders'));

      await pumpDashboard(tester);

      await tester.enterText(find.byType(TextField).first, 'orders');
      await tester.pumpAndSettle();

      expect(find.text('/orders'), findsOneWidget);
      expect(find.text('/users'), findsNothing);
    });

    testWidgets('clears the list from the app bar', (tester) async {
      repository.addApiRecord(_record(id: 'a', statusCode: 200));

      await pumpDashboard(tester);
      expect(find.text('/v1/users'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();

      expect(find.text('No API calls captured yet'), findsOneWidget);
      expect(repository.apiRecords, isEmpty);
    });
  });

  group('API detail', () {
    testWidgets('shows the status meaning, headers, and parameters',
        (tester) async {
      repository.addApiRecord(_record(id: 'a', statusCode: 404));

      await pumpDashboard(tester);
      await tester.tap(find.text('/v1/users'));
      await tester.pumpAndSettle();

      // The meaning of the code, which is the point of the feature.
      expect(find.text('404 Not Found'), findsOneWidget);
      expect(find.textContaining('No resource exists at this URL'), findsOneWidget);

      // Sections for headers and parameters. The later ones sit below the
      // fold in the test viewport, so scroll them into view rather than
      // asserting they are already painted.
      expect(find.text('Request headers'), findsOneWidget);
      expect(find.text('Query parameters'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Response headers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Response headers'), findsOneWidget);
      expect(find.text('Path parameters'), findsOneWidget);
    });

    testWidgets('shows timing and size metrics', (tester) async {
      repository.addApiRecord(_record(id: 'a', statusCode: 200));

      await pumpDashboard(tester);
      await tester.tap(find.text('/v1/users'));
      await tester.pumpAndSettle();

      expect(find.text('DURATION'), findsOneWidget);
      expect(find.text('250 ms'), findsWidgets);
    });

    testWidgets('offers a copy-as-cURL action', (tester) async {
      repository.addApiRecord(_record(id: 'a', statusCode: 200));

      await pumpDashboard(tester);
      await tester.tap(find.text('/v1/users'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.terminal_rounded), findsOneWidget);
    });
  });

  group('crash and leak tabs', () {
    testWidgets('lists a captured crash', (tester) async {
      repository.addCrash(
        CrashRecord(
          id: 'c1',
          timestamp: DateTime(2026, 9, 4, 10, 30),
          error: 'StateError: cart total went negative',
          source: CrashSource.flutterFramework,
          stackTrace: '#0 main',
        ),
      );

      await pumpDashboard(tester, tab: DashboardTab.crashes);

      expect(find.textContaining('cart total went negative'), findsOneWidget);
      expect(find.text('StateError'), findsOneWidget);
    });

    testWidgets('opens crash detail with the stack trace', (tester) async {
      repository.addCrash(
        CrashRecord(
          id: 'c1',
          timestamp: DateTime(2026, 9, 4, 10, 30),
          error: 'StateError: broke',
          source: CrashSource.manual,
          stackTrace: '#0      MyApp.build (package:myapp/main.dart:42)',
        ),
      );

      await pumpDashboard(tester, tab: DashboardTab.crashes);
      await tester.tap(find.textContaining('StateError: broke').first);
      await tester.pumpAndSettle();

      expect(find.text('Crash detail'), findsOneWidget);
      expect(find.text('Stack trace'), findsOneWidget);
      expect(find.textContaining('main.dart:42'), findsWidgets);
    });

    testWidgets('lists a detected leak with its confidence', (tester) async {
      repository.addLeak(
        LeakRecord(
          id: 'l1',
          detectedAt: DateTime(2026, 9, 4, 10, 30),
          objectType: 'MyPageState',
          kind: LeakKind.retainedObject,
          confidence: LeakConfidence.confirmed,
          retainedForMs: 9000,
          details: 'Still reachable after disposal.',
        ),
      );

      await pumpDashboard(tester, tab: DashboardTab.leaks);

      expect(find.text('MyPageState'), findsOneWidget);
      expect(find.text('CONFIRMED'), findsOneWidget);
      expect(find.textContaining('retained 9000 ms'), findsOneWidget);
    });

    testWidgets('opens leak detail with the explanation', (tester) async {
      repository.addLeak(
        LeakRecord(
          id: 'l1',
          detectedAt: DateTime(2026, 9, 4, 10, 30),
          objectType: 'MyController',
          kind: LeakKind.retainedObject,
          confidence: LeakConfidence.confirmed,
          details: 'A stream subscription was never cancelled.',
        ),
      );

      await pumpDashboard(tester, tab: DashboardTab.leaks);
      await tester.tap(find.text('MyController'));
      await tester.pumpAndSettle();

      expect(find.text('Leak detail'), findsOneWidget);
      expect(find.text('What this means'), findsOneWidget);
      expect(
        find.textContaining('stream subscription was never cancelled'),
        findsOneWidget,
      );
    });
  });

  group('when Stacker is not initialised', () {
    testWidgets('shows an explanation instead of throwing', (tester) async {
      await StackerLocator.tearDown();

      await tester.pumpWidget(
        const MaterialApp(home: StackerDashboard()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stacker is not capturing'), findsOneWidget);
      expect(find.textContaining('release builds'), findsOneWidget);
    });
  });
}
