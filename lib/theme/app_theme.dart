import 'package:flutter/material.dart';

/// Paleta: azul pizarra profundo + neutros fríos y un dorado de acento.
class AppColors {
  static const ink = Color(0xFF1C2433);
  static const inkSoft = Color(0xFF2A3446);
  static const primary = Color(0xFF2B4C7E);
  static const primaryDark = Color(0xFF1F3A63);
  static const primarySoft = Color(0xFFE9EFF8);
  static const accent = Color(0xFFE8B04B);
  static const accentSoft = Color(0xFFFDF3DF);
  static const background = Color(0xFFF5F7FA);
  static const surface = Colors.white;
  static const line = Color(0xFFDFE4EC);
  static const muted = Color(0xFF687284);
  static const green = Color(0xFF2E7D32);
  static const greenSoft = Color(0xFFE6F2E7);
  static const red = Color(0xFFC62828);
  static const redSoft = Color(0xFFFBE9E9);
  static const orange = Color(0xFFD9730D);
  static const orangeSoft = Color(0xFFFFF0DC);
  static const blue = Color(0xFF3A6FB0);
  static const blueSoft = Color(0xFFE5EEF9);
  static const whatsapp = Color(0xFF1FA855);
}

class AppTheme {
  static const radius = 12.0;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.accent,
      onSecondary: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.background,
      surfaceContainer: AppColors.background,
      surfaceContainerHigh: const Color(0xFFECEFEA),
      surfaceContainerHighest: const Color(0xFFE4E8E2),
      outline: const Color(0xFFB7BFB8),
      outlineVariant: AppColors.line,
      error: AppColors.red,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Barlow');
    final text = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: AppColors.ink, fontFamily: 'Barlow', fontSize: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.ink,
        indicatorColor: AppColors.accent,
        surfaceTintColor: Colors.transparent,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.ink : Colors.white70)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontFamily: 'Barlow',
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? Colors.white : Colors.white70,
            )),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.ink,
        indicatorColor: AppColors.accent,
        selectedIconTheme: IconThemeData(color: AppColors.ink),
        unselectedIconTheme: IconThemeData(color: Colors.white70),
        selectedLabelTextStyle: TextStyle(fontFamily: 'Barlow', color: Colors.white, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: TextStyle(fontFamily: 'Barlow', color: Colors.white70),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: const BorderSide(color: AppColors.line)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.primary, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.red)),
        labelStyle: const TextStyle(color: AppColors.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE4E8E2),
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 16),
          shape: rounded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(64, 50),
          side: const BorderSide(color: AppColors.ink, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 15),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary, textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: rounded,
        extendedTextStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 15),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.primary,
        checkmarkColor: Colors.white,
        labelStyle: const TextStyle(fontFamily: 'Barlow', color: AppColors.ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(fontFamily: 'Barlow', color: Colors.white, fontWeight: FontWeight.w600),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.white),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.ink),
          iconColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.ink),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.ink,
        titleTextStyle: TextStyle(fontFamily: 'Barlow', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
        subtitleTextStyle: TextStyle(fontFamily: 'Barlow', fontSize: 13.5, color: AppColors.muted),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(fontFamily: 'Barlow', color: Colors.white, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    );
  }
}
