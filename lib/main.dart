import 'package:xournalpp/src/app_brand.dart';
import 'package:xournalpp/src/compat/brand_preferences_stub.dart'
    if (dart.library.io) 'package:xournalpp/src/compat/brand_preferences_io.dart';
import 'package:xournalpp/src/dynamic_color_adapter.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:xournalpp/src/app_appearance.dart';
import 'package:xournalpp/src/app_features.dart';
import 'package:provider/provider.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:flutter/services.dart';
import 'package:xournalpp/src/external_documents.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:xournalpp/l10n/app_localizations.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await migrateBrandPreferences();
  final documents = arguments
      .where((path) => path.toLowerCase().endsWith('.pdf'))
      .map(
        (path) => <String, String>{
          'uri': path.startsWith('file:') ? Uri.parse(path).toFilePath() : path,
        },
      )
      .toList();
  try {
    documents.addAll(await ExternalDocuments.pending());
  } on PlatformException catch (_) {
    // A denied activation must not prevent the library from opening.
  } on MissingPluginException catch (_) {}
  runApp(XournalppMobile(initialDocuments: documents));
}

const Color kDefaultSeedColor = ThemeController.kDefaultAccent;

const double kFontSizeDivision = 1.6;
const double kHugeFontSize = 72 / kFontSizeDivision;
const double kLargeFontSize = 28 / kFontSizeDivision;
const double kBodyFontSize = 24 / kFontSizeDivision;
const double kEmphasisFontSize = 25.2 / kFontSizeDivision;

class XournalppMobile extends StatefulWidget {
  final List<Map<String, String>> initialDocuments;
  const XournalppMobile({super.key, this.initialDocuments = const []});

  // Compatibilita' col vecchio codice: permette di cambiare tema da altre pagine.
  static _XournalppMobileState of(BuildContext context) =>
      context.findAncestorStateOfType<_XournalppMobileState>()!;

  @override
  State<XournalppMobile> createState() => _XournalppMobileState();
}

class _XournalppMobileState extends State<XournalppMobile> {
  final ThemeController _theme = ThemeController();
  final PluginController? _plugins = AppFeatures.plugins
      ? PluginController()
      : null;
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  Future<void> _documentQueue = Future<void>.value();

  void _openDocument(Map<String, String> document) {
    _documentQueue = _documentQueue.then((_) async {
      try {
        final file = await ExternalDocuments.importPdf(document);
        if (!mounted) return;
        _navigator.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => WorkspacePage(initialFile: file),
          ),
        );
      } catch (_) {
        if (mounted)
          _messenger.currentState?.showSnackBar(
            const SnackBar(
              content: Text('Impossibile aprire il PDF selezionato'),
            ),
          );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _theme.load();
    if (AppFeatures.plugins) _plugins?.load();
    ExternalDocuments.channel.setMethodCallHandler((call) async {
      if (call.method == 'openPdf') {
        _openDocument(Map<String, String>.from(call.arguments as Map));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final document in widget.initialDocuments) {
        _openDocument(document);
      }
      try {
        for (final document in await ExternalDocuments.pending(listen: true)) {
          if (mounted) _openDocument(document);
        }
      } on PlatformException catch (_) {
      } on MissingPluginException catch (_) {}
    });
  }

  @override
  void dispose() {
    _theme.dispose();
    if (AppFeatures.plugins) _plugins?.dispose();
    ExternalDocuments.channel.setMethodCallHandler(null);
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
        if (AppFeatures.plugins)
          ChangeNotifierProvider<PluginController>.value(value: _plugins!),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            return MaterialApp(
              navigatorKey: _navigator,
              scaffoldMessengerKey: _messenger,
              debugShowCheckedModeBanner: false,
              title: AppBrand.name,
              locale: theme.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppAppearance.buildTheme(
                theme,
                flutterColorScheme(darkDynamic),
              ),
              themeMode: ThemeMode.dark,
              home: OpenPage(restoreWorkspace: widget.initialDocuments.isEmpty),
            );
          },
        ),
      ),
    );
  }
}
