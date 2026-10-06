# Specifiche del Progetto (SPEC.md)

**Status:** FINALIZED

## Descrizione Generale
Il progetto è un porting modernizzato delle funzionalità principali di **Xournal++** per dispositivi mobili (Android), Windows, Linux e Web. Si tratta di un'applicazione di note-taking pensata per il disegno a mano libera, l'annotazione di PDF e la gestione di quaderni digitali.

## Funzionalità Attuali dell'App

1. **Gestione File e Appunti**
   - Creazione di nuovi documenti vuoti.
   - Apertura di file salvati di recente.
   - Organizzazione dei file tramite tag (Tutti, Appunti, Scuola, Lavoro).
   - Lettura e parsing di file nativi `.xopp`.

2. **Disegno e Annotazione**
   - Supporto per input tramite Stilo (Stylus) con riconoscimento del palmo.
   - Strumenti di disegno:
     - **Penna** (colori e spessori personalizzabili).
     - **Evidenziatore** (colori e spessori personalizzabili).
     - **Gomma** (modalità pixel o intero tratto, raggio regolabile).
     - **Forme geometriche** (linea, rettangolo, cerchio, ecc.).
   - Supporto all'importazione e rendering di sfondi PDF.

3. **Produttività e Utility**
   - **Pomodoro Timer** integrato per la gestione dei cicli di studio/lavoro.
   - Supporto ai tasti fisici della penna (es. tasto inferiore per gomma, tasto superiore per selezione).
   - Personalizzazione del tema visivo e dei colori primari (integrazione con Material You / Dynamic Color).

## Schermate dell'Applicazione

### 1. `OpenPage` (Schermata Iniziale)
La pagina principale che funge da file manager e hub di partenza.
- **Griglia dei file recenti**: Mostra l'anteprima, il nome e il tag dei file aperti di recente.
- **Barra dei filtri**: Permette di filtrare i documenti tramite i tag predefiniti.
- **Menu Impostazioni**: Consente all'utente di cambiare il tema (incluso l'uso del colore dinamico di sistema) e configurare le azioni associate ai tasti fisici della penna (es. Gomma, Lazo, Evidenziatore).
- **Creazione Nuovo Appunto**: Un Floating Action Button che apre un dialog per creare una nuova nota.

### 2. `WorkspacePage` (Gestore Schede)
Un contenitore per i documenti aperti che implementa un'interfaccia a schede (Tab).
- Permette di avere **più documenti aperti contemporaneamente** e passare da uno all'altro tramite una `TabBar` posizionata in basso (o sotto l'app bar).
- Gestisce l'apertura di PDF in nuove schede.
- Si occupa di avvisare l'utente (prompt) in caso di chiusura di un documento con modifiche non salvate.
- **(Novità) Modalità Split Screen**: oltre alle schede, può affiancare due documenti con un divisore centrale trascinabile e un'unica toolbar globale, instradando i comandi al solo pannello con focus attivo (vedi sezione «Split Screen Interno e Toolbar Unificata»).

### 3. `CanvasPage` (Area di Disegno)
Il nucleo dell'applicazione, dove avviene l'interazione grafica.
- Gestisce lo zoom e il pan tramite `ZoomableWidget` e `InteractiveViewer`.
- Sovrappone la tela di inchiostro (`XppPageStack`) sopra un eventuale sfondo PDF.
- Dispone di una `CanvasToolbar` personalizzata per selezionare gli strumenti e gestirne le proprietà tramite popup contestuali. In modalità Split Screen questa toolbar diventa **unica e globale** (vedi sezione dedicata) e agisce sul pannello che detiene il focus.
- Intercetta i tocchi della stilo rispetto a quelli del dito tramite un `RawGestureDetector` (`StylusGestureRecognizer`).

## Logica di Business
La logica di disegno, lo stato degli strumenti attivi e la gestione del contenuto del file `.xopp` sono demandati alla classe `CanvasController`.
- `CanvasController` incapsula i dati degli strumenti, le proprietà della penna/gomma e le chiamate di rendering.
- Il tracciamento dei punti (stroking) e il riconoscimento delle forme (Shape Recognition) vengono gestiti tramite listener di puntatore specializzati (`PointerListener`).
- Il salvataggio/caricamento avviene serializzando o deserializzando il file interno in un formato compatibile con l'XML compresso standard di Xournal++.

## Restyling Grafico: Interfaccia "Nothing OS" Estesa

### Descrizione
L'interfaccia utente sarà sottoposta a un restyling profondo e coerente, ispirato alle direttive estetiche di "Nothing OS". L'obiettivo è ottenere una UI pulita, focalizzata sul contenuto e caratterizzata da un minimalismo estremo, pur permettendo un livello di personalizzazione cromatica che si distacca dal canonico rosso del brand ispiratore.

