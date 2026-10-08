# Architettura del Progetto (ARCHITECTURE.md)

## Alberatura delle Directory

La cartella principale con il codice sorgente è `lib/`, strutturata come segue:

```text
lib/
├── controllers/          # Logica di business e controllori di stato
│   ├── canvas_controller.dart
│   └── workspace_controller.dart   # (Nuovo) Stato sollevato: split, focus, toolbar unica
├── generated/            # File generati automaticamente (es. per la localizzazione)
├── l10n/                 # File per la traduzione e localizzazione (i18n) dell'app
├── layer_contents/       # Implementazioni per i contenuti specifici dei livelli (tratti, testi, ecc.)
├── pages/                # Schermate UI (View)
│   ├── CanvasPage.dart
│   ├── OpenPage.dart
│   └── WorkspacePage.dart
├── src/                  # Modelli dati principali e core logic (parser .xopp)
│   ├── compat/           # Codice per compatibilità multipiattaforma (es. file picker per web/desktop)
│   ├── ShapeRecognizer.dart
│   ├── XppBackground.dart
│   ├── XppFile.dart      # Struttura del documento Xournal++
│   ├── XppLayer.dart
│   ├── XppPage.dart
│   └── globals.dart
├── widgets/              # Componenti UI riutilizzabili
│   ├── canvas_toolbar.dart
│   ├── PointerListener.dart
│   ├── PomodoroTimer.dart
│   ├── ToolBoxBottomSheet.dart
│   ├── XppPageStack.dart
│   ├── ZoomableWidget.dart
│   ├── split_screen_view.dart    # (Nuovo) Gestore della vista affiancata e del divisore
│   └── ...
├── main.dart             # Entry point mobile dell'app
└── main_desktop.dart     # Entry point desktop dell'app
```

## Gestione dello Stato

L'applicazione utilizza principalmente il pacchetto **Provider** per la gestione dello stato reattivo e **SharedPreferences** per la persistenza locale delle configurazioni.

1. **Provider (`ChangeNotifierProvider`)**
   - Il `CanvasController` estende `ChangeNotifier` e viene fornito all'albero dei widget tramite un `ChangeNotifierProvider` all'interno della `CanvasPage`.
   - Utilizza i `Consumer<CanvasController>` per ricostruire parti dell'interfaccia (es. la tela, la toolbar) quando le proprietà di disegno (spessore, colore, strumento attivo) cambiano o quando si aggiungono tratti al file.

2. **SharedPreferences (Persistenza Locale)**
   - Utilizzato nella `OpenPage` e in `main.dart` per salvare le preferenze dell'utente tra diverse sessioni (ad esempio: il colore d'accento personalizzato per il tema, uso di Dynamic Color, azioni dei tasti hardware della stilo, elenco dei file recenti).

3. **Stato Locale dei Widget (`StatefulWidget`)**
   - La gestione dei tab multipli (`WorkspacePage`) e filtri UI più semplici (es. selezione tag in `OpenPage`) è mantenuta nello stato locale usando standard `StatefulWidget`.
   - **(Novità Split Screen)**: lo stato di split, focus e divisore è **sollevato** in un nuovo `WorkspaceController` (`ChangeNotifier`, fornito via `Provider` alla radice della `WorkspacePage`), che possiede anche i `CanvasController` dei documenti aperti. È questo controllore a rendere possibile la **toolbar unica globale** che agisce sul solo pannello con focus (vedi sezione «Architettura dello Split Screen e della Toolbar Unificata»).

## Dipendenze Principali

Le librerie più importanti che guidano il funzionamento dell'app (come definite in `pubspec.yaml`):

- **Stato e Ciclo di vita**: 
  - `provider`: per l'iniezione delle dipendenze e lo stato reattivo del canvas.
  - `shared_preferences`: archiviazione locale delle configurazioni base.
  - `after_layout`: esecuzione di callback post-rendering iniziale.
- **Core (XML e Dati)**: 
  - `archive`: per decomprimere/comprimere i file gzip generati da Xournal++.
  - `xml`: per il parsing e la scrittura della struttura XML dei file `.xopp`.
  - `vector_math`: per manipolazioni spaziali, zoom, pan.
- **Disegno e PDF**: 
  - `perfect_freehand`: per calcolare in tempo reale lo spessore variabile del tratto (stroke) imitando l'inchiostro naturale.
  - `pdf`, `pdfx`: per la generazione e il rendering a schermo di file PDF come sfondo dei documenti. Il plugin `printing` non è utilizzato e non è più una dipendenza.
- **Accesso ai File**: 
  - `file_picker`, `path_provider`: per aprire, salvare e localizzare i file all'interno del file system nei diversi sistemi operativi.
  - `desktop_drop`: per implementare funzionalità drag-and-drop su computer desktop.
- **Interfaccia Utente (UI/UX)**: 
  - `dynamic_color`: per l'integrazione con i temi Material You di Android.
  - `flutter_colorpicker`: per la selezione di colori customizzati per le penne.
  - `font_awesome_flutter`: set esteso di icone vettoriali.
  - `multi_split_view` (o librerie simili): (Nuova) per implementare e gestire nativamente il divisore trascinabile (slider) tra i due canvas.

## Architettura UI/UX (Restyling "Nothing OS")

L'implementazione del restyling visivo avviene puramente a livello di Presentation Layer, mantenendo inalterati la logica di business e il motore Canvas sottostante.

