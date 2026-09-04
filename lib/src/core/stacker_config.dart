/// When the in-app toast for each API call should appear.
enum ToastPolicy {
  /// Show a toast for every completed call.
  always,

  /// Show a toast only for non-2xx responses and transport failures.
  errorsOnly,

  /// Never show toasts. The dashboard still records everything.
  never,
}

/// Configuration for the Stacker library.
///
/// Every field has a working default, so `const StackerConfig()` is a valid
/// production-safe starting point.
class StackerConfig {
  const StackerConfig({
    this.maxApiRecords = 200,
    this.maxCrashRecords = 100,
    this.maxLeakRecords = 100,
    this.toastPolicy = ToastPolicy.always,
    this.toastDuration = const Duration(seconds: 3),
    this.showLauncherBubble = true,
    this.captureCrashes = true,
    this.detectLeaks = true,
    this.leakRetentionWindow = const Duration(seconds: 8),
    this.memorySampleInterval = const Duration(seconds: 5),
    this.maxBodyLength = 250 * 1024,
    this.redactedHeaders = defaultRedactedHeaders,
    this.redactedBodyKeys = defaultRedactedBodyKeys,
    this.redactionPlaceholder = '••• redacted •••',
    this.enabledOverride,
  })  : assert(maxApiRecords > 0, 'maxApiRecords must be positive'),
        assert(maxCrashRecords > 0, 'maxCrashRecords must be positive'),
        assert(maxLeakRecords > 0, 'maxLeakRecords must be positive'),
        assert(maxBodyLength > 0, 'maxBodyLength must be positive');

  /// Headers redacted by default. Matching is case-insensitive.
  ///
  /// Bearer tokens and cookies are the most common accidental leak when a
  /// developer shares a captured call, so they are hidden unless overridden.
  static const Set<String> defaultRedactedHeaders = <String>{
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
    'x-auth-token',
    'x-access-token',
    'x-csrf-token',
    'x-session-token',
    'api-key',
    'apikey',
  };

  /// JSON body keys redacted by default. Matching is case-insensitive.
  static const Set<String> defaultRedactedBodyKeys = <String>{
    'password',
    'newPassword',
    'oldPassword',
    'token',
    'accessToken',
    'refreshToken',
    'idToken',
    'clientSecret',
    'secret',
    'pin',
    'otp',
    'ssn',
    'cardNumber',
    'cvv',
  };

  /// Maximum number of API calls kept in the ring buffer.
  final int maxApiRecords;

  /// Maximum number of crashes kept in the ring buffer.
  final int maxCrashRecords;

  /// Maximum number of leaks kept in the ring buffer.
  final int maxLeakRecords;

  final ToastPolicy toastPolicy;
  final Duration toastDuration;

  /// Whether the draggable in-app bubble is shown by `StackerOverlay`.
  final bool showLauncherBubble;

  /// Whether Flutter and Dart error handlers are installed.
  final bool captureCrashes;

  /// Whether leak detection is active.
  final bool detectLeaks;

  /// How long after `expectDisposed` an object may stay reachable before it
  /// is reported. Generous by default to avoid false positives from
  /// animations and route transitions still holding a reference.
  final Duration leakRetentionWindow;

  /// How often resident memory is sampled for trend detection.
  final Duration memorySampleInterval;

  /// Bodies longer than this are truncated before being stored, so a large
  /// download cannot balloon memory usage.
  final int maxBodyLength;

  final Set<String> redactedHeaders;
  final Set<String> redactedBodyKeys;

  /// Text substituted for a redacted value.
  final String redactionPlaceholder;

  /// Forces capture on or off, bypassing the automatic debug-mode check.
  ///
  /// Leave this `null` in almost all cases. Setting it to `true` will capture
  /// traffic in a release build; see the README's security note before doing so.
  final bool? enabledOverride;

  StackerConfig copyWith({
    int? maxApiRecords,
    int? maxCrashRecords,
    int? maxLeakRecords,
    ToastPolicy? toastPolicy,
    Duration? toastDuration,
    bool? showLauncherBubble,
    bool? captureCrashes,
    bool? detectLeaks,
    Duration? leakRetentionWindow,
    Duration? memorySampleInterval,
    int? maxBodyLength,
    Set<String>? redactedHeaders,
    Set<String>? redactedBodyKeys,
    String? redactionPlaceholder,
    bool? enabledOverride,
  }) {
    return StackerConfig(
      maxApiRecords: maxApiRecords ?? this.maxApiRecords,
      maxCrashRecords: maxCrashRecords ?? this.maxCrashRecords,
      maxLeakRecords: maxLeakRecords ?? this.maxLeakRecords,
      toastPolicy: toastPolicy ?? this.toastPolicy,
      toastDuration: toastDuration ?? this.toastDuration,
      showLauncherBubble: showLauncherBubble ?? this.showLauncherBubble,
      captureCrashes: captureCrashes ?? this.captureCrashes,
      detectLeaks: detectLeaks ?? this.detectLeaks,
      leakRetentionWindow: leakRetentionWindow ?? this.leakRetentionWindow,
      memorySampleInterval: memorySampleInterval ?? this.memorySampleInterval,
      maxBodyLength: maxBodyLength ?? this.maxBodyLength,
      redactedHeaders: redactedHeaders ?? this.redactedHeaders,
      redactedBodyKeys: redactedBodyKeys ?? this.redactedBodyKeys,
      redactionPlaceholder: redactionPlaceholder ?? this.redactionPlaceholder,
      enabledOverride: enabledOverride ?? this.enabledOverride,
    );
  }
}
