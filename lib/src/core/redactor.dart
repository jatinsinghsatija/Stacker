import 'dart:convert';

import 'stacker_config.dart';

/// Removes credentials from captured headers and bodies before they are stored.
///
/// Redaction happens at capture time, not at display time, so a secret never
/// reaches the ring buffer and cannot leak through a shared report.
class Redactor {
  const Redactor(this._config);

  final StackerConfig _config;

  /// Returns a copy of [headers] with sensitive values replaced.
  Map<String, String> headers(Map<String, dynamic>? headers) {
    if (headers == null || headers.isEmpty) return const <String, String>{};
    final redacted = <String, String>{};
    for (final entry in headers.entries) {
      final value = _stringify(entry.value);
      redacted[entry.key] = _isRedactedHeader(entry.key)
          ? _config.redactionPlaceholder
          : value;
    }
    return redacted;
  }

  /// Returns a copy of [params] with sensitive values replaced.
  ///
  /// Query parameters are checked against both header and body key lists,
  /// since tokens commonly appear as `?access_token=...`.
  Map<String, String> parameters(Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return const <String, String>{};
    final redacted = <String, String>{};
    for (final entry in params.entries) {
      final value = _stringify(entry.value);
      final sensitive =
          _isRedactedHeader(entry.key) || _isRedactedBodyKey(entry.key);
      redacted[entry.key] =
          sensitive ? _config.redactionPlaceholder : value;
    }
    return redacted;
  }

  /// Serialises and redacts a request or response body.
  ///
  /// JSON bodies are walked so nested secrets are caught. Non-JSON bodies are
  /// stringified and truncated but otherwise passed through, since there is no
  /// reliable way to locate a secret inside an opaque payload.
  String? body(Object? body) {
    if (body == null) return null;
    if (body is List<int>) {
      return _truncate('<binary ${body.length} bytes>');
    }

    if (body is Map || body is List) {
      return _truncate(
        const JsonEncoder.withIndent('  ').convert(_walk(body)),
      );
    }

    final text = body is String ? body : body.toString();
    if (text.isEmpty) return null;

    // Try to parse as JSON so nested keys can be redacted.
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map || decoded is List) {
        return _truncate(
          const JsonEncoder.withIndent('  ').convert(_walk(decoded)),
        );
      }
    } on FormatException {
      // Not JSON — fall through and handle as form-encoded or plain text.
    }

    if (text.contains('=') && !text.contains('\n')) {
      return _truncate(_redactFormEncoded(text));
    }
    return _truncate(text);
  }

  /// Recursively redacts values under sensitive keys.
  Object? _walk(Object? node) {
    if (node is Map) {
      return node.map((key, dynamic value) {
        final name = key.toString();
        if (_isRedactedBodyKey(name)) {
          return MapEntry(name, _config.redactionPlaceholder);
        }
        return MapEntry(name, _walk(value));
      });
    }
    if (node is List) {
      return node.map<Object?>(_walk).toList();
    }
    return node;
  }

  /// Redacts sensitive fields in an `application/x-www-form-urlencoded` body.
  String _redactFormEncoded(String text) {
    return text.split('&').map((pair) {
      final index = pair.indexOf('=');
      if (index <= 0) return pair;
      final key = pair.substring(0, index);
      if (_isRedactedBodyKey(Uri.decodeQueryComponent(key)) ||
          _isRedactedHeader(Uri.decodeQueryComponent(key))) {
        return '$key=${_config.redactionPlaceholder}';
      }
      return pair;
    }).join('&');
  }

  bool _isRedactedHeader(String name) {
    final lower = name.toLowerCase();
    return _config.redactedHeaders.any(
      (candidate) => candidate.toLowerCase() == lower,
    );
  }

  bool _isRedactedBodyKey(String name) {
    final lower = name.toLowerCase();
    return _config.redactedBodyKeys.any(
      (candidate) => candidate.toLowerCase() == lower,
    );
  }

  String _truncate(String text) {
    final limit = _config.maxBodyLength;
    if (text.length <= limit) return text;
    final omitted = text.length - limit;
    return '${text.substring(0, limit)}\n\n… truncated, $omitted more characters';
  }

  static String _stringify(Object? value) {
    if (value == null) return '';
    if (value is Iterable) return value.join(', ');
    return value.toString();
  }
}
