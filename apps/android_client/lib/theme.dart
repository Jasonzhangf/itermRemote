import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF0C0F14);
  static const Color surface = Color(0xFF141923);
  static const Color surfaceElevated = Color(0xFF1C2330);
  static const Color border = Color(0xFF2A3242);
  static const Color accent = Color(0xFFEA4F3B);
  static const Color accentSoft = Color(0xFFEA4F3B);
  static const Color textPrimary = Color(0xFFF4F6F8);
  static const Color textSecondary = Color(0xFF9BA4B2);
  static const Color textMuted = Color(0xFF6D7787);
  static const Color success = Color(0xFF2CCB6F);
  static const Color warning = Color(0xFFFFB020);
  static const Color error = Color(0xFFE84A4A);

  static ThemeData dark() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: background,
      textTheme: _buildTextTheme(),
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentSoft,
        surface: surface,
        background: background,
        error: error,
        onPrimary: textPrimary,
        onSecondary: textPrimary,
        onSurface: textPrimary,
        onBackground: textPrimary,
        onError: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textSecondary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    return const TextTheme(
      displayLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: textPrimary),
      displayMedium: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: textPrimary),
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: textPrimary),
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: textPrimary),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: textPrimary),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
      titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
      bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary),
      bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: textPrimary),
      bodySmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: textSecondary),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary),
      labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textPrimary),
      labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: textSecondary),
    );
  }
}
