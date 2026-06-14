import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

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
          IconButton(icon: Icon(Icons.settings), onPressed: () {}),
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
                crossAxisCount: 2, 
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75, 
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
                      // --- LA NUOVA LOGICA DI CARICAMENTO ---
                      String? savedPath = fileData['path'];
                      
                      if (savedPath != null && savedPath.isNotEmpty) {
                        File localFile = File(savedPath);
                        
                        if (await localFile.exists()) {
                          try {
                            final bytes = await localFile.readAsBytes();
                            FilePickerCross fpc = FilePickerCross(bytes, path: savedPath);
                            XppFile loadedFile = await XppFile.fromFilePickerCross(
							  fpc, 
							  (progress) {}, // Lasciamo vuota la barra di caricamento per ora
							  (_) async => throw Exception('File non trovato') // Gestiamo un eventuale file PDF mancante
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
                        // Fallback di sicurezza se la path non esiste
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