import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/stacker_inspector.dart';

void main() {
  group('HttpStatus.classOf', () {
    test('maps each range to its class', () {
      expect(HttpStatus.classOf(100), HttpStatusClass.informational);
      expect(HttpStatus.classOf(200), HttpStatusClass.success);
      expect(HttpStatus.classOf(301), HttpStatusClass.redirection);
      expect(HttpStatus.classOf(404), HttpStatusClass.clientError);
      expect(HttpStatus.classOf(503), HttpStatusClass.serverError);
    });

    test('treats out-of-range values as unknown', () {
      expect(HttpStatus.classOf(0), HttpStatusClass.unknown);
      expect(HttpStatus.classOf(99), HttpStatusClass.unknown);
      expect(HttpStatus.classOf(600), HttpStatusClass.unknown);
      expect(HttpStatus.classOf(-1), HttpStatusClass.unknown);
    });

    test('classifies boundary codes correctly', () {
      expect(HttpStatus.classOf(199), HttpStatusClass.informational);
      expect(HttpStatus.classOf(299), HttpStatusClass.success);
      expect(HttpStatus.classOf(399), HttpStatusClass.redirection);
      expect(HttpStatus.classOf(499), HttpStatusClass.clientError);
      expect(HttpStatus.classOf(599), HttpStatusClass.serverError);
    });
  });

  group('HttpStatus.lookup', () {
    test('returns the reason phrase and meaning for a known code', () {
      final info = HttpStatus.lookup(404);

      expect(info, isNotNull);
      expect(info!.code, 404);
      expect(info.reasonPhrase, 'Not Found');
      expect(info.meaning, isNotEmpty);
      expect(info.statusClass, HttpStatusClass.clientError);
    });

    test('returns null for an unregistered code', () {
      expect(HttpStatus.lookup(299), isNull);
      expect(HttpStatus.lookup(477), isNull);
    });

    test('explains the no-response sentinel', () {
      final info = HttpStatus.lookup(HttpStatus.noResponse);

      expect(info, isNotNull);
      expect(info!.reasonPhrase, 'No Response');
      expect(info.meaning, contains('never received'));
    });

    test('covers the codes a developer most often has to look up', () {
      for (final code in <int>[401, 403, 409, 418, 422, 428, 429, 451]) {
        final info = HttpStatus.lookup(code);
        expect(info, isNotNull, reason: '$code should be documented');
        expect(info!.meaning.length, greaterThan(20));
      }
    });

    test('covers the widely deployed unofficial codes', () {
      // These show up constantly behind Cloudflare and nginx, and a developer
      // seeing 522 in a log has no idea what it means without help.
      for (final code in <int>[499, 520, 521, 522, 524, 525]) {
        expect(HttpStatus.lookup(code), isNotNull, reason: '$code is common');
      }
    });
  });

  group('HttpStatus.describe', () {
    test('synthesises a description for an unknown code', () {
      final info = HttpStatus.describe(477);

      expect(info.code, 477);
      expect(info.reasonPhrase, 'Client Error');
      expect(info.meaning, contains('non-standard'));
    });

    test('flags a value outside the HTTP range', () {
      expect(HttpStatus.describe(9000).meaning, contains('outside'));
    });
  });

  group('HttpStatus.isSuccess', () {
    test('accepts only the 2xx range', () {
      expect(HttpStatus.isSuccess(200), isTrue);
      expect(HttpStatus.isSuccess(204), isTrue);
      expect(HttpStatus.isSuccess(299), isTrue);
      expect(HttpStatus.isSuccess(199), isFalse);
      expect(HttpStatus.isSuccess(300), isFalse);
      expect(HttpStatus.isSuccess(404), isFalse);
    });
  });
}
