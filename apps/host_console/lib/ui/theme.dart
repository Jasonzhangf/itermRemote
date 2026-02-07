import 'package:flutter/material.dart';

/// Professional Dark Theme - Black/Gray + Red Accent
/// Inspired by ToDesk layout but with distinct professional styling

class AppTheme {
  // Primary Colors
  static const Color background = Color(0xFF0D0D0D);        // Deep black
  static const Color surface = Color(0xFF1A1A1A);          // Dark gray surface
  static const Color surfaceElevated = Color(0xFF242424);  // Elevated surface
  static const Color surfaceHover = Color(0xFF2D2D2D);     // Hover state
  
  // Accent Colors
  static const Color accentRed = Color(0xFFE53935);        // Primary red
  static const Color accentRedDark = Color(0xFFB71C1C);    // Dark red
  static const Color accentRedLight = Color(0xFFEF5350);   // Light red
  static const Color accentOrange = Color(0xFFFF5722);     // Orange accent
  
  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);      // White
  static const Color textSecondary = Color(0xFFB3B3B3);    // Light gray
  static const Color textMuted = Color(0xFF666666);        // Muted gray
  static const Color textDisabled = Color(0xFF4D4D4D);     // Disabled
  
  // Status Colors
  static const Color statusSuccess = Color(0xFF4CAF50);
  static const Color statusWarning = Color(0xFFFF9800);
  static const Color statusError = Color(0xFFE53935);
  static const Color statusInfo = Color(0xFF2196F3);
  
  // Border Colors
  static const Color border = Color(0xFF333333);
  static const Color borderActive = Color(0xFFE53935);
  static const Color divider = Color(0xFF262626);

  // Gradients
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
  );
  
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE53935), Color(0xFFFF5722)],
  );

  // Theme Data
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: background,
      primaryColor: accentRed,
      colorScheme: const ColorScheme.dark(
        primary: accentRed,
        secondary: accentOrange,
        surface: surface,
        background: background,
        error: statusError,
        onPrimary: textPrimary,
        onSecondary: textPrimary,
        onSurface: textPrimary,
        onBackground: textPrimary,
        onError: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentRed,
          foregroundColor: textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentRedLight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: accentRed, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: statusError, width: 1),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textMuted),
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: surfaceHover,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceElevated,
        selectedColor: accentRed.withOpacity(0.2),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: textPrimary, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border),
        ),
        textStyle: const TextStyle(color: textPrimary, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

/// Custom text styles
class AppTextStyles {
  static const TextStyle headline = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppTheme.textPrimary,
    letterSpacing: -0.5,
  );
  
  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppTheme.textPrimary,
    letterSpacing: 0.3,
  );
  
  static const TextStyle subtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppTheme.textSecondary,
  );
  
  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppTheme.textPrimary,
    height: 1.5,
  );
  
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppTheme.textMuted,
  );
  
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppTheme.textSecondary,
    letterSpacing: 0.5,
  );
}
