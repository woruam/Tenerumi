# Analisi di provenienza e opportunità di ottimizzazione di OSI

Data: 8 ottobre 2026. Analisi statica del codice, senza modifiche al funzionamento dell’app.

## Risultato principale

OSI deriva chiaramente dalla base di **Xournal++ Mobile**, ma oggi contiene una notevole estensione e riscrittura. Escludendo i file generati delle traduzioni, **29 degli 85 file Dart hanno lo stesso percorso di un file upstream**: 2 sono testualmente identici, 1 conserva esattamente gli stessi token, 26 sono modificati. Gli altri 56 file non hanno un corrispondente nello stesso percorso upstream.

Il **7,44% dei token Dart non generati** ricade in sequenze di almeno 20 token consecutivi presenti anche nell’upstream: **8.007 su 107.640**. È una misura riproducibile di somiglianza lessicale, **non una percentuale certa di paternità o derivazione**. Una riscrittura può mantenere architettura e idee senza conservare il testo; viceversa, costrutti standard Flutter possono coincidere. Non è quindi corretto concludere che il restante 92,56% sia interamente originale.

Le ottimizzazioni più prudenti sono la riduzione delle scansioni ripetute della geometria, invalidazioni delle miniature limitate alla pagina modificata e pulizia dei componenti legacy. Undo, cache dei tratti e serializzazione degli allegati offrono margini maggiori, ma richiedono prove specifiche prima di intervenire. Nessuna proposta è presentata come miglioramento di FPS già misurato.

## 1. Riferimenti e metodo

