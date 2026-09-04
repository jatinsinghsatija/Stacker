import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_host/main.dart' as host;

/// The module's only real contract is that it re-exports the dashboard entry
/// point under the exact name `StackerActivity` and
/// `StackerDashboardPresenter` start the engine with.
///
/// If this name is ever renamed or the export dropped, `flutter build aar`
/// still succeeds and the AAR still publishes — but every native host crashes
/// at runtime with a missing-entry-point error. That silent failure is what
/// this test exists to catch at build time.
void main() {
  test('the module exports the dashboard entry point', () {
    expect(
      host.stackerDashboardMain,
      isA<Function>(),
      reason: 'StackerActivity starts its engine at "stackerDashboardMain"; '
          'renaming it breaks every native host at runtime',
    );
  });
}
