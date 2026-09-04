# Changelog

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