- Snapshot OSI analizzato: `1d1baa784182e6f3657b9cb33b244f9708811bed`, branch `main`.
- Primo commit della cronologia locale: `ae59dd05c3b4a3f771030d43eeff5ad8c911b467`, 14 giugno 2026. La cronologia locale contiene 42 commit e parte già da una copia modificata: manca la genealogia Git completa dell’upstream.
- Upstream effettivamente scaricato e confrontato: [Xournal++ Mobile su GitLab, commit ce62f95](https://gitlab.com/TheOneWithTheBraid/xournalpp_mobile/-/tree/ce62f95f13717ca636d3cec8c2f4212bdd3ef5b9), del 30 gennaio 2022, messaggio “Updated dependencies”.
- Il [mirror GitHub indicato nel README](https://github.com/xournalpp/xournalpp_mobile/) ha restituito 404 sia nella consultazione web sia nel tentativo di clone. Il confronto numerico usa il repository GitLab, non risultati memorizzati dal motore di ricerca.

Lo script [audit_upstream.py](../scripts/audit_upstream.py) legge i file dai commit Git, evitando di includere file di build o modifiche locali non salvate. Confronta:

1. Uguaglianza del testo completo allo stesso percorso.
2. Uguaglianza dei token ignorando commenti e spazi: distingue riformattazione da modifica del testo del programma.
3. Token allineati allo stesso percorso, usando `SequenceMatcher` senza esclusione automatica dei token frequenti.
4. Copertura di sequenze esatte di 20 token cercate in **tutti** i file upstream del medesimo ambito, per individuare anche frammenti trasferiti fra file. Ogni token locale è contato una sola volta.

La tokenizzazione è lessicale e basata su espressioni regolari, non su un AST Dart. Include nomi, stringhe, numeri e punteggiatura; ignora i commenti. L’allineamento allo stesso percorso può accostare anche frammenti molto brevi e punteggiatura: è una metrica diagnostica, meno significativa dei blocchi consecutivi. Il confronto non ricostruisce la storia di rinomini e non dimostra indipendenza progettuale.

Sono esclusi test, documentazione, font, immagini, dipendenze scaricate e cartelle di build. I file Dart generati sono mostrati separatamente. Il secondo ambito aggiunge solamente Kotlin/Java sotto `android/app/src/main/`; non rappresenta tutti i file di configurazione o ogni piattaforma Flutter.

## 2. Quanto codice coincide con la base upstream

| Ambito | File OSI / upstream | Righe non vuote OSI | Token OSI | Token in blocchi condivisi ≥20 | Copertura |
|---|---:|---:|---:|---:|---:|
| Dart applicativo, senza `lib/generated/` | 85 / 30 | 17.798 | 107.640 | 8.007 | **7,44%** |
| Dart completo, incluse traduzioni generate | 90 / 35 | 19.059 | 112.817 | 13.184 | 11,69% |
| Dart non generato + Kotlin/Java Android | 91 / 31 | 18.289 | 111.729 | 8.007 | 7,17% |
| Dart completo + Kotlin/Java Android | 96 / 36 | 19.550 | 116.906 | 13.184 | 11,28% |

“Righe non vuote” comprende i commenti: non è un conteggio di istruzioni. I token sono unità lessicali, non righe di codice.

### File Dart non generati

| Stato | Numero | Quota dei file |
|---|---:|---:|
| Testo identico allo stesso percorso | 2 | 2,35% |
| Token identici, con differenze nei commenti/spazi | 1 | 1,18% |
| Stesso percorso, contenuto modificato | 26 | 30,59% |
| Nessun file upstream nello stesso percorso | 56 | 65,88% |

I due file identici sono `lib/src/XppPageContentWidget.dart` e `lib/widgets/ContextualBottomSheet.dart`; il terzo è `lib/main_desktop.dart`. Quest’ultimo contiene soltanto 17 token: è equivalente ma troppo breve per la metrica dei blocchi di 20 token.

Cinque file di traduzioni generate conservano gli stessi token dell’upstream. Contribuiscono 5.177 dei 13.184 token condivisi dell’ambito Dart completo, circa il **39,27%**. Includerli senza evidenziarlo gonfierebbe la percezione del riuso del codice applicativo.

L’allineamento dei token allo stesso percorso trova invece 12.467 token su 107.640 (**11,58%**) nel Dart non generato. Questo valore e il 7,44% non sono estremi di un intervallo di confidenza: misurano criteri diversi.

### Evoluzione dalla prima copia locale

Nel primo commit locale erano presenti 41 file Dart, 5.620 righe non vuote e 33.286 token. Con la stessa metrica, incluse le traduzioni generate, 18.388 token (**55,24%**) ricadevano in blocchi upstream condivisi. Oggi i file sono 90 e la copertura è 11,69%. Questo documenta una forte crescita e modifica della base locale; non consente di attribuire individualmente ogni nuovo frammento.

### Parti riconoscibilmente ereditate

Modello XOPP (`XppFile`, pagine, livelli e contenuti), serializzazione XML, adattatori di apertura, parte dei menu strumenti e traduzioni conservano elementi della base Mobile. L’organizzazione `layer_contents/`, i nomi `Xpp*` e il namespace `package:xournalpp` sono coerenti con questa origine, ma da soli non misurano la quantità di codice copiato.

Esempi di copertura lessicale per file: `ToolBoxBottomSheet.dart` 990/1.022 token; `XppPagesListView.dart` 785/800; `XppBackground.dart` 1.021/2.467; `XppFile.dart` 1.420/3.465; `XppStroke.dart` 816/5.031. I primi due sono componenti legacy: una forte somiglianza non implica che siano attualmente utilizzati nell’interfaccia.

Controllers, workspace/sessione, audio sincronizzato, plugin, geometria incrementale, navigatore attuale, cache e nuovo export PDF hanno soprattutto percorsi assenti nell’upstream. “Assente nello stesso percorso” significa aggiunta o ricollocazione rispetto allo snapshot confrontato, non prova di originalità assoluta. L’UI di `CanvasPage` e `OpenPage` è ampiamente modificata pur mantenendo i nomi dei file upstream.

Il file `LICENSE` conserva il testo EUPL 1.2 dell’upstream, verificato ignorando le differenze di fine riga. Questo rapporto non svolge una valutazione legale della licenza.

## 3. Opportunità di ottimizzazione verificate nel codice

### A. Geometria dei tratti: ridurre le scansioni — priorità alta, rischio contenuto

Riferimenti: [XppStroke.dart:122](../lib/layer_contents/XppStroke.dart#L122), `bottomRight` a riga 135, `bounds()` a riga 334; [XppPageStack.dart:169](../lib/widgets/XppPageStack.dart#L169).

`getOffset()` esegue due scansioni dei punti per i minimi; `bottomRight` ne esegue altre due. Nei tratti non curvi, `bounds()` aggiunge la scansione del raggio massimo: fino a cinque passaggi sulla stessa lista. Il master painter richiede inoltre l’offset quando deve ridipingere.

Proposta: calcolare minimi, massimi e raggio nello stesso passaggio; eventualmente conservare un risultato legato alla revisione geometrica del tratto. Da circa `5n` visite si passa a `n` per il calcolo completo, senza cambiare pressione o coordinate. Non significa un guadagno di cinque volte sui tempi totali dell’app. La cache della geometria già presente nel canvas infinito va riutilizzata dove opportuno.

Verifica necessaria: vuoti, punti singoli, coordinate negative, forme curve, gomma, spostamento/ridimensionamento, undo e plugin. Una cache basata soltanto sull’identità della lista non basta se i punti possono essere modificati.

### B. Miniature: invalidazione per pagina — priorità alta, rischio medio

Riferimento: [document_navigator.dart:106](../lib/widgets/document_navigator.dart#L106).

Le righe visibili confrontano la propria revisione con `controller.pluginRevision`, globale per documento. Dopo una modifica a una sola pagina, possono rigenerarsi tutte le miniature montate, anche se le altre pagine sono identiche. Esiste già un debounce di 650 ms: non va rimosso.

Proposta: revisione di contenuto per pagina, più invalidazione esplicita per sfondo e livelli; distinguere la semplice selezione della pagina dal suo contenuto. Conservare generation guard e cancellazione timer. L’indice non deve diventare una falsa identità dopo inserimento di pagine.

Verifica necessaria: una pagina modificata rigenera una sola miniatura; undo, livelli, inserimenti prima/dopo, cambio documento e background PDF aggiornano sempre quella corretta.

### C. Cache dei tratti: evitare ricostruzioni cicliche — priorità alta solo su pagine dense, rischio medio

Riferimento: [XppStroke.dart:476](../lib/layer_contents/XppStroke.dart#L476).

La cache globale è limitata a 64 tratti/25.000 campioni. `_CachedInkPath.matches()` confronta ogni riferimento ai punti a ogni accesso. Una pagina con più di 64 tratti disegnata sempre nello stesso ordine può espellere progressivamente le geometrie che serviranno al repaint successivo. I `RepaintBoundary` attuali attenuano il problema: non significa che ogni pan provochi questo lavoro.

Proposta: identificare la geometria con una revisione esplicita, oppure usare cache per pagina montata con limiti reali e rilascio allo smontaggio. Conservare il limite di memoria; aumentare semplicemente il numero di voci può peggiorare i dispositivi con poca RAM.

Verifica necessaria: contare ricostruzioni dei path su 100–1.000 tratti durante modifiche, zoom e cambi pagina; controllare heap e corrispondenza dopo mutazioni/undo. Miglioramento da dimostrare con benchmark, non garantito dal solo refactoring.

### D. Undo: evitare copie integrali ripetute — beneficio potenziale alto, rischio alto

Riferimento: [canvas_controller.dart:1240](../lib/controllers/canvas_controller.dart#L1240).

Ogni snapshot duplica tutti i livelli e i punti della pagina. Lo storico conserva fino a 50 snapshot; undo/redo genera altre copie della pagina corrente. Il costo cresce con l’inchiostro accumulato, anche per una modifica piccola. Le immagini compresse sono già condivise dagli snapshot: non serve introdurre altre copie.

Proposta futura: comandi reversibili o contenuti immutabili condivisi con copia solo degli elementi modificati. **Non ridurre lo storico per ottenere un apparente miglioramento**, perché cambierebbe una feature. Un semplice trasferimento delle copie a un worker non elimina la quantità di dati.

Verifica necessaria: equivalenza dello storico per disegno, gomma, livelli, selezioni, plugin e pagine inserite; tempo di inizio input e memoria su pagine dense. Da affrontare dopo gli interventi più circoscritti.

### E. Export PDF: alleggerire carta e immagini — priorità media, rischio medio

Riferimento: [document_export.dart:94](../lib/src/document_export.dart#L94).

Anche quando l’inchiostro è vettoriale, la carta viene creata come PNG di pagina intera. Le immagini nei blocchi speciali sono decodificate e ricodificate insieme ai contenuti vicini.

Proposta: colore uniforme della carta come rettangolo PDF, poi progressivamente righe/griglie vettoriali; inserimento diretto dell’immagine originale quando compatibile, con clip e ordine conservati. Questo può ridurre rasterizzazione e dimensione del file. Restano necessari i fallback per contenuti che richiedono i painter attuali.

Verifica necessaria: confronto visivo con carta chiara/scura, righe, puntini, opacità, immagini sovrapposte e pagine PDF. Non tornare a rasterizzare l’intera pagina per semplificare il codice: si perderebbe la qualità appena corretta.

### F. XOPP con audio/PDF grandi: ridurre memoria temporanea — priorità media, rischio alto

Riferimenti: [XppFile.dart:478](../lib/src/XppFile.dart#L478), [note_audio.dart:18](../lib/src/note_audio.dart#L18).

La scrittura crea XML, stringa XML, bytes UTF-8 e gzip. L’audio e gli allegati sono incorporati in base64. Per esempio 128 MiB di audio producono circa 170,7 MiB di base64 prima degli altri dati: il picco RAM non coincide col peso finale del file. Il worker evita di occupare la UI, ma non elimina queste rappresentazioni temporanee.

Proposta futura: scrittura XML/UTF-8/compressione incrementale, conservando XOPP, metadati, escaping, allegati e scrittura atomica. Riuso del checkpoint e gzip livello 1 sono già implementati e vanno mantenuti.

Verifica necessaria: XOPP riaperto equivalente, allegati byte per byte, picco RAM, annullamento/errori, modifiche durante save e compatibilità desktop. Non promettere un miglioramento a partire dal solo conteggio delle copie.

### G. Componenti legacy non collegati: semplificazione — priorità media, rischio basso dopo controllo

Il grafo statico di import/export, comprese le importazioni condizionali, non raggiunge 11 file dagli entrypoint `main.dart`/`main_desktop.dart`: tre adattatori `conditional/open_file/*` e otto widget elencati nei dati allegati. Fra questi: `EditingToolbar.dart`, `MainDrawer.dart`, `QuotaTile.dart`, `XppPagesListView.dart`, `ContextualBottomSheet.dart`.

Proposta: eliminare o isolare il codice legacy dopo verifica degli altri entrypoint/test. Il grafo è a livello di file: non è una prova universale di codice morto. Flutter può già escluderlo dal binario; **non attribuisco alla rimozione un miglioramento di FPS**. Il beneficio principale è evitare manutenzione di UI obsolete e percorsi alternativi confusi.

`RichTextField`, in [XppText.dart:136](../lib/layer_contents/XppText.dart#L136), non ha istanziazioni rilevate nel repository e crea `TextEditingController`/`FocusNode` senza `dispose()`. È un rischio latente se riattivato, non un leak dimostrato nell’app attuale. Se mantenuto, completare il lifecycle.

### H. Modello strumenti: rimuovere duplicazioni — priorità media, rischio contenuto

Riferimenti: [XppStroke.dart:407](../lib/layer_contents/XppStroke.dart#L407) e sottoclassi successive; [ToolBoxBottomSheet.dart:218](../lib/widgets/ToolBoxBottomSheet.dart#L218).

Le sottoclassi del tratto ridichiarano proprietà già presenti nella classe base (`tool`, `points`, `color`, `editingTool`). L’enum `EditingTool` è definito dentro il file della vecchia bottom sheet e importato da modelli e controller.

Proposta: unificare lo storage delle proprietà e spostare l’enum in un piccolo modulo di dominio. Conservare firme dei costruttori, mutabilità prevista e `newStroke()`. La riduzione della dipendenza modello→widget migliora chiarezza; non va confusa con un miglioramento misurato del rendering.

Verifica necessaria: tutte le sottoclassi, clone, serializzazione, selezione strumenti e plugin.

### I. Cache immagini: budget e indicizzazione — priorità media per foto grandi, rischio medio

Riferimento: [decoded_image_cache.dart:20](../lib/src/decoded_image_cache.dart#L20).

Il target di 32 MiB/16 immagini è morbido: le immagini visibili protette non vengono espulse. La risoluzione originale preserva lo zoom, ma una singola immagine 4.000×3.000 può richiedere circa 45,8 MiB di pixel RGBA. `lookup()` e il controllo dei proprietari effettuano scansioni lineari; con poche immagini il costo è limitato.

Proposta: prima misurare foto realmente presenti; poi eventuali versioni a risoluzione proporzionata al viewport con affinamento al termine dello zoom. Un indice per identità deve preservare riferimenti deboli e rilascio: usare una normale Map con chiavi forti potrebbe reintrodurre ritenzione dei bytes.

Verifica necessaria: nessun placeholder persistente, qualità al massimo zoom, risorse liberate, cambio scheda durante decode e heap dopo apertura/chiusura. Non imporre un cap basso che peggiori la nitidezza.

### J. Miniature PDF: riuso della sorgente — priorità media, rischio medio

Riferimenti: [canvas_controller.dart:982](../lib/controllers/canvas_controller.dart#L982) e `_rasterPdfBackground()` a riga 560.

La coda thumbnail è seriale, ma ogni thumbnail PDF apre e chiude nuovamente la sorgente. Visualizzazione ed export hanno già un riuso controllato del documento.

Proposta: riuso di un solo handle nella coda thumbnail per pagine consecutive della stessa sorgente, con chiusura a riposo/cambio/sospensione. Non condividere il medesimo handle con un rendering concorrente della tela.

Verifica necessaria: conteggio aperture/chiusure, file distinti, errori e dispose durante apertura o rendering. Resta necessario il budget di 50.000 pixel per miniatura.

## 4. Ottimizzazioni già presenti da preservare

Sono già implementati: paginazione virtuale con ricerca binaria e callback accorpati per frame; subtree stabile durante pan/zoom; repaint esplicito dell’inchiostro; riconoscimento touch/stylo e palm rejection; gomme con maschere locali senza `Path.combine` nell’input; cache PDF LRU limitata per bytes/pagine; coda nativa seriale e chiusure in `finally`; cache immagini con rilascio e protezione dei risultati tardivi; salvataggi tramite snapshot/checkpoint; compressione e assemblaggio PDF nel worker; audio compresso su disco e polling protetto.

Semplificare questi percorsi con una ricostruzione globale a ogni input, ricalcolo di tutte le pagine, copia indiscriminata dei bytes o rendering PDF illimitato peggiorerebbe l’app. Un file lungo non è, da solo, prova di lentezza: separare `PointerListener` o il controller in moduli può facilitare la manutenzione, purché il percorso dell’input non introduca nuove allocazioni/notifiche.

## 5. Verifica e ordine consigliato

Questo turno ha verificato il confronto upstream, i conteggi, il grafo degli import e i percorsi indicati. Non ha modificato l’app e non ha eseguito nuove misure su un tablet. Le 170 regressioni e il confronto Poppler disponibili in [pdf-quality.md](pdf-quality.md) appartengono al precedente snapshot analizzato, non validano automaticamente le proposte sopra.

Ordine suggerito: A e G/H; B; misure per C/J; infine D/F e adattamento immagini I. Per ogni cambiamento futuro mantenere regressioni di stylo, pressione, palm rejection, gomma, zoom, livelli, undo, audio, sessioni e save/export. Su Android profile/release misurare tempi UI/raster, p50/p95 di save, ricostruzioni dei path/miniature e heap dopo cicli ripetuti. Accettare un refactoring solo se preserva il comportamento e non peggiora tali misure; un risultato desktop non equivale a FPS Android.

## 6. Riproducibilità e dati

Dati completi per file: [upstream-audit.json](validation/upstream-audit.json). Riepilogo dell’esecuzione: [upstream-audit-summary.txt](validation/upstream-audit-summary.txt).

Dopo aver clonato l’upstream originale, dalla radice OSI:

```text
python scripts/audit_upstream.py <cartella-upstream> --local-revision 1d1baa784182e6f3657b9cb33b244f9708811bed --upstream-revision ce62f95f13717ca636d3cec8c2f4212bdd3ef5b9
```

Lo script contiene controlli della tokenizzazione per commenti, formattazione e stringhe, e restituisce anche la raggiungibilità degli import condizionali. La copia upstream è stata solo consultata; non sono stati eseguiti suoi script/build.

## Appendice: inventario dei file Dart non generati

“Assente” indica assenza dello stesso percorso nell’upstream. “Blocco condiviso” è la percentuale di token del file coperta da sequenze upstream di almeno 20 token; uno zero non dimostra assenza di derivazione.

| File | Confronto allo stesso percorso | Righe non vuote | Token | Blocco condiviso |
|---|---|---:|---:|---:|
| `lib/controllers/canvas_controller.dart` | Assente | 1386 | 8953 | 0.00% |
| `lib/controllers/note_audio_controller.dart` | Assente | 326 | 2165 | 0.00% |
| `lib/controllers/theme_controller.dart` | Assente | 174 | 967 | 0.00% |
| `lib/controllers/workspace_controller.dart` | Assente | 153 | 796 | 0.00% |
| `lib/layer_contents/XppImage.dart` | Modificato | 107 | 699 | 27.47% |
| `lib/layer_contents/XppStroke.dart` | Modificato | 652 | 5031 | 16.22% |
| `lib/layer_contents/XppTexImage.dart` | Modificato | 131 | 842 | 35.99% |
| `lib/layer_contents/XppText.dart` | Modificato | 131 | 736 | 42.26% |
| `lib/main.dart` | Modificato | 77 | 387 | 10.08% |
| `lib/main_desktop.dart` | Token identici | 5 | 17 | 0.00% |
| `lib/pages/CanvasPage.dart` | Modificato | 906 | 4084 | 0.00% |
| `lib/pages/OpenPage.dart` | Modificato | 1032 | 5156 | 0.50% |
| `lib/pages/WorkspacePage.dart` | Assente | 532 | 3201 | 0.00% |
| `lib/plugins/plugin_controller.dart` | Assente | 616 | 4565 | 0.00% |
| `lib/plugins/plugin_examples.dart` | Assente | 311 | 910 | 0.00% |
| `lib/plugins/plugin_latex.dart` | Assente | 90 | 610 | 0.00% |
| `lib/plugins/plugin_manager_page.dart` | Assente | 577 | 3268 | 0.00% |
| `lib/plugins/plugin_manifest.dart` | Assente | 210 | 1456 | 0.00% |
| `lib/plugins/plugin_package.dart` | Assente | 44 | 315 | 0.00% |
| `lib/plugins/plugin_runtime.dart` | Assente | 264 | 2281 | 0.00% |
| `lib/plugins/plugin_script.dart` | Assente | 19 | 101 | 0.00% |
| `lib/plugins/plugin_script_native.dart` | Assente | 96 | 569 | 0.00% |
| `lib/plugins/plugin_script_stub.dart` | Assente | 13 | 46 | 0.00% |
| `lib/plugins/plugin_services.dart` | Assente | 289 | 2174 | 0.00% |
| `lib/plugins/plugin_ui.dart` | Assente | 191 | 1194 | 0.00% |
| `lib/src/HexColor.dart` | Modificato | 20 | 123 | 100.00% |
| `lib/src/PdfImage.dart` | Modificato | 46 | 308 | 0.00% |
| `lib/src/ShapeRecognizer.dart` | Assente | 119 | 1116 | 0.00% |
| `lib/src/XppBackground.dart` | Modificato | 377 | 2467 | 41.39% |
| `lib/src/XppFile.dart` | Modificato | 596 | 3465 | 40.98% |
| `lib/src/XppLayer.dart` | Modificato | 49 | 311 | 56.59% |
| `lib/src/XppPage.dart` | Modificato | 49 | 283 | 0.00% |
| `lib/src/XppPageContentWidget.dart` | Identico | 34 | 146 | 100.00% |
| `lib/src/XppPageSize.dart` | Assente | 10 | 82 | 0.00% |
| `lib/src/app_appearance.dart` | Assente | 160 | 915 | 0.00% |
| `lib/src/autosave_store.dart` | Assente | 131 | 987 | 0.00% |
| `lib/src/canvas_geometry_cache.dart` | Assente | 19 | 117 | 0.00% |
| `lib/src/compat/file_picker_cross.dart` | Assente | 147 | 898 | 0.00% |
| `lib/src/compat/internal_storage_generic.dart` | Assente | 19 | 152 | 0.00% |
| `lib/src/compat/internal_storage_io.dart` | Assente | 48 | 336 | 0.00% |
| `lib/src/conditional/open_file/open_file_generic.dart` | Modificato | 5 | 22 | 90.91% |
| `lib/src/conditional/open_file/open_file_io.dart` | Modificato | 8 | 54 | 85.19% |
| `lib/src/conditional/open_file/open_file_web.dart` | Modificato | 4 | 22 | 90.91% |
| `lib/src/content_snapshot.dart` | Assente | 52 | 284 | 0.00% |
| `lib/src/decoded_image_cache.dart` | Assente | 144 | 982 | 0.00% |
| `lib/src/document_export.dart` | Assente | 430 | 3122 | 0.00% |
| `lib/src/document_scene_geometry.dart` | Assente | 21 | 131 | 0.00% |
| `lib/src/dynamic_color_adapter.dart` | Assente | 55 | 317 | 0.00% |
| `lib/src/globals.dart` | Modificato | 7 | 35 | 0.00% |
| `lib/src/ink_geometry.dart` | Assente | 57 | 332 | 0.00% |
| `lib/src/library_metadata.dart` | Assente | 93 | 673 | 0.00% |
| `lib/src/note_audio.dart` | Assente | 99 | 709 | 0.00% |
| `lib/src/note_tags.dart` | Assente | 51 | 368 | 0.00% |
| `lib/src/pdf_raster_cache.dart` | Assente | 39 | 246 | 0.00% |
| `lib/src/recent_documents.dart` | Assente | 132 | 993 | 0.00% |
| `lib/src/selection_clipboard.dart` | Assente | 46 | 321 | 0.00% |
| `lib/src/workspace_session.dart` | Assente | 109 | 838 | 0.00% |
| `lib/widgets/ContextualBottomSheet.dart` | Identico | 22 | 141 | 100.00% |
| `lib/widgets/DropFile.dart` | Modificato | 124 | 777 | 24.45% |
| `lib/widgets/EditingToolbar.dart` | Modificato | 248 | 1336 | 24.63% |
| `lib/widgets/MainDrawer.dart` | Modificato | 94 | 494 | 56.68% |
| `lib/widgets/PointerListener.dart` | Modificato | 1488 | 9619 | 2.30% |
| `lib/widgets/PomodoroTimer.dart` | Assente | 513 | 2700 | 0.00% |
| `lib/widgets/QuotaTile.dart` | Modificato | 8 | 36 | 0.00% |
| `lib/widgets/ToolBoxBottomSheet.dart` | Modificato | 229 | 1022 | 96.87% |
| `lib/widgets/ToolSettingsMenu.dart` | Assente | 138 | 661 | 0.00% |
| `lib/widgets/XppPageStack.dart` | Modificato | 163 | 906 | 33.89% |
| `lib/widgets/XppPagesListView.dart` | Modificato | 135 | 800 | 98.12% |
| `lib/widgets/ZoomableWidget.dart` | Modificato | 425 | 2480 | 3.39% |
| `lib/widgets/app_info_dialog.dart` | Assente | 60 | 319 | 0.00% |
| `lib/widgets/audio_timeline_overlay.dart` | Assente | 107 | 749 | 0.00% |
| `lib/widgets/canvas_app_bar.dart` | Assente | 122 | 736 | 0.00% |
| `lib/widgets/canvas_toolbar.dart` | Assente | 328 | 1860 | 1.13% |
| `lib/widgets/document_library_card.dart` | Assente | 220 | 1153 | 0.00% |
| `lib/widgets/document_navigator.dart` | Assente | 178 | 875 | 0.00% |
| `lib/widgets/infinite_canvas.dart` | Assente | 313 | 2132 | 0.00% |
| `lib/widgets/layers_panel.dart` | Assente | 208 | 1013 | 0.00% |
| `lib/widgets/note_audio_panel.dart` | Assente | 200 | 1095 | 0.00% |
| `lib/widgets/note_tag_picker.dart` | Assente | 102 | 500 | 0.00% |
| `lib/widgets/saved_notes_dialog.dart` | Assente | 66 | 434 | 0.00% |
| `lib/widgets/split_resize_scope.dart` | Assente | 10 | 74 | 0.00% |
| `lib/widgets/split_screen_view.dart` | Assente | 173 | 1033 | 0.00% |
| `lib/widgets/unified_toolbar.dart` | Assente | 433 | 1889 | 0.00% |
| `lib/widgets/unsaved_document_dialog.dart` | Assente | 40 | 231 | 0.00% |
| `lib/widgets/virtual_page_column.dart` | Assente | 143 | 897 | 0.00% |
