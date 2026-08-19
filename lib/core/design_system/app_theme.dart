import 'package:flutter/material.dart';

abstract final class AppColors {
  // Light social lobby surfaces observed in the runtime reference video.
  static const Color lobbyBackground = Color(0xFFF4F7FF);
  static const Color lobbySurface = Colors.white;
  static const Color lobbySurfaceSoft = Color(0xFFF0F3FF);
  static const Color lobbySky = Color(0xFFE8F5FF);
  static const Color lobbyLavender = Color(0xFFF0EAFF);
  static const Color lobbyText = Color(0xFF20243A);
  static const Color lobbyTextSecondary = Color(0xFF7C839E);
  static const Color lobbyDivider = Color(0xFFE8EBF4);

  // Immersive room surfaces.
  static const Color background = Color(0xFF050817);
  static const Color backgroundElevated = Color(0xFF080D23);
  static const Color surface = Color(0xFF0D1430);
  static const Color surfaceHigh = Color(0xFF151E42);
  static const Color surfaceHighest = Color(0xFF202952);

  static const Color primary = Color(0xFF8068FF);
  static const Color primaryBright = Color(0xFFA58EFF);
  static const Color secondary = Color(0xFFFF70B6);
  static const Color accent = Color(0xFF55D7FF);
  static const Color gold = Color(0xFFFFC96B);
  static const Color success = Color(0xFF57DFAF);
  static const Color warning = Color(0xFFFFC36A);
  static const Color error = Color(0xFFFF6986);

  static const Color textPrimary = Color(0xFFF8F6FF);
  static const Color textSecondary = Color(0xFFAEB4D2);
  static const Color textTertiary = Color(0xFF777FAD);
  static const Color divider = Color(0xFF252E55);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[primary, Color(0xFF7046F4), secondary],
  );

  static const LinearGradient roomGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF21184D),
      Color(0xFF101936),
      Color(0xFF080D22),
      background,
    ],
    stops: <double>[0, 0.32, 0.68, 1],
  );
}

abstract final class AppTheme {
  static ThemeData dark() {
    const ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.surfaceHighest,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      tertiary: AppColors.accent,
      onTertiary: Color(0xFF03131B),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceHighest,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.divider,
      error: AppColors.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.backgroundElevated,
      visualDensity: VisualDensity.standard,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.18,
        ),
        headlineSmall: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 23,
          fontWeight: FontWeight.w800,
          height: 1.22,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleSmall: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          height: 1.48,
        ),
        bodySmall: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          height: 1.45,
        ),
        labelLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh.withValues(alpha: 0.88),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 50),
          foregroundColor: Colors.white,
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.backgroundElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.backgroundElevated,
        showDragHandle: true,
        dragHandleColor: AppColors.divider,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHighest,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData lobby() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.lobbySurface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.lobbySurface,
        onSurface: AppColors.lobbyText,
        outline: AppColors.lobbyDivider,
      ),
      scaffoldBackgroundColor: AppColors.lobbyBackground,
      canvasColor: AppColors.lobbySurface,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.lobbyText,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.18,
        ),
        headlineSmall: TextStyle(
          color: AppColors.lobbyText,
          fontSize: 23,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          color: AppColors.lobbyText,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppColors.lobbyText,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: TextStyle(
          color: AppColors.lobbyText,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          color: AppColors.lobbyText,
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: AppColors.lobbyText,
          fontSize: 14,
          height: 1.48,
        ),
        bodySmall: TextStyle(
          color: AppColors.lobbyTextSecondary,
          fontSize: 12,
          height: 1.45,
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.lobbyText,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lobbySurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.lobbyDivider),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.92),
        hintStyle: const TextStyle(color: AppColors.lobbyTextSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.lobbyDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.lobbyTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.lobbySurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.lobbySurface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.lobbySurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}
