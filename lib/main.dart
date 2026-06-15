import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <-- Serve per salvare il colore!
import 'package:xournalpp/pages/OpenPage.dart';
import 'generated/l10n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XournalppMobile());
}

const Color kDefaultSeedColor = Colors.indigo;

const double kFontSizeDivision = 1.6;
const double kHugeFontSize = 72 / kFontSizeDivision;
const double kLargeFontSize = 28 / kFontSizeDivision;
const double kBodyFontSize = 24 / kFontSizeDivision;
const double kEmphasisFontSize = 25.2 / kFontSizeDivision;

class XournalppMobile extends StatefulWidget {
  const XournalppMobile({super.key});

  // Questo trucco ci permette di cambiare il colore da qualsiasi altra pagina dell'app!
  static _XournalppMobileState of(BuildContext context) =>
      context.findAncestorStateOfType<_XournalppMobileState>()!;

  @override
  State<XournalppMobile> createState() => _XournalppMobileState();
}

class _XournalppMobileState extends State<XournalppMobile> {
  Color _customColor = kDefaultSeedColor;
  bool _useDynamicColor = true;

  @override
  void initState() {
    super.initState();
    _loadColorPreference();
  }

  // Carica il colore salvato quando apri l'app
  Future<void> _loadColorPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt('custom_theme_color');
    final useDyn = prefs.getBool('use_dynamic_color') ?? true;

    if (colorValue != null) {
      setState(() {
        _customColor = Color(colorValue);
        _useDynamicColor = useDyn;
      });
    }
  }

  // Questa è la funzione che chiameremo dalle impostazioni per cambiare colore
  void updateThemeColor(Color newColor, bool useDynamic) async {
    setState(() {
      _customColor = newColor;
      _useDynamicColor = useDynamic;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('custom_theme_color', newColor.value);
    await prefs.setBool('use_dynamic_color', useDynamic);
  }

  ThemeData _buildTheme(Brightness brightness, ColorScheme? dynamicScheme) {
    final fallbackScheme = ColorScheme.fromSeed(
      seedColor: _customColor, 
      brightness: brightness,
    );

    var colorScheme = (_useDynamicColor && dynamicScheme != null) 
        ? dynamicScheme 
        : fallbackScheme;

    if (brightness == Brightness.dark) {
      colorScheme = colorScheme.copyWith(
        surface: Colors.black, 
      );
    }

    // --- MAGIA DEL COLORE DELLA TOOLBAR ---
    final isDark = brightness == Brightness.dark;
    
    // 1. Scegliamo la "tela" di base: grigio molto scuro per la notte, grigio chiaro per il giorno
    final baseToolbarColor = isDark ? Colors.grey.shade900 : Colors.grey.shade200;
    
    // 2. Applichiamo l'influenza del colore dell'utente (primary) al 15% di intensità sopra il grigio
    final toolbarColor = Color.alphaBlend(
      colorScheme.primary.withOpacity(0.15), // Se vuoi più riflesso colorato, alza a 0.20 o 0.25!
      baseToolbarColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Open Sans',
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: isDark 
          ? Colors.black 
          : colorScheme.surfaceContainerHighest,
          
      appBarTheme: AppBarTheme(
        // Applichiamo il nostro colore personalizzato alla Toolbar!
        backgroundColor: toolbarColor, 
        foregroundColor: colorScheme.onSurface,
        elevation: 0, 
        scrolledUnderElevation: 0, // Evita che cambi colore in modo strano quando scorri la pagina
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: kIsWeb ? 'Xournal++ Web' : 'Xournal++ Mobile',
          localizationsDelegates: const [
            S.delegate,
            DefaultMaterialLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          theme: _buildTheme(Brightness.light, lightDynamic),
          darkTheme: _buildTheme(Brightness.dark, darkDynamic),
          themeMode: ThemeMode.system,
          home: OpenPage(),
        );
      },
    );
  }
}