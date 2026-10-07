import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stile delle icone dell'app (personalizzazione).
enum AppIconStyle { outlined, rounded, sharp }

/// Controller globale del tema "Nothing OS".
///
/// Possiede: colore d'accento, uso del Dynamic Color (Material You),
/// sfondo nero puro (OLED) oppure grigio scurissimo, e lo stile delle icone.
/// Tutto viene salvato in SharedPreferences e ripristinato all'avvio.
class ThemeController extends ChangeNotifier {
  static const Color kDefaultAccent = const Color(0xFFD71921);

  // Chiavi di persistenza (quelle del tema restano identiche alle vecchie
  // versioni dell'app, così le preferenze già salvate non vanno perse).
  static const String _kColor = 'custom_theme_color';
  static const String _kDynamic = 'use_dynamic_color';
  static const String _kPureBlack = 'theme_pure_black';
  static const String _kIconStyle = 'app_icon_style';

  Color accent = kDefaultAccent;
  bool useDynamicColor = true;
  bool pureBlack = true;
  AppIconStyle iconStyle = AppIconStyle.outlined;

  /// Set di icone coerente con lo stile scelto dall'utente.
  AppIcons get icons => AppIcons(iconStyle);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorValue = prefs.getInt(_kColor);
      if (colorValue != null) accent = Color(colorValue);
      useDynamicColor = prefs.getBool(_kDynamic) ?? true;
      pureBlack = prefs.getBool(_kPureBlack) ?? true;
      final styleIndex = prefs.getInt(_kIconStyle);
      if (styleIndex != null &&
          styleIndex >= 0 &&
          styleIndex < AppIconStyle.values.length) {
        iconStyle = AppIconStyle.values[styleIndex];
      }
      notifyListeners();
    } catch (_) {
      // Preferenze non disponibili: si resta sui default.
    }
  }

  /// Imposta un colore d'accento manuale (disattiva il Dynamic Color:
  /// scegliere un colore a mano implica volere quel colore, non Material You).
  Future<void> setAccent(Color color) async {
    accent = color;
    useDynamicColor = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kColor, color.value);
    await prefs.setBool(_kDynamic, false);
  }

  /// Attiva/disattiva il Dynamic Color di Android (Material You).
  Future<void> setDynamicColor(bool value) async {
    useDynamicColor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDynamic, value);
  }

  Future<void> setPureBlack(bool value) async {
    pureBlack = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPureBlack, value);
  }

  Future<void> setIconStyle(AppIconStyle style) async {
    iconStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kIconStyle, style.index);
  }
}

/// Mappa semantica delle icone dell'app: ogni voce restituisce la variante
/// Material (outlined / rounded / sharp) scelta dall'utente nelle impostazioni.
class AppIcons {
  final AppIconStyle style;
  const AppIcons(this.style);

  IconData _pick(IconData outlined, IconData rounded, IconData sharp) {
    switch (style) {
      case AppIconStyle.outlined:
        return outlined;
      case AppIconStyle.rounded:
        return rounded;
      case AppIconStyle.sharp:
        return sharp;
    }
  }

  // ------------------------------------------------------------- Toolbar
  IconData get undo => _pick(Icons.undo, Icons.undo_rounded, Icons.undo_sharp);
  IconData get redo => _pick(Icons.redo, Icons.redo_rounded, Icons.redo_sharp);
  IconData get pen =>
      _pick(Icons.edit_outlined, Icons.edit_rounded, Icons.edit_sharp);
  IconData get highlighter => _pick(
    Icons.highlight_outlined,
    Icons.highlight_rounded,
    Icons.highlight_sharp,
  );
  IconData get shapes => _pick(
    Icons.interests_outlined,
    Icons.interests_rounded,
    Icons.interests_sharp,
  );
  IconData get lasso =>
      _pick(Icons.all_out_outlined, Icons.all_out_rounded, Icons.all_out_sharp);
  IconData get hand => _pick(
    Icons.pan_tool_alt_outlined,
    Icons.pan_tool_alt_rounded,
    Icons.pan_tool_alt_sharp,
  );
  IconData get addPage => _pick(
    Icons.note_add_outlined,
    Icons.note_add_rounded,
    Icons.note_add_sharp,
  );
  IconData get pdf => _pick(
    Icons.picture_as_pdf_outlined,
    Icons.picture_as_pdf_rounded,
    Icons.picture_as_pdf_sharp,
  );
  IconData get timer =>
      _pick(Icons.timer_outlined, Icons.timer_rounded, Icons.timer_sharp);

  // ---------------------------------------------------------- Navigazione
  IconData get back => _pick(
    Icons.arrow_back_outlined,
    Icons.arrow_back_rounded,
    Icons.arrow_back_sharp,
  );
  IconData get close =>
      _pick(Icons.close_outlined, Icons.close_rounded, Icons.close_sharp);
  IconData get add =>
      _pick(Icons.add_outlined, Icons.add_rounded, Icons.add_sharp);
  IconData get split => _pick(
    Icons.vertical_split_outlined,
    Icons.vertical_split_rounded,
    Icons.vertical_split_sharp,
  );
  IconData get splitActive =>
      _pick(Icons.vertical_split, Icons.vertical_split, Icons.vertical_split);
  IconData get settings => _pick(
    Icons.settings_outlined,
    Icons.settings_rounded,
    Icons.settings_sharp,
  );
  IconData get search =>
      _pick(Icons.search_outlined, Icons.search_rounded, Icons.search_sharp);
  IconData get file => _pick(
    Icons.insert_drive_file_outlined,
    Icons.insert_drive_file_rounded,
    Icons.insert_drive_file_sharp,
  );
  IconData get folder => _pick(
    Icons.folder_open_outlined,
    Icons.folder_open_rounded,
    Icons.folder_open_sharp,
  );
  IconData get info =>
      _pick(Icons.info_outline, Icons.info_outline_rounded, Icons.info_sharp);

  // -------------------------------------------------------------- Pomodoro
  IconData get play => _pick(
    Icons.play_arrow_outlined,
    Icons.play_arrow_rounded,
    Icons.play_arrow_sharp,
  );
  IconData get pause =>
      _pick(Icons.pause_outlined, Icons.pause_rounded, Icons.pause_sharp);
  IconData get reset =>
      _pick(Icons.refresh_outlined, Icons.refresh_rounded, Icons.refresh_sharp);
  IconData get skip => _pick(
    Icons.skip_next_outlined,
    Icons.skip_next_rounded,
    Icons.skip_next_sharp,
  );
  IconData get tune =>
      _pick(Icons.tune_outlined, Icons.tune_rounded, Icons.tune_sharp);
}
