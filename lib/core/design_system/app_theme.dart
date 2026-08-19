import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color background = Color(0xFF080A17);
  static const Color surface = Color(0xFF121529);
  static const Color surfaceHigh = Color(0xFF1B1E38);
  static const Color primary = Color(0xFF8B73FF);
  static const Color secondary = Color(0xFFFF75B5);
  static const Color accent = Color(0xFF61D9FF);
  static const Color textPrimary = Color(0xFFF7F5FF);
  static const Color textSecondary = Color(0xFFA7A9C1);
  static const Color divider = Color(0xFF2A2D48);
  static const Color success = Color(0xFF63E6A7);
  static const Color warning = Color(0xFFFFC56E);
  static const Color error = Color(0xFFFF6B7D);
}

abstract final class SocialColors {
  static const Color page = Color(0xFFF6F8FD);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardSoft = Color(0xFFF0F3FF);
  static const Color primary = Color(0xFF7866F2);
  static const Color primaryDark = Color(0xFF5C4BD1);
  static const Color secondary = Color(0xFFFF7EAF);
  static const Color accent = Color(0xFF42BEE8);
  static const Color textPrimary = Color(0xFF17213C);
  static const Color textSecondary = Color(0xFF65708B);
  static const Color textTertiary = Color(0xFF9BA4B8);
  static const Color divider = Color(0xFFE6EAF3);
  static const Color success = Color(0xFF32B990);
  static const Color warning = Color(0xFFFFA852);
  static const Color error = Color(0xFFE85B74);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[primary, Color(0xFF9A6FE8), secondary],
  );
}

abstract final class RoomColors {
  static const Color background = Color(0xFF08091B);
  static const Color surface = Color(0xD9171831);
  static const Color surfaceHigh = Color(0xED24234B);
  static const Color primary = Color(0xFF9A82FF);
  static const Color secondary = Color(0xFFFF78B7);
  static const Color accent = Color(0xFF6EE0FF);
  static const Color gold = Color(0xFFFFD070);
  static const Color textPrimary = Color(0xFFF9F7FF);
  static const Color textSecondary = Color(0xFFC0C3DC);
  static const Color success = Color(0xFF69E5B0);
  static const Color warning = Color(0xFFFFC66F);
  static const Color error = Color(0xFFFF738B);
}

abstract final class AppTheme {
  static ThemeData dark() => room();

  static ThemeData social() {
    const ColorScheme scheme = ColorScheme.light(
      primary: SocialColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE7E2FF),
      onPrimaryContainer: SocialColors.primaryDark,
      secondary: SocialColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFFFE5EF),
      onSecondaryContainer: Color(0xFF8D365C),
      tertiary: SocialColors.accent,
      onTertiary: Colors.white,
      surface: SocialColors.card,
      onSurface: SocialColors.textPrimary,
      surfaceContainerHighest: SocialColors.cardSoft,
      onSurfaceVariant: SocialColors.textSecondary,
      outline: SocialColors.divider,
      error: SocialColors.error,
      onError: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: SocialColors.card,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: SocialColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.18,
        ),
        titleLarge: TextStyle(
          color: SocialColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          height: 1.22,
        ),
        titleMedium: TextStyle(
          color: SocialColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.28,
        ),
        titleSmall: TextStyle(
          color: SocialColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          color: SocialColors.textPrimary,
          fontSize: 16,
          height: 1.46,
        ),
        bodyMedium: TextStyle(
          color: SocialColors.textPrimary,
          fontSize: 14,
          height: 1.44,
        ),
        bodySmall: TextStyle(
          color: SocialColors.textSecondary,
          fontSize: 12,
          height: 1.42,
        ),
        labelLarge: TextStyle(
          color: SocialColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(
          color: SocialColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: const IconThemeData(color: SocialColors.textPrimary),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: SocialColors.textPrimary,
        titleTextStyle: TextStyle(
          color: SocialColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.9),
        hintStyle: const TextStyle(color: SocialColors.textTertiary),
        prefixIconColor: SocialColors.textSecondary,
        suffixIconColor: SocialColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x1217263F)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: SocialColors.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          foregroundColor: Colors.white,
          backgroundColor: SocialColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 46),
          foregroundColor: SocialColors.textPrimary,
          side: const BorderSide(color: SocialColors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SocialColors.primary,
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: SocialColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x1017263F)),
        ),
      ),
      dividerColor: SocialColors.divider,
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFAFFFFFF),
        selectedItemColor: SocialColors.primary,
        unselectedItemColor: SocialColors.textTertiary,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SocialColors.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: SocialColors.card,
        showDragHandle: true,
        dragHandleColor: SocialColors.divider,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: SocialColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SocialColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  static ThemeData room() {
    const ColorScheme scheme = ColorScheme.dark(
      primary: RoomColors.primary,
      onPrimary: Colors.white,
      primaryContainer: RoomColors.surfaceHigh,
      onPrimaryContainer: RoomColors.textPrimary,
      secondary: RoomColors.secondary,
      onSecondary: Colors.white,
      tertiary: RoomColors.accent,
      onTertiary: Color(0xFF06141A),
      surface: RoomColors.surface,
      onSurface: RoomColors.textPrimary,
      surfaceContainerHighest: RoomColors.surfaceHigh,
      onSurfaceVariant: RoomColors.textSecondary,
      outline: Color(0xFF35345B),
      error: RoomColors.error,
      onError: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: RoomColors.background,
      canvasColor: RoomColors.surface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: RoomColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.18,
        ),
        titleLarge: TextStyle(
          color: RoomColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: RoomColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: TextStyle(
          color: RoomColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          color: RoomColors.textPrimary,
          fontSize: 16,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          color: RoomColors.textPrimary,
          fontSize: 14,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          color: RoomColors.textSecondary,
          fontSize: 12,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          color: RoomColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(
          color: RoomColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.09),
        hintStyle: const TextStyle(color: RoomColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: RoomColors.primary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          foregroundColor: Colors.white,
          backgroundColor: RoomColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: RoomColors.textPrimary,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: RoomColors.primary,
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: RoomColors.textPrimary,
          minimumSize: const Size(44, 44),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF13142C),
        modalBackgroundColor: Color(0xFF13142C),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0xFF464665),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF171830),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: RoomColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: RoomColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xF20D1020),
        selectedItemColor: RoomColors.textPrimary,
        unselectedItemColor: RoomColors.textSecondary,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
