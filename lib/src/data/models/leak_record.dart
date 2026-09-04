/// How a suspected leak was detected.
enum LeakKind {
  /// A watched object was still reachable after the retention window and
  /// several forced GC cycles — a genuine retain cycle in Dart.
  retainedObject,

  /// Resident memory grew steadily across consecutive samples without
  /// falling back, which suggests an unbounded allocation somewhere.
  growingHeap,

  /// Reported by the platform's own tooling on the native side.
  nativeReport,
}

/// Confidence that an entry is a real leak rather than noise.
enum LeakConfidence {
  /// The object outlived its retention window and survived forced GCs.
  confirmed,

  /// A trend was observed, but it may be legitimate caching or warm-up.
  suspected,
}

/// One suspected memory leak, with the time it was detected.
class LeakRecord {
  const LeakRecord({
    required this.id,
    required this.detectedAt,
    required this.objectType,
    required this.kind,
    this.confidence = LeakConfidence.suspected,
    this.label,
    this.allocatedAt,
    this.retainedForMs,
    this.rssBytes,
    this.rssDeltaBytes,
    this.gcCyclesSurvived,
    this.details,
    this.allocationStackTrace,
  });

  /// Stable identifier, unique for the process lifetime.
  final String id;

  /// When the leak was flagged.
  final DateTime detectedAt;

  /// Runtime type of the object that leaked, e.g. `_MyPageState`.
  final String objectType;

  /// Optional caller-supplied label distinguishing several instances.
  final String? label;

  final LeakKind kind;
  final LeakConfidence confidence;

  /// When the object was registered for watching.
  final DateTime? allocatedAt;

  /// How long the object stayed reachable past its expected disposal.
  final int? retainedForMs;

  /// Resident set size at detection time, in bytes.
  final int? rssBytes;

  /// Change in resident set size across the observed window, in bytes.
  final int? rssDeltaBytes;

  /// Number of forced GC cycles the object survived.
  final int? gcCyclesSurvived;

  /// Extra human-readable explanation.
  final String? details;

  /// Stack trace captured when the object was registered, so the
  /// allocation site is visible in the dashboard.
  final String? allocationStackTrace;

  /// Display title for the list row.
  String get title => label == null ? objectType : '$objectType ($label)';

  /// [retainedForMs] as a [Duration], when present.
  Duration? get retainedFor =>
      retainedForMs == null ? null : Duration(milliseconds: retainedForMs!);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'detectedAt': detectedAt.toIso8601String(),
        'objectType': objectType,
        'label': label,
        'kind': kind.name,
        'confidence': confidence.name,
        'allocatedAt': allocatedAt?.toIso8601String(),
        'retainedForMs': retainedForMs,
        'rssBytes': rssBytes,
        'rssDeltaBytes': rssDeltaBytes,
        'gcCyclesSurvived': gcCyclesSurvived,
        'details': details,
        'allocationStackTrace': allocationStackTrace,
      };

  /// Builds a record from a native platform payload.
  factory LeakRecord.fromNative(Map<dynamic, dynamic> raw) {
    final rawTime = raw['detectedAt'];
    final detectedAt = rawTime is int
        ? DateTime.fromMillisecondsSinceEpoch(rawTime)
        : DateTime.tryParse(rawTime?.toString() ?? '') ?? DateTime.now();

    final kindName = raw['kind']?.toString();
    final kind = LeakKind.values.firstWhere(
      (candidate) => candidate.name == kindName,
      orElse: () => LeakKind.nativeReport,
    );

    final confidenceName = raw['confidence']?.toString();
    final confidence = LeakConfidence.values.firstWhere(
      (candidate) => candidate.name == confidenceName,
      orElse: () => LeakConfidence.suspected,
    );

    int? intOf(Object? value) =>
        value is int ? value : int.tryParse(value?.toString() ?? '');

    return LeakRecord(
      id: raw['id']?.toString() ??
          'leak-${DateTime.now().microsecondsSinceEpoch}',
      detectedAt: detectedAt,
      objectType: raw['objectType']?.toString() ?? 'Unknown',
      label: raw['label']?.toString(),
      kind: kind,
      confidence: confidence,
      retainedForMs: intOf(raw['retainedForMs']),
      rssBytes: intOf(raw['rssBytes']),
      rssDeltaBytes: intOf(raw['rssDeltaBytes']),
      gcCyclesSurvived: intOf(raw['gcCyclesSurvived']),
      details: raw['details']?.toString(),
      allocationStackTrace: raw['allocationStackTrace']?.toString(),
    );
  }

  /// Renders the record as a shareable report.
  String toReport() {
    final buffer = StringBuffer()
      ..writeln('[${confidence.name.toUpperCase()}] $title')
      ..writeln('Kind: ${kind.name}')
      ..writeln('Detected at: ${detectedAt.toIso8601String()}');
    if (allocatedAt != null) {
      buffer.writeln('Registered at: ${allocatedAt!.toIso8601String()}');
    }
    if (retainedForMs != null) {
      buffer.writeln('Retained for: $retainedForMs ms past disposal');
    }
    if (gcCyclesSurvived != null) {
      buffer.writeln('Survived GC cycles: $gcCyclesSurvived');
    }
    if (rssBytes != null) {
      buffer.writeln('RSS: ${formatBytes(rssBytes!)}');
    }
    if (rssDeltaBytes != null) {
      final sign = rssDeltaBytes! >= 0 ? '+' : '-';
      buffer.writeln('RSS change: $sign${formatBytes(rssDeltaBytes!.abs())}');
    }
    if (details != null) buffer.writeln('\n$details');
    if (allocationStackTrace != null && allocationStackTrace!.isNotEmpty) {
      buffer
        ..writeln('\nAllocation stack trace')
        ..writeln(allocationStackTrace);
    }
    return buffer.toString();
  }

  /// Formats a byte count using binary units.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = <String>['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}
