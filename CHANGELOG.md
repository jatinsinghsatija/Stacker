# Changelog

## 0.2.0

Fixes per-call toasts on the native platforms, and adds a native iOS binary
distribution.

### Fixed
- **Native hosts showed no toasts at all.** `showNativeToast` existed on all
  three layers and was never called from anywhere — dead code. Toasts are
  drawn by `StackerOverlay`, a Flutter widget, so a native app with no Flutter
  UI on screen could never display one. Capture worked; nothing was visible,
  which read as "the library is broken".
  - Android: `StackerToast` draws a custom view into the foreground activity.
  - iOS: `StackerToast` draws a `UIWindow` overlay.
  - Both reuse the exact colours, radii and type scale from `StackerTheme`, so
    the three platforms are visually identical. Verified on a real native
    Kotlin app and a real native Swift app, not just in the Flutter example.
- **iOS dashboard rendered black when reopened.** A `FlutterEngine` renders
  into one `FlutterViewController` at a time, and the dismissed controller
  still held the surface. The stale controller is now released first.
- **`Stacker.init()` hung forever in widget tests.** It awaits platform-channel
  calls, which never reply when no host is attached, so any app calling it from
  its own `testWidgets` froze until the framework killed the run after ten
  minutes — with no useful error. Channel calls now time out after 2s and the
  native event stream degrades to empty instead of blocking.
- **iOS toast badge stretched across the card** instead of hugging its text,
  because `UIStackView` distributed width equally. Fixed with explicit
  content-hugging priorities.
- **The iOS artifact black-screened on every simulator.** `flutter build
  ios-framework --no-debug` produces AOT Dart only for the device slice; the
  simulator slice was an 82 KB stub with zero snapshot symbols, so the engine
  failed with "Engine run configuration was invalid" and rendered a black,
  unsized view. The pod now ships **both** framework sets as `Debug` and
  `Release` subspecs — Debug (JIT, with a Dart kernel blob) runs on the
  simulator, Release (AOT) on device. The packaging script fails the build if
  the Debug simulator kernel blob is ever missing again.

### Added
- **Native iOS via CocoaPods.** `StackerInspector.podspec` vends prebuilt
  XCFrameworks, so native iOS hosts need no Flutter SDK.
  `scripts/build_ios_frameworks.sh` packages the release zip.
- `StackerAutoAttach.enable()` (iOS) and `StackerAndroid.enable()` (Android):
  one call to turn on capture, toasts, crash handling, and the dashboard
  entry point.

### Changed
- Published as `stacker_inspector` on pub.dev and `StackerInspector` on
  CocoaPods. Both `stacker` and `Stacker` were already taken by other
  packages, so the original names could not be published. Every Dart, Kotlin
  and Swift type keeps its `Stacker` prefix — no user-facing API changed.

## 0.1.0

Initial release. Published as `stacker_inspector` on pub.dev, and as prebuilt
binaries on JitPack (native Android) and CocoaPods (native iOS).

### Distribution
- **pub.dev** — `flutter pub add stacker_inspector` for Flutter and hybrid apps.
- **JitPack** — one Gradle line for native Android. The debug AAR carries an
  `activity-alias`, so a second launcher icon appears automatically with no
  manifest edits; the release AAR does not contain it at all.
- **CocoaPods** — one Podfile line for native iOS, vending prebuilt
  XCFrameworks so no Flutter SDK is needed on developer machines or CI.
  `StackerAutoAttach.enable()` installs a shake gesture and a floating bubble,
  since iOS cannot add a second home-screen icon.

### Capture
- API call recording for Dio and `package:http` on the Dart side.
- Native capture: OkHttp interceptor (Android), `URLProtocol` hook (iOS).
  Native records made before the Flutter engine attaches are buffered and
  drained once Dart connects.
- Status code meanings for every IANA-registered code plus the widely
  deployed Cloudflare and nginx codes.
- Crash capture via `FlutterError.onError`,
  `PlatformDispatcher.onError`, and `Isolate.addErrorListener`, each chained
  to any previously installed handler.
- Memory leak detection: `WeakReference` retention tracking (reported as
  confirmed) and resident-memory trend sampling (reported as suspected).

### Dashboard
- Three tabs — Network, Crashes, Memory — with per-tab search and filters.
- Detail screens showing headers, query and path parameters, bodies,
  timings, sizes, and the status code's meaning.
- Copy as cURL and copy full report.
- Debug-only per-call toasts and a draggable launcher bubble.
- Debug-only launcher icon on Android via an `activity-alias`.

### Architecture
- BLoC with explicit events and states for each tab.
- GetIt dependency injection on a dedicated container, isolated from the
  host app's own GetIt instance.
- Fixed-capacity ring buffers; nothing is written to disk.
- Credential redaction applied at capture time, including nested JSON.

### Safety
- Capture, toasts, timers, and the launcher icon are all disabled in release
  builds. `Stacker.init()` is a no-op there and needs no `kDebugMode` guard.
