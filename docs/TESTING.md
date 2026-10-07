# Verifica del progetto

Aggiornamento del 6 ottobre 2026: Flutter 3.47.6 / Dart 3.13.5 e 16 dipendenze
aggiornate. Dopo le correzioni di evidenziatore e lazo, la suite completa passa
70 test. La revisione PDF/XOPP del 7 ottobre passa 77 test; l'analisi non rileva
errori o warning (195 informazioni sullo stile). Consultare
[salvataggio ed esportazione](DOCUMENT_EXPORT.md) per formati, destinazioni e URI Android.
Consultare [evidenziatore e selezione](SELECTION_TOOLS.md) per copia, spostamento,
incolla con pressione prolungata della penna e prove di questa revisione.
Consultare [il rapporto aggiornato](DEPENDENCY_UPGRADE.md) per build, vincoli
residui e limiti della verifica. I riepiloghi delle revisioni precedenti sotto
descrivono lo stato di quelle revisioni.

La revisione plugin avanzati del 7 ottobre aggiunge runtime JavaScript, pacchetti,
formule reali, Anki, OCR e API asincrone. Consultare [la guida plugin](../PLUGIN_GUIDE.md)
per editor guidato, JavaScript, API, SDK ed esempi importabili. Le prove aggiornate
sono in `validation/advanced-plugins-all-tests.txt`, `advanced-plugins-analyze-final.txt`,
`advanced-plugins-build-final.txt` e `advanced-plugins-web-build.txt`.

Verifica finale: **103 test superati**, inclusi 4 test JavaScript nativi reali;
analisi con **zero errori e zero warning** (196 info di stile); build Android
release **117,8 MB** e build Web release riuscite. Il motore JavaScript e il
modello OCR locale aumentano la dimensione dell'APK. JavaScript è disponibile
su Android/desktop; la build Web mantiene i workflow JSON. Non sono state
eseguite prove fisiche dell'OCR, dei selettori file o della pressione della penna.

