import 'package:flutter/material.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';

class WorkspacePage extends StatefulWidget {
  final XppFile? initialFile;
  
  WorkspacePage({this.initialFile}); 

  @override
  _WorkspacePageState createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> with TickerProviderStateMixin {
  List<XppFile> openDocuments = [];
  late TabController _tabController;

  Map<XppFile, GlobalKey<CanvasPageState>> canvasKeys = {};

  @override
  void initState() {
    super.initState();
    final startFile = widget.initialFile ?? (XppFile.empty()..title = "Nuovo Documento 1");
    openDocuments.add(startFile);
    canvasKeys[startFile] = GlobalKey<CanvasPageState>(); 
    
    _initTabController();
  }

  void _initTabController() {
    _tabController = TabController(length: openDocuments.length, vsync: this);
  }

  void _addNewDocument() {
    setState(() {
      final newFile = XppFile.empty()..title = "Nuovo Documento ${openDocuments.length + 1}";
      openDocuments.add(newFile);
      canvasKeys[newFile] = GlobalKey<CanvasPageState>(); 
      
      _tabController.dispose();
      _initTabController();
      _tabController.animateTo(openDocuments.length - 1);
    });
  }

  Future<void> _closeDocument(int index) async {
    final fileToClose = openDocuments[index];
    final key = canvasKeys[fileToClose];

    final canClose = await key?.currentState?.promptSaveIfUnsaved() ?? true;

    if (canClose) {
      if (openDocuments.length <= 1) {
        Navigator.of(context).pop(); 
        return; 
      }
      setState(() {
        openDocuments.removeAt(index);
        canvasKeys.remove(fileToClose); 
        
        _tabController.dispose();
        _initTabController();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: 0, 
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(50),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back), 
                onPressed: () async {
                  final currentFile = openDocuments[_tabController.index];
                  final key = canvasKeys[currentFile];
                  final canClose = await key?.currentState?.promptSaveIfUnsaved() ?? true;
                  if (canClose) Navigator.of(context).pop();
                }
              ),
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  
                  // Mantiene spenti i fastidiosi "lampi" grigi di quando clicchi
                  overlayColor: MaterialStateProperty.all(Colors.transparent),
                  splashFactory: NoSplash.splashFactory,
                  
                  // --- IL NUOVO CONTRASTO VISIVO ---
                  // 1. Uno sfondo morbido e arrotondato SOLO per la scheda attiva
                  indicator: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.9),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ), 
                  
                  // 2. Scheda ATTIVA: Testo pieno e in grassetto
                  labelColor: Theme.of(context).colorScheme.onSurface, 
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  
                  // 3. Schede INATTIVE: Testo sbiadito e font normale
                  unselectedLabelColor: Colors.grey.withOpacity(0.45),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
                  // ---------------------------------

                  tabs: List.generate(openDocuments.length, (index) {
				// ... [IL RESTO RIMANE UGUALE] ...
                    return Tab(
                      child: Container(
                        width: 150, // Larghezza fissa: tutte le schede saranno identiche!
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween, // Distanzia il testo dalla X
                          children: [
                            Expanded(
                              child: Text(
                                openDocuments[index].title ?? "Documento",
                                overflow: TextOverflow.ellipsis, // Aggiunge "..." se il titolo è troppo lungo
                                maxLines: 1, // Forza il testo su una sola riga
                              ),
                            ),
                            SizedBox(width: 8),
                            InkWell(
                              onTap: () => _closeDocument(index), 
                              borderRadius: BorderRadius.circular(50),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0), // Rende la "X" più facile da tappare col dito
                                child: Icon(Icons.close, size: 16),
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  }),
                  // --- FINE DEL FIX DELLE SCHEDE ---
                ),
              ),
              IconButton(icon: Icon(Icons.add), onPressed: _addNewDocument),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: NeverScrollableScrollPhysics(),
        children: openDocuments.map((file) {
          canvasKeys.putIfAbsent(file, () => GlobalKey<CanvasPageState>()); 
          return CanvasPage(
            key: canvasKeys[file], 
            file: file
          );
        }).toList(),
      ),
    );
  }
}