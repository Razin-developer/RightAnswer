import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

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
      case 'light':
        set(ThemeMode.light);
        break;
      case 'dark':
        set(ThemeMode.dark);
        break;
      default:
        set(ThemeMode.system);
    }
  }
}

final themeNotifier = ThemeNotifier();

// ── Anthropic Design Tokens ───────────────────────────────────────────────────
const _coral = Color(0xFFCC785C);
const _coralActive = Color(0xFFA9583E);
const _canvas = Color(0xFFFAF9F5);
const _surfaceSoft = Color(0xFFF5F0E8);
const _surfaceCard = Color(0xFFEFE9DE);
const _surfaceDark = Color(0xFF181715);
const _surfaceDarkElevated = Color(0xFF252320);
const _ink = Color(0xFF141413);
const _body = Color(0xFF3D3D3A);
const _muted = Color(0xFF6C6A64);
const _hairline = Color(0xFFE6DFD8);
const _onDark = Color(0xFFFAF9F5);
const _onDarkSoft = Color(0xFFA09D96);
const _error = Color(0xFFC64545);

// ── Font helpers ──────────────────────────────────────────────────────────────
TextStyle _playfair({
  double size = 28,
  FontWeight weight = FontWeight.w400,
  double height = 1.2,
  double letterSpacing = -0.3,
  Color? color,
}) =>
    GoogleFonts.playfairDisplay(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );

TextStyle _inter({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  double height = 1.55,
  Color? color,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
    );

TextStyle _mono({double size = 13, Color? color}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      height: 1.6,
      color: color,
    );

// ── Text Themes ───────────────────────────────────────────────────────────────
TextTheme _textTheme(Color displayColor, Color bodyColor) => TextTheme(
      // Display — Playfair Display serif
      displayLarge: _playfair(size: 64, height: 1.05, letterSpacing: -1.5, color: displayColor),
      displayMedium: _playfair(size: 48, height: 1.1, letterSpacing: -1.0, color: displayColor),
      displaySmall: _playfair(size: 36, height: 1.15, letterSpacing: -0.5, color: displayColor),
      // Headings — Playfair Display serif
      headlineLarge: _playfair(size: 28, height: 1.2, letterSpacing: -0.3, color: displayColor),
      headlineMedium: _playfair(size: 22, height: 1.25, letterSpacing: -0.2, color: displayColor),
      headlineSmall: _playfair(size: 18, height: 1.3, letterSpacing: -0.1, color: displayColor),
      // Titles — Inter sans
      titleLarge: _inter(size: 22, weight: FontWeight.w500, height: 1.3, color: bodyColor),
      titleMedium: _inter(size: 18, weight: FontWeight.w500, height: 1.4, color: bodyColor),
      titleSmall: _inter(size: 16, weight: FontWeight.w500, height: 1.4, color: bodyColor),
      // Body — Inter sans
      bodyLarge: _inter(size: 16, height: 1.55, color: bodyColor),
      bodyMedium: _inter(size: 14, height: 1.55, color: bodyColor),
      bodySmall: _inter(size: 13, height: 1.55, color: bodyColor),
      // Labels / captions — Inter sans
      labelLarge: _inter(size: 14, weight: FontWeight.w500, height: 1.0, color: bodyColor),
      labelMedium: _inter(size: 13, weight: FontWeight.w500, height: 1.4, color: bodyColor),
      labelSmall: _inter(size: 12, weight: FontWeight.w500, height: 1.4, color: bodyColor),
    );

// ── Light Theme ───────────────────────────────────────────────────────────────
ThemeData lightTheme() {
  final cs = ColorScheme(
    brightness: Brightness.light,
    primary: _coral,
    onPrimary: Colors.white,
    primaryContainer: _surfaceCard,
    onPrimaryContainer: _ink,
    secondary: _muted,
    onSecondary: Colors.white,
    secondaryContainer: _surfaceSoft,
    onSecondaryContainer: _ink,
    error: _error,
    onError: Colors.white,
    surface: _canvas,
    onSurface: _ink,
    surfaceContainerLowest: _canvas,
    surfaceContainerLow: _surfaceSoft,
    surfaceContainer: _surfaceCard,
    surfaceContainerHigh: _surfaceCard,
    surfaceContainerHighest: Color(0xFFE8E0D2),
    onSurfaceVariant: _body,
    outline: _hairline,
    outlineVariant: _hairline,
    inverseSurface: _surfaceDark,
    onInverseSurface: _onDark,
    inversePrimary: _coral,
    shadow: _ink,
    scrim: _ink,
  );

  return _base(cs, _ink, _body).copyWith(
    scaffoldBackgroundColor: _canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: _canvas,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: _ink.withValues(alpha: 0.06),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: _playfair(size: 20, color: _ink, letterSpacing: -0.3),
    ),
    dividerColor: _hairline,
    cardColor: _surfaceCard,
  );
}

