# Salvare ed esportare gli appunti

Nel menu **Impostazioni documento** della barra superiore:

- **Salva** aggiorna il documento XOPP corrente; per un documento nuovo mantiene il salvataggio nella libreria dell'app.
- **Salva come XOPP** apre il selettore della destinazione e propone un nome con estensione `.xopp`. Dopo il salvataggio, questa è la destinazione del documento corrente, disponibile anche nella libreria.
- **Esporta PDF** apre il selettore della destinazione e propone un nome `.pdf`. L'esportazione non cambia la destinazione del documento XOPP e non sostituisce il salvataggio degli appunti modificabili.

I comandi operano sul documento con focus, anche in modalità affiancata. Durante un salvataggio/esportazione non è possibile avviarne un secondo. Annullare il selettore non produce un messaggio di successo e conserva il percorso originale e le modifiche ancora da salvare. Se la scrittura fallisce, il documento resta modificato e viene mostrato l'errore.

## Formati

**XOPP** conserva pagine, livelli, tratti, testo, immagini, formule e cancellature, per continuare a modificare gli appunti. Il formato è quello già letto dall'app; non è stato introdotto un formato incompatibile. I PDF originali vengono incorporati per poter riaprire gli appunti in questa app senza i vecchi percorsi. Gli allegati PDF incorporati e le maschere di cancellazione sono estensioni OSIpp: non si deve presumere che Xournal++ desktop interpreti queste estensioni.

**PDF** riproduce l'aspetto dei fogli: carta e modelli, sfondi PDF, tutti i livelli, forme, evidenziatore, cancellature, testo, immagini e formule come appaiono nel canvas. Tutte le pagine sono esportate nelle loro dimensioni originali, anche quelle mai visualizzate o rimosse dalla cache. Se uno sfondo non è disponibile, l'esportazione segnala un errore anziché produrre un PDF incompleto.

Le pagine PDF contengono immagini raster: testo e tratti non sono oggetti modificabili/selezionabili nel PDF. La rasterizzazione usa fino a 2 pixel per punto (144 dpi), con un limite di circa 4 milioni di pixel e 4096 pixel per lato per pagina. Le pagine vengono preparate in sequenza e le immagini native temporanee liberate dopo ciascuna pagina. I contenuti modificabili sono copiati all'inizio, così una modifica durante l'esportazione non cambia le pagine esportate.

## Documenti Android

I riferimenti `content://` restituiti dal selettore sono gestiti attraverso il ContentResolver Android: lettura per la libreria, verifica disponibilità e aggiornamento del file originale. L'app tenta di conservare i permessi concessi dal selettore; la loro durata dipende dal provider scelto. Queste operazioni avvengono su una coda nativa in background. I PDF sono salvati con il tipo MIME `application/pdf`.

## Verifica

`document_export_test.dart` controlla i pixel esportati di inchiostro cancellato, testo, formule, immagini e secondo livello; la presenza di tutte le pagine PDF non memorizzate in cache e le loro dimensioni; l'errore per uno sfondo mancante; il round trip XOPP con contenuto misto e PDF allegato; annullamento, errori e aggiornamento della destinazione; lettura/salvataggio di URI Android attraverso il canale simulato. `document_toolbar_test.dart` verifica i comandi sul documento attivo e la disabilitazione durante il salvataggio, anche su telefono.

Le prove sono in `docs/validation/document-export-tests.txt`, `document-export-analyze.txt` e `document-export-android-build.txt`. Il provider Android e il selettore del dispositivo richiedono ancora una prova fisica per verificare i permessi dopo il riavvio dell'app.

Il 7 ottobre 2026 la suite completa passa 77 test. L'analisi non rileva errori o avvisi; restano 195 informazioni sullo stile. Il controllo di formattazione dei sette file Dart modificati è superato.

La build Android release è riuscita: `build/app/outputs/flutter-apk/app-release.apk` (58,2 MB). Rimangono i warning già documentati sulle future versioni minime di Gradle/AGP/Kotlin; non hanno impedito la compilazione.
