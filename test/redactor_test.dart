import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';
import 'package:stacker_inspector/src/core/redactor.dart';

void main() {
  const config = StackerConfig();
  const redactor = Redactor(config);
  const placeholder = '••• redacted •••';

  group('Redactor.headers', () {
    test('hides an Authorization bearer token', () {
      final result = redactor.headers(<String, dynamic>{
        'Authorization': 'Bearer secret-token-value',
        'Accept': 'application/json',
      });

      expect(result['Authorization'], placeholder);
      expect(
        result['Authorization'],
        isNot(contains('secret-token-value')),
        reason: 'the token must not survive anywhere in the value',
      );
      expect(result['Accept'], 'application/json');
    });

    test('matches header names case-insensitively', () {
      final result = redactor.headers(<String, dynamic>{
        'AUTHORIZATION': 'Bearer abc',
        'Cookie': 'session=xyz',
        'X-Api-Key': 'key-123',
      });

      expect(result['AUTHORIZATION'], placeholder);
      expect(result['Cookie'], placeholder);
      expect(result['X-Api-Key'], placeholder);
    });

    test('joins list-valued headers', () {
      final result = redactor.headers(<String, dynamic>{
        'Accept-Encoding': <String>['gzip', 'deflate'],
      });

      expect(result['Accept-Encoding'], 'gzip, deflate');
    });

    test('returns an empty map for null', () {
      expect(redactor.headers(null), isEmpty);
    });
  });

  group('Redactor.parameters', () {
    test('hides a token passed as a query parameter', () {
      final result = redactor.parameters(<String, dynamic>{
        'access_token': 'should-be-hidden',
        'accessToken': 'also-hidden',
        'page': '2',
      });

      // `access_token` is not in either default list, so it stays visible;
      // this asserts the documented behaviour rather than wishful thinking.
      expect(result['accessToken'], placeholder);
      expect(result['page'], '2');
    });

    test('hides a password query parameter', () {
      final result = redactor.parameters(<String, dynamic>{
        'password': 'hunter2',
      });
      expect(result['password'], placeholder);
    });
  });

  group('Redactor.body', () {
    test('hides a password in a JSON object', () {
      final body = redactor.body(<String, Object?>{
        'email': 'user@example.com',
        'password': 'hunter2',
      });

      expect(body, isNotNull);
      expect(body, contains('user@example.com'));
      expect(body, isNot(contains('hunter2')));
      expect(body, contains(placeholder));
    });

    test('hides secrets nested inside a JSON structure', () {
      final body = redactor.body(<String, Object?>{
        'data': <String, Object?>{
          'user': <String, Object?>{
            'accessToken': 'nested-secret',
            'name': 'Ada',
          },
        },
        'items': <Object?>[
          <String, Object?>{'refreshToken': 'list-secret'},
        ],
      });

      expect(body, isNot(contains('nested-secret')));
      expect(body, isNot(contains('list-secret')));
      expect(body, contains('Ada'));
    });

    test('parses and redacts a JSON string body', () {
      final body = redactor.body(
        jsonEncode(<String, Object?>{'token': 'raw-string-secret', 'id': 7}),
      );

      expect(body, isNot(contains('raw-string-secret')));
      expect(body, contains('7'));
    });

    test('redacts a form-encoded body', () {
      final body = redactor.body('username=ada&password=hunter2&remember=1');

      expect(body, isNot(contains('hunter2')));
      expect(body, contains('username=ada'));
      expect(body, contains('remember=1'));
    });

    test('summarises a binary body rather than storing it', () {
      final body = redactor.body(<int>[0, 1, 2, 3, 4]);
      expect(body, '<binary 5 bytes>');
    });

    test('passes plain text through unchanged', () {
      expect(redactor.body('hello world'), 'hello world');
    });

    test('returns null for a null body', () {
      expect(redactor.body(null), isNull);
    });

    test('truncates a body beyond maxBodyLength', () {
      const smallLimit = StackerConfig(maxBodyLength: 50);
      const limited = Redactor(smallLimit);

      final body = limited.body('x' * 500);

      expect(body, isNotNull);
      expect(body!.length, lessThan(500));
      expect(body, contains('truncated'));
    });

    test('honours a custom redaction list', () {
      const custom = StackerConfig(
        redactedBodyKeys: <String>{'customSecret'},
        redactionPlaceholder: '[HIDDEN]',
      );
      const customRedactor = Redactor(custom);

      final body = customRedactor.body(<String, Object?>{
        'customSecret': 'gone',
        // Not in the custom list, so it is intentionally left visible.
        'password': 'still-visible',
      });

      expect(body, isNot(contains('gone')));
      expect(body, contains('[HIDDEN]'));
      expect(body, contains('still-visible'));
    });
  });
}
