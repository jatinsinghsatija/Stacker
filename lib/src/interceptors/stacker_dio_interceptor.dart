import 'package:dio/dio.dart';

import '../core/id_generator.dart';
import '../core/redactor.dart';
import '../data/models/api_record.dart';
import '../data/repository/stacker_repository.dart';

/// Dio interceptor that records every request, response, and error.
///
/// Add it last in the interceptor chain so it observes the final headers
/// after any auth or retry interceptor has run:
///
/// ```dart
/// dio.interceptors.add(StackerDioInterceptor());
/// ```
///
/// The interceptor never rethrows and never modifies the request or response
/// — a bug in a debug tool must not change the behaviour of the app it is
/// observing. Every handler body is wrapped so a capture failure is swallowed.
class StackerDioInterceptor extends Interceptor {
  /// Creates an interceptor bound to the given collaborators.
  ///
  /// All parameters default to the values registered in the Stacker
  /// container, so `StackerDioInterceptor()` is the normal usage.
  StackerDioInterceptor({
    StackerRepository? repository,
    Redactor? redactor,
    IdGenerator? idGenerator,
  })  : _explicitRepository = repository,
        _explicitRedactor = redactor,
        _explicitIds = idGenerator;

  final StackerRepository? _explicitRepository;
  final Redactor? _explicitRedactor;
  final IdGenerator? _explicitIds;

