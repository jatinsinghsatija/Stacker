import 'dart:convert';

import '../../core/http_status.dart';

/// Lifecycle state of a captured HTTP call.
enum ApiCallState {
  /// The request left the client; no response has arrived yet.
  pending,

  /// A response (of any status code) was received.
  complete,

  /// The call failed at the transport level, or was cancelled.
  failed,
}

/// Which side of the stack captured a call.
enum CaptureOrigin {
  /// Captured by the Dart interceptor (Dio / package:http).
  dart,

  /// Captured by the native OkHttp interceptor on Android.
  android,

  /// Captured by the native URLSession hook on iOS.
  ios,

  /// Pushed in manually via the public API.
  manual,
}

/// One captured HTTP request/response pair.
///
/// Instances are immutable; the interceptor creates a [ApiCallState.pending]
/// record when the request goes out and replaces it via [copyWith] once the
/// response (or error) lands.
class ApiRecord {
  const ApiRecord({
    required this.id,
    required this.method,
    required this.url,
    required this.requestTime,
    this.state = ApiCallState.pending,
    this.origin = CaptureOrigin.dart,
    this.requestHeaders = const <String, String>{},
    this.queryParameters = const <String, String>{},
    this.pathParameters = const <String, String>{},
    this.requestBody,
    this.requestContentType,
    this.requestSizeBytes,
    this.statusCode,
    this.responseTime,
    this.responseHeaders = const <String, String>{},
    this.responseBody,
    this.responseContentType,
    this.responseSizeBytes,
    this.errorMessage,
    this.errorType,
  });

  /// Stable identifier, unique for the process lifetime.
  final String id;

  /// Uppercase HTTP verb, e.g. `GET`.
  final String method;

  /// Full request URL including the query string.
  final String url;

  /// When the request was handed to the transport.
  final DateTime requestTime;

  /// When the response or error was observed. `null` while pending.
  final DateTime? responseTime;

  final ApiCallState state;
  final CaptureOrigin origin;

  /// Request headers as sent, after redaction.
  final Map<String, String> requestHeaders;

  /// Query string parameters parsed out of [url].
  final Map<String, String> queryParameters;

  /// Path parameters, when the caller supplied a URI template.
  final Map<String, String> pathParameters;

  /// Request body rendered as text, or `null` for bodyless requests.
  final String? requestBody;
  final String? requestContentType;
  final int? requestSizeBytes;

  /// Response status code, or `null` while pending / on transport failure.
  final int? statusCode;

  final Map<String, String> responseHeaders;
  final String? responseBody;
  final String? responseContentType;
  final int? responseSizeBytes;

  /// Transport-level error description, when [state] is [ApiCallState.failed].
  final String? errorMessage;

  /// Runtime type or category of the error, e.g. `DioExceptionType.connectionTimeout`.
  final String? errorType;

  /// Host portion of [url], for grouping and display.
  String get host => Uri.tryParse(url)?.host ?? '';

  /// Path portion of [url] — what the list row shows as the endpoint.
  String get path {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return url;
    return parsed.path.isEmpty ? '/' : parsed.path;
  }

  /// Wall-clock duration of the call, or `null` while pending.
  Duration? get duration {
    final end = responseTime;
    if (end == null) return null;
    return end.difference(requestTime);
  }

  /// Status code for display purposes; falls back to [HttpStatus.noResponse]
  /// so that failed calls still resolve to a meaningful description.
  int get effectiveStatusCode =>
      statusCode ?? (state == ApiCallState.failed ? HttpStatus.noResponse : 0);

  /// The looked-up meaning of [statusCode].
  HttpStatusInfo? get statusInfo {
    if (state == ApiCallState.pending) return null;
    return HttpStatus.describe(effectiveStatusCode);
  }

  /// `true` when the call finished with a 2xx status.
  bool get isSuccess =>
      statusCode != null && HttpStatus.isSuccess(statusCode!);

  /// Total bytes moved in both directions, when known.
  int get totalSizeBytes => (requestSizeBytes ?? 0) + (responseSizeBytes ?? 0);

  ApiRecord copyWith({
    ApiCallState? state,
    CaptureOrigin? origin,
    Map<String, String>? requestHeaders,
    Map<String, String>? queryParameters,
    Map<String, String>? pathParameters,
    String? requestBody,
    String? requestContentType,
    int? requestSizeBytes,
    int? statusCode,
    DateTime? responseTime,
    Map<String, String>? responseHeaders,
    String? responseBody,
    String? responseContentType,
    int? responseSizeBytes,
    String? errorMessage,
    String? errorType,
  }) {
    return ApiRecord(
      id: id,
      method: method,
      url: url,
      requestTime: requestTime,
      state: state ?? this.state,
      origin: origin ?? this.origin,
      requestHeaders: requestHeaders ?? this.requestHeaders,
      queryParameters: queryParameters ?? this.queryParameters,
      pathParameters: pathParameters ?? this.pathParameters,
      requestBody: requestBody ?? this.requestBody,
      requestContentType: requestContentType ?? this.requestContentType,
      requestSizeBytes: requestSizeBytes ?? this.requestSizeBytes,
      statusCode: statusCode ?? this.statusCode,
      responseTime: responseTime ?? this.responseTime,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      responseBody: responseBody ?? this.responseBody,
      responseContentType: responseContentType ?? this.responseContentType,
      responseSizeBytes: responseSizeBytes ?? this.responseSizeBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      errorType: errorType ?? this.errorType,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'method': method,
        'url': url,
        'requestTime': requestTime.toIso8601String(),
        'responseTime': responseTime?.toIso8601String(),
        'state': state.name,
        'origin': origin.name,
        'requestHeaders': requestHeaders,
        'queryParameters': queryParameters,
        'pathParameters': pathParameters,
        'requestBody': requestBody,
        'requestContentType': requestContentType,
        'requestSizeBytes': requestSizeBytes,
        'statusCode': statusCode,
        'statusMeaning': statusInfo?.meaning,
        'responseHeaders': responseHeaders,
        'responseBody': responseBody,
        'responseContentType': responseContentType,
        'responseSizeBytes': responseSizeBytes,
        'errorMessage': errorMessage,
        'errorType': errorType,
        'durationMs': duration?.inMilliseconds,
      };

  /// Builds a record from a native platform payload.
  ///
  /// Unknown or malformed fields degrade to sensible defaults rather than
  /// throwing, because this data crosses a method channel from Kotlin/Swift.
  factory ApiRecord.fromNative(Map<dynamic, dynamic> raw) {
    Map<String, String> stringMap(Object? value) {
      if (value is! Map) return const <String, String>{};
      return value.map(
        (key, dynamic v) => MapEntry(key.toString(), v?.toString() ?? ''),
      );
    }

    DateTime timeFrom(Object? value, {DateTime? fallback}) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is String) {
        return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
      }
      return fallback ?? DateTime.now();
    }

