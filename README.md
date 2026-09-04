<div align="center">

<img src="doc/stacker_icon.svg" width="96" height="96" alt="Stacker icon" />

# Stacker

**A Chucker-style debug inspector for API calls, crashes, and memory leaks —
for Flutter, native Android, native iOS, and hybrid apps.**

`pub add stacker_inspector` for Flutter · one Gradle line for native Android

[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.27-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%5E3.9-0175C2?logo=dart)](https://dart.dev)
[![BLoC](https://img.shields.io/badge/state-BLoC-6A1B9A)](https://bloclibrary.dev)
[![DI](https://img.shields.io/badge/DI-GetIt-00897B)](https://pub.dev/packages/get_it)
[![Tests](https://img.shields.io/badge/tests-159%20passing-2E7D32)]()
[![pub.dev](https://img.shields.io/badge/pub.dev-stacker-0175C2)](https://pub.dev/packages/stacker_inspector)
[![JitPack](https://img.shields.io/badge/JitPack-native%20Android-brightgreen)](https://jitpack.io)
[![Release safe](https://img.shields.io/badge/release-auto%20disabled-C62828)]()

</div>

---

## What it does

| | |
|---|---|
| 🌐 **Every API call** | Status code **and what it means**, request/response headers, query params, path params, bodies, timings, sizes |
| 💥 **Crashes** | Uncaught Flutter, Dart, and native errors with a timestamp and full stack trace |
| 🧠 **Memory leaks** | Retained-object detection via `WeakReference`, plus resident-memory trend sampling |
| 🍞 **Live toasts** | Each call raises a toast with its status code and endpoint, on **all three platforms** — **debug only** |
| 🧭 **Separate launcher icon** | A second app icon that opens the dashboard directly — **debug only** |
| 🎯 **Intent / deep link** | Open the dashboard from native code any time |
| 🔒 **Release safe** | Capture, toasts, icon, and timers are all **off** in release builds |

### Install

No Flutter SDK required for the native paths — both ship prebuilt binaries.

| Your app | Channel | Install |
|---|---|---|
| **Flutter / hybrid** | pub.dev | `flutter pub add stacker_inspector` |
| **Native Android** | JitPack | one Gradle line — [§2](#2-native-android-kotlinjava--via-jitpack) |
| **Native iOS** | CocoaPods | one Podfile line — [§3](#3-native-ios-swift--via-cocoapods) |

---

## Table of contents

- [Quick start](#quick-start)
- [Integration: Flutter app](#1-flutter-app-2-lines)
- [Integration: native Android (JitPack)](#2-native-android-kotlinjava--via-jitpack)
- [Integration: native iOS (CocoaPods)](#3-native-ios-swift--via-cocoapods)
- [Integration: hybrid / add-to-app](#4-hybrid--add-to-app)
- [The debug-only launcher icon](#the-debug-only-launcher-icon)
- [Opening the dashboard](#opening-the-dashboard)
- [Memory leak detection](#memory-leak-detection)
- [Crash capture](#crash-capture)
- [Configuration](#configuration)
- [Security](#security-read-this)
- [Architecture](#architecture)
- [What Stacker does *not* do](#what-stacker-does-not-do)
- [Troubleshooting](#troubleshooting)

---

## Quick start

```yaml
# pubspec.yaml
dependencies:
  stacker_inspector: ^0.2.0
```

```dart
import 'package:stacker_inspector/stacker_inspector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Stacker.init();                      // ← 1. initialise
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => StackerOverlay(child: child),  // ← 2. toasts + bubble
    home: const HomePage(),
  );
}
```

```dart
// 3. attach to your HTTP client
dio.interceptors.add(StackerDioInterceptor());
```

That's it. Run in debug and every call appears in the dashboard.

---

## 1. Flutter app (2 lines)

### Step 1 — initialise

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Stacker.init();
  runApp(const MyApp());
}
```

> **Release builds:** `init()` returns immediately and registers nothing. Leave
> this line in — no `if (kDebugMode)` guard needed.

### Step 2 — add the overlay

```dart
MaterialApp(
  builder: (context, child) => StackerOverlay(child: child),
  home: const HomePage(),
)
```

This adds the per-call toast stack and the draggable layers bubble that opens
the dashboard. In release it returns `child` untouched.

### Step 3 — attach to your HTTP client

<details open>
<summary><b>Dio</b></summary>

```dart
final dio = Dio()
  ..interceptors.add(StackerDioInterceptor());   // add LAST
```

Add it **last** so it sees the final headers after any auth or retry
interceptor has run.

To show path parameters in the dashboard, pass them explicitly — Dio
interpolates the path before interceptors run, so the template is not
recoverable:

```dart
dio.get(
  '/users/42/orders',
  options: Options(extra: {
    'stacker.pathParameters': {'userId': '42'},
  }),
);
```
</details>

<details>
<summary><b>package:http</b></summary>

```dart
final client = StackerHttpClient(inner: http.Client());
final response = await client.get(Uri.parse('https://api.example.com/users'));
```

Use this client everywhere you would use `http.Client()`. The response body is
buffered for capture and handed back as a fresh stream, so your code reads it
normally.
</details>

<details>
<summary><b>Retrofit (Dart)</b></summary>

Retrofit delegates to Dio, so the Dio interceptor covers it:

```dart
final dio = Dio()..interceptors.add(StackerDioInterceptor());
final api = RestClient(dio);
```
</details>

<details>
<summary><b>Chopper, GraphQL, or a custom client</b></summary>

Both Chopper and `graphql_flutter` accept a `package:http` client:

```dart
// Chopper
ChopperClient(client: StackerHttpClient(inner: http.Client()), ...);

// graphql_flutter
HttpLink('https://api.example.com/graphql',
  httpClient: StackerHttpClient(inner: http.Client()));
```

For anything else, record calls yourself:

```dart
Stacker.recordApiCall(ApiRecord(
  id: 'my-call-1',
  method: 'GET',
  url: 'https://api.example.com/thing',
  requestTime: DateTime.now(),
  statusCode: 200,
  responseTime: DateTime.now(),
  state: ApiCallState.complete,
));
```
</details>

---

## 2. Native Android (Kotlin/Java) — via JitPack

**One dependency line.** No Flutter SDK on your machine, no submodules, no
manifest edits. In a debug build a second launcher icon appears next to your
app's own icon; tapping it opens the full Stacker dashboard.

### Step 1 — add the repository

```gradle
// settings.gradle
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' }
        // Hosts the Flutter engine artifacts the dashboard needs.
        maven { url 'https://storage.googleapis.com/download.flutter.io' }
    }
}
```

### Step 2 — add the dependency

```gradle
// app/build.gradle
dependencies {
    def stacker = 'com.github.jatinsinghsatija.Stacker'
    def stackerVersion = 'v0.2.0'

    debugImplementation   "$stacker:stacker_inspector_debug:$stackerVersion"
    debugImplementation   "$stacker:flutter_debug:$stackerVersion"

    // Optional. Omit both lines to keep Stacker out of release builds
    // entirely — see "Release builds" below.
    releaseImplementation "$stacker:stacker_inspector_release:$stackerVersion"
    releaseImplementation "$stacker:flutter_release:$stackerVersion"
}
```

> ### ⚠️ Do not use the aggregate coordinate
>
> JitPack's page will offer you a single line like
> `com.github.jatinsinghsatija:Stacker:v0.2.0`. **It does not work here.** That
> coordinate resolves to an aggregate POM listing all four modules, so Gradle
> pulls the debug *and* release Flutter engines into the same variant and the
> build fails:
>
> ```
> Execution failed for task ':app:mergeDebugNativeLibs'.
> > 2 files found with path 'lib/armeabi-v7a/libflutter.so'
> ```
>
> Use the four per-variant lines above instead. Note the group id gains a
> `.stacker` suffix (`com.github.USER.stacker`, not `com.github.USER`) — that
> is JitPack's convention for multi-module builds.

That is the whole integration. The launcher icon, the dashboard activity, and
the icon assets all arrive through manifest merging.

> **Why `1.0` and not the release number?** `flutter build aar` always stamps
> its output as Maven version `1.0` — this is a Flutter toolchain behaviour,
> not a Stacker choice. You select a *release* with the JitPack tag, which
> pins which immutable build you resolve:
>
> ```gradle
> dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { 
            url 'https://jitpack.io'
            content {includeGroupByRegex 'com.github.jatinsinghsatija.*'}
               }
        maven { 
            url 'https://storage.googleapis.com/download.flutter.io'
            content {includeGroupByRegex 'io.flutter.*'}
               }
         }
}
> ```
>
> To move between Stacker releases, change the tag JitPack builds (see the
> JitPack page for the repo), not the `1.0` in these lines.

<details>
<summary><b>Requirements — please read, these are not optional</b></summary>

| Requirement | Value | Why |
|---|---|---|
| `compileSdk` | **36 or higher** | Set by the Flutter engine AAR, not by Stacker. Building against 35 fails with "requires libraries and applications that depend on it to compile against version 36 or later". |
| Android Gradle Plugin | **8.9+** | Needed for `compileSdk 36`. |
| `minSdk` | 24+ | |
| Debug APK size | **+~90 MB** | The Flutter engine plus the compiled dashboard. Debug only. Verified on a bare native app: 49 MB → 141 MB. |

If a ~90 MB debug APK is unacceptable for your team, use
`debugImplementation` on a dedicated build variant, or skip the dashboard and
consume records yourself — see "Capture without the dashboard" below.
</details>

### Step 3 — turn capture on

One call, in your `Application`:

```kotlin
class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        if (BuildConfig.DEBUG) {
            StackerAndroid.enable(this)
        }
    }
}
```

`StackerAndroid.enable()` does four things:

1. turns capture on, so the OkHttp interceptor starts recording;
2. shows a **per-call toast** for every completed request and every crash —
   the same dark card the Flutter overlay draws;
3. installs the crash handler;
4. warms the dashboard's Flutter engine so the first open is instant.

<details>
<summary>Tuning it</summary>

```kotlin
StackerAndroid.enable(
    this,
    // ALL (default) · ERRORS_ONLY · NONE
    toastPolicy = StackerToast.Policy.ERRORS_ONLY,
    // Pass false if you use Crashlytics, Sentry or Bugsnag — see the crash caveat.
    installCrashHandler = false,
    // Pass false to skip ~1s of background work at launch.
    warmUpDashboard = false,
)
```

Toasts are drawn from Kotlin, not routed through Flutter, so they appear on
your native screens whether or not the dashboard has ever been opened. Tapping
one opens the dashboard on the matching tab.
</details>

> The launcher icon works without any of this — the icon and dashboard
> function on their own. `enable()` is what turns on **capture and toasts**.

### Step 4 — add the OkHttp interceptor

```kotlin
val client = OkHttpClient.Builder()
    .addInterceptor(StackerOkHttpInterceptor())   // add LAST
    .build()
```

Add it **last** so it sees the final request after any auth or retry
interceptor has run. This covers **Retrofit** too, since Retrofit runs on
OkHttp:

```kotlin
Retrofit.Builder()
    .client(client)
    .baseUrl("https://api.example.com/")
    .build()
```

<details>
<summary>Interceptor options</summary>

```kotlin
StackerOkHttpInterceptor(
    maxBodyBytes = 512L * 1024L,
    redactedHeaders = setOf("authorization", "x-my-secret"),
)
```
</details>

### Opening the dashboard from code

The launcher icon is usually enough, but you can open it directly:

```kotlin
StackerActivity.launch(this, initialTab = "crashes")   // api | crashes | leaks
startActivity(StackerActivity.intent(this, "api"))
```

**By explicit intent** — from adb, another module, or a debug menu:

```kotlin
val intent = Intent().apply {
    component = ComponentName(packageName, "com.stacker.stacker.StackerActivity")
    putExtra("com.stacker.INITIAL_TAB", "api")
}
startActivity(intent)
```

```bash
adb shell am start -n com.example.myapp/com.stacker.stacker.StackerActivity
```

### Release builds

Two independent safeguards, both verified against real APKs:

1. **The launcher alias lives in the library's `debug` source set**, so
   `stacker_release.aar` does not contain it. It cannot be enabled at runtime
   because it is not in the artifact.
2. **`StackerPlugin` refuses to enable the component** unless
   `FLAG_DEBUGGABLE` is set on the host app.

Measured on a bare native Kotlin app consuming these exact artifacts:

| | debug APK | release APK |
|---|---|---|
| Launcher icons | **2** (app + Stacker) | **1** (app only) |
| `StackerLauncherAlias` | present | **absent** |
| `ic_stacker` resources | present | **0, stripped** |

For maximum certainty, omit the two `releaseImplementation` lines. Stacker is
then absent from release builds entirely — but note that any code calling
`StackerActivity` or `StackerOkHttpInterceptor` must then be inside a
`debug`-only source set, or your release build will not compile.

### Capture without the dashboard

`StackerOkHttpInterceptor` and `StackerCrashHandler` have **no Flutter
dependency**. If you only want to capture records and render them in your own
UI, take `stacker_debug` alone and omit `flutter_debug` — the capture classes
work, and the launcher icon simply opens nothing. This is a deliberate,
supported configuration; it is not a drop-in Chucker replacement.

---

## 3. Native iOS (Swift) — via CocoaPods

**One Podfile line.** No Flutter SDK on your machine or on CI — the pod ships
prebuilt XCFrameworks. Shake the device or tap the floating bubble to open the
dashboard.

### Step 1 — add the pod

```ruby
# Podfile
platform :ios, '13.0'

target 'MyApp' do
  use_frameworks!

  pod 'StackerInspector',
      :podspec => 'https://raw.githubusercontent.com/jatinsinghsatija/Stacker/v0.2.0/StackerInspector.podspec',
      :configurations => ['Debug']
end
```

```bash
pod install
```

`:configurations => ['Debug']` keeps Stacker out of your release builds
entirely — the equivalent of Android's `debugImplementation`.

> ### Use the `/Debug` subspec on simulators
>
> The pod ships two framework sets and the choice matters:
>
> | Subspec | Runs on | Why |
> |---|---|---|
> | `StackerInspector/Debug` | **simulator + device** | JIT engine with a Dart kernel blob |
> | `StackerInspector/Release` | device only | AOT engine; Apple's AOT compiler does not target the simulator |
>
> `StackerInspector/Debug` is the default, so plain `pod 'StackerInspector'`
> also works. Pinning `/Release` and then running on a simulator fails with
> `Engine run configuration was invalid` and a black dashboard — verified, and
> the reason both sets are shipped.

<details>
<summary><b>Requirements — please read</b></summary>

| Requirement | Value | Why |
|---|---|---|
| Deployment target | **iOS 13+** | Flutter engine minimum. |
| `use_frameworks!` | **required** | The pod vends dynamic XCFrameworks. |
| First `pod install` | **~142 MB download** | Both the Debug (JIT, simulator-capable) and Release (AOT) framework sets. CocoaPods caches it, so this is a one-time cost per machine. |
| Xcode | 15+ | |

If a `:configurations => ['Debug']` pod is not viable for your setup, see
"Release builds" below for the alternative.
</details>

### Step 2 — enable it

One call, in `AppDelegate`:

```swift
import StackerInspector

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        StackerAutoAttach.enable()
        #endif
        return true
    }
}
```

`StackerAutoAttach.enable()` does four things:

1. turns capture on;
2. registers `StackerURLProtocol` globally, so `URLSession.shared` traffic is
   captured;
3. installs a **shake gesture** that opens the dashboard from any screen;
4. shows a **draggable floating bubble** as a second way in.

```swift
StackerAutoAttach.enable(showBubble: false)   // shake gesture only
```

> **Why no second home-screen icon on iOS?** iOS has no equivalent of
> Android's `activity-alias`. The only supported way to change an app's icon is
> `setAlternateIconName`, which replaces the app's *own* icon and shows a
> system alert every time — unusable for a debug tool. The shake gesture and
> bubble are the standard iOS substitutes.

### Step 3 — capture URLSession traffic

`StackerAutoAttach.enable()` already calls `registerGlobally()`, which reaches
`URLSession.shared` and any session built from a default configuration —
covering **Alamofire** and most SDKs.

It does **not** reach a session whose `protocolClasses` were replaced
wholesale, nor a background session; the OS loads those outside the app's URL
loading system. For those, install into the configuration directly:

```swift
let config = URLSessionConfiguration.default
StackerURLProtocol.install(in: config)
let session = URLSession(configuration: config)
```

### Step 4 — crash capture (optional)

```swift
#if DEBUG
StackerCrashHandler.install()
#endif
```

> ⚠️ **Do not call this if you already use Crashlytics, Sentry, or Bugsnag.**
> They install their own handlers and whichever installs last wins the signal
> path. Use `StackerCrashHandler.recordNonFatal(_:)` for handled errors
> instead, and let the dedicated SDK own fatal crashes. See
> [Crash capture](#crash-capture) for the full caveat.

### Opening the dashboard from code

```swift
StackerAutoAttach.openDashboard(initialTab: "crashes")   // api | crashes | leaks
StackerDashboardPresenter.shared.present(initialTab: "api")
```

**Via a URL scheme** — add one to a debug-only `Info.plist`, then:

```swift
func application(_ app: UIApplication, open url: URL, options: ...) -> Bool {
    #if DEBUG
    if url.scheme == "stacker" {
        StackerAutoAttach.openDashboard(initialTab: url.host ?? "api")
        return true
    }
    #endif
    return false
}
```

```bash
xcrun simctl openurl booted stacker://crashes
```

### Release builds

`:configurations => ['Debug']` is the primary safeguard — the pod is not
linked into release builds at all, so nothing to strip.

If you must link it in every configuration, the runtime gate still holds:
capture stays off until `StackerAutoAttach.enable()` is called, so guarding
that one call with `#if DEBUG` is sufficient. The bubble and shake gesture are
both no-ops while capture is disabled.

### If the dashboard renders letterboxed

If the dashboard (or your whole app) appears inset with black bands top and
bottom, your app is running in iOS **compatibility mode** — a legacy 4.7"
canvas — not full screen. This is an app-level setting, not something Stacker
controls.

Your `Info.plist` needs a launch-screen declaration. Modern apps use:

```xml
<key>UILaunchScreen</key>
<dict/>
```

Older projects use `UILaunchStoryboardName` pointing at a storyboard. With
neither key present, iOS letterboxes the app and every view inside it,
including the dashboard.

### Debugging note

Flutter needs an LLDB init file to debug correctly when embedded on recent iOS
versions. If you hit breakpoint oddities in your *own* code after adding
Stacker, follow Flutter's
[Set LLDB Init File](https://docs.flutter.dev/to/ios-add-to-app-embed-setup)
step. This affects debugging only, never runtime behaviour.

---

## 4. Hybrid / add-to-app

Already have Flutter screens inside a native app? Do both:

1. **Native side** — the OkHttp interceptor (Android) or `StackerURLProtocol` (iOS)
   for native traffic.
2. **Flutter side** — `Stacker.init()` plus the Dio/http interceptor for Dart traffic.

Both feed the **same dashboard**. Each row shows an origin badge —
🤖 `ANDROID`, 📱 `IOS`, or 💙 `DART` — so you can tell which layer made the call.

> **Startup calls are not lost.** Native requests made before the Flutter engine
> attaches are buffered (up to 200) and drained into the dashboard as soon as
> Dart connects.

---

## The debug-only launcher icon

A second app icon that opens the dashboard straight from the launcher, exactly
like Chucker.

### Android — automatic

**You do not add any manifest XML.** The `activity-alias` ships inside the
library's own `debug` source set, so it merges into your app the moment you
add the dependency. Add Stacker, build a debug APK, and a second icon appears
on the home screen.

<img src="doc/stacker_icon.svg" width="56" height="56" align="left" hspace="12" alt="" />

The `@mipmap/ic_stacker_launcher` icon ships with the library — three offset
plates under a magnifier, so the stack reads at launcher size and is never
mistaken for your own app icon. The mark above is the same artwork
(`doc/stacker_icon.svg`), generated from the launcher vector so the two cannot
drift apart.

<br clear="left" />

Two independent safeguards keep it out of production:

1. The alias is in the library's `debug` source set, so `stacker_release.aar`
   does not contain it at all. It cannot be turned on at runtime because it is
   not in the artifact.
2. `StackerPlugin` refuses to enable the component when `FLAG_DEBUGGABLE` is
   absent, even if asked.

<details>
<summary>Customising the label or icon</summary>

Override the string resource in your own `src/debug/res/values/strings.xml`:

```xml
<resources>
    <string name="stacker_launcher_label">Debug tools</string>
</resources>
```

For a different icon, declare your own alias in
`src/debug/AndroidManifest.xml` pointing at
`com.stacker.stacker.StackerActivity` with your own `android:icon`, and
disable the bundled one:

```xml
<activity-alias
    android:name="com.stacker.stacker.StackerLauncherAlias"
    android:enabled="false"
    tools:node="merge" />
```
</details>


### iOS — shake or bubble instead

iOS has no `activity-alias` equivalent, so no library can add a second
home-screen icon. `setAlternateIconName` replaces the app's *own* icon and
shows a system alert on every call, which rules it out for a debug tool.

The substitutes, all debug-gated:

| Mechanism | Native iOS | Flutter |
|---|---|---|
| **Shake the device** | `StackerAutoAttach.enable()` | — |
| **Floating bubble** | `StackerAutoAttach.enable()` | `StackerOverlay` |
| **URL scheme** | debug-only `Info.plist` | same |
| **Code** | `StackerAutoAttach.openDashboard()` | `Stacker.openDashboard(context)` |

---

## Opening the dashboard

| From | Code |
|---|---|
| Flutter | `Stacker.openDashboard(context)` |
| Flutter (specific tab) | `Stacker.openDashboard(context, initialTab: DashboardTab.leaks)` |
| Flutter → native host | `Stacker.openNativeDashboard()` |
| Android | `StackerActivity.launch(context, "api")` |
| iOS (native) | `StackerAutoAttach.openDashboard(initialTab: "api")` |
| iOS — shake | shake the device, after `StackerAutoAttach.enable()` |
| iOS — bubble | tap the floating button |
| In-app bubble | Tap the layers button (from `StackerOverlay`) |
| Launcher | Tap the Stacker launcher icon (Android debug) |
| A toast | Tap it to jump to that record |
| As a route | `MaterialPageRoute(builder: (_) => const StackerDashboard())` |

---

## Memory leak detection

Two mechanisms with deliberately different confidence levels.

### 1. Retained objects — `CONFIRMED`

Register an object, then declare when it should be gone. If it is **still
reachable** after the retention window and three check cycles, something holds
a strong reference to it. That is proof, not a guess — the same principle
LeakCanary uses.

```dart
class _MyPageState extends State<MyPage> {
  @override
  void initState() {
    super.initState();
    Stacker.watchForLeaks(this, label: 'MyPage');
  }

  @override
  void dispose() {
    Stacker.expectDisposed(this);   // ← "this should now be garbage"
    super.dispose();
  }
}
```

Works for anything with a lifecycle — BLoCs, controllers, repositories:

```dart
class MyBloc extends Bloc<MyEvent, MyState> {
  MyBloc() : super(MyState()) {
    Stacker.watchForLeaks(this);
  }

  @override
  Future<void> close() {
    Stacker.expectDisposed(this);
    return super.close();
  }
}
```

> Only a `WeakReference` is kept, so watching an object never keeps it alive
> and never *causes* the leak it is looking for.

**Typical culprits:** an uncancelled `StreamSubscription`, a live `Timer`, an
`AnimationController` that was never disposed, a listener still registered, or
a closure capturing `this` stored in a long-lived singleton.

### 2. Growing resident memory — `SUSPECTED`

Resident memory is sampled on an interval. Six consecutive rises totalling
more than 24 MB, with no fall-back, are reported as **suspected** — never
confirmed, because a warming image or response cache produces the same shape.

---

## Crash capture

### Flutter and Dart — reliable

`Stacker.init()` installs three handlers, covering all three escape routes:

| Hook | Catches |
|---|---|
| `FlutterError.onError` | Framework errors (build, layout, paint, gestures) |
| `PlatformDispatcher.onError` | Uncaught async Dart errors |
| `Isolate.addErrorListener` | Errors that bypass both |

Any existing handler is **chained**, so Crashlytics, Sentry, and the red screen
keep working.

Record a handled error explicitly:

```dart
try {
  await riskyOperation();
} catch (error, stackTrace) {
  Stacker.recordError(
    error,
    stackTrace,
    context: 'Syncing the cart',
    metadata: {'cartId': cart.id},
  );
}
```

### Native crashes — read the caveat

<details>
<summary><b>⚠️ Native fatal crashes are best-effort. Expand for the honest details.</b></summary>

**Android** (`StackerCrashHandler.install()`) hooks
`Thread.setDefaultUncaughtExceptionHandler` and chains to the previous handler.

**iOS** (`StackerCrashHandler.install()`) hooks `NSSetUncaughtExceptionHandler`
and `sigaction` for `SIGABRT`/`SIGSEGV`/`SIGBUS`/`SIGILL`/`SIGFPE`/`SIGTRAP`.

Three real limitations:

1. **Records are in-memory only.** They do not survive the crash. Reopening the
   app shows an empty crash list. A crash caught while the dashboard is already
   open is usually visible; a crash during startup generally is not.
2. **A signal handler may only call async-signal-safe functions.** Sending a
   record over a method channel is not one of them. The signal path is
   deliberately minimal and delivery is not guaranteed.
3. **It conflicts with Crashlytics, Sentry, and Bugsnag**, which install their
   own handlers. Whichever installs last wins the signal path.

**Recommendation:** if you already use a real crash reporter, **do not call
`install()`**. Use `recordNonFatal()` for handled errors and let the dedicated
SDK own fatal crashes. Stacker's crash tab is then a live view of Flutter-side
errors during a debug session, which is what it is genuinely good at.
</details>

---

## Configuration

Every field has a sensible default; `const StackerConfig()` is production-safe.

```dart
await Stacker.init(
  config: const StackerConfig(
    // Buffer sizes (fixed-capacity ring buffers, oldest evicted)
    maxApiRecords: 200,
    maxCrashRecords: 100,
    maxLeakRecords: 100,

    // Toasts
    toastPolicy: ToastPolicy.always,        // always | errorsOnly | never
    toastDuration: Duration(seconds: 3),

    // UI
    showLauncherBubble: true,

    // Detectors
    captureCrashes: true,
    detectLeaks: true,
    leakRetentionWindow: Duration(seconds: 8),
    memorySampleInterval: Duration(seconds: 5),

    // Payload limits
    maxBodyLength: 250 * 1024,

    // Redaction
    redactedHeaders: StackerConfig.defaultRedactedHeaders,
    redactedBodyKeys: StackerConfig.defaultRedactedBodyKeys,
    redactionPlaceholder: '••• redacted •••',
  ),
);
```

**Only want toasts for failures?**

```dart
await Stacker.init(
  config: const StackerConfig(toastPolicy: ToastPolicy.errorsOnly),
);
```

**Reading captured data programmatically:**

```dart
final failures = Stacker.apiRecords.where((r) => !r.isSuccess);
final report   = Stacker.apiRecords.first.toReport();
final curl     = Stacker.apiRecords.first.toCurl();
```

---

## Security: read this

### Secrets are redacted at capture time

`Authorization`, `Cookie`, `X-Api-Key`, and friends — plus body keys like
`password`, `accessToken`, `clientSecret` — are replaced **before** anything
reaches the buffer. A redacted value never exists in memory, so it cannot leak
through a shared report or a screenshot.

Redaction walks nested JSON, so `{"data":{"user":{"accessToken":"…"}}}` is
caught too.

**What redaction does not cover.** Matching is by *key name*, applied to
request headers, query parameters, and request bodies. A secret that appears
in a **response body** under a key Stacker does not know about is stored as
received — if your login endpoint returns `{"jwt": "…"}`, add `jwt` to
`redactedBodyKeys`. Likewise a token embedded in free-form text, or in a key
you have not listed, is not detected. Redaction is a strong default, not a
guarantee: review the list against your own API surface.

Add your own:

```dart
const StackerConfig(
  redactedHeaders: {...StackerConfig.defaultRedactedHeaders, 'x-internal-token'},
  redactedBodyKeys: {...StackerConfig.defaultRedactedBodyKeys, 'nationalId'},
)
```

### Nothing is written to disk

Records live in memory for the process lifetime only. No storage permission is
needed and no captured token is left on the device after the app exits.

### ⚠️ `enabledOverride`

```dart
const StackerConfig(enabledOverride: true)   // DANGER
```

This forces capture on **in release builds**. That means real user request and
response bodies, and any header you have not added to the redaction list, held
in the memory of a shipped app — with a dashboard that anyone holding the phone
can open.

Only use it for an internal QA build that never reaches a store, and treat that
build as containing production data. **Never ship it.**

---

## Architecture

```
lib/
├── stacker.dart                    # public API barrel
└── src/
    ├── core/
    │   ├── http_status.dart         # status code → meaning (all IANA + Cloudflare/nginx)
    │   ├── stacker_config.dart
    │   ├── redactor.dart            # capture-time secret removal
    │   ├── id_generator.dart
    │   └── service_locator.dart     # GetIt container
    ├── data/
    │   ├── models/                  # ApiRecord, CrashRecord, LeakRecord
    │   ├── repository/              # RingBuffer + StackerRepository
    │   └── sources/                 # method + event channel bridge
    ├── domain/
    │   ├── crash_reporter.dart      # 3 error hooks, chained
    │   └── leak_detector.dart       # WeakReference retention + RSS trend
    ├── interceptors/                # Dio interceptor, http client wrapper
    └── presentation/
        ├── blocs/                   # api_list, crash_list, leak_list
        ├── screens/                 # dashboard, list + detail per tab
        └── widgets/                 # overlay (toasts + bubble), shared UI
```

### BLoC

Each tab has a bloc with explicit events and states:

```dart
// Events                              // State
ApiListSubscriptionRequested           ApiListState(
ApiListUpdated                           status, records, query, filter
ApiListSearchChanged                   )
ApiListFilterChanged                   → state.visibleRecords
ApiListCleared
```

The repository is the single source of truth; blocs mirror it and layer search
and filtering on top. Filtering lives in the state's `visibleRecords` getter,
so changing a filter never discards captured data.

### Dependency injection

A **dedicated `GetIt` instance** (`GetIt.asNewInstance()`), not `GetIt.instance`
— your app probably uses GetIt too, and a shared container would mean Stacker's
registrations and yours fighting over the same namespace.

```dart
StackerLocator.get<StackerRepository>();   // singleton
StackerLocator.get<ApiListBloc>();          // factory — fresh per route
```

### Testing

159 tests, all passing:

```
ring_buffer          10   capacity, eviction, in-place replacement
redactor             15   headers, nested JSON, form bodies, truncation
http_status          11   every class, boundaries, unofficial codes
repository           15   ordering, capacity, streams, post-dispose safety
api_list_bloc        15   events, states, filters, search
leak_detector        14   real retention detection + false-positive suppression
crash_reporter       14   3 hooks, handler chaining, native parsing
dio_interceptor      14   against a real loopback HTTP server
http_client           8   stream re-emission verified
service_locator      12   DI wiring, isolation, hot restart
overlay_navigation    4   both dashboard entry points actually navigate
overlay_toast        10   toast content, policies, capping, tap-to-open
dashboard_widget     17   full UI, navigation, empty states
```

```bash
flutter test
```

---

## What Stacker does *not* do

Being explicit so you can pick the right tool:

| Not supported | Use instead |
|---|---|
| Full retaining paths for a leak | Flutter DevTools → Memory → heap snapshot |
| Crash reports surviving a restart | Crashlytics, Sentry |
| Capturing native traffic from a background `URLSession` (iOS) | `StackerURLProtocol.install(in:)` on that session |
| Capturing traffic from a session with `protocolClasses` replaced (iOS) | Same |
| Capturing raw sockets / gRPC over HTTP2 | Not intercepted |
| Persisting records across app restarts | By design — nothing touches disk |
| A second home-screen icon on iOS | OS limitation — use the shake gesture or bubble |
| Production monitoring | Datadog, New Relic |

---

## Troubleshooting

<details>
<summary><b>No calls appear in the dashboard</b></summary>

1. Confirm capture is on: `print(Stacker.isEnabled)`. It is `false` in release.
2. Confirm `await Stacker.init()` ran *before* the request.
3. Confirm the interceptor is attached to the **same** client instance making calls.
4. On Android, confirm `StackerOkHttpInterceptor` is on the `OkHttpClient` your
   Retrofit instance actually uses.
</details>

<details>
<summary><b>The launcher icon does not appear (Android)</b></summary>

1. The `activity-alias` must be in `src/debug/AndroidManifest.xml`, not `src/main/`.
2. The app must be debuggable — check `BuildConfig.DEBUG`.
3. Some launchers cache the icon list; try relaunching the launcher.
4. Verify the merged manifest: `./gradlew :app:processDebugManifest` then inspect
   `app/build/intermediates/merged_manifests/`.
</details>

<details>
<summary><b>No toasts</b></summary>

`StackerOverlay` must wrap your app via `MaterialApp.builder`, and
`toastPolicy` must not be `never`. A toast only fires for a *completed* call,
never a pending one.
</details>

<details>
<summary><b>A leak is not reported</b></summary>

You need **both** halves: `watchForLeaks` at creation and `expectDisposed` at
the end of life. Reporting also requires the retention window (default 8 s) to
elapse *and* three check cycles at `memorySampleInterval` (default 5 s) — so
allow roughly 20 seconds.
</details>

<details>
<summary><b>ProviderNotFoundException when opening a record</b></summary>

Only happens if you push `ApiDetailScreen` yourself. It needs `ApiListBloc` in
scope:

```dart
BlocProvider.value(
  value: context.read<ApiListBloc>(),
  child: ApiDetailScreen(recordId: id),
)
```

Pushing `StackerDashboard` (the supported path) handles this for you.
</details>

<details>
<summary><b>Response body is empty for a large download</b></summary>

Bodies are truncated at `maxBodyLength` (250 KB default) so capture cannot
balloon memory. Raise it if you need more, or expect binary payloads to show as
`<binary N bytes>`.
</details>

<details>
<summary><b>iOS: <code>pod install</code> is slow or the download is huge</b></summary>

Expected. The pod is ~142 MB because it carries **two** complete framework
sets: Debug (JIT, the only one that runs on a simulator) and Release (AOT, for
device builds). Shipping Release alone would black-screen every simulator, so
both are required. CocoaPods caches it per machine, so only the first
`pod install` pays that cost.
</details>

<details>
<summary><b>iOS: "No such module 'StackerInspector'"</b></summary>

1. `use_frameworks!` must be present in the Podfile — the pod vends dynamic
   frameworks.
2. Open the `.xcworkspace`, never the `.xcodeproj`.
3. If you used `:configurations => ['Debug']`, the module only exists in Debug
   builds. Any code importing it must be inside `#if DEBUG`.
</details>

<details>
<summary><b>iOS: shake gesture does nothing</b></summary>

1. `StackerAutoAttach.enable()` must have run — it is what installs the hook.
2. On the simulator, use **Device ▸ Shake** rather than moving the mouse.
3. If your app already swizzles `motionEnded`, whichever installs last wins.
   Use the bubble or call `openDashboard()` from your own debug menu instead.
</details>

<details>
<summary><b>iOS: breakpoints behave oddly after adding Stacker</b></summary>

Flutter needs an LLDB init file when embedded on recent iOS versions. Follow
Flutter's [Set LLDB Init File](https://docs.flutter.dev/to/ios-add-to-app-embed-setup)
step. This affects debugging only, not runtime behaviour.
</details>

---

## Publishing (maintainers)

**Full step-by-step guide: [RELEASE.md](RELEASE.md).** It assumes no prior
publishing experience and covers all three channels, including what "success"
looks like at each step.

One repository, three channels:

| Channel | Command | Notes |
|---|---|---|
| **pub.dev** | `flutter pub publish` | Permanent — a version can never be reused. Publish `0.2.0-dev.1` first. |
| **JitPack** | `git tag v0.2.0 && git push origin v0.2.0` | Builds on demand; nothing to upload. First build takes 10–20 min. |
| **CocoaPods** | `./scripts/build_ios_frameworks.sh 0.2.0` | Attach the resulting ~142 MB zip to the GitHub Release. |

Quick pre-flight:

```bash
flutter analyze && flutter test && flutter pub publish --dry-run
```

Expect `0 warnings` and an archive around **140 KB**. If it is megabytes,
`.pubignore` is broken — it exists to keep `stacker_host/` out of the package.

`.github/workflows/ci.yml` asserts the properties that matter most, so a
regression fails CI rather than shipping:

- the Android launcher alias is present in `stacker_debug` and **absent** from
  `stacker_release`;
- the published POM does not pin `kotlin-stdlib` onto consumers;
- the pub.dev archive stays small.

## License

See [LICENSE](LICENSE).
