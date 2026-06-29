import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global theme notifier — lives for the app lifetime, no package needed.
class ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  void set(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void setFromString(String s) {
    switch (s) {
      case 'light': set(ThemeMode.light); break;
      case 'dark':  set(ThemeMode.dark);  break;
      default:      set(ThemeMode.system);
    }
  }
}

final themeNotifier = ThemeNotifier();

// ── Colour tokens ──────────────────────────────────────────────────────────
const _seed = Color(0xFF2563EB); // blue-600

ThemeData lightTheme() {
  final cs = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light)
      .copyWith(
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF0A0A0A),
        surfaceContainerLowest: const Color(0xFFF8F9FA),
        surfaceContainer: const Color(0xFFF1F3F5),
      );
  return _base(cs).copyWith(
    scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFFFFFFFF),
      foregroundColor: const Color(0xFF0A0A0A),
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: const TextStyle(
        color: Color(0xFF0A0A0A),
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    dividerColor: const Color(0xFFE5E7EB),
    cardColor: const Color(0xFFFFFFFF),
  );
}

ThemeData darkTheme() {
  final cs = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark)
      .copyWith(
        surface: const Color(0xFF000000),        // true black
        onSurface: const Color(0xFFE8E8E8),
        surfaceContainerLowest: const Color(0xFF000000),
        surfaceContainer: const Color(0xFF111111),
        surfaceContainerHigh: const Color(0xFF1A1A1A),
      );
  return _base(cs).copyWith(
    scaffoldBackgroundColor: const Color(0xFF000000),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF000000),
      foregroundColor: const Color(0xFFE8E8E8),
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.white.withValues(alpha: 0.04),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: const TextStyle(
        color: Color(0xFFE8E8E8),
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    dividerColor: const Color(0xFF1E1E1E),
    cardColor: const Color(0xFF111111),
  );
}

ThemeData _base(ColorScheme cs) => ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        color: cs.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        filled: true,
        fillColor: cs.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
