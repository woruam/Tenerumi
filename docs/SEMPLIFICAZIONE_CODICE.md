# Proposte di semplificazione del codice

Revisione statica del 14 ottobre 2026. **Questo documento contiene proposte: nessuna modifica al codice è stata applicata per questa revisione.** L'obiettivo è ridurre duplicazioni e stato superfluo mantenendo il comportamento attuale, compresi formati salvati, gesti, tempi dei checkpoint, accessibilità e gestione degli errori.

## Perimetro e criteri

Sono stati esaminati i sorgenti dell'app relativi a interfaccia, input, rendering, serializzazione, esportazione e archiviazione, insieme ai test pertinenti. I file generati, la cache delle dipendenze e il codice dei pacchetti vendorizzati non sono obiettivi di questa proposta. I numeri di riga riportati descrivono il checkout esaminato e possono cambiare con interventi successivi.

La ricerca delle referenze identifica gli utilizzi presenti nel repository; non dimostra l'assenza di consumatori esterni di una classe o di un metodo pubblico. Per questo le rimozioni di API pubbliche sono **condizionate**, mentre i dettagli privati senza effetti osservabili sono candidati più semplici. Non vengono stimati risparmi di righe o miglioramenti prestazionali senza misurazione.

Per la sola aggiunta di questo documento basta verificare il diff e i collegamenti. I test indicati sotto sono controlli da effettuare **quando si applicherà una proposta**; questa revisione documentale non richiede di eseguirli tutti.

## Interventi meccanici e rimozioni condizionate

### 1. Eliminare l'override vuoto di `initState`

**Evidenza:** [_InfiniteCanvasState](../lib/widgets/infinite_canvas.dart), riga 37, ridefinisce `initState` soltanto per chiamare `super.initState()`.

**Riscrittura proposta:** rimuovere questo override privato. L'inizializzazione già espressa dai campi rimane invariata e il metodo ereditato viene chiamato normalmente dal framework. Non eliminare `dispose` o `didUpdateWidget`: rilasciano risorse e sostituiscono cache quando cambia il controller.

**Rischio:** basso; confidenza alta. **Verifica:** [palm_toolbar_regression_test.dart](../test/palm_toolbar_regression_test.dart) e [canvas_workspace_test.dart](../test/canvas_workspace_test.dart), con montaggio, cambio controller e smontaggio del canvas infinito.

### 2. Rimuovere il parametro non utilizzato `reference`

**Evidenza:** [CanvasController.insertBlankPage](../lib/controllers/canvas_controller.dart), riga 1669, richiede `reference` ma nel corpo sceglie formato e sfondo da `paper ?? file!.defaultPaper`. I tre chiamanti locali, alle righe 1664, 1732 e 1746, passano espressioni senza effetti collaterali.

**Riscrittura proposta:** rimuovere il parametro e gli argomenti dai chiamanti verificati. Non sostituirlo con la pagina precedente: reintrodurrebbe l'ereditarietà del modello personalizzato che il comportamento attuale evita.

**Rischio:** basso nel codice dell'app, condizionato alla verifica di eventuali chiamanti esterni del metodo pubblico; confidenza alta sull'inutilizzo locale. **Verifica:** [paper_templates_test.dart](../test/paper_templates_test.dart) e [workspace_navigation_test.dart](../test/workspace_navigation_test.dart), comprese posizione, dimensioni, modello originale e generazione automatica.

### 3. Derivare il conteggio dei tocchi dal set degli identificativi

**Evidenza:** [ZoomableWidgetState](../lib/widgets/ZoomableWidget.dart), righe 143, 216–218 e 238–239, conserva `_touchPointers` oltre a `_touchIds.length` e copia il valore in `_touchSession.pointers`.

**Riscrittura proposta:** usare una variabile locale derivata dal set, oppure assegnare direttamente la lunghezza alla sessione. Mantenere `_touchSession.pointers`, il reset della sessione e l'incremento di `cancellationEpoch` quando si raggiungono due tocchi. Ridurre lo stato duplicato non deve cambiare l'ordine delle transizioni.

**Rischio:** basso-medio; confidenza alta sulla duplicazione, da verificare sulla sequenza degli eventi. **Verifica:** [pointer_input_test.dart](../test/pointer_input_test.dart), [palm_toolbar_regression_test.dart](../test/palm_toolbar_regression_test.dart) e [workspace_navigation_test.dart](../test/workspace_navigation_test.dart).

