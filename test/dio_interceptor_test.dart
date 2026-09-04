import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';
import 'package:stacker_inspector/src/core/id_generator.dart';
import 'package:stacker_inspector/src/core/redactor.dart';

/// A real loopback HTTP server, so the interceptor is exercised over an actual
/// socket rather than a mocked adapter — that is the only way to be sure the
/// response body is still readable by the caller after capture.
class _TestServer {
  _TestServer._(this._server);

  final HttpServer _server;

  String get origin => 'http://${_server.address.host}:${_server.port}';

  static Future<_TestServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _TestServer._(server);
    testServer._listen();
    return testServer;
  }

  void _listen() {
    _server.listen((HttpRequest request) async {
      final path = request.uri.path;
      // Drain the request body so the socket is not left half-read.
      final requestBody = await utf8.decoder.bind(request).join();

      switch (path) {
        case '/ok':
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..headers.add('X-Custom-Response', 'response-value')
            ..write(jsonEncode(<String, Object?>{'ok': true, 'id': 42}));
        case '/created':
          request.response
            ..statusCode = 201
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(<String, Object?>{'echo': requestBody}));
        case '/missing':
          request.response
            ..statusCode = 404
            ..write('not found');
        case '/boom':
          request.response
            ..statusCode = 500
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(<String, Object?>{'error': 'internal'}));
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late _TestServer server;
  late InMemoryStackerRepository repository;
  late Dio dio;

  setUpAll(() async {
    server = await _TestServer.start();
  });

  tearDownAll(() async {
    await server.stop();
  });

  setUp(() {
    repository = InMemoryStackerRepository(const StackerConfig());
    dio = Dio(
      BaseOptions(
        baseUrl: server.origin,
        // Let 4xx/5xx come back as responses so both paths are covered.
        validateStatus: (_) => true,
      ),
    )..interceptors.add(
        StackerDioInterceptor(
          repository: repository,
          redactor: const Redactor(StackerConfig()),
          idGenerator: IdGenerator(),
        ),
      );
  });

  tearDown(() async {
    // Deliberately not calling dio.close(): Dio instances created without an
    // explicit adapter share the default one, so closing any of them would
    // break the sockets used by the remaining tests.
    await repository.dispose();
  });

  group('successful requests', () {
    test('captures a 200 with headers, params, and body', () async {
      final response = await dio.get<dynamic>(
        '/ok',
        queryParameters: <String, dynamic>{'page': '2', 'sort': 'name'},
        options: Options(
          headers: <String, Object?>{'X-Request-Id': 'req-1'},
        ),
      );

      // The caller must receive an untouched response.
      expect(response.statusCode, 200);
      expect(response.data, isA<Map<dynamic, dynamic>>());
      expect((response.data as Map<dynamic, dynamic>)['id'], 42);

      expect(repository.apiRecords, hasLength(1));
      final record = repository.apiRecords.single;
      expect(record.method, 'GET');
      expect(record.state, ApiCallState.complete);
      expect(record.statusCode, 200);
      expect(record.path, '/ok');
      expect(record.queryParameters['page'], '2');
      expect(record.queryParameters['sort'], 'name');
      expect(record.requestHeaders['X-Request-Id'], 'req-1');
      expect(record.responseHeaders['x-custom-response'], 'response-value');
      expect(record.responseBody, contains('42'));
      expect(record.duration, isNotNull);
      expect(record.origin, CaptureOrigin.dart);
    });

    test('resolves the status meaning', () async {
      await dio.get<dynamic>('/ok');

      final info = repository.apiRecords.single.statusInfo;
      expect(info, isNotNull);
      expect(info!.reasonPhrase, 'OK');
      expect(info.meaning, isNotEmpty);
    });

    test('captures a POST body and marks it 201', () async {
      await dio.post<dynamic>(
        '/created',
        data: <String, Object?>{'name': 'Ada'},
      );

      final record = repository.apiRecords.single;
      expect(record.method, 'POST');
      expect(record.statusCode, 201);
      expect(record.requestBody, contains('Ada'));
    });

    test('redacts an Authorization header before storing it', () async {
      await dio.get<dynamic>(
        '/ok',
        options: Options(
          headers: <String, Object?>{
            'Authorization': 'Bearer super-secret-token',
          },
        ),
      );

      final record = repository.apiRecords.single;
      expect(record.requestHeaders['Authorization'], isNot(contains('super-secret-token')));
      expect(
        record.toReport(),
        isNot(contains('super-secret-token')),
        reason: 'a shared report must not leak the token',
      );
    });

    test('redacts a password in the request body', () async {
      await dio.post<dynamic>(
        '/created',
        data: <String, Object?>{'email': 'a@b.com', 'password': 'hunter2'},
      );

      final record = repository.apiRecords.single;
      expect(record.requestBody, isNot(contains('hunter2')));
      expect(record.requestBody, contains('a@b.com'));
    });

    test('records path parameters supplied via extra', () async {
      await dio.get<dynamic>(
        '/ok',
        options: Options(
          extra: <String, dynamic>{
            'stacker.pathParameters': <String, String>{'userId': '42'},
          },
        ),
      );

      expect(repository.apiRecords.single.pathParameters['userId'], '42');
    });
  });

  group('error responses', () {
    test('captures a 404 with its meaning', () async {
      await dio.get<dynamic>('/missing');

      final record = repository.apiRecords.single;
      expect(record.statusCode, 404);
      expect(record.state, ApiCallState.complete);
      expect(record.isSuccess, isFalse);
      expect(record.statusInfo!.reasonPhrase, 'Not Found');
    });

    test('captures a 500', () async {
      await dio.get<dynamic>('/boom');

      final record = repository.apiRecords.single;
      expect(record.statusCode, 500);
      expect(record.responseBody, contains('internal'));
    });

    test('records a 500 that Dio raises as an exception', () async {
      final strict = Dio(BaseOptions(baseUrl: server.origin))
        ..interceptors.add(
          StackerDioInterceptor(
            repository: repository,
            redactor: const Redactor(StackerConfig()),
            idGenerator: IdGenerator(),
          ),
        );

      await expectLater(
        strict.get<dynamic>('/boom'),
        throwsA(isA<DioException>()),
      );

      final record = repository.apiRecords.single;
      expect(
        record.statusCode,
        500,
        reason: 'a DioException carrying a response must keep its status code',
      );
      expect(record.state, ApiCallState.complete);
    });

    test('records a transport failure with no status code', () async {
      final failing = Dio(
        BaseOptions(
          // Reserved TEST-NET-1 address; connection will not succeed.
          baseUrl: 'http://192.0.2.1:9',
          connectTimeout: const Duration(milliseconds: 300),
        ),
      )..interceptors.add(
          StackerDioInterceptor(
            repository: repository,
            redactor: const Redactor(StackerConfig()),
            idGenerator: IdGenerator(),
          ),
        );

      await expectLater(
        failing.get<dynamic>('/nowhere'),
        throwsA(isA<DioException>()),
      );

      final record = repository.apiRecords.single;
      expect(record.state, ApiCallState.failed);
      expect(record.statusCode, isNull);
      expect(record.errorMessage, isNotNull);
      expect(record.errorType, isNotNull);
      expect(
        record.effectiveStatusCode,
        HttpStatus.noResponse,
        reason: 'the dashboard needs something to describe',
      );
      expect(record.statusInfo!.reasonPhrase, 'No Response');
    });
  });

  group('lifecycle and robustness', () {
    test('marks a request pending before the response arrives', () async {
      final future = dio.get<dynamic>('/ok');

      // Dio dispatches its interceptor chain through an async queue, so
      // onRequest has not run yet at this point. Yield until the pending
      // record appears rather than hardcoding a microtask count, which would
      // be brittle across Dio versions.
      for (var i = 0; i < 20 && repository.apiRecords.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(repository.apiRecords, hasLength(1));
      expect(repository.apiRecords.single.state, ApiCallState.pending);
      expect(repository.apiRecords.single.responseTime, isNull);

      await future;

      expect(
        repository.apiRecords,
        hasLength(1),
        reason: 'completing must update in place, not append a duplicate',
      );
      expect(repository.apiRecords.single.state, ApiCallState.complete);
    });

    test('keeps concurrent calls separate', () async {
      await Future.wait<void>(<Future<void>>[
        dio.get<dynamic>('/ok'),
        dio.get<dynamic>('/missing'),
        dio.get<dynamic>('/boom'),
      ]);

      expect(repository.apiRecords, hasLength(3));
      expect(
        repository.apiRecords.map((record) => record.statusCode).toSet(),
        <int>{200, 404, 500},
      );
      // Ids must be unique or records would overwrite each other.
      expect(
        repository.apiRecords.map((record) => record.id).toSet(),
        hasLength(3),
      );
    });

    test('passes calls through when Stacker is not initialised', () async {
      // No explicit collaborators and no container: resolve returns null.
      final unbound = Dio(BaseOptions(baseUrl: server.origin))
        ..interceptors.add(StackerDioInterceptor());

      final response = await unbound.get<dynamic>('/ok');

      expect(
        response.statusCode,
        200,
        reason: 'an interceptor left in a release build must be inert',
      );
      expect(repository.apiRecords, isEmpty);
    });

    test('generates a cURL command for a captured call', () async {
      await dio.post<dynamic>(
        '/created',
        data: <String, Object?>{'name': 'Ada'},
      );

      final curl = repository.apiRecords.single.toCurl();
      expect(curl, startsWith('curl -X POST'));
      expect(curl, contains('/created'));
      expect(curl, contains('Ada'));
    });
  });
}
