/// Where a crash or error was observed.
enum CrashSource {
  /// Thrown inside the Flutter framework (build, layout, paint, gesture).
  flutterFramework,

  /// An uncaught Dart error outside the framework, via `PlatformDispatcher`.
  dartUncaught,

  /// A caught error reported explicitly through the public API.
  manual,

  /// An uncaught Java/Kotlin exception on Android.
  androidNative,

  /// An uncaught Objective-C/Swift exception or fatal signal on iOS.
  iosNative,
}

/// How severe an entry is; drives the colour of the row in the dashboard.
enum CrashSeverity {
  /// The app terminated, or would have.
  fatal,

  /// Recorded but the app kept running.
  nonFatal,
}

/// One captured crash or uncaught error, with a timestamp.
class CrashRecord {
  const CrashRecord({
    required this.id,
    required this.timestamp,
    required this.error,
    required this.source,
    this.severity = CrashSeverity.fatal,
    this.stackTrace,
    this.library,
    this.context,
    this.isolateName,
    this.metadata = const <String, String>{},
  });

  /// Stable identifier, unique for the process lifetime.
  final String id;

  /// When the crash was observed.
  final DateTime timestamp;

  /// The `toString()` of the thrown object.
  final String error;

  /// Formatted stack trace, when one was available.
  final String? stackTrace;

  final CrashSource source;
  final CrashSeverity severity;

  /// The library the error came from, as reported by `FlutterErrorDetails`.
  final String? library;

  /// What the framework was doing when the error occurred.
  final String? context;

  /// Name of the isolate that raised the error, when known.
  final String? isolateName;

  /// Extra key/value pairs attached by the caller.
  final Map<String, String> metadata;

  /// First line of [error], used for the collapsed list row.
  String get title {
    final firstLine = error.split('\n').first.trim();
    return firstLine.isEmpty ? 'Unknown error' : firstLine;
  }

  /// The exception's runtime type when [error] follows the
  /// `TypeName: message` convention, otherwise `'Error'`.
  String get errorType {
    final match = RegExp(r'^([A-Za-z_$][\w$<>,. ]*?):').firstMatch(error);
    return match?.group(1)?.trim() ?? 'Error';
  }

  /// The top-most application frame, useful as a one-line locator.
  String? get topFrame {
    final trace = stackTrace;
    if (trace == null || trace.isEmpty) return null;
    for (final line in trace.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Skip framework noise so the first shown frame is more likely app code.
      if (trimmed.contains('package:flutter/') ||
          trimmed.contains('dart:async') ||
          trimmed.contains('dart:ui')) {
        continue;
      }
      return trimmed;
    }
    return stackTrace!.split('\n').first.trim();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'error': error,
        'stackTrace': stackTrace,
        'source': source.name,
        'severity': severity.name,
        'library': library,
        'context': context,
        'isolateName': isolateName,
        'metadata': metadata,
      };

  /// Builds a record from a native platform payload.
  factory CrashRecord.fromNative(Map<dynamic, dynamic> raw) {
    final rawTime = raw['timestamp'];
    final timestamp = rawTime is int
        ? DateTime.fromMillisecondsSinceEpoch(rawTime)
        : DateTime.tryParse(rawTime?.toString() ?? '') ?? DateTime.now();

    final sourceName = raw['source']?.toString();
    final source = CrashSource.values.firstWhere(
      (candidate) => candidate.name == sourceName,
      orElse: () => CrashSource.manual,
    );

    final severityName = raw['severity']?.toString();
    final severity = CrashSeverity.values.firstWhere(
      (candidate) => candidate.name == severityName,
      orElse: () => CrashSeverity.fatal,
    );

    return CrashRecord(
      id: raw['id']?.toString() ??
          'crash-${DateTime.now().microsecondsSinceEpoch}',
      timestamp: timestamp,
      error: raw['error']?.toString() ?? 'Unknown native error',
      stackTrace: raw['stackTrace']?.toString(),
      source: source,
      severity: severity,
      library: raw['library']?.toString(),
      context: raw['context']?.toString(),
      isolateName: raw['isolateName']?.toString(),
      metadata: raw['metadata'] is Map
          ? (raw['metadata'] as Map).map(
              (key, dynamic value) =>
                  MapEntry(key.toString(), value?.toString() ?? ''),
            )
          : const <String, String>{},
    );
  }

  /// Renders the record as a shareable report.
  String toReport() {
    final buffer = StringBuffer()
      ..writeln('[${severity.name.toUpperCase()}] $errorType')
      ..writeln('Time: ${timestamp.toIso8601String()}')
      ..writeln('Source: ${source.name}');
    if (library != null) buffer.writeln('Library: $library');
    if (context != null) buffer.writeln('Context: $context');
    if (isolateName != null) buffer.writeln('Isolate: $isolateName');
    for (final entry in metadata.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    buffer
      ..writeln('\nError')
      ..writeln(error);
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      buffer
        ..writeln('\nStack trace')
        ..writeln(stackTrace);
    }
    return buffer.toString();
  }
}
