import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:stacker_inspector/stacker_inspector.dart';
import 'package:stacker_inspector/src/core/id_generator.dart';
import 'package:stacker_inspector/src/core/redactor.dart';

void main() {
  late HttpServer server;
  late String origin;
  late InMemoryStackerRepository repository;
  late StackerHttpClient client;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://${server.address.host}:${server.port}';
    server.listen((HttpRequest request) async {
      final body = await utf8.decoder.bind(request).join();
      switch (request.uri.path) {
        case '/json':
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..headers.add('X-Trace', 'trace-1')
            ..write(jsonEncode(<String, Object?>{'value': 'hello'}));
        case '/echo':
          request.response
            ..statusCode = 201
            ..write('received:$body');
        case '/error':
          request.response
            ..statusCode = 503
            ..write('unavailable');
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  setUp(() {
    repository = InMemoryStackerRepository(const StackerConfig());
    client = StackerHttpClient(
      inner: http.Client(),
      repository: repository,
      redactor: const Redactor(StackerConfig()),
      idGenerator: IdGenerator(),
    );
  });

  tearDown(() async {
    client.close();
    await repository.dispose();
  });

  test('captures a GET and leaves the body readable by the caller', () async {
    final response = await client.get(Uri.parse('$origin/json'));

    // This is the critical assertion: capture must not consume the stream.
    expect(response.statusCode, 200);
    expect(response.body, contains('hello'));
    expect(jsonDecode(response.body), isA<Map<String, dynamic>>());

    expect(repository.apiRecords, hasLength(1));
    final record = repository.apiRecords.single;
    expect(record.method, 'GET');
    expect(record.statusCode, 200);
    expect(record.path, '/json');
    expect(record.responseBody, contains('hello'));
    expect(record.responseHeaders['x-trace'], 'trace-1');
    expect(record.responseSizeBytes, greaterThan(0));
    expect(record.duration, isNotNull);
  });

  test('captures a POST body', () async {
    final response = await client.post(
      Uri.parse('$origin/echo'),
      body: 'payload-data',
    );

    expect(response.statusCode, 201);
    expect(response.body, 'received:payload-data');

    final record = repository.apiRecords.single;
    expect(record.method, 'POST');
    expect(record.statusCode, 201);
    expect(record.requestBody, 'payload-data');
  });

  test('redacts a sensitive request header', () async {
    await client.get(
      Uri.parse('$origin/json'),
      headers: <String, String>{'X-Api-Key': 'secret-key-value'},
    );

    final record = repository.apiRecords.single;
    expect(record.requestHeaders['x-api-key'], isNot(contains('secret-key-value')));
  });

  test('captures query parameters', () async {
    await client.get(Uri.parse('$origin/json?a=1&b=two'));

    final record = repository.apiRecords.single;
    expect(record.queryParameters['a'], '1');
    expect(record.queryParameters['b'], 'two');
  });

  test('records a 503 without treating it as a transport failure', () async {
    final response = await client.get(Uri.parse('$origin/error'));

    expect(response.statusCode, 503);
    final record = repository.apiRecords.single;
    expect(record.state, ApiCallState.complete);
    expect(record.statusCode, 503);
    expect(record.statusInfo!.reasonPhrase, 'Service Unavailable');
  });

  test('records a transport failure and rethrows to the caller', () async {
    // An unresolvable host fails fast, unlike a reserved IP which simply
    // hangs until the OS connect timeout.
    await expectLater(
      client.get(Uri.parse('http://stacker-nonexistent-host.invalid/nowhere')),
      throwsA(isA<Object>()),
    );

    final record = repository.apiRecords.single;
    expect(record.state, ApiCallState.failed);
    expect(record.statusCode, isNull);
    expect(record.errorMessage, isNotNull);
  });

  test('passes calls through when Stacker is not initialised', () async {
    final unbound = StackerHttpClient(inner: http.Client());

    final response = await unbound.get(Uri.parse('$origin/json'));

    expect(
      response.statusCode,
      200,
      reason: 'a wrapper left in a release build must be inert',
    );
    expect(response.body, contains('hello'));
    expect(repository.apiRecords, isEmpty);
    unbound.close();
  });

  test('keeps concurrent calls separate', () async {
    await Future.wait<http.Response>(<Future<http.Response>>[
      client.get(Uri.parse('$origin/json')),
      client.get(Uri.parse('$origin/error')),
    ]);

    expect(repository.apiRecords, hasLength(2));
    expect(
      repository.apiRecords.map((record) => record.id).toSet(),
      hasLength(2),
    );
  });
}
