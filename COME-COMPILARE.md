# Xournal++ Mobile 2026 — Come ottenere APK, versione PC e Web

Progetto modernizzato a partire da [xournalpp_mobile](https://github.com/xournalpp/xournalpp_mobile)
(non più mantenuto). Migrato a Flutter 3.x / Dart 3, Android 16 (API 36),
Material 3, con nuove funzioni da app di note-taking moderne.

## Novità rispetto all'originale

- **Material 3 + tema scuro automatico** (segue il tema di sistema)
- **Selezione lazo**: strumento "Select" nella barra — cerchia i tratti per
  spostarli, ridimensionarli (maniglia in basso a destra) o eliminarli
- **Riconoscimento forme** (pulsante bacchetta magica): linee, cerchi,
  triangoli e rettangoli disegnati a mano vengono raddrizzati
- **Ricerca e preferiti** nella schermata iniziale (stella per fissare in alto)
- **Drag & drop** di file .xopp/.pdf su web e desktop
- **Inserimento testo** funzionante; pacchetti abbandonati sostituiti
  (file_picker, package_info_plus, desktop_drop, ecc.)
- Target Android 16 (API 36), minimo Android 7 (API 24), Gradle 8.12 / AGP 8.7

## Metodo consigliato: GitHub Actions (nessuna installazione)

1. Crea un repository su GitHub (può essere privato).
2. Carica questo progetto:
   ```
   git init
   git add .
   git commit -m "Xournal++ Mobile 2026"
   git branch -M main
   git remote add origin https://github.com/TUO-UTENTE/NOME-REPO.git
   git push -u origin main
   ```
   (in alternativa: GitHub Desktop, o trascina i file nell'interfaccia web)
3. Apri la scheda **Actions** del repository: il workflow
   "Build APK, Web and Desktop" parte da solo.
4. A fine build (~10-15 min) scarica dagli **Artifacts**:
   - `xournalpp-mobile-android-apk` → **app-release.apk** da installare sul telefono
   - `xournalpp-mobile-windows` → cartella con **xournalpp.exe** per PC
   - `xournalpp-mobile-web` → versione web (servila con un qualsiasi server statico)
   - `xournalpp-mobile-linux` → bundle per Linux

L'APK è firmato con chiave debug: per installarlo basta abilitare
"Origini sconosciute"; non è adatto al Play Store (come richiesto).

## In alternativa: compilare sul tuo PC

Con [Flutter](https://docs.flutter.dev/get-started/install) installato:

```
flutter pub get
flutter build apk --release          # APK Android (serve Android SDK)
flutter create --platforms=windows .
flutter build windows --release      # exe Windows (da Windows)
flutter build web --release          # versione web
```

## Note

- Le cartelle `web/`, `windows/`, `linux/` vengono rigenerate dal workflow
  (le versioni nel repo originale erano di toolchain obsolete).
- L'apertura diretta di file .xopp dal file manager Android apre l'app ma non
  carica il file (il pacchetto receive_sharing_intent è stato rimosso perché
  abbandonato): apri i file dal pulsante "Apri" dentro l'app.
- Il rendering LaTeX mostra il sorgente in corsivo (katex_flutter, basato su
  WebView, è stato rimosso: non funzionava su desktop).
