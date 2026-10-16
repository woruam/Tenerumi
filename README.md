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
- Registrazione vocale associata ai tratti: durante l’ascolto viene evidenziata la scrittura corrispondente al momento della registrazione.
- Apertura e salvataggio di `.xopp`, importazione di PDF ed esportazione in PDF.

La registrazione audio nativa è implementata su Android. I limiti sono **120 minuti e 48 MiB per registrazione**, con **128 MiB complessivi per appunto**. La compatibilità `.xopp` deriva da Xournal++; le estensioni specifiche di OSI possono non essere interpretate da altre applicazioni.

## Profilo pubblico e funzioni sperimentali

Le compilazioni standard includono le funzioni elencate sopra. Backup manuale,
ripristino da archivio e sistema plugin sono esclusi dalla compilazione pubblica.
**Il Pomodoro resta un plugin**, quindi è disponibile soltanto nel profilo
sperimentale, insieme alle flashcard Anki. Salvataggio automatico e recupero
degli appunti restano attivi nel profilo pubblico.

Il codice sperimentale resta nello stesso ramo ed è abilitabile solo durante
la compilazione, senza interruttori nell'app pubblica. Le preferenze e i dati
già presenti negli appunti vengono conservati. Vedi le [istruzioni per i profili
di compilazione e le funzioni sperimentali](docs/EXPERIMENTAL_FEATURES.md).

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

Per creare un APK da provare sul dispositivo:

```sh
flutter build apk --debug
```

Il file risultante è `build/app/outputs/flutter-apk/app-debug.apk`.

Per creare un APK release serve una chiave di firma stabile, anche per la distribuzione diretta senza Play Store. Alla prima distribuzione, su Windows, genera e configura la chiave una sola volta:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/configure_release.ps1
```

Lo script conserva la chiave e le password in file locali esclusi da Git e non sostituisce chiavi esistenti. Conserva insieme `android/keystore` e `android/key.properties` in una copia sicura fuori dal repository. Se esiste già una chiave utilizzata per distribuire l’app, configura quella seguendo la [guida alla firma](docs/RELEASE_SIGNING.md).

Poi, per ogni release:

```sh
flutter build apk --release
```

Il file risultante è `build/app/outputs/flutter-apk/app-release.apk`. Le cartelle per altre piattaforme sono presenti nel repository; Android è la piattaforma di riferimento per penna e audio e le funzioni native possono differire sulle altre piattaforme.

Questo comando produce il profilo pubblico: i flag `OSI_ENABLE_PLUGINS` e
`OSI_ENABLE_BACKUP` sono entrambi `false` per impostazione predefinita.
La CI li imposta esplicitamente a `false` per tutti gli artefatti distribuiti
e verifica anche le funzioni sperimentali con una seconda esecuzione dei test.

## Documentazione e contributi

- [Analisi della provenienza del codice e delle ottimizzazioni](docs/analisi-provenienza-e-ottimizzazioni.md)
- [Ottimizzazioni G, H e A](docs/ottimizzazioni-gha.md)
- [Nitidezza PDF e gestione delle risorse](docs/pdf-detail-quality.md)

Per segnalare un problema, indicare dispositivo, versione Android, versione OSI e passaggi per riprodurlo. Per problemi di esportazione è utile specificare se l’appunto è nativo oppure contiene un PDF importato e confrontare il PDF con l’originale `.xopp`.

## Origine e licenza

OSI deriva da [Xournal++ Mobile](https://gitlab.com/TheOneWithTheBraid/xournalpp_mobile) e conserva la compatibilità con il formato di appunti di Xournal++. Questo repository contiene l’evoluzione di OSI; i collegamenti agli store e ai download del progetto originale non rappresentano distribuzioni di OSI.

Il codice è distribuito secondo la licenza **EUPL-1.2**, disponibile in [LICENSE](LICENSE). Gli avvisi di copyright e le licenze dei componenti e delle risorse di terze parti restano applicabili.