Eseguire dalla radice con Flutter installato:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1
```

Lo script risolve le dipendenze, controlla errori/avvisi, esegue i test e compila il Web. Restituisce errore al primo controllo fallito e salva le prove in `docs/validation/`. Usa direttamente il runtime dell'SDK per evitare il blocco del launcher `flutter.bat` osservato su questa macchina. `-FlutterRoot C:\src\flutter` permette di specificare l'SDK. `-Quick` esegue storage, memoria e undo senza build Web; `-SkipWeb` esegue tutti i test senza build Web.

Comandi equivalenti su altri sistemi:

```sh
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter expanded
flutter build web
```

Gli avvisi e gli errori bloccano la verifica. Le informazioni sullo stile del codice storico sono visibili ma non bloccanti; i file generati non devono essere modificati per eliminarle.

## Suite e scelta dei test

| File | Regressioni |
| --- | --- |
| `document_storage_test.dart` | Percorsi Windows/Unix, nomi senza estensione, allegati PDF, numerazione nativa, elementi XML sconosciuti, entità testuali, salvataggi atomici, errori, modifiche durante salvataggio, titoli duplicati |
| `document_export_test.dart` | Fedeltà raster PDF di contenuto misto e cancellature, tutte le pagine e livelli, sfondi non in cache, dimensioni, XOPP riapribile, annullamento, errori e URI documenti Android |
| `plugin_system_test.dart` | Formato e permessi, esempi, logica e generatori, immagini, editor su telefono, persistenza, rollback, undo, budget, conflitti, aggiornamento, disattivazione e SDK |
| `advanced_plugin_test.dart` | Pacchetti e percorsi, Anki/HTML, export preparati, permessi dinamici, OCR asincrono, cancellazione, rete e rendering LaTeX/PNG |
| `plugin_javascript_test.dart` | Motore reale: moduli ES, async/await, rollback, permessi, interruzione nativa di un ciclo infinito ed esecuzione degli esempi LaTeX/Anki/OCR |
| `rendering_memory_test.dart` | Budget LRU in byte/pagine, richieste PDF seriali, dispose durante rasterizzazione, risultati obsoleti, culling di 100 pagine durante pan |
| `workspace_safety_test.dart` | Tutte le schede e split, annullamento, cambio indici, salvataggio fallito, gesture Indietro reale con documento inattivo, preferenza touch |
| `pointer_input_test.dart` | Touch abilitato/disabilitato, pinch nella stessa pagina e fra pagine, instradamento penna hardware |
| `undo_snapshot_test.dart` | Snapshot indipendenti dopo spostamento/ridimensionamento, undo/redo, geometria del testo |
| `selection_tools_test.dart` | Spessore reale dell'evidenziatore, pulsanti lazo con penna, copia/incolla con pressione prolungata, spostamento e incolla a zoom 1x/2,5x, undo/redo, appunti condivisi fra documenti e navigazione senza inchiostro |
| `library_responsive_test.dart` | Libreria con otto documenti a 380dp, leggibilità, scorrimento, nessun overflow; genera screenshot |
| `widget_test.dart` | Apertura della schermata iniziale |
| `split_resize_test.dart` | Divisore orizzontale/verticale con canvas reali, gesture disabilitate durante drag, nessuno spostamento della matrice, reflow ancorato alla pagina |
| `ink_preview_test.dart` | 400 campioni conservati in frame simulati a 120 Hz, repaint senza ricostruire il painter, cancellazione |
| `ink_round_continuity_test.dart` | Confronto raster identico fra anteprima e tratto definitivo, pressione, incroci, estremità arrotondate e invalidazione cache |
| `pixel_eraser_test.dart` | Punta circolare, sweep fra eventi distanti, tratti sovrapposti, undo per gesto, persistenza, trasformazioni e sfondo |
| `eraser_zoom_repaint_test.dart` | Cancellazione visibile nel primo frame a zoom fisso 1x/2,5x/5x, due gesti consecutivi, sfondo e undo senza pan/dezoom |
| `eraser_stability_test.dart` | 4.000 eventi rettilinei compattati, eventi ripetuti, curve/inversioni, dati non validi e campioni condivisi senza alterare gli originali |
| `document_toolbar_test.dart` | Menu visibile su telefono, salvataggio nel pannello con focus, apertura/cancellazione/errore senza perdere documenti |
| `dynamic_color_adapter_test.dart` | Compatibilità della nuova palette dynamic_color con i ruoli ThemeData di Flutter |

Per una modifica eseguire prima il file pertinente, poi la suite completa. Usare fixture piccole e dipendenze controllabili (`CanvasController.pdfRasterizer`, callback di conferma, SharedPreferences mock). Nei widget test le operazioni filesystem/isolate reali devono stare in `tester.runAsync`; aspettarle direttamente nel clock simulato può bloccare il test. Evitare download di font nei test; il test responsive carica font locali. Non usare `pumpAndSettle` con timer periodici attivi.

## Prove e limiti

La suite della revisione precedente ha superato 42 test; la relativa analisi non rileva errori o warning (restano informazioni sullo stile). Il seguito penna/gomma aggiunge 12 test non eseguiti dopo il rifiuto dell'autorizzazione per la cache SDK: consultare `docs/PIXEL_ERASER.md` e `docs/validation/ink-eraser-status.md` per lo stato attuale. Le prove precedenti sono in `docs/validation/tests.txt`, `analyze.txt` e `open-page-phone.png`; lo stato delle build è riepilogato in `docs/validation/followup-status.md`. `web-build.txt` conserva un tentativo fallito precedente alla correzione dell'adattatore dei colori: non certifica la versione attuale. Il test con 100 pagine verifica quanti widget sono montati; non misura il picco RSS su Android. La cache conserva fino a 32 raster e 16 MiB di PNG per documento; ogni raster è limitato a circa un milione di pixel. Le pagine smontate non conservano canvas; passando scheda si liberano i raster e si conserva lo zoom.

Prima di una release eseguire su un dispositivo Android e Windows: PDF di 100 pagine, pan/zoom ripetuti, importazione di due PDF diversi nel mezzo di note esistenti, riapertura del file rinominato su un secondo dispositivo, salvataggio in origine, errori di permesso/SD/cloud, stilo reale con palmo e pulsanti. La build Web riuscita della revisione precedente non certifica i plugin aggiornati: il nuovo tentativo finale è stato rifiutato nella richiesta di autorizzazione, come la build APK finale. I test JVM Android restano da eseguire.

## Compatibilità dei PDF

L'app salva i PDF compressi originali dentro elementi XML `pdf-attachment`, con riferimenti per singola pagina: rinominare o trasferire il documento conserva gli sfondi in questa app senza SharedPreferences. È un'estensione del formato: Xournal++ desktop non interpreta questi allegati; per quel programma servono ancora i PDF esterni indicati negli sfondi. La numerazione `pageno` resta conforme allo standard, a partire da 1.

Sul Web il salvataggio usa un download; i file locali richiedono il selettore e non sono riaccessibili tramite un percorso dopo il riavvio del browser. PDF.js è caricato dalla versione CDN prevista dal pacchetto `pdfx`, quindi l'avvio Web richiede accesso alla rete. Flutter `compute` sposta parsing e serializzazione su isolate nelle piattaforme native, mentre sul Web esegue nel thread corrente: una worker dedicata rimane necessaria per garantire fluidità durante salvataggi Web molto grandi.

## Debito verificabile residuo

- La nuova esportazione PDF riproduce il canvas come immagini raster; non conserva testo selezionabile o elementi vettoriali modificabili. Consultare `DOCUMENT_EXPORT.md` per copertura e limiti.
- Non sono state eseguite build Android/Windows né prove di pressione, palmo e consumo memoria sul dispositivo reale.
- La chiusura forzata del processo, della finestra nativa o del browser richiede una strategia di recupero/autosalvataggio; `PopScope` protegge la navigazione Flutter.

La cartella ricevuta non contiene un repository Git: le modifiche e le prove sono disponibili nel workspace, senza commit.


## Android e input a refresh elevato

SDK minimo corrente: Flutter 3.47 e Dart 3.13, richiesti dalle dipendenze aggiornate. Eseguire scripts/verify-android.ps1 per APK release e test JVM della selezione display; consultare docs/DEPENDENCY_UPGRADE.md, docs/ANDROID_PERFORMANCE.md e docs/INK_PERFORMANCE.md per warning residui e prove sul dispositivo. I frame a 120 Hz simulati nei test non certificano 120 fps o la latenza penna/schermo su hardware.