  /// Key under which the record id is stashed on the request's `extra` map,
  /// so the response handler can find the pending record it belongs to.
  static const String _recordIdKey = 'stacker.recordId';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    _guard(() {
      final resolved = _StackerDeps.resolve(
        _explicitRepository,
        _explicitRedactor,
        _explicitIds,
      );
      if (resolved == null) return;

      final id = resolved.ids.next('api');
      options.extra[_recordIdKey] = id;

      resolved.repository.addApiRecord(
        ApiRecord(
          id: id,
          method: options.method.toUpperCase(),
          url: options.uri.toString(),
          requestTime: DateTime.now(),
          origin: CaptureOrigin.dart,
          requestHeaders: resolved.redactor.headers(options.headers),
          queryParameters: resolved.redactor.parameters(
            options.uri.queryParameters,
          ),
          pathParameters: _pathParametersOf(options),
          requestBody: resolved.redactor.body(options.data),
          requestContentType: options.contentType ??
              options.headers['content-type']?.toString(),
          requestSizeBytes: _sizeOf(options.data),
        ),
      );
    });
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _guard(() {
      final resolved = _StackerDeps.resolve(
        _explicitRepository,
        _explicitRedactor,
        _explicitIds,
      );
      if (resolved == null) return;

      final id = response.requestOptions.extra[_recordIdKey]?.toString();
      final existing =
          id == null ? null : resolved.repository.findApiRecord(id);
      final body = resolved.redactor.body(response.data);

      final completed = (existing ??
              _syntheticRecord(response.requestOptions, resolved))
          .copyWith(
        state: ApiCallState.complete,
        statusCode: response.statusCode,
        responseTime: DateTime.now(),
        responseHeaders: resolved.redactor.headers(response.headers.map),
        responseBody: body,
        responseContentType:
            response.headers.value('content-type'),
        responseSizeBytes: _sizeOf(response.data) ??
            int.tryParse(response.headers.value('content-length') ?? ''),
      );
      resolved.repository.updateApiRecord(completed);
    });
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final error = err;
    _guard(() {
      final resolved = _StackerDeps.resolve(
        _explicitRepository,
        _explicitRedactor,
        _explicitIds,
      );
      if (resolved == null) return;

      final id = error.requestOptions.extra[_recordIdKey]?.toString();
      final existing =
          id == null ? null : resolved.repository.findApiRecord(id);
      final response = error.response;
      final base =
          existing ?? _syntheticRecord(error.requestOptions, resolved);

      // A DioException may still carry a response — a 500, for instance,
      // arrives here rather than in onResponse. Record the status when we
      // have one so the dashboard shows 500 rather than "no response".
      final completed = base.copyWith(
        state: response != null
            ? ApiCallState.complete
            : ApiCallState.failed,
        statusCode: response?.statusCode,
        responseTime: DateTime.now(),
        responseHeaders: response == null
            ? const <String, String>{}
            : resolved.redactor.headers(response.headers.map),
        responseBody: response == null
            ? null
            : resolved.redactor.body(response.data),
        responseContentType: response?.headers.value('content-type'),
        responseSizeBytes:
            response == null ? null : _sizeOf(response.data),
        errorMessage: error.message ?? error.error?.toString() ?? 'Request failed',
        errorType: error.type.name,
      );
      resolved.repository.updateApiRecord(completed);
    });
    handler.next(err);
  }

  /// Builds a record for a call whose pending entry is gone.
  ///
  /// This happens when the buffer wrapped around mid-flight, or when another
  /// interceptor short-circuited `onRequest`.
  ApiRecord _syntheticRecord(RequestOptions options, _StackerDeps deps) {
    return ApiRecord(
      id: options.extra[_recordIdKey]?.toString() ?? deps.ids.next('api'),
      method: options.method.toUpperCase(),
      url: options.uri.toString(),
      requestTime: DateTime.now(),
      origin: CaptureOrigin.dart,
      requestHeaders: deps.redactor.headers(options.headers),
      queryParameters: deps.redactor.parameters(options.uri.queryParameters),
      pathParameters: _pathParametersOf(options),
      requestBody: deps.redactor.body(options.data),
    );
  }

  /// Reads path parameters the caller attached via `extra`.
  ///
  /// Dio interpolates paths before the interceptor runs, so the original
  /// template is unrecoverable. Callers who want them shown can pass
  /// `extra: {'stacker.pathParameters': {'id': '42'}}`.
  static Map<String, String> _pathParametersOf(RequestOptions options) {
    final raw = options.extra['stacker.pathParameters'];
    if (raw is! Map) return const <String, String>{};
    return raw.map(
      (key, dynamic value) =>
          MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  static int? _sizeOf(Object? body) {
    if (body == null) return null;
    if (body is List<int>) return body.length;
    if (body is String) return body.length;
    return null;
  }

  /// Runs [action], discarding any error it throws.
  static void _guard(void Function() action) {
    try {
      action();
    } on Object {
      // Capture is best-effort. Never let the observer break the observed.
    }
  }
}

/// Bundle of the three collaborators the interceptor needs, resolved either
/// from constructor arguments or from the container.
class _StackerDeps {
  const _StackerDeps({
    required this.repository,
    required this.redactor,
    required this.ids,
  });

  final StackerRepository repository;
  final Redactor redactor;
  final IdGenerator ids;

  /// Returns the dependencies, or `null` when Stacker is not active.
  ///
  /// Returning `null` rather than throwing means an interceptor left attached
  /// in a release build where `Stacker.init` was skipped degrades to a no-op.
  static _StackerDeps? resolve(
    StackerRepository? repository,
    Redactor? redactor,
    IdGenerator? ids,
  ) {
    if (repository != null && redactor != null && ids != null) {
      return _StackerDeps(
        repository: repository,
        redactor: redactor,
        ids: ids,
      );
    }
    // Imported lazily to keep this file free of a hard dependency on the
    // locator, which matters for the unit tests that inject fakes directly.
    final locator = _locatorAccessor;
    if (locator == null) return null;
    return locator();
  }

  /// Set by `Stacker.init` so interceptors can find the live container
  /// without importing it and creating a cycle.
  static _StackerDeps? Function()? _locatorAccessor;

  static void bind(_StackerDeps? Function()? accessor) {
    _locatorAccessor = accessor;
  }
}

/// Wires the interceptor's lazy locator lookup.
///
/// Called by `Stacker.init`; not part of the public API.
void bindInterceptorDependencies({
  required StackerRepository? Function() repository,
  required Redactor? Function() redactor,
  required IdGenerator? Function() idGenerator,
}) {
  _StackerDeps.bind(() {
    final repo = repository();
    final red = redactor();
    final ids = idGenerator();
    if (repo == null || red == null || ids == null) return null;
    return _StackerDeps(repository: repo, redactor: red, ids: ids);
  });
}

/// Clears the locator binding. Called by `Stacker.dispose`.
void unbindInterceptorDependencies() => _StackerDeps.bind(null);
