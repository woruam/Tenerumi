import 'package:flutter/foundation.dart';
import 'package:xournalpp/src/dynamic_color_adapter.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';

import 'generated/l10n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XournalppMobile());
}

const Color kDefaultSeedColor = ThemeController.kDefaultAccent;

const double kFontSizeDivision = 1.6;
const double kHugeFontSize = 72 / kFontSizeDivision;
const double kLargeFontSize = 28 / kFontSizeDivision;
const double kBodyFontSize = 24 / kFontSizeDivision;
const double kEmphasisFontSize = 25.2 / kFontSizeDivision;

class XournalppMobile extends StatefulWidget {
  const XournalppMobile({super.key});

  // Compatibilita' col vecchio codice: permette di cambiare tema da altre pagine.
  static _XournalppMobileState of(BuildContext context) =>
      context.findAncestorStateOfType<_XournalppMobileState>()!;

  @override
  State<XournalppMobile> createState() => _XournalppMobileState();
}

class _XournalppMobileState extends State<XournalppMobile> {
  final ThemeController _theme = ThemeController();
  final PluginController _plugins = PluginController();

  @override
  void initState() {
    super.initState();
    _theme.load();
    _plugins.load();
  }

  @override
  void dispose() {
    _theme.dispose();
    _plugins.dispose();
    super.dispose();
  }

  /// API storica: ora delega al [ThemeController].
  /// Vecchia API mantenuta per compatibilità: aggiorna colore o Dynamic Color.
  void updateThemeColor(Color newColor, bool useDynamic) =>
      useDynamic ? _theme.setDynamicColor(true) : _theme.setAccent(newColor);

  ThemeData _buildTheme(ThemeController theme, ColorScheme? dynamicScheme) {
    // Base scura in puro stile Nothing.
    const brightness = Brightness.dark;

    final fallbackScheme = ColorScheme.fromSeed(
      seedColor: theme.accent,
      brightness: brightness,
    );

    var colorScheme = (theme.useDynamicColor && dynamicScheme != null)
        ? dynamicScheme
        : fallbackScheme;

    final Color bg = theme.pureBlack ? Colors.black : const Color(0xFF101010);

    colorScheme = colorScheme.copyWith(
      surface: theme.pureBlack
          ? const Color(0xFF0A0A0A)
          : const Color(0xFF141414),
      surfaceContainerHighest: const Color(0xFF1A1A1A),
    );

    final TextTheme baseTextTheme = ThemeData.dark().textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,

      // Tipografia Dot-Matrix (titoli) e Inter (testo)
      // Google Fonts 9's TextTheme belongs to material_ui. Apply individual
      // fonts to Flutter's shared TextStyle type to retain the SDK TextTheme.
      textTheme: baseTextTheme.copyWith(
        displayLarge: GoogleFonts.vt323(textStyle: baseTextTheme.displayLarge),
        displayMedium: GoogleFonts.vt323(
          textStyle: baseTextTheme.displayMedium,
        ),
        displaySmall: GoogleFonts.vt323(textStyle: baseTextTheme.displaySmall),
        headlineLarge: GoogleFonts.vt323(
          textStyle: baseTextTheme.headlineLarge,
        ),
        headlineMedium: GoogleFonts.vt323(
          textStyle: baseTextTheme.headlineMedium,
        ),
        headlineSmall: GoogleFonts.vt323(
          textStyle: baseTextTheme.headlineSmall,
        ),
        titleLarge: GoogleFonts.vt323(textStyle: baseTextTheme.titleLarge),
        titleMedium: GoogleFonts.vt323(textStyle: baseTextTheme.titleMedium),
        titleSmall: GoogleFonts.inter(textStyle: baseTextTheme.titleSmall),
        bodyLarge: GoogleFonts.inter(textStyle: baseTextTheme.bodyLarge),
        bodyMedium: GoogleFonts.inter(textStyle: baseTextTheme.bodyMedium),
        bodySmall: GoogleFonts.inter(textStyle: baseTextTheme.bodySmall),
        labelLarge: GoogleFonts.inter(textStyle: baseTextTheme.labelLarge),
        labelMedium: GoogleFonts.inter(textStyle: baseTextTheme.labelMedium),
        labelSmall: GoogleFonts.inter(textStyle: baseTextTheme.labelSmall),
      ),

      // Styling: Forme Squircle
      cardTheme: CardThemeData(
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(48),
        ),
        color: const Color(0xFF121212),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(56),
        ),
        backgroundColor: const Color(0xFF151515).withOpacity(0.85),
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(56)),
        ),
        backgroundColor: Color(0xFF151515),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: _theme),
        ChangeNotifierProvider<PluginController>.value(value: _plugins),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: kIsWeb ? 'Xournal++ Web' : 'Xournal++ Mobile',
              localizationsDelegates: const [
                S.delegate,
                DefaultMaterialLocalizations.delegate,
              ],
              supportedLocales: S.delegate.supportedLocales,
              theme: _buildTheme(theme, flutterColorScheme(lightDynamic)),
              darkTheme: _buildTheme(theme, flutterColorScheme(darkDynamic)),
              themeMode: ThemeMode.dark,
              home: OpenPage(),
            );
          },
        ),
      ),
    );
  }
}
