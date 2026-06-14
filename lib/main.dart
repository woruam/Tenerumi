import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart'; // <-- IMPORT DEL COLORE DINAMICO
import 'package:xournalpp/pages/OpenPage.dart';
import 'generated/l10n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XournalppMobile());
}

const Color kSeedColor = Colors.deepBlue;

const double kFontSizeDivision = 1.6;

const double kHugeFontSize = 72 / kFontSizeDivision;
const double kLargeFontSize = 28 / kFontSizeDivision;
const double kBodyFontSize = 24 / kFontSizeDivision;
const double kEmphasisFontSize = 25.2 / kFontSizeDivision;

// --- MODIFICATO: Ora accetta un ColorScheme dinamico opzionale ---
ThemeData _buildTheme(Brightness brightness, ColorScheme? dynamicColorScheme) {
  // Se Android ci fornisce un colore dinamico, usa quello. 
  // Altrimenti, usa il viola profondo (kSeedColor) come colore di salvataggio.
  final colorScheme = dynamicColorScheme ?? ColorScheme.fromSeed(
    seedColor: kSeedColor, 
    brightness: brightness
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: 'Open Sans',
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surfaceContainerHighest,
      foregroundColor: colorScheme.onSurface,
    ),
  );
}

class XournalppMobile extends StatelessWidget {
  const XournalppMobile({super.key});

  @override
  Widget build(BuildContext context) {
    // --- AVVOLTO IL TUTTO NEL DYNAMIC COLOR BUILDER ---
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
          
          // Passiamo i colori estratti dal sistema operativo ai nostri temi
          theme: _buildTheme(Brightness.light, lightDynamic),
          darkTheme: _buildTheme(Brightness.dark, darkDynamic),
          
          themeMode: ThemeMode.system,
          home: OpenPage(), 
        );
      },
    );
  }
}