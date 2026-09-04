/// Entry point used when the Stacker dashboard runs in its own Flutter engine,
/// embedded in a native Android or iOS app.
///
/// A Flutter app does not need this library — it opens the dashboard with
/// `Stacker.openDashboard(context)` instead. This exists for the native
/// add-to-app path, where `StackerActivity` (Android) and
/// `StackerDashboardPresenter` (iOS) start an engine at
/// [stackerDashboardMain].
///
/// It is a separate library from `stacker.dart` so the entry point is
/// reachable by name from a Flutter *module* without that module having to
/// import the whole public surface.
library;

export 'src/presentation/dashboard_entrypoint.dart'
    show StackerDashboardApp, stackerDashboardMain;
