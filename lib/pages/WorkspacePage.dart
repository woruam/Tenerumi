import 'package:flutter/material.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';

class WorkspacePage extends StatefulWidget {
  final XppFile? initialFile;
  
  WorkspacePage({this.initialFile}); // Costruttore aggiornato

  @override
  _WorkspacePageState createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> with TickerProviderStateMixin {
  List<XppFile> openDocuments = [];
  late TabController _tabController;

  // AGGIUNTA: Registro per mantenere il riferimento univoco ad ogni CanvasPage aperta
  Map<XppFile, GlobalKey<CanvasPageState>> canvasKeys = {};

  @override
  void initState() {
    super.initState();
    // Se ci passano un file dalla Home lo apriamo, altrimenti foglio bianco
    final startFile = widget.initialFile ?? (XppFile.empty()..title = "Nuovo Documento 1");
    openDocuments.add(startFile);
    canvasKeys[startFile] = GlobalKey<CanvasPageState>(); // Inizializza la chiave del primo file
    
    _initTabController();
  }

  void _initTabController() {
    _tabController = TabController(length: openDocuments.length, vsync: this);
  }

  void _addNewDocument() {
    setState(() {
      final newFile = XppFile.empty()..title = "Nuovo Documento ${openDocuments.length + 1}";
      openDocuments.add(newFile);
      canvasKeys[newFile] = GlobalKey<CanvasPageState>(); // Crea una nuova chiave
      
      _tabController.dispose();
      _initTabController();
      _tabController.animateTo(openDocuments.length - 1);
    });
  }

  // AGGIUNTA: Resa asincrona per aspettare la scelta dell'utente
  Future<void> _closeDocument(int index) async {
    final fileToClose = openDocuments[index];
    final key = canvasKeys[fileToClose];

    // Chiede alla CanvasPage specifica se ci sono modifiche da salvare
    // Se la chiave è nulla, assume 'true' e procede alla chiusura.
    final canClose = await key?.currentState?.promptSaveIfUnsaved() ?? true;

    if (canClose) {
      if (openDocuments.length <= 1) {
        Navigator.of(context).pop(); // Se chiudiamo l'ultimo, torniamo alla Home
        return; 
      }
      setState(() {
        openDocuments.removeAt(index);
        canvasKeys.remove(fileToClose); // Pulisce la chiave dalla memoria
        
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
              // Pulsante per tornare indietro alla Home (anche lui aspetta il salvataggio se necessario)
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
                  indicator: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  tabs: List.generate(openDocuments.length, (index) {
                    return Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(openDocuments[index].title ?? "Documento"),
                          SizedBox(width: 8),
                          InkWell(
                            onTap: () => _closeDocument(index), // Ora _closeDocument gestisce l'attesa
                            borderRadius: BorderRadius.circular(50),
                            child: Icon(Icons.close, size: 16),
                          )
                        ],
                      ),
                    );
                  }),
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
        // AGGIUNTA: Colleghiamo ogni file alla sua specifica chiave
        children: openDocuments.map((file) {
          canvasKeys.putIfAbsent(file, () => GlobalKey<CanvasPageState>()); // Sicurezza extra
          return CanvasPage(
            key: canvasKeys[file], // Passiamo il telecomando!
            file: file
          );
        }).toList(),
      ),
    );
  }
}