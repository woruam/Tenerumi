# Verifica del progetto

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
| `rendering_memory_test.dart` | Budget LRU in byte/pagine, richieste PDF seriali, dispose durante rasterizzazione, risultati obsoleti, culling di 100 pagine durante pan |
| `workspace_safety_test.dart` | Tutte le schede e split, annullamento, cambio indici, salvataggio fallito, gesture Indietro reale con documento inattivo, preferenza touch |
| `pointer_input_test.dart` | Touch abilitato/disabilitato, pinch nella stessa pagina e fra pagine, instradamento penna hardware |
| `undo_snapshot_test.dart` | Snapshot indipendenti dopo spostamento/ridimensionamento, undo/redo, geometria del testo |
| `library_responsive_test.dart` | Libreria con otto documenti a 380dp, leggibilità, scorrimento, nessun overflow; genera screenshot |
| `widget_test.dart` | Apertura della schermata iniziale |
| `split_resize_test.dart` | Divisore orizzontale/verticale con canvas reali, gesture disabilitate durante drag, nessuno spostamento della matrice, reflow ancorato alla pagina |
| `ink_preview_test.dart` | 400 campioni conservati in frame simulati a 120 Hz, repaint senza ricostruire il painter, cancellazione |
| `document_toolbar_test.dart` | Menu visibile su telefono, salvataggio nel pannello con focus, apertura/cancellazione/errore senza perdere documenti |
| `dynamic_color_adapter_test.dart` | Compatibilità della nuova palette dynamic_color con i ruoli ThemeData di Flutter |

Per una modifica eseguire prima il file pertinente, poi la suite completa. Usare fixture piccole e dipendenze controllabili (`CanvasController.pdfRasterizer`, callback di conferma, SharedPreferences mock). Nei widget test le operazioni filesystem/isolate reali devono stare in `tester.runAsync`; aspettarle direttamente nel clock simulato può bloccare il test. Evitare download di font nei test; il test responsive carica font locali. Non usare `pumpAndSettle` con timer periodici attivi.

## Prove e limiti

La suite aggiornata ha superato 42 test; l'analisi non rileva errori o warning (restano informazioni sullo stile). Le prove sono in `docs/validation/tests.txt`, `analyze.txt` e `open-page-phone.png`; lo stato delle build è riepilogato in `docs/validation/followup-status.md`. `web-build.txt` conserva un tentativo fallito precedente alla correzione dell'adattatore dei colori: non certifica la versione attuale. Il test con 100 pagine verifica quanti widget sono montati; non misura il picco RSS su Android. La cache conserva fino a 32 raster e 16 MiB di PNG per documento; ogni raster è limitato a circa un milione di pixel. Le pagine smontate non conservano canvas; passando scheda si liberano i raster e si conserva lo zoom.

Prima di una release eseguire su un dispositivo Android e Windows: PDF di 100 pagine, pan/zoom ripetuti, importazione di due PDF diversi nel mezzo di note esistenti, riapertura del file rinominato su un secondo dispositivo, salvataggio in origine, errori di permesso/SD/cloud, stilo reale con palmo e pulsanti. La build Web riuscita della revisione precedente non certifica i plugin aggiornati: il nuovo tentativo finale è stato rifiutato nella richiesta di autorizzazione, come la build APK finale. I test JVM Android restano da eseguire.

## Compatibilità dei PDF

L'app salva i PDF compressi originali dentro elementi XML `pdf-attachment`, con riferimenti per singola pagina: rinominare o trasferire il documento conserva gli sfondi in questa app senza SharedPreferences. È un'estensione del formato: Xournal++ desktop non interpreta questi allegati; per quel programma servono ancora i PDF esterni indicati negli sfondi. La numerazione `pageno` resta conforme allo standard, a partire da 1.

Sul Web il salvataggio usa un download; i file locali richiedono il selettore e non sono riaccessibili tramite un percorso dopo il riavvio del browser. PDF.js è caricato dalla versione CDN prevista dal pacchetto `pdfx`, quindi l'avvio Web richiede accesso alla rete. Flutter `compute` sposta parsing e serializzazione su isolate nelle piattaforme native, mentre sul Web esegue nel thread corrente: una worker dedicata rimane necessaria per garantire fluidità durante salvataggi Web molto grandi.

## Debito verificabile residuo

- L'esportazione PDF storica conserva i tratti ma non riproduce completamente testo, immagini, TeX e tutti gli stili del canvas. Richiede test dedicati di fedeltà prima di presentarla come esportazione completa.
- Non sono state eseguite build Android/Windows né prove di pressione, palmo e consumo memoria sul dispositivo reale.
- La chiusura forzata del processo, della finestra nativa o del browser richiede una strategia di recupero/autosalvataggio; `PopScope` protegge la navigazione Flutter.

La cartella ricevuta non contiene un repository Git: le modifiche e le prove sono disponibili nel workspace, senza commit.


## Android e input a refresh elevato

SDK minimo corrente: Flutter 3.44 e Dart 3.12, richiesti dai plugin aggiornati. Eseguire scripts/verify-android.ps1 per APK release e test JVM della selezione display; consultare docs/ANDROID_PERFORMANCE.md e docs/INK_PERFORMANCE.md per warning residui e prove sul dispositivo. I frame a 120 Hz simulati nei test non certificano 120 fps o la latenza penna/schermo su hardware.
