import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
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
import 'package:xournalpp/plugins/plugin_manager_page.dart';
import 'package:xournalpp/src/autosave_store.dart';

class OpenPage extends StatefulWidget {
  @override
  _OpenPageState createState() => _OpenPageState();
}

class _OpenPageState extends State<OpenPage> {
  List<dynamic> recentFiles = [];
  List<Map<String, dynamic>> recoveryFiles = [];

  List<String> tags = ['Tutti', 'Appunti', 'Scuola', 'Lavoro'];
  String selectedTag = 'Tutti';

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
  }

  void _loadRecentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]';
    final recoveries = await AutosaveStore.list();
    if (!mounted) return;
    setState(() {
      recoveryFiles = recoveries;
      recentFiles = jsonDecode(jsonData);
      for (var file in recentFiles) {
        if (file['tag'] == null) file['tag'] = 'Appunti';
      }
    });
  }

  void _openFile(XppFile file) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => WorkspacePage(initialFile: file)),
    ).then((_) => _loadRecentFiles());
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
      _NoteTemplate('Nothing Dark', (s) => XppBackgroundNothingDark(size: s)),
      _NoteTemplate('Nothing Light', (s) => XppBackgroundNothingLight(size: s)),
    ];
    int selectedTemplate = 1; // default: Righe (come prima)
    bool infinite = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Nuovo Appunto',
                style: TextStyle(fontWeight: FontWeight.bold),
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
                          labelText: 'Titolo del documento',
                          hintText: 'Es. Lezione di Matematica',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Canvas infinito'),
                        subtitle: const Text(
                          'Scrivi e spostati liberamente in tutte le direzioni',
                        ),
                        value: infinite,
                        onChanged: (value) =>
                            setDialogState(() => infinite = value),
                      ),
                      const Text(
                        'MODELLO PAGINA',
                        style: TextStyle(
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
                                    width: 64,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: sel
                                            ? cs.primary
                                            : Colors.grey.withOpacity(0.35),
                                        width: sel ? 2.5 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: 64,
                                        height: 88,
                                        child: templates[i]
                                            .builder(
                                              XppPageSize(
                                                width: 64,
                                                height: 88,
                                              ),
                                            )
                                            .render(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    templates[i].name,
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
                  child: const Text(
                    'Annulla',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    String title = titleController.text.trim();
                    if (title.isEmpty) title = "Senza Titolo";

                    Navigator.pop(context);

                    final _NoteTemplate chosen = templates[selectedTemplate];
                    final newFile = XppFile.empty(
                      title: title,
                      template: (s) => chosen.builder(s),
                    );
                    newFile.pages!.first.infinite = infinite;
                    _openFile(newFile);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: const Text('Crea Foglio'),
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
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AlertDialog(
                backgroundColor: const Color(0xFF151515).withOpacity(0.6),
                title: const Text(
                  'Settings',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                content: SingleChildScrollView(
                  // Evita errori di overflow se lo schermo è piccolo
                  child: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Disegna con le dita'),
                          subtitle: const Text(
                            'Un dito disegna; due dita spostano e ingrandiscono. Disattiva per ignorare il palmo.',
                          ),
                          value: touchDrawing,
                          onChanged: (value) async {
                            await prefs.setBool(
                              PreferencesKeys.kTouchDrawing,
                              value,
                            );
                            setDialogState(() => touchDrawing = value);
                          },
                        ),
                        // ==========================================
                        // SEZIONE TEMA
                        // ==========================================
                        const Text(
                          'TEMA',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Material You: usa i colori dello sfondo di Android.
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Colori dinamici (Material You)'),
                          subtitle: const Text(
                            'Segue lo sfondo del telefono',
                            style: TextStyle(fontSize: 12),
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
                          title: const Text('Nero puro (OLED)'),
                          subtitle: const Text(
                            'Sfondi completamente neri',
                            style: TextStyle(fontSize: 12),
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
                                                  color.computeLuminance() > 0.5
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
                                        title: const Text(
                                          'Colore personalizzato',
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
                                            child: const Text('Annulla'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Applica'),
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

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Divider(),
                        ),

                        // ==========================================
                        // SEZIONE ICONE
                        // ==========================================
                        const Text(
                          'STILE ICONE',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<AppIconStyle>(
                          segments: const [
                            ButtonSegment(
                              value: AppIconStyle.outlined,
                              label: Text('Linea'),
                              icon: Icon(Icons.edit_outlined),
                            ),
                            ButtonSegment(
                              value: AppIconStyle.rounded,
                              label: Text('Tonde'),
                              icon: Icon(Icons.edit_rounded),
                            ),
                            ButtonSegment(
                              value: AppIconStyle.sharp,
                              label: Text('Nette'),
                              icon: Icon(Icons.edit_sharp),
                            ),
                          ],
                          selected: {theme.iconStyle},
                          onSelectionChanged: (sel) {
                            theme.setIconStyle(sel.first);
                            setDialogState(() {});
                          },
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Divider(),
                        ),

                        // ==========================================
                        // SEZIONE PENNA
                        // ==========================================
                        const Text(
                          'PENNA (Tasti Fisici)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),

                        const Text(
                          'Tasto 1 (Vicino alla punta)',
                          style: TextStyle(fontSize: 14),
                        ),
                        DropdownButton<String>(
                          isExpanded: true,
                          value: buttonDown,
                          items: const [
                            DropdownMenuItem(
                              value: 'eraser',
                              child: Text('Gomma'),
                            ),
                            DropdownMenuItem(
                              value: 'select',
                              child: Text('Lazo'),
                            ),
                            DropdownMenuItem(
                              value: 'highlighter',
                              child: Text('Evidenziatore'),
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

                        const SizedBox(height: 16),

                        const Text(
                          'Tasto 2 (Superiore)',
                          style: TextStyle(fontSize: 14),
                        ),
                        DropdownButton<String>(
                          isExpanded: true,
                          value: buttonUp,
                          items: const [
                            DropdownMenuItem(
                              value: 'eraser',
                              child: Text('Gomma'),
                            ),
                            DropdownMenuItem(
                              value: 'select',
                              child: Text('Lazo'),
                            ),
                            DropdownMenuItem(
                              value: 'highlighter',
                              child: Text('Evidenziatore'),
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
                        const SizedBox(height: 8),
                        Text(
                          'Suggerimento: tieni premuto il tasto mentre scrivi per usare '
                          'l\'azione solo in quel tratto, oppure premilo mentre la penna '
                          'e\' sollevata (in hover) per attivare/disattivare l\'azione, '
                          'come su Samsung Notes.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Chiudi'),
                  ),
                ],
              ),
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
    final filteredFiles = selectedTag == 'Tutti'
        ? recentFiles
        : recentFiles.where((f) => f['tag'] == selectedTag).toList();

    return Scaffold(
      // --- 1. APPBAR ---
      appBar: AppBar(
        title: const Text(
          'Notes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: [
          if (context.watch<PluginController?>()
              case final PluginController plugins)
            IconButton(
              tooltip: 'Plugin',
              icon: const Icon(Icons.extension_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PluginManagerPage(plugins: plugins),
                ),
              ),
            ),
          IconButton(icon: Icon(icons.search), onPressed: () {}),
          // --- COLLEGAMENTO AL TASTO IMPOSTAZIONI ---
          IconButton(
            icon: Icon(icons.settings),
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
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.book,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Xournal Flutter',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(icons.info),
              title: const Text('Info App'),
              onTap: () {
                // Azione a tua scelta
              },
            ),
          ],
        ),
      ),

      // --- 3. BODY (Filtri e Griglia file) ---
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra orizzontale dei Tag
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
                        leading: const Icon(Icons.restore),
                        title: Text(entry['title'] as String),
                        subtitle: const Text('Ripristina copia automatica'),
                        onTap: () async {
                          try {
                            final file = await AutosaveStore.restore(entry);
                            if (mounted) _openFile(file);
                          } catch (error) {
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Recupero fallito: $error'),
                                ),
                              );
                          }
                        },
                        trailing: IconButton(
                          tooltip: 'Elimina copia di recupero',
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Elimina copia di recupero'),
                                content: const Text(
                                  'Questa copia automatica verrà eliminata.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Annulla'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Elimina'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await AutosaveStore.remove(entry['id'] as String);
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
              vertical: 8.0,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: tags.map((tag) {
                  final isSelected = tag == selectedTag;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(tag),
                      selected: isSelected,
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
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icons.folder,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Nessun documento qui",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
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
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        color: Colors.transparent,
                        shape: ContinuousRectangleBorder(
                          borderRadius: BorderRadius.circular(40),
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: InkWell(
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
                                  _openFile(loadedFile);
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Errore nella lettura del file.",
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Impossibile trovare il file fisico!",
                                    ),
                                  ),
                                );
                              }
                            } else {
                              final fileToOpen = XppFile.empty()
                                ..title = fileData['name'];
                              _openFile(fileToOpen);
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Container(
                                  color: Colors.white.withOpacity(0.05),
                                  child:
                                      fileData['preview'] != null &&
                                          fileData['preview']
                                              .toString()
                                              .isNotEmpty
                                      ? Image.memory(
                                          base64Decode(fileData['preview']),
                                          fit: BoxFit.cover,
                                        )
                                      : Icon(
                                          icons.file,
                                          size: 64,
                                          color: Colors.white.withOpacity(0.2),
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileData['name'] ?? 'Senza titolo',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      fileData['tag'] ?? 'Appunti',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewNoteDialog,
        icon: Icon(icons.add),
        label: const Text("Nuovo Appunto"),
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
