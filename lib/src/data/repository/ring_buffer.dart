import 'dart:collection';

/// A fixed-capacity FIFO buffer that evicts the oldest element when full.
///
/// Backed by [ListQueue], so appending and evicting are both amortised O(1).
/// This is the storage primitive behind every Stacker record store: capture
/// must never grow memory without bound, since the library runs inside the
/// app it is observing.
class RingBuffer<T> {
  RingBuffer(this.capacity)
      : assert(capacity > 0, 'capacity must be positive'),
        _queue = ListQueue<T>(capacity);

  /// Maximum number of elements retained.
  final int capacity;

  final ListQueue<T> _queue;

  /// Number of elements currently held.
  int get length => _queue.length;

  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;

  /// Elements in insertion order, oldest first.
  List<T> get items => List<T>.unmodifiable(_queue);

  /// Elements in reverse insertion order, newest first.
  ///
  /// This is what the dashboard lists show, so the freshest call is on top.
  List<T> get reversed => _queue.toList().reversed.toList(growable: false);

  /// Appends [element], evicting the oldest element if at capacity.
  ///
  /// Returns the evicted element, or `null` when nothing was dropped.
  T? add(T element) {
    T? evicted;
    if (_queue.length >= capacity) {
      evicted = _queue.removeFirst();
    }
    _queue.addLast(element);
    return evicted;
  }

  /// Replaces the first element satisfying [test] with [element].
  ///
  /// Returns `true` when a match was found and replaced. Used to upgrade a
  /// pending API record in place once its response arrives, which keeps the
  /// call's position in the list stable instead of re-ordering it.
  bool replaceWhere(bool Function(T element) test, T element) {
    final existing = _queue.toList();
    for (var i = 0; i < existing.length; i++) {
      if (test(existing[i])) {
        existing[i] = element;
        _queue
          ..clear()
          ..addAll(existing);
        return true;
      }
    }
    return false;
  }

  /// Returns the first element satisfying [test], or `null`.
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in _queue) {
      if (test(element)) return element;
    }
    return null;
  }

  /// Removes every element satisfying [test], returning how many were removed.
  int removeWhere(bool Function(T element) test) {
    final before = _queue.length;
    final kept = _queue.where((element) => !test(element)).toList();
    _queue
      ..clear()
      ..addAll(kept);
    return before - _queue.length;
  }

  /// Drops every element.
  void clear() => _queue.clear();
}
