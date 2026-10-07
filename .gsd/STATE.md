# Stato della correzione operativa — 2026-10-06

SPEC finalizzata; wave implementazione e integrazione completate.

## Modifiche

- Canvas con culling nelle coordinate della scena e dimensioni del pannello; zoom conservato fra schede; dispose esplicito.
- Raster PDF su richiesta, coda seriale, cache limitata, risultati obsoleti ignorati, risorse PDF chiuse in finally, allegati e associazioni per pagina persistenti.
- Percorsi multipiattaforma e origine conservata; salvataggio atomico, asincrono, con esito esplicito; modifiche successive allo snapshot restano pendenti; titoli duplicati separati.
- Protezione di ogni scheda con PopScope e prompt indipendenti dal montaggio del canvas.
- Disegno touch configurabile e pinch senza tratti accidentali; penna hardware instradata al listener interagito.
- Undo/redo con snapshot profondi; parser corretto per indici sparsi, whitespace, numerazione PDF ed entità testuali.
- Griglia responsive, configurazione Web, suite e script di verifica.

## Prove

30 test passati nella suite completa. Build Web JavaScript riuscita. Analisi senza errori/avvisi; rimangono informazioni sullo stile del codice storico. Screenshot della libreria a 380dp in docs/validation/open-page-phone.png. I log e il collaudo dello script sono in docs/validation/.

## Limiti e prossime verifiche

Consultare docs/TESTING.md per interoperabilità degli allegati con Xournal++ desktop, worker Web, fedeltà dell'esportazione PDF e prove su hardware. Non è presente .git, quindi non sono stati prodotti commit. Non considerare i test di culling una misura del picco memoria Android.

## Seguito: split, penna, toolbar e Android

Implementati blocco delle gesture e reflow ancorato durante il ridimensionamento
split, anteprima incrementale della penna, menu impostazioni con Salva/Apri file,
richiesta del refresh massimo e dispatch non bufferizzato dello stilo su Android.
Aggiornati AGP/Kotlin e plugin; rimosso printing inutilizzato, origine dei warning
Java 8. Adattata la nuova palette dynamic_color a ThemeData Flutter.

Suite aggiornata: 42 test superati. Analisi: nessun errore o warning, 215 informazioni
sullo stile. Dipendenze finali risolte. Le richieste di autorizzazione per APK e
Web finali sono state rifiutate; build finali e test JVM non verificati. I risultati
Web precedenti sopra indicati non certificano questa revisione. Stato dettagliato
in docs/validation/followup-status.md; procedure in docs/TESTING.md e
docs/ANDROID_PERFORMANCE.md. Misure su dispositivo ancora necessarie per latenza
e refresh effettivo. Il warning futuro KGP rimane con Flutter 3.44.1; la migrazione
ufficiale richiede Flutter 3.47+ e AGP 9+.

## Seguito penna/gomma - implementazione e revisione
Geometria capsule condivisa, gomma circolare swept su tutti tratti sovrapposti, diametro coerente con impostazioni, snapshot uno per gesto, cache native bounded64/25000, attributi .xopp e raster alpha PDF. Aggiunti 12 test predisposti con screenshot; non eseguiti per rifiuto autorizzazione accesso cache SDK. Nessuna build. Revisione statica ha corretto ambiguita ternario export e API clipPath; prove in docs/validation/ink-eraser-*.txt. Analisi finale in corso; riaprire stato risultato prima di dichiarare verifica completa. Portabilita attributi custom .xopp descritta in docs/PIXEL_ERASER.md. Non presente Git.
Analisi finale lib/test completata exit0: nessun errore o warning, sole informazioni stile. Nuovi test non eseguiti e screenshot non generati; nessuna build. Riepilogo finale docs/validation/ink-eraser-status.md.

## Gomma sotto zoom - 2026-10-06
Utente conferma: basta pan/dezoom per vedere taglio gia registrato. Rendering inchiostro residuo diretto, senza clip complesso; invalidazione esplicita painter via notifier in XppPageStack.setPageData; sincronizzazione page in didUpdateWidget. Aggiunte tre regressioni primo-frame raster sottozoom1/2.5/5, due gesti e undo senza modificare matrice. Corretto blu fixture raster precedente. Analisi lib/test exit0 senza errori/warning; formatting parser riusciti. Nessuna build. Test non eseguiti per precedente rifiuto accesso SDK; screenshot predisposti nongenerati. Stato docs/validation/eraser-zoom-status.md. Serve prova dispositivo utente per conferma comportamento effettivo.

## Stabilita gomma / ANR - 2026-10-06
Utente conferma dialogo Android ATTENDI/CHIUDI (ANR). Trace dispositivo non fornito. Eliminato Path.combine da rendering e hit test, eliminata cache tagli nativi precedenti. Maschera alpha dstOut isolata per tratto e limitata alla clip visibile, filtro tagli fuori viewport. Hit test distanze segmenti, compattazione esatta sweep collineari e ignorati contatti ridondanti. Campioni condivisi durante cancellazione con copy-on-write nei transform; cache Rect per gesto pulita down/up/cancel/dispose. Quattro regressioni stress aggiunte (4000 eventi). Nuova API containsVisibleInk nei test, vecchia visibleInkPath eliminata. Analisi lib/test exit0 senza errori/warning; parsing formatter verificato. Nessuna build/test Flutter eseguita per vincoli gia descritti. ANR e correttezza sul dispositivo restano da confermare. Prove docs/validation/eraser-stability-status.md.

## Aggiornamento dipendenze richieste - 2026-10-06
Pubspec solo cinque constraint: archive4.3.0 file_picker13.1.0 google_fonts8.2.1 pdf3.13.1 xml7.0.1. Lock risolve esattamente, intl0.20.2 material_ui1.2.0 vector_math2.2.0 invariati. FilePicker13 adattato pickFile/readAsBytes, Uri saveFile senza secondo write; null safe PDF e parser firstOrNull root/preview/background. Font compatibili senza modifiche, manifest senza storage legacy. Pub get exit0. Flutter analyze finale --no-pub --no-fatal-infos exit0:0errors0warnings197infospreesistenti; nessuna deprecazione. Nessuna build/test. Stato docs/validation/dependency-update-status.md, log dependency-update-pub-get.txt/dependency-update-analyze.txt. No Git.
