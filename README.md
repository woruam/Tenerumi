# OSI

**OSI** è un’app per appunti scritti a mano, disegno e annotazioni PDF, sviluppata in Flutter con particolare attenzione all’uso della penna su Android.

Versione attuale: **0.5.0**, build **31**. Il progetto è in sviluppo.

## Funzioni

- Penna con pressione, evidenziatore, gomma, forme, testo e immagini.
- Appunti su più pagine, modelli di foglio e pagine infinite.
- Pannello laterale per cambiare layer e navigare tra le anteprime delle pagine.
- Inserimento di pagine prima o dopo quella corrente e generazione della pagina successiva negli appunti nativi.
- Libreria con tag personalizzati, ricerca e cancellazione con conferma.
- Più appunti aperti in schede e ripristino della sessione.
- Backup degli appunti e ripristino su un altro dispositivo dalle impostazioni.
- Registrazione vocale associata ai tratti: durante l’ascolto viene evidenziata la scrittura corrispondente al momento della registrazione.
- Timer Pomodoro attivabile dalla sezione Plugin; l’icona compare nella toolbar solo quando il plugin è attivo.
- Flashcard per Anki con doppia selezione, set modificabile per appunto ed esportazione di testo e immagini.
- Apertura e salvataggio di `.xopp`, importazione di PDF ed esportazione in PDF.

La registrazione audio nativa è implementata su Android. I limiti sono **120 minuti e 48 MiB per registrazione**, con **128 MiB complessivi per appunto**. La compatibilità `.xopp` deriva da Xournal++; le estensioni specifiche di OSI possono non essere interpretate da altre applicazioni.

## Backup e trasferimento degli appunti

Sul dispositivo principale apri **Impostazioni → Crea Backup → Prepara backup**. L’app raccoglie gli appunti della libreria e i recuperi automatici, scegliendo le modifiche più recenti disponibili. Include tag, preferiti, immagini, PDF di sfondo, registrazioni audio e flashcard. Se alcuni file o allegati non sono accessibili, li elenca prima di consentire l’esportazione di un backup parziale.

Premi **Esporta backup** e conserva il file `OSI-backup-AAAA-MM-GG.zip`. Trasferiscilo al nuovo dispositivo con il metodo che preferisci. Sul nuovo dispositivo apri **Impostazioni → Ripristina Backup → Scegli backup**, verifica l’elenco e premi **Ripristina appunti**. Gli appunti saranno aggiunti alla libreria come nuove copie; quelli già presenti vengono conservati. Ripristinare nuovamente lo stesso archivio crea altre copie.

Il backup è un archivio manuale, senza sincronizzazione automatica. Ogni archivio supporta fino a 10000 appunti e 512 MB di contenuti `.xopp` compressi. L’archivio viene verificato prima del ripristino; in caso di errore di scrittura, la libreria precedente resta disponibile e i file importati provvisoriamente vengono rimossi.

## Plugin per lo studio

I plugin personalizzati usano workflow JSON con API controllate. JavaScript è sospeso e il relativo motore è stato rimosso dall'app: non esiste un'opzione per riattivarlo. Vedi la [guida plugin](PLUGIN_GUIDE.md) e il [modello di sicurezza](docs/PLUGIN_SECURITY.md).

In **Plugin** puoi attivare **Timer Pomodoro** e **Flashcard per Anki**. Sono disattivati inizialmente; la scelta viene conservata. Disattivando Pomodoro il pannello e l’icona scompaiono e il timer si ferma.

Per creare una flashcard, attiva il plugin Anki e premi **Doppia selezione**: trascina un riquadro sul titolo, poi uno sulla risposta. La toolbar indica il passaggio corrente; premi di nuovo lo strumento per annullare. Dopo la seconda selezione puoi correggere i testi e confermare il salvataggio. Scrittura a mano, figure e PDF vengono conservati come immagini; un testo inserito nell’editor sostituisce l’immagine nel lato esportato.

**Flashcard dell’appunto** mostra il set del documento attivo: tocca una carta per modificarla oppure usa il cestino per eliminarla. Il set viene salvato nel file `.xopp` e nei recuperi automatici, anche se il plugin è disattivato. Le carte del vecchio plugin possono essere copiate nel documento con **Copia qui le carte del vecchio plugin**.

**Esporta per Anki** crea un archivio ZIP con `flashcard.txt`, le immagini e le istruzioni: estrai l’archivio, copia le immagini in `collection.media` di Anki e importa il file di testo con HTML attivo e tipo **Basic**. Anki usa il fronte per identificare le carte già esistenti: dopo una modifica al titolo, rimuovi la vecchia carta in Anki prima di reimportare. Il formato segue la [documentazione ufficiale di Anki](https://docs.ankiweb.net/manual/importing/text-files). **Esporta JSON** crea una copia dei dati OSIpp; il JSON non è un formato di importazione nativo di Anki.

## Qualità dei PDF

L’esportazione mantiene vettoriali i tratti e le forme, oltre ai testi con font incorporati supportati. Le immagini inserite conservano i dati originali. Le pagine PDF importate, le formule, i font non supportati e il modello puntinato classico utilizzano ancora una rappresentazione raster: la loro nitidezza rimane limitata dalla risoluzione.

Nella vista Android il dettaglio delle pagine PDF viene aggiornato dopo lo zoom, renderizzando soltanto la zona visibile con un limite di memoria. Per beneficiare delle migliorie all’esportazione è necessario esportare nuovamente l’appunto originale `.xopp`.

## Avvio e compilazione

Requisiti del progetto:

- Flutter **3.47 o successivo**, con Dart **3.13 o successivo** compatibile con Flutter.
- Per Android: JDK **17**, Android SDK con piattaforma **36** e NDK **28.2.13676358**.
- Dispositivo Android **7.0 / API 24** o successivo per l’app Android.

Dalla cartella del repository:

```sh
flutter doctor
flutter pub get
flutter run
```

Per verificare il codice:

```sh
flutter test
flutter analyze
```

Per creare l’APK:

```sh
flutter build apk --release
```

Il file risultante è `build/app/outputs/flutter-apk/app-release.apk`. Le cartelle per altre piattaforme sono presenti nel repository; Android è la piattaforma di riferimento per penna e audio e le funzioni native possono differire sulle altre piattaforme.

## Documentazione e contributi

- [Analisi della provenienza del codice e delle ottimizzazioni](docs/analisi-provenienza-e-ottimizzazioni.md)
- [Ottimizzazioni G, H e A](docs/ottimizzazioni-gha.md)
- [Nitidezza PDF e gestione delle risorse](docs/pdf-detail-quality.md)

Per segnalare un problema, indicare dispositivo, versione Android, versione OSI e passaggi per riprodurlo. Per problemi di esportazione è utile specificare se l’appunto è nativo oppure contiene un PDF importato e confrontare il PDF con l’originale `.xopp`.

## Origine e licenza

OSI deriva da [Xournal++ Mobile](https://gitlab.com/TheOneWithTheBraid/xournalpp_mobile) e conserva la compatibilità con il formato di appunti di Xournal++. Questo repository contiene l’evoluzione di OSI; i collegamenti agli store e ai download del progetto originale non rappresentano distribuzioni di OSI.

Il codice è distribuito secondo la licenza **EUPL-1.2**, disponibile in [LICENSE](LICENSE). Gli avvisi di copyright e le licenze dei componenti e delle risorse di terze parti restano applicabili.
