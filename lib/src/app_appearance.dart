import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/theme_controller.dart';

/// Shared Pomodoro surfaces: opaque fills, one border, no backdrop filtering.
abstract final class AppAppearance {
  static const Color accent = ThemeController.kDefaultAccent;
  static const Color panel = Color(0xFF101010);
  static const Color raised = Color(0xFF1A1A1A);
  static const Color border = Color(0xFF292929);
  static const panelShape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(40)),
    side: BorderSide(color: border),
  );

  static ThemeData buildTheme(
    ThemeController theme,
    ColorScheme? dynamicScheme,
  ) {
    // Base scura in puro stile Nothing.
    const brightness = Brightness.dark;

    final fallbackScheme =
        ColorScheme.fromSeed(
          seedColor: theme.accent,
          brightness: brightness,
        ).copyWith(
          primary: theme.accent,
          onPrimary:
              ThemeData.estimateBrightnessForColor(theme.accent) ==
                  Brightness.dark
              ? Colors.white
              : Colors.black,
        );

    var colorScheme = (theme.useDynamicColor && dynamicScheme != null)
        ? dynamicScheme
        : fallbackScheme;

    final Color bg = theme.pureBlack ? Colors.black : const Color(0xFF101010);

    colorScheme = colorScheme.copyWith(
      surface: theme.pureBlack
          ? const Color(0xFF0A0A0A)
          : const Color(0xFF141414),
      surfaceContainerLowest: panel,
      surfaceContainerLow: panel,
      surfaceContainer: panel,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: raised,
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFFB8B8B8),
      outline: const Color(0xFF686868),
      outlineVariant: border,
      primaryContainer: raised,
      onPrimaryContainer: Colors.white,
    );

    final TextTheme baseTextTheme = ThemeData.dark().textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,

      // Tipografia Dot-Matrix (titoli) e Inter (testo)
      // Bundled fonts avoid network requests and late font replacement.
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(fontFamily: 'VT323'),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          fontFamily: 'VT323',
        ),
        displaySmall: baseTextTheme.displaySmall?.copyWith(fontFamily: 'VT323'),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontFamily: 'VT323',
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontFamily: 'VT323',
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontFamily: 'VT323',
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(fontFamily: 'VT323'),
        titleMedium: baseTextTheme.titleMedium?.copyWith(fontFamily: 'VT323'),
        titleSmall: baseTextTheme.titleSmall?.copyWith(fontFamily: 'Inter'),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(fontFamily: 'Inter'),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontFamily: 'Inter'),
        bodySmall: baseTextTheme.bodySmall?.copyWith(fontFamily: 'Inter'),
        labelLarge: baseTextTheme.labelLarge?.copyWith(fontFamily: 'Inter'),
        labelMedium: baseTextTheme.labelMedium?.copyWith(fontFamily: 'Inter'),
        labelSmall: baseTextTheme.labelSmall?.copyWith(fontFamily: 'Inter'),
      ),

      cardTheme: const CardThemeData(
        shape: panelShape,
        color: panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: const DialogThemeData(
        shape: panelShape,
        backgroundColor: panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
          side: BorderSide(color: border),
        ),
        backgroundColor: panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: panel,
        elevation: 0,
        shape: panelShape,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: raised,
        side: const BorderSide(color: border),
        shape: const StadiumBorder(),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: const StadiumBorder(),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const StadiumBorder(),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: panel,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: border)),
      ),
    );
  }
}
