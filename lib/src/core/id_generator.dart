/// Generates identifiers that are unique for the process lifetime.
///
/// Injected rather than used statically so tests can substitute a
/// deterministic sequence and assert on exact ids.
class IdGenerator {
  int _counter = 0;

  /// Returns a new id of the form `prefix-<micros>-<counter>`.
  ///
  /// The counter guarantees uniqueness even when two ids are requested inside
  /// the same microsecond, which happens with batched requests.
  String next(String prefix) {
    _counter++;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_counter';
  }
}
