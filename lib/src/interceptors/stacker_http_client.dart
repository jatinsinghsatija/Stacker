import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/id_generator.dart';
import '../core/redactor.dart';
import '../data/models/api_record.dart';
import '../data/repository/stacker_repository.dart';
import 'stacker_dio_interceptor.dart' show bindInterceptorDependencies;

/// A `package:http` [http.BaseClient] that records every call.
///
/// Wrap the client the app already uses:
///
/// ```dart
/// final client = StackerHttpClient(inner: http.Client());
/// final response = await client.get(Uri.parse('https://api.example.com/users'));
/// ```
///
/// Capture is best-effort: if recording fails, the HTTP call still proceeds
/// and its result is returned untouched.
class StackerHttpClient extends http.BaseClient {
  StackerHttpClient({
    http.Client? inner,
    StackerRepository? repository,
    Redactor? redactor,
    IdGenerator? idGenerator,
  })  : _inner = inner ?? http.Client(),
        _repository = repository,
        _redactor = redactor,
        _ids = idGenerator;

  final http.Client _inner;
  final StackerRepository? _repository;
  final Redactor? _redactor;
  final IdGenerator? _ids;

  /// Resolved collaborators, or `null` when Stacker is inactive.
  _HttpDeps? get _deps {
    final repository = _repository ?? _globalRepository?.call();
    final redactor = _redactor ?? _globalRedactor?.call();
    final ids = _ids ?? _globalIds?.call();
    if (repository == null || redactor == null || ids == null) return null;
    return _HttpDeps(repository: repository, redactor: redactor, ids: ids);
  }

  static StackerRepository? Function()? _globalRepository;
  static Redactor? Function()? _globalRedactor;
  static IdGenerator? Function()? _globalIds;

  /// Binds the container accessors. Called by `Stacker.init`.
  static void bindGlobals({
    required StackerRepository? Function() repository,
    required Redactor? Function() redactor,
    required IdGenerator? Function() idGenerator,
  }) {
    _globalRepository = repository;
    _globalRedactor = redactor;
    _globalIds = idGenerator;
    // Keep the Dio interceptor's binding in step, so initialising through
    // either entry point wires both.
    bindInterceptorDependencies(
      repository: repository,
      redactor: redactor,
      idGenerator: idGenerator,
    );
  }

  /// Clears the container accessors. Called by `Stacker.dispose`.
  static void unbindGlobals() {
    _globalRepository = null;
    _globalRedactor = null;
    _globalIds = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final deps = _deps;
    if (deps == null) return _inner.send(request);

    String? recordId;
    final requestTime = DateTime.now();

    try {
      recordId = deps.ids.next('api');
      deps.repository.addApiRecord(
        ApiRecord(
          id: recordId,
          method: request.method.toUpperCase(),
          url: request.url.toString(),
          requestTime: requestTime,
          origin: CaptureOrigin.dart,
          requestHeaders: deps.redactor.headers(request.headers),
          queryParameters:
              deps.redactor.parameters(request.url.queryParameters),
          requestBody: deps.redactor.body(_bodyOf(request)),
          requestContentType: request.headers['content-type'],
          requestSizeBytes: request.contentLength,
        ),
      );
    } on Object {
      recordId = null;
    }

    try {
      final response = await _inner.send(request);
      if (recordId == null) return response;

      // The body is a single-subscription stream, so it must be buffered here
      // and handed back as a fresh stream — reading it for capture would
      // otherwise consume it before the caller sees it.
      final bytes = await response.stream.toBytes();
      _completeRecord(deps, recordId, requestTime, response, bytes);

      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } on Object catch (error) {
      if (recordId != null) {
        _failRecord(deps, recordId, requestTime, request, error);
      }
      rethrow;
    }
  }

  void _completeRecord(
    _HttpDeps deps,
    String recordId,
    DateTime requestTime,
    http.StreamedResponse response,
    List<int> bytes,
  ) {
    try {
      final existing = deps.repository.findApiRecord(recordId);
      if (existing == null) return;
      deps.repository.updateApiRecord(
        existing.copyWith(
          state: ApiCallState.complete,
          statusCode: response.statusCode,
          responseTime: DateTime.now(),
          responseHeaders: deps.redactor.headers(response.headers),
          responseBody: deps.redactor.body(_decode(bytes, response.headers)),
          responseContentType: response.headers['content-type'],
          responseSizeBytes: bytes.length,
        ),
      );
    } on Object {
      // Best effort only.
    }
  }

  void _failRecord(
    _HttpDeps deps,
    String recordId,
    DateTime requestTime,
    http.BaseRequest request,
    Object error,
  ) {
    try {
      final existing = deps.repository.findApiRecord(recordId);
      if (existing == null) return;
      deps.repository.updateApiRecord(
        existing.copyWith(
          state: ApiCallState.failed,
          responseTime: DateTime.now(),
          errorMessage: error.toString(),
          errorType: error.runtimeType.toString(),
        ),
      );
    } on Object {
      // Best effort only.
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  /// Extracts a loggable body from [request] without consuming a stream.
  ///
  /// A `StreamedRequest` body is intentionally not read: it can only be
  /// consumed once and doing so here would break the request.
  static Object? _bodyOf(http.BaseRequest request) {
    if (request is http.Request) {
      return request.body.isEmpty ? null : request.body;
    }
    if (request is http.MultipartRequest) {
      final fields = Map<String, String>.from(request.fields);
      final files = request.files
          .map(
            (file) =>
                '${file.field}: ${file.filename ?? 'unnamed'} (${file.length} bytes)',
          )
          .toList();
      return <String, Object?>{
        if (fields.isNotEmpty) 'fields': fields,
        if (files.isNotEmpty) 'files': files,
      };
    }
    return '<streamed request body not captured>';
  }

  /// Decodes [bytes] as text using the charset in the content type.
  static Object? _decode(List<int> bytes, Map<String, String> headers) {
    if (bytes.isEmpty) return null;
    final contentType = headers['content-type']?.toLowerCase() ?? '';
    final looksBinary = contentType.startsWith('image/') ||
        contentType.startsWith('audio/') ||
        contentType.startsWith('video/') ||
        contentType.contains('octet-stream') ||
        contentType.contains('pdf') ||
        contentType.contains('zip');
    if (looksBinary) return bytes;

    try {
      return utf8.decode(bytes);
    } on FormatException {
      // Not valid UTF-8; treat as binary rather than corrupting the output.
      return bytes;
    }
  }
}

class _HttpDeps {
  const _HttpDeps({
    required this.repository,
    required this.redactor,
    required this.ids,
  });

  final StackerRepository repository;
  final Redactor redactor;
  final IdGenerator ids;
}
