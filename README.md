# OSI

**OSI** è un'applicazione open source per prendere appunti a mano libera, disegnare e annotare documenti PDF. Sviluppata in **Flutter**, è progettata con particolare attenzione all'esperienza d'uso su tablet e smartphone Android dotati di stilo o penna attiva, mantenendo piena compatibilità con il formato di file `.xopp` di [Xournal++](https://github.com/xournalpp/xournalpp).

---

## Funzionalità principali

### Inchiostrazione e disegno
- **Strumenti di scrittura naturale**: penna con sensibilità alla pressione, evidenziatore, gomma e sbianchetto.
- **Elementi grafici e contenuti**: riconoscimento e tracciamento di forme geometriche (linee, cerchi, rettangoli e solidi 3D), caselle di testo, formule LaTeX e immagini.

### Gestione del foglio e livelli
- **Tipi di pagina**: supporto per appunti multipagina con modelli predefiniti (bianco, righe, quadretti, puntinato) e modalità a tela infinita.
- **Livelli (layer)**: gestione dei livelli per ciascuna pagina con controllo di visibilità, blocco e ordinamento.
- **Organizzazione pagine**: navigazione rapida tramite miniature, inserimento, duplicazione e riordinamento.

### Documenti e PDF
- **Annotazione PDF**: importazione di documenti PDF come sfondo di scrittura con rendering nitido in fase di zoom.
- **Esportazione ad alta fedeltà**: generazione di PDF vettoriali per tratti e forme, preservando font e immagini originali.
- **Formato standard**: lettura e salvataggio nativo in formato `.xopp`.

### Studio e produttività
- **Audio sincronizzato con la scrittura**: registratore vocale integrato che associa l'audio ai tratti tracciati; durante il riascolto, la timeline evidenzia visivamente ciò che è stato scritto in quel momento.
- **Flashcard per Anki**: creazione rapida di carte con selezione visiva diretta sul canvas (fronte/retro) ed esportazione del set in formato compatibile con Anki (testo e immagini).
- **Timer Pomodoro**: timer integrato e accessibile dalla barra degli strumenti per scandire le sessioni di studio e lavoro.

### Workspace e organizzazione
- **Multitasking**: interfaccia a schede multiple e modalità a schermo diviso (*split-screen*) per visualizzare o confrontare due note in parallelo.
- **Sessione e sicurezza**: ripristino automatico dello stato del workspace all'avvio, cronologia recenti e salvataggio automatico (*autosave*).
- **Libreria e tag**: organizzazione delle note tramite tag personalizzati e ricerca istantanea.
- **Backup e ripristino**: esportazione e importazione manuale della libreria in archivio `.zip` comprensivo di note, allegati e registrazioni audio.

---

## Compilazione e avvio

### Requisiti
- **Flutter**: 3.47 o successivo (Dart 3.13+)
- **Android SDK**: API level 34–36, NDK 28.2+
- **JDK**: 17

### Installazione ed esecuzione

1. Clona il repository e installa le dipendenze:
   ```sh
   git clone https://github.com/woruam/OSIpp.git
   cd OSIpp
   flutter pub get
   ```

2. Avvia l'applicazione in modalità debug:
   ```sh
   flutter run
   ```

3. Esegui test e analisi del codice:
   ```sh
   flutter test
   flutter analyze
   ```

4. Genera il pacchetto APK per Android:
   ```sh
   flutter build apk --release
   ```
   L'APK generato sarà disponibile in `build/app/outputs/flutter-apk/app-release.apk`.

---

## Note sulle feature sperimentali

Alcune funzionalità (come il gestore plugin e i backup manuali avanzati) sono gestite da flag di compilazione per consentire verifiche isolate durante lo sviluppo:
```sh
flutter run --dart-define=OSI_ENABLE_PLUGINS=true --dart-define=OSI_ENABLE_BACKUP=true
```

---

## Origine e licenza

- Il progetto nasce come evoluzione e rifattorizzazione basata su [Xournal++ Mobile](https://gitlab.com/TheOneWithTheBraid/xournalpp_mobile).
- Distribuito sotto licenza **EUPL-1.2** (European Union Public Licence). Consulta il file [LICENSE](LICENSE) per tutti i dettagli.
