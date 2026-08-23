import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF12201D);
  static const muted = Color(0xFF64736F);
  static const canvas = Color(0xFFF3F6F4);
  static const surface = Colors.white;
  static const primary = Color(0xFF0E7C66);
  static const primaryDark = Color(0xFF075B4A);
  static const lime = Color(0xFFB8E986);
  static const amber = Color(0xFFF2A93B);
  static const danger = Color(0xFFD74B4B);
  static const outline = Color(0xFFDDE5E1);
  static const navy = Color(0xFF102723);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.ink,
          fontSize: 30,
          height: 1.08,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineSmall: TextStyle(
          color: AppColors.ink,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(color: AppColors.muted, height: 1.45),
        labelLarge: TextStyle(fontWeight: FontWeight.w700),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: AppColors.outline),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: Color(0xFFE0F3EC),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
