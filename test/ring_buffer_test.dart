import 'package:flutter_test/flutter_test.dart';
import 'package:stacker_inspector/src/data/repository/ring_buffer.dart';

void main() {
  group('RingBuffer', () {
    test('retains elements in insertion order below capacity', () {
      final buffer = RingBuffer<int>(5)
        ..add(1)
        ..add(2)
        ..add(3);

      expect(buffer.length, 3);
      expect(buffer.items, <int>[1, 2, 3]);
      expect(buffer.reversed, <int>[3, 2, 1]);
    });

    test('evicts the oldest element once at capacity', () {
      final buffer = RingBuffer<int>(3)
        ..add(1)
        ..add(2)
        ..add(3);

      final evicted = buffer.add(4);

      expect(evicted, 1);
      expect(buffer.length, 3, reason: 'capacity must be a hard bound');
      expect(buffer.items, <int>[2, 3, 4]);
    });

    test('never exceeds capacity across many additions', () {
      final buffer = RingBuffer<int>(10);
      for (var i = 0; i < 1000; i++) {
        buffer.add(i);
      }

      expect(buffer.length, 10);
      expect(buffer.items.first, 990);
      expect(buffer.items.last, 999);
    });

    test('add returns null while below capacity', () {
      final buffer = RingBuffer<int>(2);
      expect(buffer.add(1), isNull);
      expect(buffer.add(2), isNull);
      expect(buffer.add(3), 1);
    });

    test('replaceWhere swaps in place and preserves ordering', () {
      final buffer = RingBuffer<String>(4)
        ..add('a')
        ..add('b')
        ..add('c');

      final replaced = buffer.replaceWhere((value) => value == 'b', 'B');

      expect(replaced, isTrue);
      expect(
        buffer.items,
        <String>['a', 'B', 'c'],
        reason: 'an updated record must keep its position in the list',
      );
    });

    test('replaceWhere reports false when nothing matches', () {
      final buffer = RingBuffer<String>(4)..add('a');
      expect(buffer.replaceWhere((value) => value == 'zzz', 'Z'), isFalse);
      expect(buffer.items, <String>['a']);
    });

    test('firstWhereOrNull finds a match or returns null', () {
      final buffer = RingBuffer<int>(4)
        ..add(10)
        ..add(20);

      expect(buffer.firstWhereOrNull((value) => value > 15), 20);
      expect(buffer.firstWhereOrNull((value) => value > 100), isNull);
    });

    test('removeWhere drops matches and reports the count', () {
      final buffer = RingBuffer<int>(6)
        ..add(1)
        ..add(2)
        ..add(3)
        ..add(4);

      final removed = buffer.removeWhere((value) => value.isEven);

      expect(removed, 2);
      expect(buffer.items, <int>[1, 3]);
    });

    test('clear empties the buffer', () {
      final buffer = RingBuffer<int>(3)
        ..add(1)
        ..add(2)
        ..clear();

      expect(buffer.isEmpty, isTrue);
      expect(buffer.items, isEmpty);
    });

    test('rejects a non-positive capacity', () {
      expect(() => RingBuffer<int>(0), throwsA(isA<AssertionError>()));
      expect(() => RingBuffer<int>(-1), throwsA(isA<AssertionError>()));
    });
  });
}
