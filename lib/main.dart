import 'package:xournalpp/src/dynamic_color_adapter.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:xournalpp/src/app_appearance.dart';
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
              title: 'OSI',
              localizationsDelegates: const [
                S.delegate,
                DefaultMaterialLocalizations.delegate,
              ],
              supportedLocales: S.delegate.supportedLocales,
              theme: AppAppearance.buildTheme(
                theme,
                flutterColorScheme(darkDynamic),
              ),
              themeMode: ThemeMode.dark,
              home: OpenPage(),
            );
          },
        ),
      ),
    );
  }
}
