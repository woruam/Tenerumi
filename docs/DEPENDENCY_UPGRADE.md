# Dipendenze e compatibilità — 6 ottobre 2026

Il messaggio di `flutter pub outdated` non indicava un errore del progetto:
Flutter 3.44.1 / Dart 3.12.1 aveva già risolto tutte le versioni compatibili.
Anche `flutter pub upgrade` con quel SDK non cambiava alcuna dipendenza.
Le nuove versioni richiedevano un SDK più recente o dipendevano da pacchetti
bloccati da Flutter.

L'SDK installato in `C:\src\flutter` è stato aggiornato sul canale stabile a
Flutter **3.47.6 / Dart 3.13.5**. Il progetto ora richiede almeno Flutter 3.47
e Dart 3.13. Il lockfile registra le versioni risolte senza `dependency_overrides`.

| Dipendenza diretta | Prima | Dopo |
| --- | --- | --- |
| google_fonts | 8.2.1 | 9.0.0 |
| intl | 0.20.2 | 0.20.3 |
| material_ui | 1.2.0 | 1.5.0 |
| vector_math | 2.2.0 | 2.4.3 |
| xml | 7.0.1 | 7.1.0 |

Sono state aggiornate anche 11 dipendenze transitive: clock, code_assets,
cupertino_ui, hooks, matcher, meta, objective_c, petitparser, record_use,
stack_trace e test_api. Il totale è di 16 aggiornamenti rispetto al workspace
ricevuto, che conteneva già altre modifiche non committate.

## Adattamenti del codice

Aggiornamento del 7 ottobre, sistema plugin avanzato: `flutter_math_fork` e `flutter_svg` richiedono XML **7.0.1** tramite `vector_graphics_compiler`; il progetto conserva `xml: ^7.0.1`, senza override. FJS è fissato a **3.2.0**, perché la ricetta degli artefatti 3.3.2 distribuita su pub.dev esclude Android/Windows. Il bridge è fissato a **2.12.0**, corrispondente alla versione del codice generato da FJS 3.2.0: la serie successiva è rifiutata dal controllo di avvio. Il lockfile è quello verificato dai test nativi e dalla build APK. La tabella precedente documenta il primo upgrade, non queste successive aggiunte.

- Google Fonts 9 usa il `TextTheme` del pacchetto `material_ui`, distinto da
  quello dell'SDK Flutter. Il tema applica ora Inter e VT323 ai singoli
  `TextStyle`, condivisi fra i due sistemi. Conserva font, ruoli e impostazioni
  di base. Il test della schermata iniziale verifica tutti i 15 ruoli,
  la dimensione del testo e il peso del titolo.
- Dart 3.13 rifiuta il modificatore `final` sul parametro del costruttore
  `HexColor`: è stato rimosso senza cambiare il parsing dei colori.
- Aggiunto `cupertino_icons` 2.0.0: include il font Cupertino richiesto
  dalle librerie UI e assente nella prima compilazione Web.
- La suite eseguita prima dell'upgrade rilevava un errore già presente nel
  reset della gomma. `PointerListener` ora comunica esplicitamente la fine
  del gesto dopo l'ultimo campione o all'annullamento. Il canvas usa questo
  callback invece di affidarsi all'ordine degli eventi dei listener antenati.
  Il test verifica uno snapshot undo per gesto, diametro, rilascio,
  annullamento e undo indipendente del secondo gesto.
- Flutter ha migrato le esclusioni standard di `analysis_options.yaml`
  (build, android, web) e rimosso da `.gitignore` il vecchio registrant Web.
  Il codice applicativo e i test restano inclusi nell'analisi.

## Pacchetti che restano alla versione compatibile

| Pacchetto | Risolto | Latest | Vincolo che impedisce l'upgrade |
| --- | --- | --- | --- |
| cross_file | 0.3.5+5 | 0.4.0 | file_picker e desktop_drop richiedono la serie 0.3.x |
| dbus | 0.7.15 | 0.8.0 | desktop_drop 0.8.4 richiede `^0.7.10` |
| file_picker_linux | 2.0.0 | 2.0.2 | le versioni successive richiedono dbus `^0.8.0` |
| material_color_utilities | 0.13.0 | 0.13.1 | Flutter 3.47.6 impone esattamente 0.13.0 |
| qr | 3.0.2 | 4.0.0 | barcode, usato da pdf, richiede `^3.0.0` |
| test_api | 0.7.12 | 0.7.14 | flutter_test impone esattamente 0.7.12 |

Queste righe residue sono normali: per eliminarle occorrono nuove release
dei pacchetti che impongono i vincoli. Forzare override non è necessario per
l'applicazione e aggirerebbe la compatibilità dichiarata dai manutentori.

## Verifiche

- Risoluzione delle dipendenze riuscita: `validation/upgrade-resolution.txt`.
- Analisi riuscita con `--no-fatal-infos`: zero errori e warning; 197 info
  preesistenti, come prima dell'upgrade. `validation/upgrade-analyze.txt`.
- Suite completa riuscita: **61 test**. `validation/upgrade-tests.txt`.
- Controlli mirati su font e gomma: 9 test riusciti.
  `validation/upgrade-focused-tests.txt`.
- Build Web release riuscita, con font Cupertino incluso e senza l'avviso
  di asset mancante: `validation/upgrade-web-build.txt`. Anche il dry run
  Wasm è riuscito; non equivale a una verifica runtime di una build Wasm.
- Build APK Android release riuscita: `validation/upgrade-android-build.txt`.
  Output: `../build/app/outputs/flutter-apk/app-release.apk` (54,8 MB).
  Rimangono avvisi sulla futura dismissione di Gradle 8.14, AGP 8.12.1 e
  Kotlin 2.2.20; sono ancora accettati dal nuovo Flutter. Non sono stati
  usati flag per saltare la validazione delle dipendenze di build.
- Test JVM Android release riusciti: **3 test**, zero errori, fallimenti o
  test saltati (`DisplayModePolicyTest`). `validation/upgrade-android-tests.txt`;
  risultati XML in `../build/app/test-results/testReleaseUnitTest/`.
- Formattazione dei sei file Dart modificati controllata, senza modifiche
  residue. Anche `git diff --check` sui file interessati è riuscito.
- La compilazione Windows richiede Visual Studio con gli strumenti C++,
  non installato su questa macchina; non è verificata.
- Le prove su dispositivi reali, inclusi stilo e selettori nativi,
  restano distinte dai test e dalle compilazioni.

Lo stato prima dell'upgrade è conservato nei file `upgrade-*-before.*`;
la versione SDK è in `validation/upgrade-sdk-version.json`.
Le segnalazioni di accesso negato nel log dei test di storage sono errori
provocati intenzionalmente per verificare la conservazione del file originale.
Il warning sul tap di un pulsante Salva disabilitato era già presente prima
dell'upgrade e il relativo test passa.

## Fonti

- [Google Fonts: migrazione e requisiti SDK](https://pub.dev/packages/google_fonts/changelog).
- [Material UI: requisiti SDK e novità](https://pub.dev/packages/material_ui/changelog).
- [XML: Dart 3.13 e PetitParser 7.1](https://pub.dev/packages/xml/changelog).
- [Tag ufficiale Flutter 3.47.6](https://github.com/flutter/flutter/tree/3.47.6).

I vincoli transitivi sono stati verificati anche nei `pubspec.yaml`
dell'SDK installato e dei pacchetti scaricati nella cache.