### 4. Togliere i parametri colore privati non letti dai painter della griglia

**Evidenza:** [_LinePainter, _RuledPainter e _GraphPainter](../lib/src/XppBackground.dart), righe 298, 326 e 354, ricevono `color` senza leggerlo nel disegno; le linee usano un grigio fisso. Il colore del foglio viene dipinto separatamente dal contenitore o da `paintPaperBackground`.

**Riscrittura proposta:** eliminare soltanto i campi e i parametri privati inutilizzati, aggiornando le istanze corrispondenti. Non rimuovere il colore dalle classi degli sfondi o dalla serializzazione; non estendere questa rimozione a `_SmithPainter`, che adatta il contrasto al colore della carta. Si può anche rimuovere il commento provvisorio «lascia qui sotto tutti i tuoi Painter» a riga 296.

**Rischio:** basso; confidenza alta. **Verifica:** [paper_templates_test.dart](../test/paper_templates_test.dart) e [document_export_test.dart](../test/document_export_test.dart), confronto dei pixel e riapertura del colore del foglio.

### 5. Valutare il campo di compatibilità `enabled` senza cancellare i rebuild

**Evidenza:** [ZoomableWidgetState.enabled](../lib/widgets/ZoomableWidget.dart), riga 132, viene scritto da [CanvasPage](../lib/pages/CanvasPage.dart) alle righe 274, 500 e 887, ma non è letto nei sorgenti dell'app. Il commento dichiara esplicitamente una finalità di compatibilità. Le assegnazioni sono racchiuse in chiamate a `setState`, che hanno un effetto distinto dalla scrittura del campo.

**Riscrittura proposta:** dopo avere verificato i consumatori della classe pubblica, deprecare o rimuovere il campo e le assegnazioni. Conservare inizialmente i rebuild, oppure dimostrarne la ridondanza verificando che `ctrl.setTool` e la ricostruzione del widget aggiornino già `stylusPanEnabled` e gli altri parametri interessati. Non eliminare automaticamente l'intero callback.

**Rischio:** medio; confidenza alta sull'assenza di letture locali, condizionata sugli effetti dei rebuild e sulle API esterne. **Verifica:** cambio Penna/Mano, zoom e stilo con [palm_toolbar_regression_test.dart](../test/palm_toolbar_regression_test.dart) e [pointer_input_test.dart](../test/pointer_input_test.dart).

### 6. Valutare `XppStrokePainter.isComplete` come API, non come controllo attivo

**Evidenza:** [XppStrokePainter](../lib/layer_contents/XppStroke.dart), righe 437, 454 e 462, dichiara e assegna `isComplete`; la ricerca delle referenze nel codice dell'app e nei test non individua letture.

**Riscrittura proposta:** verificare prima gli utilizzatori del costruttore pubblico; solo successivamente rimuovere o deprecare parametro e campo. Non confonderlo con `_immutableSamples`: quest'ultimo distingue campioni modificabili e geometria consolidata ed è essenziale per la correttezza della cache.

**Rischio:** medio per compatibilità pubblica; confidenza alta sull'inutilizzo locale, non sulla possibilità di rimozione universale. **Verifica:** [saved_document_home_test.dart](../test/saved_document_home_test.dart), [selection_tools_test.dart](../test/selection_tools_test.dart) e i test della geometria in [performance_resources_test.dart](../test/performance_resources_test.dart).

### 7. Inventariare tre helper pubblici senza chiamanti locali

**Evidenza:** [XppFile](../lib/src/XppFile.dart) contiene `openAndEdit` a riga 171, `toFilePickerCross` a riga 985 e `toFilePickerCrossAsync` a riga 1050. La ricerca nei sorgenti dell'app e nei test restituisce le definizioni, senza chiamanti locali.

**Riscrittura proposta:** registrare gli helper come candidati di compatibilità e verificare plugin, integrazioni e distribuzione della libreria prima di una rimozione. Non eliminare `open`, `fromFilePickerCross`, `toUint8ListAsync` o `serializeSnapshotAsync`, che hanno utilizzi effettivi. L'helper `openAndEdit` contiene inoltre navigazione, messaggi ed errori: se esistono consumatori, il suo comportamento non può essere sostituito implicitamente con quello della home.

