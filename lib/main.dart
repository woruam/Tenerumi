import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'generated/l10n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XournalppMobile());
}

const Color kSeedColor = Colors.deepPurple;

const double kFontSizeDivision = 1.6;

const double kHugeFontSize = 72 / kFontSizeDivision;
const double kLargeFontSize = 28 / kFontSizeDivision;
const double kBodyFontSize = 24 / kFontSizeDivision;
const double kEmphasisFontSize = 25.2 / kFontSizeDivision;

ThemeData _buildTheme(Brightness brightness) {
  final colorScheme =
      ColorScheme.fromSeed(seedColor: kSeedColor, brightness: brightness);
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kIsWeb ? 'Xournal++ Web' : 'Xournal++ Mobile',
      localizationsDelegates: const [
        S.delegate,
        DefaultMaterialLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: OpenPage(), // <--- PUNTA ALLA HOME PAGE CORRETTA
    );
  }
}