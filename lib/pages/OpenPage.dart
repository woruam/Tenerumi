import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

// Importante: serve per chiamare la funzione di cambio colore che abbiamo messo nel main
import 'package:xournalpp/main.dart'; 

class OpenPage extends StatefulWidget {
  @override
  _OpenPageState createState() => _OpenPageState();
}

class _OpenPageState extends State<OpenPage> {
  List<dynamic> recentFiles = [];
  
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
    setState(() {
      recentFiles = jsonDecode(jsonData);
      for(var file in recentFiles) {
        if(file['tag'] == null) file['tag'] = 'Appunti';
      }
    });
  }

  void _openFile(XppFile file) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => WorkspacePage(initialFile: file)),
    ).then((_) => _loadRecentFiles()); 
  }

  // --- FINESTRA DI DIALOGO PER CREARE LA NOTA ---
  Future<void> _showNewNoteDialog() async {
    TextEditingController titleController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nuovo Appunto', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Titolo del documento',
                  hintText: 'Es. Lezione di Matematica',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                String title = titleController.text.trim();
                if (title.isEmpty) title = "Senza Titolo";
                
                Navigator.pop(context); 
                
                final newFile = XppFile.empty()..title = title;
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
      }
    );
  }

  // --- POPUP DELLE IMPOSTAZIONI (TEMA E PENNA) ---
  Future<void> _showSettingsDialog() async {
    // 1. Carichiamo le impostazioni attuali salvate in memoria
    final prefs = await SharedPreferences.getInstance();
    String buttonDown = prefs.getString('buttonDownAction') ?? 'eraser';
    String buttonUp = prefs.getString('buttonUpAction') ?? 'select';

    final List<Color> colors = [
      Colors.indigo, Colors.blue, Colors.teal, Colors.green, 
      Colors.orange, Colors.red, Colors.pink, Colors.purple,
    ];

    await showDialog(
      context: context,
      builder: (context) {
        // Usiamo StatefulBuilder per far aggiornare a schermo i Dropdown quando li cambiamo
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView( // Evita errori di overflow se lo schermo è piccolo
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==========================================
                    // SEZIONE TEMA
                    // ==========================================
                    const Text('TEMA', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        // Tasto per il colore Dinamico di Android (Material You)
                        InkWell(
                          onTap: () {
                            XournalppMobile.of(context).updateThemeColor(Colors.indigo, true);
                            Navigator.pop(context);
                          },
                          child: CircleAvatar(
                            backgroundColor: Colors.grey.shade300,
                            radius: 22,
                            child: const Icon(Icons.android, color: Colors.black54),
                          ),
                        ),
                        // Colori manuali
                        ...colors.map((color) {
                          return InkWell(
                            onTap: () {
                              XournalppMobile.of(context).updateThemeColor(color, false);
                              Navigator.pop(context);
                            },
                            child: CircleAvatar(backgroundColor: color, radius: 22),
                          );
                        }).toList(),
                      ],
                    ),
                    
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Divider(),
                    ),

                    // ==========================================
                    // SEZIONE PENNA
                    // ==========================================
                    const Text('PENNA (Tasti Fisici)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 12),
                    
                    const Text('Tasto 1 (Vicino alla punta)', style: TextStyle(fontSize: 14)),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: buttonDown,
                      items: const [
                        DropdownMenuItem(value: 'eraser', child: Text('Gomma')),
                        DropdownMenuItem(value: 'select', child: Text('Lazo')),
                        DropdownMenuItem(value: 'highlighter', child: Text('Evidenziatore')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => buttonDown = v);
                          prefs.setString('buttonDownAction', v); // Salva in memoria!
                        }
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    const Text('Tasto 2 (Superiore)', style: TextStyle(fontSize: 14)),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: buttonUp,
                      items: const [
                        DropdownMenuItem(value: 'eraser', child: Text('Gomma')),
                        DropdownMenuItem(value: 'select', child: Text('Lazo')),
                        DropdownMenuItem(value: 'highlighter', child: Text('Evidenziatore')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => buttonUp = v);
                          prefs.setString('buttonUpAction', v); // Salva in memoria!
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi')),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredFiles = selectedTag == 'Tutti' 
        ? recentFiles 
        : recentFiles.where((f) => f['tag'] == selectedTag).toList();

    return Scaffold(
      // --- 1. APPBAR ---
      appBar: AppBar(
        title: const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          // --- COLLEGAMENTO AL TASTO IMPOSTAZIONI ---
          IconButton(
            icon: const Icon(Icons.settings), 
            onPressed: _showSettingsDialog, // Apre il menu del colore!
          ),
        ],
      ),
      
      // --- 2. DRAWER (Il menù laterale) ---
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.book, size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  const Text('Xournal Flutter', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                      Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text("Nessun documento qui", style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  )
                )
              : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6, // NUMERO DI COLONNE
                crossAxisSpacing: 10, 
                mainAxisSpacing: 10,  
                childAspectRatio: 1, 
              ),
              itemCount: filteredFiles.length,
              itemBuilder: (context, index) {
                final fileData = filteredFiles[index];
                return Card(
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () async {
                      String? savedPath = fileData['path'];
                      
                      if (savedPath != null && savedPath.isNotEmpty) {
                        File localFile = File(savedPath);
                        
                        if (await localFile.exists()) {
                          try {
                            final bytes = await localFile.readAsBytes();
                            FilePickerCross fpc = FilePickerCross(bytes, path: savedPath);
                            
                            XppFile loadedFile = await XppFile.fromFilePickerCross(
                              fpc, 
                              (progress) {}, 
                              (_) async => throw Exception('File non trovato') 
                            );
                            
                            loadedFile.title = fileData['name']; 
                            _openFile(loadedFile);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Errore nella lettura del file.")));
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossibile trovare il file fisico!")));
                        }
                      } else {
                        final fileToOpen = XppFile.empty()..title = fileData['name'];
                        _openFile(fileToOpen);
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            color: Colors.grey.shade200,
                            child: fileData['preview'] != null && fileData['preview'].toString().isNotEmpty
                              ? Image.memory(base64Decode(fileData['preview']), fit: BoxFit.cover)
                              : const Icon(Icons.insert_drive_file, size: 64, color: Colors.grey),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fileData['name'] ?? 'Senza titolo', 
                                style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(fileData['tag'] ?? 'Appunti', 
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        )
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
        icon: const Icon(Icons.add),
        label: const Text("Nuovo Appunto"),
      ),
    );
  }
}