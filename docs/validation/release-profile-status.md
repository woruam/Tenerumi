# Profilo pubblico e correzione XOPP — 16 ottobre 2026

## Comportamento

`AppFeatures.plugins` e `AppFeatures.manualBackup` sono costanti di
compilazione disattivate per impostazione predefinita. Il profilo pubblico
non inizializza il controller plugin né carica gli archivi plugin salvati,
non espone plugin, backup manuale, ripristino, Pomodoro o Anki. Il Pomodoro
rimane un plugin, disponibile solo nel profilo sperimentale.

Salvataggio automatico, recupero, importazione/esportazione XOPP/PDF e dati
già salvati nei documenti restano disponibili. Le preferenze sperimentali
restano conservate. Nessun nuovo ramo è stato creato.

Su Android, lo stesso flag seleziona i sorgenti nativi e la dipendenza OCR:
MLKit e il canale PluginOcr sono esclusi dal profilo pubblico.

`XppText` e `XppTexImage` passano il testo originale a `XmlText`: il serializer
XML esegue una sola codifica. Nessuna decodifica euristica dei vecchi appunti,
che potrebbe alterare testo letterale come `&lt;`. I test coprono caratteri
speciali, Unicode, entità letterali, DOM, stream e salvataggi ripetuti.

## Verifiche

- Suite pubblica completa: 336 test superati, 4 esclusi perché specifici
  delle interfacce sperimentali; il test aggiunto successivamente sul
  contratto dei flag è passato nella successiva esecuzione mirata.
- Suite sperimentale completa: 341 test superati, nessuna esclusione.
- Smoke finali dei profili: 2/2 test superati per ciascun profilo, con
  schermate pubbliche leggibili in `release-profile-stable-public-*.png`.
- Analisi Flutter e Dart concluse con codice 0: nessun errore o warning;
  316 informazioni di stile non bloccanti.
- Il test XOPP che prima falliva ora passa in entrambi i profili.
- APK ARM64 pubblico release compilato con firma di produzione configurata;
  firma verificata rispetto al certificato atteso, con rifiuto delle firme debug.
- Audit APK e report AOT: assenti moduli Dart plugin, backup, timer e pannelli
  Anki; assenti classe nativa PluginOcr, classi MLKit e modelli OCR.
- Compilazione Android sperimentale riuscita; audit positivo della presenza
  di PluginOcr/MLKit, confermando il funzionamento di entrambi i profili nativi.
- Revisione indipendente approvata, incluso il controllo del report AOT.

Log: `release-profile-stable-tests.txt`,
`release-profile-experimental-all-tests.txt`,
`release-profile-artifact-audit.txt`, `release-profile-signature-audit.txt`,
`release-profile-build.txt`. Il report dimensioni originale è generato da
Flutter tramite `--analyze-size`.
Le verifiche native sperimentali sono registrate in
`release-profile-experimental-build.txt` e
`release-profile-experimental-native-audit.txt`; le analisi in
`release-profile-analyze.txt` e `release-profile-dart-analyze.txt`.

## Riproduzione

```sh
flutter test --dart-define=OSI_ENABLE_PLUGINS=false --dart-define=OSI_ENABLE_BACKUP=false
flutter test --dart-define=OSI_ENABLE_PLUGINS=true --dart-define=OSI_ENABLE_BACKUP=true
flutter build apk --release --target-platform android-arm64 --analyze-size --dart-define=OSI_ENABLE_PLUGINS=false --dart-define=OSI_ENABLE_BACKUP=false
python scripts/check_distribution.py --apk build/app/outputs/flutter-apk/app-release.apk --size-report PERCORSO_REPORT_FLUTTER.json
```

Il report AOT va indicato con il percorso stampato da Flutter al termine
della compilazione. Per verificare anche la firma, usare `--apksigner` e il
certificato atteso come descritto nella guida alla firma. Nessuna release
GitHub è stata pubblicata durante questa sessione.
