import 'package:flutter/material.dart';

class Brand {
  static const ink = Color(0xFF0F1B2D);
  static const teal = Color(0xFF14B8A6);
  static const indigo = Color(0xFF6366F1);
  static const coral = Color(0xFFFF6B6B);
  static const sand = Color(0xFFF6F7FB);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1B2D), Color(0xFF1E3A5F), Color(0xFF14B8A6)],
  );

  static const memberColors = [
    Color(0xFF6366F1),
    Color(0xFFFF6B6B),
    Color(0xFFF59E0B),
    Color(0xFF14B8A6),
    Color(0xFFEC4899),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
  ];

  static ThemeData darkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.dark,
      surface: const Color(0xFF16233A),
    );
    return _build(scheme, const Color(0xFF0B1424), teal);
  }

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return _build(scheme, sand, ink);
  }

  static ThemeData _build(ColorScheme scheme, Color bg, Color button) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Theme-aware colours so every screen works in light and dark mode.
extension UiColors on BuildContext {
  ColorScheme get _cs => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get surface => _cs.surface;
  Color get bg => Theme.of(this).scaffoldBackgroundColor;
  Color get text => _cs.onSurface;
  Color get muted => _cs.onSurface.withValues(alpha: .6);
  Color get subtle => _cs.onSurface.withValues(alpha: .3);
  Color get line => _cs.onSurface.withValues(alpha: .12);
}
