# Aggiornamento dipendenze — 2026-10-06

Modificati solo i cinque constraint diretti richiesti:
archive ^4.3.0, file_picker ^13.1.0, google_fonts ^8.2.1, pdf ^3.13.1, xml ^7.0.1.
pub get risolve esattamente queste versioni e aggiorna pubspec.lock e il grafo
transitivo. Constraint e versioni risolte di intl (0.20.2), material_ui (1.2.0)
e vector_math (2.2.0) rimangono invariati; nessun upgrade globale.

Adattamenti:

- file_picker_cross.dart: pickFile/readAsBytes invece del vecchio risultato
  files/withData; path nullable, Android content URI e browser blob supportati.
  saveFile restituisce Uri e scrive i byte; rimosso il secondo write filesystem.
  Il download Web mantiene il comportamento del plugin, che restituisce null
  dopo aver avviato il download; sulle altre piattaforme null indica annullamento.
- canvas_controller.dart: rimossi force-unwrap dei percorsi di importazione;
  fallback per PDF basati su byte e collegamenti legacy.
- XppFile.dart: firstOrNull per radice, preview e background; radice assente
  produce FormatException, preview assente usa immagine trasparente.
- GoogleFonts.interTextTheme e vt323/textStyle compatibili con 8.2.1:
  nessuna modifica UI necessaria.
- AndroidManifest.xml non richiede READ_EXTERNAL_STORAGE/WRITE_EXTERNAL_STORAGE:
  nessun permesso READ_MEDIA aggiunto per il selettore documenti.

Verifica:

- flutter pub get: exit 0, dependency-update-pub-get.txt.
- flutter analyze --no-pub --no-fatal-infos: exit 0, 0 errori e 0 warning,
  nessuna deprecazione segnalata. Rimangono 197 informazioni sul codice
  preesistente (stile, nomi, import, BuildContext), senza disabilitarne le regole.
  Log finale dependency-update-analyze.txt.
- Primo analyze aveva rilevato i breaking changes file_picker; il log finale
  contiene la successiva esecuzione dopo le correzioni.
- Nessuna build o test eseguito per questa richiesta.

La cartella non contiene un repository Git; nessun commit prodotto.
