import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/src/core/service_locator.dart';
import 'package:stacker_inspector/stacker_inspector.dart';

/// Covers the Flutter toast overlay.
///
/// This file exists because the toast path had no test at all, and that gap
/// let a real bug ship: `showNativeToast` was built on all three platforms
/// and never called from anywhere, so native Android and native iOS hosts
/// captured everything correctly but displayed nothing. Flutter worked, but
/// nothing proved it, so the asymmetry went unnoticed until it was found by
/// hand on a device.
///
/// Note on pumping: these tests never call `pumpAndSettle`. A visible toast
/// schedules a retirement `Timer`, so settling waits for an animation that is
/// pending by design and the test hangs. Explicit `pump(duration)` advances
/// the clock deterministically instead.
ApiRecord _completed({
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
    responseTime: DateTime(2026, 9, 4, 10, 30, 0, 120),
    state: ApiCallState.complete,
    statusCode: statusCode,
  );
}

void main() {
  late StackerRepository repository;

  /// Mounts the overlay and returns once the first frame is up.
  ///
  /// Deliberately uses `StackerLocator.setUp` rather than `Stacker.init`.
  /// `init` awaits platform-channel calls, and `testWidgets` runs under fake
  /// async where the real `Timer` backing their timeout never fires — so the
  /// future never completes and the test hangs until the framework kills it
  /// after ten minutes. `StackerOverlay` only needs the container, which is
  /// exactly what `setUp` provides.
  Future<void> pumpOverlay(
    WidgetTester tester, {
    ToastPolicy policy = ToastPolicy.always,
  }) async {
    await StackerLocator.setUp(
      StackerConfig(
        enabledOverride: true,
        toastPolicy: policy,
        // The bubble is irrelevant here and would match icon finders.
        showLauncherBubble: false,
      ),
    );
    Stacker.debugSetEnabledForTesting(true);
    repository = StackerLocator.get<StackerRepository>();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => StackerOverlay(child: child),
        home: const Scaffold(body: Center(child: Text('host app'))),
      ),
    );
    await tester.pump();
  }

  /// Advances just enough for a stream event to reach the overlay and paint.
  Future<void> settleToast(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  tearDown(() async {
    Stacker.debugSetEnabledForTesting(false);
    await StackerLocator.tearDown();
  });

  testWidgets('a completed call raises a toast with status and endpoint',
      (tester) async {
    await pumpOverlay(tester);

    repository.addApiRecord(_completed(id: 'a', statusCode: 200));
    await settleToast(tester);

    expect(find.text('200'), findsOneWidget);
    expect(find.text('GET /v1/users'), findsOneWidget);
  });

  testWidgets('a transport failure raises an ERR toast', (tester) async {
    await pumpOverlay(tester);

    repository.addApiRecord(
      ApiRecord(
        id: 'fail',
        method: 'GET',
        url: 'https://nope.invalid/ping',
        requestTime: DateTime(2026, 9, 4),
        responseTime: DateTime(2026, 9, 4),
        state: ApiCallState.failed,
        errorMessage: 'Connection refused',
      ),
    );
    await settleToast(tester);

    expect(
      find.text('ERR'),
      findsOneWidget,
      reason: 'a failed call has no status code to display',
    );
  });

  testWidgets('a crash raises a toast', (tester) async {
    await pumpOverlay(tester);

    repository.addCrash(
      CrashRecord(
        id: 'c1',
        timestamp: DateTime(2026, 9, 4, 10, 30),
        error: 'StateError: cart total went negative',
        source: CrashSource.manual,
        severity: CrashSeverity.nonFatal,
      ),
    );
    await settleToast(tester);

    expect(find.text('WARN'), findsOneWidget);
    expect(find.text('StateError'), findsOneWidget);
  });

  testWidgets('a pending call raises no toast', (tester) async {
    await pumpOverlay(tester);

    repository.addApiRecord(
      ApiRecord(
        id: 'pending',
        method: 'GET',
        url: 'https://api.example.com/slow',
        requestTime: DateTime(2026, 9, 4),
      ),
    );
    await settleToast(tester);

    expect(
      find.text('GET /slow'),
      findsNothing,
      reason: 'an in-flight request must not toast until it completes',
    );
  });

  testWidgets('errorsOnly hides a 2xx and shows a 5xx', (tester) async {
    await pumpOverlay(tester, policy: ToastPolicy.errorsOnly);

    repository.addApiRecord(_completed(id: 'ok', statusCode: 200, path: '/ok'));
    await settleToast(tester);
    expect(find.text('200'), findsNothing);

    repository.addApiRecord(
      _completed(id: 'bad', statusCode: 500, path: '/bad'),
    );
    await settleToast(tester);
    expect(find.text('500'), findsOneWidget);
  });

  testWidgets('ToastPolicy.never suppresses everything', (tester) async {
    await pumpOverlay(tester, policy: ToastPolicy.never);

    repository.addApiRecord(_completed(id: 'a', statusCode: 500));
    repository.addCrash(
      CrashRecord(
        id: 'c',
        timestamp: DateTime(2026, 9, 4),
        error: 'StateError: x',
        source: CrashSource.manual,
      ),
    );
    await settleToast(tester);

    expect(find.text('500'), findsNothing);
    expect(find.text('FATAL'), findsNothing);
  });

  testWidgets('a burst is capped at three visible toasts', (tester) async {
    await pumpOverlay(tester);

    for (var i = 0; i < 6; i++) {
      repository.addApiRecord(
        _completed(id: 'r$i', statusCode: 200, path: '/r$i'),
      );
      await tester.pump();
    }
    await settleToast(tester);

    expect(
      find.text('200'),
      findsNWidgets(3),
      reason: 'a burst of calls must not cover the whole screen',
    );
    expect(find.text('GET /r0'), findsNothing);
    expect(find.text('GET /r5'), findsOneWidget);
  });

  testWidgets('a toast retires on its own', (tester) async {
    await pumpOverlay(tester);

    repository.addApiRecord(_completed(id: 'a', statusCode: 200));
    await settleToast(tester);
    expect(find.text('200'), findsOneWidget);

    // Default toastDuration is 3s; add the 140ms fade.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('200'), findsNothing);
  });

  testWidgets('tapping a toast opens the dashboard', (tester) async {
    await pumpOverlay(tester);

    repository.addApiRecord(_completed(id: 'a', statusCode: 404));
    await settleToast(tester);

    await tester.tap(find.text('404'));

    // Cannot use pumpAndSettle: the toast's retirement Timer is pending by
    // design, so settling would wait forever. Pump enough frames for the
    // route transition to finish instead.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Stacker'), findsOneWidget);
    // The tab label carries a live count, e.g. "Network (1)", so match the
    // prefix rather than the bare word.
    expect(find.textContaining('Network'), findsOneWidget);

    // Let the toast's retirement Timer expire. flutter_test asserts that no
    // Timer is pending when the widget tree is disposed, so leaving it live
    // fails the test after the assertions have already passed.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the overlay is inert when capture is disabled', (tester) async {
    // No Stacker.init at all — the release-build path.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => StackerOverlay(child: child),
        home: const Scaffold(body: Center(child: Text('host app'))),
      ),
    );
    await tester.pump();

    expect(
      find.text('host app'),
      findsOneWidget,
      reason: 'the overlay must pass the app through untouched',
    );
  });
}