**Rischio:** medio; confidenza limitata alla ricerca locale. **Verifica futura:** ricerca completa dei chiamanti, analisi statica e [open_file_home_test.dart](../test/open_file_home_test.dart), [document_storage_test.dart](../test/document_storage_test.dart), [document_export_test.dart](../test/document_export_test.dart).

## Deduplicazioni strutturali da applicare separatamente

### 8. Condividere il disegno delle righe, mantenendo due stili XML

**Evidenza:** [_LinePainter e _RuledPainter](../lib/src/XppBackground.dart), righe 298 e 326, implementano attualmente la stessa geometria: righe orizzontali ogni 24 punti, stesso clipping, colore e spessore.

**Riscrittura proposta:** usare un solo painter privato per entrambe le classi di sfondo. Conservare `XppBackgroundSolidLined` e `XppBackgroundSolidRuled` e i rispettivi valori XML `lined` e `ruled`. La voce «Righe con margine» non autorizza ad aggiungere una linea verticale: sarebbe un cambiamento grafico rispetto al codice attuale.

**Rischio:** basso-medio; confidenza alta. **Verifica:** confronto dei pixel prima/dopo per entrambi gli stili e roundtrip XOPP con [paper_templates_test.dart](../test/paper_templates_test.dart) e [document_export_test.dart](../test/document_export_test.dart).

### 9. Usare i descrittori condivisi dei modelli anche nella home

**Evidenza:** [OpenPage._showNewNoteDialog](../lib/pages/OpenPage.dart), riga 286, ricostruisce una lista di `_NoteTemplate`; [PaperTemplate](../lib/src/paper_template.dart) descrive già nomi e costruttori degli stessi modelli.

**Riscrittura proposta:** derivare i descrittori della home da un sottoinsieme esplicito di `PaperTemplate`, evitando la seconda classe di descrizione. Conservare ordine, etichette, modelli disponibili, anteprime e selezione iniziale «Righe». Non usare indiscriminatamente `PaperTemplate.values`: inserirebbe anche «Righe con margine» nella home. Il modello originale deve continuare a essere memorizzato in `defaultPaper`.

**Rischio:** medio per variazioni involontarie dell'interfaccia; confidenza alta sulla duplicazione. **Verifica:** [paper_templates_test.dart](../test/paper_templates_test.dart) e un controllo della creazione dalla home, includendo canvas infinito e riapertura.

### 10. Estrarre la sola lettura del riferimento allo sfondo

**Evidenza:** [CanvasController.hasMissingBackground e associateBackground](../lib/controllers/canvas_controller.dart), righe 626 e 635, ripetono lo switch che restituisce `filename` per sfondi PDF o immagine.

**Riscrittura proposta:** introdurre un piccolo helper puro che restituisca il riferimento o `null`. Mantenere fuori dall'helper il controllo della disponibilità, la scelta del picker, la validazione delle pagine PDF e i controlli di identità dopo gli `await`.

**Rischio:** basso; confidenza alta. **Verifica:** [document_storage_test.dart](../test/document_storage_test.dart), [pdf_selection_test.dart](../test/pdf_selection_test.dart) e [astra_security_fixes_test.dart](../test/astra_security_fixes_test.dart). Un nome XML deve restare una chiave opaca, mai un'autorizzazione ad aprire un percorso.

### 11. Evitare calcoli ripetuti nello stesso passaggio di esportazione

**Evidenza:** [document_export.dart](../lib/src/document_export.dart), righe 235–250, ripete `content.bounds()` e `_vectorFontAsset(content)`; il raster ripete `content.bounds()` intorno a riga 910.

**Riscrittura proposta:** introdurre variabili locali nei punti in cui lo snapshot è dimostrabilmente stabile. Per i rettangoli non anticipare la lettura oltre `await flush()` senza dimostrare l'immutabilità: il codice attuale legge il rettangolo definitivo dopo quell'attesa. Lo stesso vincolo vale nel raster: le due chiamate a `bounds()` sono separate da `await decode(...)`. Riutilizzare il rettangolo per decodifica e composizione è equivalente soltanto su uno snapshot stabile; se il contenuto può mutare, mantenere la lettura della destinazione dopo l'attesa. Conservare validazione, errori, font di fallback e ordine dei contenuti.