1. **Gestione Tematica Globale (`ThemeData`)**
   - Il tema dell'app (gestito in `main.dart`) applica costantemente un dark mode profondo. 
   - Il **colore d'accento** scelto dall'utente viene iniettato dinamicamente nel `ColorScheme` globale. L'albero dei widget reattivo (tramite Provider o setState alla radice) garantisce che la modifica cromatica si propaghi istantaneamente a tutti gli indicatori di stato, switch e icone attive, senza logica aggiuntiva nei singoli componenti.

2. **Styling System (Forme e Glassmorfismo)**
   - Le forme a "squircle" sono implementate nativamente applicando un `ContinuousRectangleBorder` ai container o ai bottoni, standardizzando l'arrotondamento in tutta l'app.
   - Gli effetti glassmorfici (toolbar, menu a tendina) si affidano al widget `BackdropFilter` accoppiato a un filtro di sfocatura (`ImageFilter.blur`) e a sfondi container con canale alpha (opacità) molto basso.

3. **Micro-Animazioni e Animazioni di Stato**
   - I feedback tattili e visivi meccanici sfruttano primitive di animazione implicita di Flutter come `AnimatedScale`, `AnimatedOpacity` e `AnimatedContainer`. Questo approccio assicura alte prestazioni a 60fps/120fps senza gravare sul thread che gestisce il tracciamento della penna.

## Flusso dei Dati
1. L'utente apre un file da `OpenPage`. 
2. Viene istanziato un oggetto `XppFile` e passato a `WorkspacePage`.
3. `WorkspacePage` crea una nuova tab e inizializza un `CanvasPage`. Nel caso venga attivato lo **Split Screen**, `WorkspacePage` affianca un secondo `CanvasPage` all'interno di un layout diviso (es. `multi_split_view`).
4. Ogni `CanvasPage` crea il proprio `CanvasController` legato al file specifico, isolando lo stato. Un `PointerListener` si mette in ascolto degli eventi touch/stilo per quel singolo pannello.
5. Quando l'utente disegna, il controller del pannello interagito aggiorna i layer del proprio `XppFile` e il `Provider` notifica la UI per eseguire il repaint unicamente su quel canvas tramite il suo `XppPageStack`.


## Architettura dello Split Screen e della Toolbar Unificata

### Stato attuale e obiettivo
Lo split-screen è già abilitato (`split_screen_view.dart` su `multi_split_view`): la `WorkspacePage` affianca due `CanvasPage`. Nell'implementazione corrente, però, **ogni `CanvasPage` possiede la propria toolbar** (`CanvasToolbar` come `appBar`), quindi in modalità affiancata compaiono **due** toolbar. L'obiettivo architetturale è una **toolbar unica globale** che comandi **solo** il pannello con focus, come da `SPEC.md`.

### Sollevamento dello stato (lifting state up)
Si introduce un controllore di alto livello, **`WorkspaceController`** (`ChangeNotifier`), fornito via `ChangeNotifierProvider` alla radice della `WorkspacePage`. Possiede:
- i `CanvasController` di ciascun documento aperto (stato di disegno isolato per documento);
- la modalità split (`splitEnabled`) e la posizione del divisore (`dividerRatio`);
- gli indici dei pannelli affiancati e il **pannello con focus** (`activePanel`).

La toolbar non vive più dentro le singole `CanvasPage`: diventa un componente **globale** montato in cima alla `WorkspacePage` e legato a `WorkspaceController.active`, cioè al `CanvasController` del pannello attivo. Ogni comando (penna, colore, spessore, forma, gomma, PDF) è così instradato esclusivamente al pannello con focus. Al cambio di focus, `notifyListeners()` ricostruisce la toolbar allineandola allo stato del nuovo pannello attivo.

### Gestione del focus
Ogni pannello segnala il focus al primo evento di puntatore (`Listener.onPointerDown → workspace.focus(panel)`). Il pannello attivo è evidenziato con un bordo 1px nel colore d'accento (coerente "Nothing OS"); l'inattivo resta in scala di grigi senza oscurarne il contenuto.

### Mappatura delle coordinate (zoom per-pannello)
Ogni pannello mantiene il proprio `TransformationController` (`InteractiveViewer`). Prima di inviare i punti dello stilo al `CustomPainter`, le coordinate globali sono convertite in coordinate-tela tramite l'**inverso della matrice** (`controller.toScene(local)` ≡ `MatrixUtils.transformPoint(Matrix4.inverted(value), local)`). Ciò elimina il disallineamento in zoom-out, indipendentemente per ciascun pannello. Input separato per `PointerDeviceKind`: `stylus` → disegno, `touch` → pinch-zoom/pan.

### Divisore responsive
Il divisore di `multi_split_view` aggiorna `dividerRatio` con vincoli di larghezza minima (range indicativo 0.2–0.8). In base a `LayoutBuilder`/orientamento, lo split può collassare a vista singola preservando i documenti aperti.

### Persistenza dei tratti con PDF multipli
La gestione resta su **Provider** (coerente con lo stack esistente): l'import PDF inserisce le pagine in modo **incrementale e non distruttivo** nel documento del pannello attivo (inizio/centro/fine o nuova scheda), senza ricreare il file né azzerare i tratti esistenti. Il layering è garantito dallo `Stack` (PDF in background, `CustomPaint` in foreground).