    final requestTime = timeFrom(raw['requestTime']);
    final rawStatus = raw['statusCode'];
    final statusCode = rawStatus is int
        ? rawStatus
        : int.tryParse(rawStatus?.toString() ?? '');
    final error = raw['errorMessage']?.toString();
    final url = raw['url']?.toString() ?? '';

    final ApiCallState state;
    if (error != null && error.isNotEmpty) {
      state = ApiCallState.failed;
    } else if (statusCode != null) {
      state = ApiCallState.complete;
    } else {
      state = ApiCallState.pending;
    }

    final originName = raw['origin']?.toString();
    final origin = CaptureOrigin.values.firstWhere(
      (candidate) => candidate.name == originName,
      orElse: () => CaptureOrigin.manual,
    );

    return ApiRecord(
      id: raw['id']?.toString() ??
          'native-${DateTime.now().microsecondsSinceEpoch}',
      method: (raw['method']?.toString() ?? 'GET').toUpperCase(),
      url: url,
      requestTime: requestTime,
      responseTime: raw['responseTime'] == null
          ? null
          : timeFrom(raw['responseTime'], fallback: requestTime),
      state: state,
      origin: origin,
      requestHeaders: stringMap(raw['requestHeaders']),
      queryParameters: stringMap(raw['queryParameters']).isNotEmpty
          ? stringMap(raw['queryParameters'])
          : _queryOf(url),
      pathParameters: stringMap(raw['pathParameters']),
      requestBody: raw['requestBody']?.toString(),
      requestContentType: raw['requestContentType']?.toString(),
      requestSizeBytes: raw['requestSizeBytes'] is int
          ? raw['requestSizeBytes'] as int
          : null,
      statusCode: statusCode,
      responseHeaders: stringMap(raw['responseHeaders']),
      responseBody: raw['responseBody']?.toString(),
      responseContentType: raw['responseContentType']?.toString(),
      responseSizeBytes: raw['responseSizeBytes'] is int
          ? raw['responseSizeBytes'] as int
          : null,
      errorMessage: (error?.isEmpty ?? true) ? null : error,
      errorType: raw['errorType']?.toString(),
    );
  }

  static Map<String, String> _queryOf(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return const <String, String>{};
    return Map<String, String>.from(parsed.queryParameters);
  }

  /// Renders the record as a shareable cURL command.
  String toCurl() {
    final buffer = StringBuffer("curl -X $method '$url'");
    for (final entry in requestHeaders.entries) {
      buffer.write(" \\\n  -H '${entry.key}: ${entry.value}'");
    }
    final body = requestBody;
    if (body != null && body.isNotEmpty) {
      final escaped = body.replaceAll("'", r"'\''");
      buffer.write(" \\\n  -d '$escaped'");
    }
    return buffer.toString();
  }

  /// Renders the record as a human-readable report for sharing.
  String toReport() {
    final buffer = StringBuffer()
      ..writeln('$method $url')
      ..writeln('Origin: ${origin.name}')
      ..writeln('Requested at: ${requestTime.toIso8601String()}');

    final finished = responseTime;
    if (finished != null) {
      buffer.writeln('Responded at: ${finished.toIso8601String()}');
      buffer.writeln('Duration: ${duration!.inMilliseconds} ms');
    }

    final info = statusInfo;
    if (info != null) {
      buffer
        ..writeln('Status: ${info.code} ${info.reasonPhrase}')
        ..writeln('Meaning: ${info.meaning}');
    }
    if (errorMessage != null) {
      buffer.writeln('Error: ${errorType ?? 'Error'} — $errorMessage');
    }

    void section(String title, Map<String, String> map) {
      if (map.isEmpty) return;
      buffer.writeln('\n$title');
      for (final entry in map.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    section('Request headers', requestHeaders);
    section('Query parameters', queryParameters);
    section('Path parameters', pathParameters);
    section('Response headers', responseHeaders);

    if (requestBody != null && requestBody!.isNotEmpty) {
      buffer
        ..writeln('\nRequest body')
        ..writeln(requestBody);
    }
    if (responseBody != null && responseBody!.isNotEmpty) {
      buffer
        ..writeln('\nResponse body')
        ..writeln(responseBody);
    }
    return buffer.toString();
  }

  /// Pretty-prints [body] when it parses as JSON, otherwise returns it as-is.
  static String prettyPrint(String? body) {
    if (body == null || body.isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } on FormatException {
      return body;
    }
  }
}