**Rischio:** basso per i calcoli puri su snapshot, medio se cambia il momento della lettura; confidenza alta sulla ripetizione. **Verifica:** [document_export_test.dart](../test/document_export_test.dart) e [pdf_selection_test.dart](../test/pdf_selection_test.dart), incluse immagini, crop e contenuti sovrapposti.

### 12. Condividere l'involucro JSON con checksum

**Evidenza:** [critical_backend_io.stageRecovery e stageLibrary](../lib/src/compat/critical_backend_io.dart), righe 136 e 211, ripetono la produzione di byte UTF-8 contenenti `payload` e `sha256`.

**Riscrittura proposta:** estrarre un encoder che riceva la stringa `payload` **già serializzata** e restituisca gli stessi byte. Lasciare nei chiamanti la serializzazione dell'oggetto, la risoluzione della directory e i nomi dei file. In particolare, non spostare `jsonEncode(entry)` attraverso gli `await` esistenti: cambierebbe il momento in cui viene catturato un oggetto potenzialmente mutabile.

**Rischio:** basso-medio; confidenza alta sulla duplicazione. **Verifica:** equivalenza byte per byte, rilevamento di checksum errati e recupero degli indici con [astra_recovery_performance_test.dart](../test/astra_recovery_performance_test.dart) e [astra_security_fixes_test.dart](../test/astra_security_fixes_test.dart).

### 13. Condividere la clonazione di un livello con contratto esplicito

**Evidenza:** [CanvasController.snapshotLayers](../lib/controllers/canvas_controller.dart), riga 1557; [exportPageSnapshot](../lib/src/document_export.dart), riga 35; [captureFlashcardSelection](../lib/widgets/note_flashcards_panel.dart), intorno a riga 55, ripetono la copia di nome, visibilità, blocco e contenuti tramite `cloneContents`.

**Riscrittura proposta:** introdurre un helper che cloni un livello preservando anche le posizioni dei contenuti `null`, secondo il contratto attuale di `cloneContents`. Non sostituire direttamente la copia di [XppFile.snapshot](../lib/src/XppFile.dart), intorno a riga 1025: lì `whereType<XppContent>()` elimina i `null` e il callback PDF viene reso trasferibile all'isolate. Le due politiche devono restare esplicite.

**Rischio:** medio; confidenza alta sulla parte comune. **Verifica:** undo/redo e indipendenza delle modifiche in [selection_tools_test.dart](../test/selection_tools_test.dart), [astra_recovery_performance_test.dart](../test/astra_recovery_performance_test.dart), [study_plugins_test.dart](../test/study_plugins_test.dart) e [document_export_test.dart](../test/document_export_test.dart).

### 14. Condividere il contenuto del pannello Forme, mantenendo il suo contenitore

**Evidenza:** [CanvasPage._openShapeSettings](../lib/pages/CanvasPage.dart), riga 691, e [UnifiedToolbar._openShapeSettings](../lib/widgets/unified_toolbar.dart), riga 233, ripetono elenco delle forme, colori, spessori e collegamenti al controller. I contenitori e le chiavi di ancoraggio sono distinti.

**Riscrittura proposta:** estrarre prima il solo widget del contenuto e, se realmente comune, il descrittore di una forma. Lasciare nei chiamanti apertura, posizionamento, dimensioni, chiusura e aggiornamento del pannello. Non unificare simultaneamente tutte le impostazioni degli strumenti e il sistema dei popup.

**Rischio:** medio; confidenza alta sulla duplicazione del contenuto, da verificare sulle differenze dei contenitori. **Verifica:** [study_plugins_test.dart](../test/study_plugins_test.dart), [document_toolbar_test.dart](../test/document_toolbar_test.dart) e controllo su telefono e pannelli multipli: scegliere una forma non deve modificare colore o larghezza della penna.

### 15. Condividere il ciclo di vita dei documenti PDF aperti per una sola operazione

**Evidenza:** [PdfImage.dart](../lib/src/PdfImage.dart), `pdfPageCount` a riga 64, `pdfImage` a riga 75, `pdfPageSize` a riga 105 e `pdfPageSizes` a riga 122, ripetono `_validatePdfBytes`, apertura tramite `openPdfData` e `try/finally` con chiusura del documento. Ogni funzione possiede il documento soltanto per la propria operazione.