### Requisiti Visivi e Tipografici
- **Tema Scuro Predominante**: L'interfaccia prediligerà fondi neri assoluti o grigi molto scuri per massimizzare il contrasto, ridurre il rumore visivo e diminuire l'affaticamento oculare.
- **Tipografia Dot-Matrix**: I titoli delle sezioni principali, le intestazioni dei menu e i contatori numerici (come il Pomodoro Timer) utilizzeranno un font in stile dot-matrix (a matrice di punti) per conferire l'iconico aspetto tecno-retrò. Il corpo del testo utilizzerà invece un font sans-serif moderno e ultra-leggibile.
- **Forme "Squircle"**: I contenitori, le schede della griglia dei file, i pulsanti e i menu a tendina abbandoneranno gli angoli vivi a favore di forme a "squircle" (superellissi) ultra-arrotondate.
- **Bordi Glassmorfici Sottili**: I menu contestuali, le toolbar fluttuanti e le finestre di dialogo presenteranno sfondi solidi o leggermente traslucidi accompagnati da bordi finissimi (1px) semi-trasparenti, creando una netta ma delicata separazione visiva tra i livelli.

### Comportamento Atteso (UI/UX)
- **Stati degli Strumenti (Attivo vs Inattivo)**: L'iconografia si baserà rigorosamente su icone outline minimaliste. Uno strumento inattivo (es. la gomma disattivata) si presenterà in grigio spento con bassa opacità. Quando selezionato, l'icona acquisirà maggior peso visivo e si illuminerà con il colore d'accento scelto dall'utente, fungendo da netto indicatore di stato.
- **Interfaccia Decluttered**: Le barre degli strumenti e le opzioni avanzate (scelta colore, spessore) saranno nascoste per default all'interno di pannelli a scomparsa fluida o bottom sheet espandibili. Solo l'essenziale sarà mantenuto costantemente visibile a schermo.
- **Micro-Animazioni Reattive**: Ogni interazione con i pulsanti o con le schede restituirà un feedback visivo immediato tramite animazioni rapide ed elastiche (es. leggero "rimbalzo" o ridimensionamento al tocco), trasmettendo un senso di estrema fluidità e reattività meccanica.

### Personalizzazione del Tema e Colore d'Accento
- **Scelta del Colore d'Accento**: L'utente avrà la possibilità di sostituire il rosso standard del tema Nothing con un colore personalizzato (es. ciano, verde fluo, viola).
- **Flusso di Selezione**: All'interno del Menu Impostazioni, l'utente visualizzerà una palette curata di tonalità vivaci (o integrerà il motore Dynamic Color). Cliccando su un colore, l'intero tema si aggiornerà istantaneamente in tempo reale.
- **Applicazione del Colore**: Il colore d'accento verrà applicato in modo chirurgico: andrà a illuminare esclusivamente gli switch attivi, i contorni dei pulsanti selezionati, le icone focus della toolbar e alcuni dettagli tipografici decorativi (come specifici punti nel font dot-matrix). Il resto dell'interfaccia rimarrà rigorosamente in scala di grigi per far risaltare l'elemento cromatico.


## Split Screen Interno e Toolbar Unificata

### Descrizione
La `WorkspacePage` introduce una modalità di **visualizzazione affiancata (Split Screen)** che consente di mostrare contemporaneamente due documenti — o due viste indipendenti — all'interno della stessa schermata di lavoro, separati da un **divisore centrale trascinabile**. L'obiettivo è abilitare il confronto e l'annotazione incrociata (ad esempio prendere appunti su un pannello mentre si consulta un PDF o un altro quaderno nell'altro) senza abbandonare il contesto. La funzionalità è pienamente integrata con l'estetica "Nothing OS" e governata da un'**unica toolbar globale** posta in alto.

