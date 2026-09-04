import 'package:flutter/material.dart';

import '../core/http_status.dart';
import '../data/models/api_record.dart';
import '../data/models/crash_record.dart';
import '../data/models/leak_record.dart';

/// Colours and text styles for the dashboard.
///
/// The dashboard builds its own [Theme] rather than inheriting the host app's,
/// so a heavily branded app cannot make the inspector unreadable — a debug
/// tool needs consistent, legible defaults regardless of where it is embedded.
abstract final class StackerTheme {
  /// Accent used for the app bar and interactive elements.
  static const Color accent = Color(0xFF2962FF);

  static const Color _successLight = Color(0xFF1B873F);
  static const Color _successDark = Color(0xFF4ADE80);
  static const Color _redirectLight = Color(0xFF7A5AF8);
  static const Color _redirectDark = Color(0xFFA78BFA);
  static const Color _warnLight = Color(0xFFB45309);
  static const Color _warnDark = Color(0xFFFBBF24);
  static const Color _errorLight = Color(0xFFC62828);
  static const Color _errorDark = Color(0xFFF87171);
  static const Color _neutralLight = Color(0xFF546E7A);
  static const Color _neutralDark = Color(0xFF94A3B8);

  /// The dashboard's theme for the given [brightness].
  static ThemeData themeFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF11151C) : const Color(0xFFF5F7FA),
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? const Color(0xFF161C26) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF11151C),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? const Color(0xFF161C26) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1D2531) : Colors.white,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06),
      ),
    );
  }

  /// Monospaced style used for headers, bodies, and stack traces.
  ///
  /// The platform-appropriate families are listed explicitly because Flutter
  /// has no portable "monospace" alias, and payload alignment matters here.
  static TextStyle monospace({
    double fontSize = 13,
    Color? color,
    FontWeight? fontWeight,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>[
        'Menlo',
        'SF Mono',
        'Roboto Mono',
        'Courier New',
        'monospace',
      ],
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      height: height,
    );
  }

  /// Colour representing an HTTP status code.
  static Color statusColor(int? code, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    if (code == null) {
      return isDark ? _neutralDark : _neutralLight;
    }
    return switch (HttpStatus.classOf(code)) {
      HttpStatusClass.success => isDark ? _successDark : _successLight,
      HttpStatusClass.redirection => isDark ? _redirectDark : _redirectLight,
      HttpStatusClass.clientError => isDark ? _warnDark : _warnLight,
      HttpStatusClass.serverError => isDark ? _errorDark : _errorLight,
      HttpStatusClass.informational => isDark ? _neutralDark : _neutralLight,
      HttpStatusClass.unknown => isDark ? _neutralDark : _neutralLight,
    };
  }

  /// Colour for an API record, accounting for pending and failed states.
  static Color recordColor(ApiRecord record, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (record.state) {
      ApiCallState.pending => isDark ? _neutralDark : _neutralLight,
      ApiCallState.failed => isDark ? _errorDark : _errorLight,
      ApiCallState.complete => statusColor(record.statusCode, brightness),
    };
  }

  /// Colour for a crash severity.
  static Color severityColor(CrashSeverity severity, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (severity) {
      CrashSeverity.fatal => isDark ? _errorDark : _errorLight,
      CrashSeverity.nonFatal => isDark ? _warnDark : _warnLight,
    };
  }

  /// Colour for a leak confidence level.
  static Color confidenceColor(
    LeakConfidence confidence,
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    return switch (confidence) {
      LeakConfidence.confirmed => isDark ? _errorDark : _errorLight,
      LeakConfidence.suspected => isDark ? _warnDark : _warnLight,
    };
  }

  /// Colour used for the HTTP method label.
  static Color methodColor(String method, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (method.toUpperCase()) {
      'GET' => isDark ? _successDark : _successLight,
      'POST' => isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0),
      'PUT' || 'PATCH' => isDark ? _warnDark : _warnLight,
      'DELETE' => isDark ? _errorDark : _errorLight,
      _ => isDark ? _neutralDark : _neutralLight,
    };
  }
}