**Riscrittura proposta:** estrarre un helper privato generico, per esempio `withOwnedPdf`, che validi i byte, apra il documento con lo stesso `openPdfData`, attenda il callback dell'operazione e chiuda il documento nel `finally`. Le singole operazioni devono conservare validazione dell'indice e delle dimensioni, limite delle pagine e, quando aprono una pagina, il rispettivo `finally` con `page.close()`. Non cambiare la serializzazione delle aperture, gli errori o il momento della chiusura; un semplice `return callback(doc)` senza attenderlo chiuderebbe la risorsa troppo presto.

**Rischio:** medio per il ciclo di vita asincrono; confidenza alta sulla duplicazione. **Verifica:** [document_export_test.dart](../test/document_export_test.dart), [pdf_selection_test.dart](../test/pdf_selection_test.dart) e [performance_resources_test.dart](../test/performance_resources_test.dart), incluse aperture concorrenti, indice errato, errore del renderer e chiusura sia della pagina sia del documento. Gli handle persistenti della vista e quelli dell'export nel controller hanno ownership differente e restano fuori da questo helper.

## Vincoli da non indebolire per rendere il codice più corto

- **Salvataggio e recupero:** conservare code seriali, lease dei blob, checkpoint locale prima dell'originale, controllo dei conflitti, verifica della scrittura e ACK audio dopo la messa in sicurezza dei dati. [CanvasController._flushAutosave](../lib/controllers/canvas_controller.dart) distingue intenzionalmente salvataggio esplicito e compattazione programmata; la verifica dei puntatori all'ingresso della coda e dopo l'anteprima non è una duplicazione eliminabile.
- **Input:** gli stati di prossimità dello stilo, contatto, puntatori rifiutati, epoch e cancellazione del gesto proteggono casi diversi. Le implementazioni finite e infinite si possono confrontare, ma non fondere soltanto perché presentano condizioni simili. Mantenere sia precisione dello stilo sia recupero di una nuova gesture dopo il contatto.
- **Cache e rendering:** preservare geometria immutabile condivisa, limiti del working set e delle immagini, cache di sfondi, invalidazione per revisione e rilascio delle risorse. Non aumentare la memoria trattenuta o togliere gli yield per nascondere complessità. La codifica dei tratti densi fuori dal thread dell'interfaccia deve continuare a produrre gli stessi byte.
- **Formati:** conservare stili XML distinti, filtro Android compatibile con estensioni MIME sconosciute, riconoscimento PDF dal contenuto, carta predefinita originale e metadati delle note vecchie. Un refactoring non autorizza modifiche a etichette, modelli disponibili, Smith, dimensioni dei quadretti o comportamenti dei pulsanti.

## Ordine suggerito per una futura implementazione

1. Fissare un baseline sul checkout da modificare, identificare consumatori delle API pubbliche e selezionare i test pertinenti. Nessun baseline nuovo è stato eseguito per questo documento.
2. Applicare soltanto la rimozione dell'override vuoto e dei parametri privati inutilizzati; verificare diff e analisi statica.
3. Ridurre il conteggio duplicato dei tocchi e valutare la rimozione di `reference`; eseguire i test dei gesti e delle pagine.
4. Riunire i painter delle righe senza cambiare stili XML o pixel; aggiungere il confronto diretto tra i due sfondi.
5. Estrarre riferimento dello sfondo e involucro con checksum, con controlli di equivalenza e recupero.
6. Introdurre il helper dei livelli e le variabili locali dell'export mantenendo filtri, tempi di lettura e ordine di disegno.
7. Condividere descrittori della home e contenuto del pannello Forme; controllare l'interfaccia nelle due superfici esistenti.
8. Decidere separatamente le API pubbliche candidate (`enabled`, `isComplete`, tre helper di `XppFile`); verificare compatibilità e rebuild prima di rimuoverle.
9. Deduplicare per ultimo il ciclo di vita delle quattro operazioni PDF senza estenderlo agli handle persistenti della vista o dell'export. Rieseguire i controlli funzionali e di recupero interessati; misurare prestazioni soltanto se si intende dichiarare un beneficio prestazionale.

Ogni passo va sottoposto a review con un diff circoscritto. Quando il contratto di un componente non è sufficientemente chiaro, mantenere il codice esistente e documentare la differenza prima di deduplicarlo.
