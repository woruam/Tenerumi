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
          title: Text('Nuovo Appunto', style: TextStyle(fontWeight: FontWeight.bold)),
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
              child: Text('Annulla', style: TextStyle(color: Colors.grey)),
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
              child: Text('Crea Foglio'),
            ),
          ],
        );
      }
    );
  }

  // --- POPUP DELLE IMPOSTAZIONI (CAMBIO COLORE) ---
  Future<void> _showSettingsDialog() async {
    final List<Color> colors = [
      Colors.indigo, Colors.blue, Colors.teal, Colors.green, 
      Colors.orange, Colors.red, Colors.pink, Colors.purple,
    ];

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Impostazioni App', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Colore del tema:', style: TextStyle(fontSize: 16)),
              SizedBox(height: 16),
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
                      child: Icon(Icons.android, color: Colors.black54),
                    ),
                  ),
                  // Colori manuali
                  ...colors.map((color) {
                    return InkWell(
                      onTap: () {
                        // Cambia colore e disattiva quello dinamico
                        XournalppMobile.of(context).updateThemeColor(color, false);
                        Navigator.pop(context);
                      },
                      child: CircleAvatar(backgroundColor: color, radius: 22),
                    );
                  }).toList(),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Chiudi')),
          ],
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
      appBar: AppBar(
        title: Text('I Miei Appunti', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(icon: Icon(Icons.search), onPressed: () {}),
          // --- ECCO IL COLLEGAMENTO AL TASTO IMPOSTAZIONI ---
          IconButton(
            icon: Icon(Icons.settings), 
            onPressed: _showSettingsDialog, // Apre il menu del colore!
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                      SizedBox(height: 16),
                      Text("Nessun documento qui", style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  )
                )
              : GridView.builder(
              padding: EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6, // <-- NUMERO DI COLONNE (più sono, più le card sono piccole)
                crossAxisSpacing: 10, // Spazio orizzontale tra le card
                mainAxisSpacing: 10,  // Spazio verticale tra le card
                childAspectRatio: 1, // <-- PROPORZIONE: più si avvicina a 1, più la card è quadrata e meno ingombrante in altezza
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
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore nella lettura del file.")));
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Impossibile trovare il file fisico!")));
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
                              : Icon(Icons.insert_drive_file, size: 64, color: Colors.grey),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fileData['name'] ?? 'Senza titolo', 
                                style: TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              SizedBox(height: 4),
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
        icon: Icon(Icons.add),
        label: Text("Nuovo Appunto"),
      ),
    );
  }
}