// ── Dark Theme ────────────────────────────────────────────────────────────────
ThemeData darkTheme() {
  final cs = ColorScheme(
    brightness: Brightness.dark,
    primary: _coral,
    onPrimary: Colors.white,
    primaryContainer: _surfaceDarkElevated,
    onPrimaryContainer: _onDark,
    secondary: _onDarkSoft,
    onSecondary: _surfaceDark,
    secondaryContainer: _surfaceDarkElevated,
    onSecondaryContainer: _onDark,
    error: _error,
    onError: Colors.white,
    surface: _surfaceDark,
    onSurface: _onDark,
    surfaceContainerLowest: _surfaceDark,
    surfaceContainerLow: _surfaceDark,
    surfaceContainer: Color(0xFF1F1E1B),
    surfaceContainerHigh: _surfaceDarkElevated,
    surfaceContainerHighest: Color(0xFF2E2C28),
    onSurfaceVariant: _onDarkSoft,
    outline: Color(0xFF3A3834),
    outlineVariant: Color(0xFF2E2C28),
    inverseSurface: _canvas,
    onInverseSurface: _ink,
    inversePrimary: _coralActive,
    shadow: Colors.black,
    scrim: Colors.black,
  );

  return _base(cs, _onDark, _onDarkSoft).copyWith(
    scaffoldBackgroundColor: _surfaceDark,
    appBarTheme: AppBarTheme(
      backgroundColor: _surfaceDark,
      foregroundColor: _onDark,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: _playfair(size: 20, color: _onDark, letterSpacing: -0.3),
    ),
    dividerColor: const Color(0xFF2E2C28),
    cardColor: _surfaceDarkElevated,
  );
}

// ── Shared Base ───────────────────────────────────────────────────────────────
ThemeData _base(ColorScheme cs, Color displayColor, Color bodyColor) => ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      textTheme: _textTheme(displayColor, bodyColor),
      cardTheme: CardThemeData(
        color: cs.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _coral,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          minimumSize: const Size(0, 40),
          textStyle: _inter(size: 14, weight: FontWeight.w500, height: 1.0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          minimumSize: const Size(0, 40),
          textStyle: _inter(size: 14, weight: FontWeight.w500, height: 1.0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _coral,
          textStyle: _inter(size: 14, weight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _coral, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        hintStyle: _inter(size: 14, color: bodyColor.withValues(alpha: 0.45)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        titleTextStyle: _inter(size: 14, weight: FontWeight.w500, color: displayColor),
        subtitleTextStyle: _inter(size: 13, color: bodyColor.withValues(alpha: 0.6)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
          side: BorderSide(color: cs.outline),
        ),
        backgroundColor: cs.surfaceContainerLow,
        labelStyle: _inter(size: 13, weight: FontWeight.w500, color: displayColor),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: _inter(size: 14, color: cs.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: _coral,
        thumbColor: _coral,
        inactiveTrackColor: cs.outline,
        overlayColor: _coral.withValues(alpha: 0.12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : cs.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _coral : cs.surfaceContainerHighest,
        ),
      ),
    );
