import 'package:xournalpp/l10n/app_localizations.dart';
import 'package:xournalpp/src/app_brand.dart';
import 'package:xournalpp/widgets/settings_section.dart';
import 'package:xournalpp/widgets/stylus_menu_settings.dart';
import 'package:xournalpp/src/workspace_session.dart';
import 'package:xournalpp/src/note_tags.dart';
import 'package:xournalpp/src/recent_documents.dart';
import 'package:xournalpp/widgets/note_tag_picker.dart';
import 'package:xournalpp/widgets/app_info_dialog.dart';
import 'package:xournalpp/widgets/note_backup_dialog.dart';
import 'package:xournalpp/src/app_appearance.dart';

import 'package:flutter/material.dart';
import 'package:xournalpp/src/stylus_profile.dart';
import 'package:xournalpp/src/critical_data.dart';
import 'package:flutter/services.dart';
import 'package:xournalpp/controllers/note_audio_controller.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/src/app_features.dart';
import 'package:xournalpp/plugins/plugin_manager_page.dart';
import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/compat/audio_platform_stub.dart'
    if (dart.library.io) 'package:xournalpp/src/compat/audio_platform_io.dart';
import 'package:xournalpp/widgets/document_library_card.dart';

class OpenPage extends StatefulWidget {
  final bool restoreWorkspace;
  const OpenPage({super.key, this.restoreWorkspace = true});
  @override
  _OpenPageState createState() => _OpenPageState();
}

class _OpenPageState extends State<OpenPage> {
  List<dynamic> recentFiles = [];
  List<Map<String, dynamic>> recoveryFiles = [];
  List<Map<String, dynamic>> audioRecoveries = [];