### Requisiti Funzionali
- **Affiancamento di due pannelli**: la workspace può ospitare due aree di disegno (`CanvasPage`) affiancate orizzontalmente (in landscape) o impilate verticalmente (in portrait). Ogni pannello è legato al proprio `XppFile` e al proprio `CanvasController`, con stato (strumento, zoom, pan, pagina corrente, tratti, undo/redo) **completamente isolato**.
- **Toolbar unica globale e contestuale**: una sola toolbar in alto, condivisa, comanda strumento attivo, colore, spessore, gomma, forme, import PDF, ecc. I comandi si applicano **esclusivamente al pannello che detiene il focus attivo**; la toolbar riflette in tempo reale lo stato dello strumento del pannello attivo e si adatta contestualmente al suo contenuto.
- **Divisore ridimensionabile**: un separatore trascinabile regola in continuo la proporzione tra i due pannelli (indicativamente dal 20% all'80%), con un **vincolo di larghezza minima** per pannello che ne garantisce l'usabilità.
- **Ridimensionamento automatico e responsive**: al variare delle dimensioni della finestra (rotazione del dispositivo, multi-window di Android, ridimensionamento su desktop) i due pannelli si riadattano fluidamente mantenendo la proporzione del divisore. Se lo spazio disponibile scende sotto una soglia minima, lo split **collassa automaticamente a vista singola** (a schede) preservando entrambi i documenti aperti.
- **Gestione del focus**: in ogni momento un solo pannello è "attivo". Il focus passa al pannello interagito per ultimo (stilo, dito o tap esplicito sull'intestazione del pannello) ed è chiaramente segnalato a schermo.
- **Persistenza dello stato di split**: modalità (singola/affiancata), file assegnati a ciascun pannello, posizione del divisore e pannello con focus vengono mantenuti durante la sessione e, ove previsto, ripristinati alla riapertura.

### Requisiti Visivi (coerenza "Nothing OS")
- **Divisore minimalista**: separatore sottile in grigio scuro, con un'impugnatura (handle) centrale a "matrice di punti" (dot-matrix) appena percettibile; durante il trascinamento si illumina con il **colore d'accento** scelto dall'utente.
- **Indicatore di pannello attivo**: il pannello con focus è evidenziato da un bordo finissimo (1px) nel colore d'accento e/o da un'etichetta nella sua intestazione; il pannello inattivo resta in scala di grigi con un leggero calo di contrasto, **senza mai oscurarne il contenuto**.
- **Toolbar unificata glassmorfica**: la toolbar globale adotta lo sfondo solido/traslucido e i bordi finissimi semi-trasparenti già previsti per i menu Nothing OS, con icone outline minimaliste e stato attivo illuminato dall'accento.
- **Forme squircle e micro-animazioni**: apertura/chiusura dello split e spostamento del divisore avvengono con animazioni rapide ed elastiche; i contenitori dei pannelli adottano angoli a squircle.

### Casi d'Uso
1. **Appunti + PDF a confronto**: l'utente apre un PDF nel pannello sinistro e prende appunti a mano libera nel pannello destro, scorrendo e zoomando i due in modo indipendente.
2. **Confronto di due quaderni**: due file `.xopp` differenti vengono affiancati per confrontare o ricopiare contenuti.
3. **Regolazione dello spazio**: l'utente trascina il divisore per dare più spazio al documento su cui sta scrivendo; un doppio tap sul divisore ripristina la proporzione 50/50.
4. **Rotazione del dispositivo**: ruotando da landscape a portrait i due pannelli passano da affiancati a impilati senza perdere lo stato; se lo schermo è troppo piccolo si torna automaticamente alla vista a schede.
5. **Comando contestuale**: con lo split attivo, selezionando "Evidenziatore" dalla toolbar unica lo strumento si applica solo al pannello attivo, mentre l'altro mantiene il proprio strumento corrente.

### Comportamento Atteso (UI/UX)
- **Attivazione/Disattivazione**: lo split si attiva da un controllo dedicato (icona "split" nella toolbar globale o voce "Apri in affiancato" nel menu di una scheda); la disattivazione riporta alla vista a schede singola mantenendo entrambi i documenti aperti.
- **Instradamento dei comandi**: ogni azione della toolbar è inviata al `CanvasController` del **solo** pannello attivo; il cambio di focus aggiorna immediatamente lo stato mostrato dalla toolbar (strumento, colore, spessore correnti del nuovo pannello attivo).
- **Indipendenza del canvas**: zoom, pan, pagina corrente, undo/redo e import PDF sono indipendenti per pannello; il fix delle coordinate dello stilo (conversione globale→locale tramite matrice inversa) si applica **per-pannello** sulla rispettiva tela scalata.
- **Vincoli del divisore**: il trascinamento è limitato dalla larghezza minima per pannello, sotto la quale il pannello non si riduce ulteriormente; il riposizionamento è fluido (target 60/120 fps) e non interferisce con il tracciamento dello stilo.
- **Degrado graduale (responsive)**: sotto la soglia minima di larghezza complessiva lo split collassa a vista singola con notifica non invasiva; tornando sopra la soglia può essere riattivato ripristinando l'ultima configurazione.
- **Coerenza dello stato**: la chiusura di un documento in uno dei due pannelli, in presenza di modifiche non salvate, segue lo stesso prompt di conferma già previsto per le schede.