  List<String> tags = ['Tutti', 'Appunti', 'Scuola', 'Lavoro'];
  String selectedTag = 'Tutti';
  bool _deletingNote = false;
  bool _openingFile = false;
  String _searchQuery = '';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showNoteActions(Map<String, dynamic> entry) async {
    if (_deletingNote) return;
    final l10n = context.l10n;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              entry['name'] as String? ?? l10n.newNote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(l10n.changeTag),
            onTap: () => Navigator.pop(sheetContext, 'tag'),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(l10n.delete),
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'tag') await _editNoteTag(entry);
    if (action == 'delete') await _confirmDeleteNote(entry);
  }

  Future<void> _confirmDeleteNote(Map<String, dynamic> entry) async {
    if (_deletingNote) return;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteNoteConfirmTitle),
        content: Text(
          l10n.deleteNoteConfirmMessage(entry['name'] as String? ?? l10n.newNote),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _deletingNote) return;
    _deletingNote = true;
    try {
      await RecentDocuments.delete(entry);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.noteDeleted)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.deleteNoteFailed),
          ),
        );
    } finally {
      _deletingNote = false;
      if (mounted) await _loadRecentFiles();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
    if (widget.restoreWorkspace) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreWorkspace());
    }
  }

  Future<void> _restoreWorkspace() async {
    RestoredWorkspace? restored;
    try {
      restored = await WorkspaceSession.restore();
    } catch (error) {
      CriticalData.warnings.add('Sessione non disponibile: $error');
      if (mounted) setState(() {});
      return;
    }
    if (!mounted ||
        restored == null ||
        ModalRoute.of(context)?.isCurrent != true)
      return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WorkspacePage(restored: restored)),
    );
    if (mounted) await _loadRecentFiles();
  }

  Future<void> _loadRecentFiles() async {
    try {
      final files = await RecentDocuments.list();
      final recoveries = await AutosaveStore.list();
      final availableTags = await NoteTags.load();
      List<Map<String, dynamic>> stagedAudio = [];
      try {
        if (nativeAudioAvailable) {
          final raw = await AndroidNoteAudioBackend.channel.invokeMethod<List>(
            'orphans',
          );
          stagedAudio = (raw ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((e) => e['noteId'] is String && e['count'] is int)
              .toList();
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        recoveryFiles = recoveries;
        audioRecoveries = stagedAudio;
        recentFiles = files;
        tags = ['Tutti', ...availableTags];
        if (!tags.contains(selectedTag)) selectedTag = 'Tutti';
        for (final file in recentFiles) {
          final currentTag = NoteTags.normalize(
            file['tag'] as String? ?? 'Appunti',
          );
          file['tag'] =
              availableTags
                  .where((tag) => tag.toLowerCase() == currentTag.toLowerCase())
                  .firstOrNull ??
              'Appunti';
        }
      });
    } catch (error) {
      CriticalData.warnings.add('Impossibile aprire la libreria: $error');
      if (mounted) setState(() {});
    }
  }

  Future<String?> _createTag(BuildContext dialogContext) async {
    final tag = await showCreateNoteTagDialog(dialogContext);
    if (tag == null) return null;
    final available = await NoteTags.load();
    if (!mounted) return null;
    setState(() => tags = ['Tutti', ...available]);
    return tag;
  }

  Future<void> _editNoteTag(Map<String, dynamic> entry) async {
    final l10n = context.l10n;
    String chosen = entry['tag'] as String? ?? 'Appunti';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(l10n.changeTag),
          content: SizedBox(
            width: 360,
            child: NoteTagPicker(
              tags: tags.where((tag) => tag != 'Tutti').toList(),
              value: chosen,
              onChanged: (tag) => update(() => chosen = tag),
              onCreate: () async {
                final tag = await _createTag(context);
                if (context.mounted && tag != null) update(() => chosen = tag);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await RecentDocuments.setTag(entry, result);
      if (!mounted) return;
      setState(() => selectedTag = result);
      await _loadRecentFiles();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.updateTagFailed)),
        );
      }
    }
  }

  void _openFile(XppFile file) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => WorkspacePage(initialFile: file)),
    ).then((_) {
      if (mounted) _loadRecentFiles();
    });
  }

  Future<void> _openDeviceFile() async {
    if (_openingFile) return;
    setState(() => _openingFile = true);
    final l10n = context.l10n;
    try {
      final file = await XppFile.open(
        (_) {},
        (_) => FilePickerCross.importFromStorage(
          type: FileTypeCross.custom,
          fileExtension: 'pdf',
        ),
      );
      if (mounted) _openFile(file);
    } catch (error) {
      if (mounted && error != 'No file selected.') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.fileOpenFailed(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _openingFile = false);
    }
  }

  // --- FINESTRA DI DIALOGO PER CREARE LA NOTA (con scelta del modello) ---
  Future<void> _showNewNoteDialog() async {
    TextEditingController titleController = TextEditingController();
    // I modelli di pagina disponibili. La funzione costruisce lo sfondo alla
    // dimensione giusta al momento della creazione del file.
    final List<_NoteTemplate> templates = [
      _NoteTemplate(
        'Bianco',
        (s) => XppBackgroundSolidPlain(color: Colors.white, size: s),
      ),
      _NoteTemplate(
        'Righe',
        (s) => XppBackgroundSolidLined(color: Colors.white, size: s),
      ),
      _NoteTemplate(
        'Quadretti',
        (s) => XppBackgroundSolidGraph(color: Colors.white, size: s),
      ),
      _NoteTemplate(
        'Puntini',
        (s) => XppBackgroundSolidDot(color: Colors.white, size: s),
      ),
      _NoteTemplate('Carta di Smith', (s) => XppBackgroundSmith(size: s)),
      _NoteTemplate('Nothing Dark', (s) => XppBackgroundNothingDark(size: s)),
      _NoteTemplate('Nothing Light', (s) => XppBackgroundNothingLight(size: s)),
    ];
    int selectedTemplate = 1; // default: Righe (come prima)
    bool infinite = false;
    String noteTag = selectedTag == 'Tutti' ? 'Appunti' : selectedTag;
    final l10n = context.l10n;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                l10n.newNote,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: l10n.documentTitleLabel,
                          hintText: l10n.documentTitleHint,
                          prefixIcon: const Icon(Icons.edit_note_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      NoteTagPicker(
                        tags: tags.where((tag) => tag != 'Tutti').toList(),
                        value: noteTag,
                        onChanged: (tag) => setDialogState(() => noteTag = tag),
                        onCreate: () async {
                          final tag = await _createTag(context);
                          if (context.mounted && tag != null) {
                            setDialogState(() => noteTag = tag);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.infiniteCanvas),
                        subtitle: Text(l10n.infiniteCanvasSubtitle),
                        value: infinite,
                        onChanged: (value) =>
                            setDialogState(() => infinite = value),
                      ),
                      Text(
                        l10n.pageModelHeader,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Anteprime in miniatura dei modelli: il rendering usa lo
                      // stesso painter delle pagine vere, quindi cio' che vedi
                      // e' cio' che ottieni.
                      SizedBox(
                        height: 118,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: templates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, i) {
                            final bool sel = i == selectedTemplate;
                            final cs = Theme.of(context).colorScheme;
                            return InkWell(
                              onTap: () =>
                                   setDialogState(() => selectedTemplate = i),
                              borderRadius: BorderRadius.circular(10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 66,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: sel
                                            ? cs.primary
                                            : Colors.grey.withOpacity(0.35),
                                        width: sel ? 2.5 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        FittedBox(
                                          fit: BoxFit.cover,
                                          child: SizedBox(
                                            width: 66,
                                            height: 90,
                                            child: templates[i]
                                                .builder(
                                                  XppPageSize(
                                                    width: 66,
                                                    height: 90,
                                                  ),
                                                )
                                                .render(),
                                          ),
                                        ),
                                        if (sel)
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: cs.primary,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.check,
                                                size: 10,
                                                color: cs.onPrimary,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.paperTemplateName(templates[i].name),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: sel
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    l10n.cancel,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    String title = titleController.text.trim();
                    if (title.isEmpty) title = l10n.untitledDocument;

                    Navigator.pop(context);

                    final _NoteTemplate chosen = templates[selectedTemplate];
                    final newFile = XppFile.empty(
                      title: title,
                      tag: noteTag,
                      template: (s) => chosen.builder(s),
                    );
                    newFile.pages!.first.infinite = infinite;
                    setState(() => selectedTag = noteTag);
                    _openFile(newFile);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: Text(l10n.createSheet),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- POPUP DELLE IMPOSTAZIONI (TEMA, ICONE E PENNA) ---
  Future<void> _showSettingsDialog() async {
    // 1. Carichiamo le impostazioni attuali salvate in memoria
    final ThemeController theme = context.read<ThemeController>();
    final prefs = await SharedPreferences.getInstance();
    String buttonDown = prefs.getString('buttonDownAction') ?? 'eraser';
    String buttonUp = prefs.getString('buttonUpAction') ?? 'select';
    var stylusProfile = StylusProfile.fromPreference(
      prefs.getString(StylusProfile.preferenceKey),
    );
    bool touchDrawing = prefs.getBool(PreferencesKeys.kTouchDrawing) ?? false;

    // Colori predefiniti in stile Nothing (accesi su fondo nero).
    final List<Color> colors = [
      ThemeController.kDefaultAccent,
      Colors.red,
      const Color(0xFF00FF00),
      const Color(0xFF00FFFF),
      const Color(0xFFFF00FF),
      Colors.yellowAccent,
      Colors.white,
      Colors.orangeAccent,
    ];

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;
            final l10n = AppLocalizations(theme.locale);
            return AlertDialog(
              backgroundColor: AppAppearance.panel,
              title: Text(
                l10n.settings,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                // Evita errori di overflow se lo schermo è piccolo
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsSection(
                        id: 'appearance',
                        title: l10n.appearance,
                        subtitle: l10n.appearanceSubtitle,
                        icon: Icons.palette_outlined,
                        children: [
                          // Material You: usa i colori dello sfondo di Android.
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.dynamicColors),
                            subtitle: Text(
                              l10n.dynamicColorsSubtitle,
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: theme.useDynamicColor,
                            onChanged: (v) {
                              theme.setDynamicColor(v);
                              setDialogState(() {});
                            },
                          ),
                          // Nero puro: sfondi #000 per schermi OLED.
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.pureBlack),
                            subtitle: Text(
                              l10n.pureBlackSubtitle,
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: theme.pureBlack,
                            onChanged: (v) {
                              theme.setPureBlack(v);
                              setDialogState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          Opacity(
                            opacity: theme.useDynamicColor ? 0.35 : 1,
                            child: IgnorePointer(
                              ignoring: theme.useDynamicColor,
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  // Colori manuali predefiniti
                                  ...colors.map((color) {
                                    final bool sel =
                                        !theme.useDynamicColor &&
                                        theme.accent.value == color.value;
                                    return InkWell(
                                      onTap: () {
                                        theme.setAccent(color);
                                        setDialogState(() {});
                                      },
                                      child: CircleAvatar(
                                        backgroundColor: color,
                                        radius: 22,
                                        child: sel
                                            ? Icon(
                                                Icons.check,
                                                color:
                                                    color.computeLuminance() >
                                                        0.5
                                                    ? Colors.black
                                                    : Colors.white,
                                              )
                                            : null,
                                      ),
                                    );
                                  }).toList(),
                                  // Colore personalizzato: apre la ruota dei colori.
                                  InkWell(
                                    onTap: () async {
                                      Color picked = theme.accent;
                                      final bool? ok = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(
                                            l10n.customColor,
                                          ),
                                          content: SingleChildScrollView(
                                            child: ColorPicker(
                                              pickerColor: picked,
                                              onColorChanged: (c) => picked = c,
                                              enableAlpha: false,
                                              labelTypes: const [],
                                              pickerAreaBorderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: Text(l10n.cancel),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: Text(l10n.apply),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        theme.setAccent(picked);
                                        setDialogState(() {});
                                      }
                                    },
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const SweepGradient(
                                          colors: [
                                            Colors.red,
                                            Colors.orange,
                                            Colors.yellow,
                                            Colors.green,
                                            Colors.cyan,
                                            Colors.blue,
                                            Colors.purple,
                                            Colors.red,
                                          ],
                                        ),
                                        border: Border.all(
                                          color: cs.outline.withOpacity(0.4),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.colorize,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          Text(
                            l10n.iconStyle,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AppIconStyle.values.map((style) {
                              final labels = [
                                l10n.iconStyleLine,
                                l10n.iconStyleRounded,
                                l10n.iconStyleSharp,
                              ];
                              return ChoiceChip(
                                label: Text(labels[style.index]),
                                selected: theme.iconStyle == style,
                                onSelected: (_) {
                                  theme.setIconStyle(style);
                                  setDialogState(() {});
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      SettingsSection(
                        id: 'language',
                        title: l10n.languageSectionTitle,
                        subtitle: l10n.languageSectionSubtitle,
                        icon: Icons.language_outlined,
                        children: [
                          RadioListTile<String>(
                            key: const ValueKey('language-option-en'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.languageEnglish),
                            value: 'en',
                            groupValue: theme.languageCode,
                            onChanged: (v) async {
                              if (v != null) {
                                await theme.setLanguage(v);
                                setDialogState(() {});
                              }
                            },
                          ),
                          RadioListTile<String>(
                            key: const ValueKey('language-option-it'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.languageItalian),
                            value: 'it',
                            groupValue: theme.languageCode,
                            onChanged: (v) async {
                              if (v != null) {
                                await theme.setLanguage(v);
                                setDialogState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                      SettingsSection(
                        id: 'pen',
                        title: l10n.penAndGestures,
                        subtitle: l10n.penAndGesturesSubtitle,
                        icon: Icons.edit_outlined,
                        children: [
                          ListTile(
                            key: const ValueKey('stylus-menu-settings'),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.touch_app_outlined),
                            title: Text(l10n.stylusRadialMenu),
                            subtitle: Text(l10n.stylusRadialMenuSubtitle),
                            onTap: () async {
                              await showStylusMenuSettings(context, theme);
                              if (context.mounted) setDialogState(() {});
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.drawWithFingers),
                            subtitle: Text(l10n.drawWithFingersSubtitle),
                            value: touchDrawing,
                            onChanged: (value) async {
                              await prefs.setBool(
                                PreferencesKeys.kTouchDrawing,
                                value,
                              );
                              if (context.mounted)
                                setDialogState(() => touchDrawing = value);
                            },
                          ),
                          Text(
                            l10n.stylusButtons,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),

                          DropdownButton<StylusProfile>(
                            key: const ValueKey('stylus-profile-setting'),
                            isExpanded: true,
                            value: stylusProfile,
                            items: [
                              DropdownMenuItem(
                                value: StylusProfile.automatic,
                                child: Text(l10n.stylusProfileAuto),
                              ),
                              DropdownMenuItem(
                                value: StylusProfile.singleButton,
                                child: Text(l10n.stylusProfileSingle),
                              ),
                              DropdownMenuItem(
                                value: StylusProfile.twoButtons,
                                child: Text(l10n.stylusProfileTwo),
                              ),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              await prefs.setString(
                                StylusProfile.preferenceKey,
                                value.name,
                              );
                              if (context.mounted)
                                setDialogState(() => stylusProfile = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(
                            stylusProfile == StylusProfile.singleButton
                                ? l10n.stylusSideButton
                                : l10n.stylusButton1,
                            style: const TextStyle(fontSize: 14),
                          ),
                          DropdownButton<String>(
                            isExpanded: true,
                            value: buttonDown,
                            items: [
                              DropdownMenuItem(
                                value: 'eraser',
                                child: Text(l10n.actionEraser),
                              ),
                              DropdownMenuItem(
                                value: 'select',
                                child: Text(l10n.actionLasso),
                              ),
                              DropdownMenuItem(
                                value: 'highlighter',
                                child: Text(l10n.actionHighlighter),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => buttonDown = v);
                                prefs.setString(
                                  'buttonDownAction',
                                  v,
                                ); // Salva in memoria!
                              }
                            },
                          ),

                          if (stylusProfile.supportsSecondaryButton) ...[
                            const SizedBox(height: 16),

                            Text(
                              l10n.stylusButton2,
                              style: const TextStyle(fontSize: 14),
                            ),
                            DropdownButton<String>(
                              isExpanded: true,
                              value: buttonUp,
                              items: [
                                DropdownMenuItem(
                                  value: 'eraser',
                                  child: Text(l10n.actionEraser),
                                ),
                                DropdownMenuItem(
                                  value: 'select',
                                  child: Text(l10n.actionLasso),
                                ),
                                DropdownMenuItem(
                                  value: 'highlighter',
                                  child: Text(l10n.actionHighlighter),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setDialogState(() => buttonUp = v);
                                  prefs.setString(
                                    'buttonUpAction',
                                    v,
                                  ); // Salva in memoria!
                                }
                              },
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            stylusProfile.usesTemporaryButton
                                ? l10n.stylusSingleTip
                                : l10n.stylusTwoTip,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      SettingsSection(
                        id: 'pages',
                        title: l10n.pagesAndNavigation,
                        subtitle: l10n.pagesAndNavigationSubtitle,
                        icon: Icons.description_outlined,
                        children: [
                          SwitchListTile(
                            key: const ValueKey('page-scrollbar-setting'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.pageScrollbar),
                            subtitle: Text(l10n.pageScrollbarSubtitle),
                            value: theme.showPageScrollbar,
                            onChanged: (value) {
                              theme.setPageScrollbar(value);
                              setDialogState(() {});
                            },
                          ),
                          ListTile(
                            key: const ValueKey('page-border-color-setting'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.currentPageBorderColor),
                            trailing: Icon(
                              Icons.circle,
                              color: theme.currentPageBorderColor,
                            ),
                            onTap: () async {
                              Color picked = theme.currentPageBorderColor;
                              final apply = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(l10n.currentPageBorderColor),
                                  content: SingleChildScrollView(
                                    child: ColorPicker(
                                      pickerColor: picked,
                                      onColorChanged: (color) => picked = color,
                                      enableAlpha: false,
                                      labelTypes: const [],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: Text(l10n.cancel),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: Text(l10n.apply),
                                    ),
                                  ],
                                ),
                              );
                              if (apply == true) {
                                await theme.setCurrentPageBorderColor(picked);
                                if (context.mounted) setDialogState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                      if (AppFeatures.manualBackup)
                        SettingsSection(
                          id: 'backup',
                          title: l10n.backupAndRestore,
                          subtitle: l10n.backupAndRestoreSubtitle,
                          icon: Icons.backup_outlined,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.backup_outlined),
                              title: Text(l10n.createBackup),
                              subtitle: Text(l10n.createBackupSubtitle),
                              onTap: () async {
                                Navigator.pop(context);
                                await showNoteBackupDialog(
                                  this.context,
                                  restore: false,
                                );
                                if (mounted) await _loadRecentFiles();
                              },
                            ),
                            ListTile(
                              key: const ValueKey('restore-backup'),
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.restore_outlined),
                              title: Text(l10n.restoreBackup),
                              subtitle: Text(l10n.restoreBackupSubtitle),
                              onTap: () async {
                                Navigator.pop(context);
                                await showNoteBackupDialog(
                                  this.context,
                                  restore: true,
                                );
                                if (mounted) await _loadRecentFiles();
                              },
                            ),
                          ],
                        ),
                      SettingsSection(
                        id: 'about',
                        title: l10n.about,
                        subtitle: l10n.aboutSubtitle,
                        icon: Icons.info_outline,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Image.asset(
                              AppBrand.logo,
                              width: 40,
                              height: 40,
                              cacheWidth: 120,
                            ),
                            title: Text(l10n.aboutTenerumi),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showTenerumiAppInfo(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.close),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Set di icone scelto dall'utente (linea/tonde/nette).
    final AppIcons icons = context.watch<ThemeController>().icons;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final baseFiltered = selectedTag == 'Tutti'
        ? recentFiles
        : recentFiles.where((f) => f['tag'] == selectedTag).toList();
    final query = _searchQuery.trim().toLowerCase();
    final filteredFiles = query.isEmpty
        ? baseFiltered
        : baseFiltered.where((f) {
            final name = (f['name'] as String? ?? '').toLowerCase();
            final tag = (f['tag'] as String? ?? '').toLowerCase();
            return name.contains(query) || tag.contains(query);
          }).toList();

    return Scaffold(
      // --- 1. APPBAR ---
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(AppBrand.logo, width: 32, height: 32, cacheWidth: 96),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                AppBrand.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          if (AppFeatures.plugins)
            if (context.watch<PluginController?>()
                case final PluginController plugins)
              IconButton(
                tooltip: l10n.pluginsTooltip,
                icon: const Icon(Icons.extension_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PluginManagerPage(plugins: plugins),
                  ),
                ),
              ),
          IconButton(
            icon: Icon(_showSearch ? Icons.close : icons.search),
            tooltip: _showSearch ? l10n.close : l10n.searchNotes,
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          // --- COLLEGAMENTO AL TASTO IMPOSTAZIONI ---
          IconButton(
            icon: Icon(icons.settings),
            tooltip: l10n.settings,
            onPressed:
                _showSettingsDialog, // Apre il menu di personalizzazione!
          ),
        ],
      ),

      // --- 2. DRAWER (Il menù laterale) ---
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: AppAppearance.panel,
                border: const Border(
                  bottom: BorderSide(color: AppAppearance.border),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Image.asset(
                    AppBrand.logo,
                    width: 56,
                    height: 56,
                    cacheWidth: 168,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    AppBrand.name,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(icons.info),
              title: Text(l10n.appInfoTitle),
              onTap: () {
                Navigator.pop(context);
                showTenerumiAppInfo(context);
              },
            ),
          ],
        ),
      ),

      // --- 3. BODY (Filtri e Griglia file) ---
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedTag == 'Tutti' ? l10n.allNotes : selectedTag,
                    style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.1,
                        ) ??
                        const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('home-open-file'),
                  onPressed: _openingFile ? null : _openDeviceFile,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(l10n.openFile),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: l10n.searchNotes,
                  prefixIcon: Icon(icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppAppearance.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppAppearance.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.primary),
                  ),
                  filled: true,
                  fillColor: AppAppearance.raised,
                ),
              ),
            ),
          if (CriticalData.warnings.isNotEmpty)
            MaterialBanner(
              content: Text(CriticalData.warnings.join('\n')),
              actions: [
                TextButton(
                  onPressed: () =>
                      setState(() => CriticalData.warnings.clear()),
                  child: Text(l10n.understood),
                ),
              ],
            ),
          // Barra orizzontale dei Tag
          if (audioRecoveries.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.mic),
              title: Text(
                l10n.audioToRecoverTitle(audioRecoveries.length),
              ),
              subtitle: Text(
                l10n.audioToRecoverSubtitle,
              ),
              onTap: () async {
                final entry = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: Text(l10n.recoverAudio),
                    children: [
                      for (final e in audioRecoveries)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, e),
                          child: Text(
                            '${e['count']} segmenti — ${e['noteId']}',
                          ),
                        ),
                    ],
                  ),
                );
                if (entry == null || !mounted) return;
                final file = XppFile.empty(title: l10n.recoveredAudioTitle)
                  ..localId = entry['noteId'] as String;
                _openFile(file);
              },
            ),
          if (recoveryFiles.isNotEmpty)
            SizedBox(
              height: 96,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: recoveryFiles.length,
                itemBuilder: (context, index) {
                  final entry = recoveryFiles[index];
                  return SizedBox(
                    width: 280,
                    child: Card(
                      child: ListTile(
                        leading: SizedBox(
                          width: 42,
                          height: 54,
                          child: DocumentPreviewImage(
                            encoded: entry['preview'] is String
                                ? entry['preview'] as String
                                : null,
                            fallbackIcon: Icons.restore,
                          ),
                        ),
                        title: Text(
                          entry['title'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${l10n.restoreAutoCopySubtitle}\n${documentModifiedLabel(entry['modifiedAt'] ?? (entry['time'] is int ? DateTime.fromMillisecondsSinceEpoch(entry['time'] as int, isUtc: true).toIso8601String() : null))}',
                          style: const TextStyle(fontSize: 11),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          try {
                            final file = await AutosaveStore.restore(entry);
                            if (mounted) _openFile(file);
                          } catch (error) {
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.recoveryFailed(error)),
                                ),
                              );
                          }
                        },
                        trailing: IconButton(
                          tooltip: l10n.deleteRecoveryCopy,
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(l10n.deleteRecoveryCopy),
                                content: Text(
                                  l10n.deleteRecoveryCopyConfirm,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text(l10n.cancel),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(l10n.delete),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await AutosaveStore.remove(
                                entry['key'] as String,
                              );
                              _loadRecentFiles();
                            }
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 6.0,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: tags.map((tag) {
                  final isSelected = tag == selectedTag;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(tag == 'Tutti' ? l10n.defaultTagAll : tag),
                      selected: isSelected,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? cs.onSurface
                            : cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: isSelected
                              ? cs.primary
                              : AppAppearance.border,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      backgroundColor: AppAppearance.panel,
                      selectedColor: AppAppearance.raised,
                      onSelected: (bool selected) {
                        setState(() => selectedTag = tag);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Expanded(
            child: filteredFiles.isEmpty
                ? (recentFiles.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: AppAppearance.raised,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: AppAppearance.border),
                                ),
                                child: Icon(
                                  icons.folder,
                                  size: 40,
                                  color: cs.primary.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                l10n.noDocumentsHere,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.tapPlusToStart,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 56,
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                l10n.noResultsFound,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.noResultsFoundSubtitle(_searchQuery),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                icon: const Icon(Icons.clear, size: 16),
                                label: Text(l10n.clearSearch),
                                style: OutlinedButton.styleFrom(
                                  shape: const StadiumBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1,
                        ),
                    itemCount: filteredFiles.length,
                    itemBuilder: (context, index) {
                      final fileData = filteredFiles[index];
                      return DocumentLibraryCard(
                        key: ValueKey(
                          '${fileData['path'] ?? ''}-${fileData['name'] ?? ''}-$index',
                        ),
                        entry: Map<String, dynamic>.from(fileData),
                        fallbackIcon: icons.file,
                        onLongPress: () => _showNoteActions(
                          Map<String, dynamic>.from(fileData),
                        ),
                        onTagEdit: () =>
                            _editNoteTag(Map<String, dynamic>.from(fileData)),
                        onTap: () async {
                          String? savedPath = fileData['path'];

                          if (savedPath != null && savedPath.isNotEmpty) {
                            if (await FilePickerCross.exists(savedPath)) {
                              try {
                                final fpc =
                                    await FilePickerCross.fromInternalPath(
                                      path: savedPath,
                                    );

                                XppFile loadedFile =
                                    await XppFile.fromFilePickerCross(
                                      fpc,
                                      (progress) {},
                                      (_) async =>
                                          throw Exception('File non trovato'),
                                    );

                                loadedFile.title = fileData['name'];
                                if (fileData['localId'] is String)
                                  loadedFile.localId =
                                      fileData['localId'] as String;
                                loadedFile.tag =
                                    fileData['tag'] as String? ??
                                    loadedFile.tag;
                                _openFile(loadedFile);
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      l10n.fileReadError,
                                    ),
                                  ),
                                );
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.physicalFileNotFound,
                                  ),
                                ),
                              );
                            }
                          } else {
                            final fileToOpen = XppFile.empty()
                              ..title = fileData['name']
                              ..tag = fileData['tag'] as String?;
                            _openFile(fileToOpen);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewNoteDialog,
        icon: Icon(icons.add),
        label: Text(l10n.newNote),
      ),
    );
  }
}

/// Modello di pagina selezionabile nel dialogo "Nuovo Appunto".
class _NoteTemplate {
  final String name;
  final XppBackground Function(XppPageSize size) builder;
  const _NoteTemplate(this.name, this.builder);
}
