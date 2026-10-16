# Stato della correzione operativa — 2026-10-06

## Profili di compilazione e XOPP — 2026-10-16

- Sul ramo attuale, flag compile-time OSI_ENABLE_PLUGINS/OSI_ENABLE_BACKUP
  entrambi false di default; profilo pubblico senza runtime/UI plugin e backup
  manuale. Pomodoro resta plugin ed è escluso dal profilo pubblico.
- Android seleziona sorgenti OCR e MLKit solo nel profilo sperimentale.
  Autosave, recupero, esportazioni ordinarie e dati esistenti preservati.
- Corretto doppio escaping XppText/XppTexImage: il serializer XML riceve testo
  grezzo; test DOM/stream/Unicode/entità letterali e salvataggi ripetuti.
- Suite pubblica completa: 336 pass/4 skip; sperimentale: 341 pass. Nuovo
  contratto flag verificato nella successiva passata mirata del profilo pubblico.
- APK ARM64 release compilato e firmato; verificati certificato atteso,
  assenza dei moduli sperimentali nel report AOT e assenza MLKit/PluginOcr.
- CI, istruzioni di compilazione, README e guida plugin allineati. Revisione
  indipendente approvata. Dettagli in docs/validation/release-profile-status.md.
- Analisi finale senza errori/warning (316 info); build Android sperimentale
  verificata con canale OCR presente. Smoke dei due profili 2/2 ciascuno.
- Nessun nuovo ramo, commit o pubblicazione GitHub effettuato.

## Esperienza di scrittura e navigazione — 2026-10-16

- Completate le otto richieste: penna minima realmente sottile, doppio tocco
  senza zoom, Incolla compatto, barra pagine opzionale, bordo sottile con
  colore configurabile, ritorno PDF con immagine nel primo fotogramma,
  apertura PDF dal sistema, icona Pomodoro con riempimento progressivo.
- Cache inattive limitate a due schede/quattro raster ciascuna/32 MiB;
  immagini decodificate entro il budget condiviso. Geometria vecchie penne
  preservata per spessori >=0,5.
- Revisione indipendente approvata. 47 regressioni mirate superate;
  analisi senza errori o warning; APK debug finale compilato.
- Suite completa: rimane l'errore preesistente di doppio escaping nel test
  streamed XOPP, documentato in docs/validation/experience-status.md.
- Windows build bloccata dal requisito locale link simbolici/Modalità
  sviluppatore. Apri con/stilo vanno confermati sul dispositivo fisico.
- Prove, log e schermate in docs/validation/experience-*; guida apertura
  dal sistema in docs/pdf-open-with.md. Nessun commit effettuato.

## Revisione sicurezza plugin — 2026-10-10

- Riprodotto con un file temporaneo innocuo il caricamento di moduli esterni in FJS 3.2.0. Motore/bridge rimossi dalle dipendenze dell'app; JavaScript rifiutato nel controller e nei runner, senza preferenze, flag o interruttori di riattivazione.
- Workflow JSON LaTeX/OCR disponibili; rafforzati ZIP/decompressione, dati e default UI, permessi immutabili, geometrie, risorse, cancellazione e HTTPS/DNS. Guida e modello di minaccia aggiornati.
- Prove: 209 test superati, analisi senza errori/warning, APK release compilato e ispezionato senza FJS/bridge. Log in `docs/validation/plugin-security-*`; rapporto in `docs/PLUGIN_SECURITY.md`.
- Limiti residui: prove OCR/file picker su Android fisico, manutenzione dei decoder e del nucleo. Un futuro motore richiede loader chiuso e isolamento del sistema operativo, non un opt-in utente.

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

## Estetica Pomodoro - 2026-10-07
Tema condiviso opaco, bordi sottili e forme continue applicati a libreria, navigazione, toolbar e menu. Rimosso blur UI; timer e anello isolati; font VT323/Inter locali con licenze OFL. Personalizzazione conservata. 133 test passati, verifica visiva telefono/desktop, analisi senza errori/warning (199 infos), diff check pulito. Prove e limiti in docs/validation/pomodoro-style-status.md. Frame time Android non misurato; nessun APK.

## Libreria grigia / schede non cliccabili - 2026-10-08
Riprodotta LocaleDataException nel DateFormat della data durante avvio reale. Precedente test visivo mascherava il difetto inizializzando simboli date: rimossa inizializzazione. Formato numerico locale ora indipendente da Intl. 17 test mirati superati; nuova regressione legacy xopp + creazione/salvataggio/riavvio/riapertura via UI, anteprime decodificate e pixel contenuto verificati. Screenshot home/nota controllati. Analisi senza errori/warning, diff check pulito. Stato e prove in docs/validation/library-grey-status.md. APK su telefono non verificato; serve ricompilazione utente.

## OSI 0.5 e tag - 2026-10-08
Scelta/creazione tag nel nuovo appunto, riassegnazione da scheda, catalogo persistito con migrazione legacy. Tag in modello, snapshot, .xopp e metadati recenti. Nome pubblico OSI (Android/Web/UI/export), applicationId e dati conservati. Versione 0.5.0+31, Info app condivisa con versione/build runtime, descrizione, credito/licenza. 138 test passati; screenshot telefono verificati; analisi senza errori/warning e diff check pulito. Prove/istruzioni in docs/validation/osi-tags-status.md. Nessun APK generato; richiede ricompilazione per il telefono.

## Audio sincronizzato - 2026-10-08
Implementati backend Android, audio portabile XOPP, associazioni per campione/tratto, pannello di ascolto e seek dalla penna. Snapshot/eraser/clipboard conservano link e bytes immutabili. Lifecycle finalizza prima di save/close, sospende in background e rilascia risorse; coda svuotata a riposo e preferenze ignorate dopo dispose. 147 regressioni passate, compilazione Kotlin riuscita, analyze senza errori/warning, screenshot docs/validation/audio-timeline-panel.png. Audit e prova hardware pendente descritti in docs/audio-notes.md. Nessun APK né push.

## Eliminazione dalla home - 2026-10-08
Menu pressione prolungata Cambia tag/Elimina con conferma nominativa. Cancellazione file/recente/recovery, refresh e messaggio errore. Supporto provider Android per content URI; serializzazione recenti azzerata a riposo. 150 test Flutter, analyze senza errori/warning, compilazione Kotlin e screenshot verificati. Dettagli docs/home-note-deletion.md. Nessun APK/push.

## Navigazione e continuità workspace - 2026-10-08
Pannello laterale Livelli/Pagine con anteprime lazy, inserimento prima/dopo anche nei PDF, undo/livelli rimappati. Icone colore, fogli squadrati, Incolla 1100 ms. Auto pagina solo note native finite, no catene vuote. Audio scelto dall’utente 120 minuti/48 MiB per registrazione/128 MiB per appunto. Apertura note interne in schede, sessione ripristinata con template, pagina, zoom, split/focus e checkpoint. Gesti filtrati palmo/stilo/terzo contatto, ancoraggio al cambio dita e nessuna inerzia; coordinate penna verificate a zoom 2.3. 161 regressioni, Kotlin riuscito, analisi senza errori/warning, screenshot telefono/desktop. Audit e limiti hardware docs/workspace-navigation.md; nessun APK/push.

## Reattività, export e memoria - 2026-10-08
Virtualizzazione a range stabile/ricerca binaria, paint esplicito su revisione, badge zoom separato. XOPP gzip1 senza copie superflue e riuso checkpoint validato; PDF assemblato in worker, immagini alla risoluzione output e handle sorgenti condivisi/chiusi. Immagini native spostate fuori modello, cache a fonti deboli con ownership dei renderer, decode tardivi rilasciati, niente listener permanenti per import. Dispose TextPainter/controller formule; code svuotate a riposo. 169 test, benchmark 10.000 pagine/300 pan zero ricostruzioni, benchmark gzip lossless, analyze senza errori/warning, Kotlin riuscito. Limiti hardware/target cache morbido/audio RAM documentati in docs/performance-and-memory.md. Nessun APK/push.

## Qualità PDF — 2026-10-08
Export ibrido con tratti a mano libera vettoriali, pressione e gomma locale; fallback trasparenti ritagliati fino a 288 dpi. Renderer PDF utilizza il budget condiviso di quattro milioni di pixel. 170 test completi, otto test risorse/rendering, analyze senza errori/warning e confronto Poppler riusciti. Audit docs/pdf-quality.md; riesportare i vecchi PDF da XOPP. Verifica hardware Android ancora manuale.

## Analisi provenienza e ottimizzazioni — 2026-10-08
Rapporto docs/analisi-provenienza-e-ottimizzazioni.md completato contro upstream GitLab ce62f95 e OSI 1d1baa7. 85 file Dart non generati: 29 corrispondenti per percorso, 56 assenti; 8.007/107.640 token in blocchi condivisi >=20 (7,44%, somiglianza non paternità). Inventario per file, grafo import condizionali e dieci opportunità con rischi/verifiche. Script e JSON riproducibili; controlli conteggi, tokenizzazione e link riusciti. Nessuna modifica runtime o build.

## Interventi G/H/A — fase G
Rimossi 12 file legacy senza utilizzatori attivi, RichTextField e contratto render placeholder dei contenuti. Renderer canvas corrente conservato. 13 test input/export riusciti; nessun riferimento runtime/test ai simboli rimossi. H e A da completare.

## Interventi G/H/A — fase H
EditingTool spostato in src/editing_tool.dart senza cambiare ordine/nomi; import runtime/test migrati e vecchia bottom sheet rimossa. Proprietà dei tratti conservate solo nella base; firme, mutabilità e default editingTool osservabile null preservati. Test clone/XML/mutazioni e regressioni selezione/gomma/audio riusciti. A da completare.

## Interventi G/H/A — completati il 9 ottobre 2026
A: estremi/raggio in un passaggio, curve invariate, nessuna cache aggiuntiva. 10.000 campioni: 50.002 accessi oracle vs 10.001 nuovo bounds. 174 test completi riusciti; analyze senza errori/warning (180 info), confronto PDF/Poppler riuscito. Audit docs/ottimizzazioni-gha.md. B/C/D/E/F/I/J esclusi; nessuna build APK/push.


## Nitidezza PDF e README OSI — 2026-10-09
Forme/whiteout, carta nativa e font supportati esportati vettoriali; immagini originali conservate. Sans Android incorpora Roboto di sistema se leggibile, altrimenti fallback fedele. Dettaglio PDF per regione visibile con texture native, debounce 180 ms e limite circa 2 MP/2048 per lato; niente bitmap completo proporzionale allo zoom. Identità include pagina/sorgente per inserimento/undo. Chiusura pagina prima update, risultati tardivi scartati, timer/listener/texture sostituite/documenti liberati anche in background o errore. README riscritto per OSI 0.5.0+31. 179 test completi, analyze senza errori/warning (180 info preesistenti), confronti Poppler/pypdf e immagini verificati. Limiti: sfondi PDF importati ancora raster, puntinato classico/formule/font non disponibili in fallback; dispositivo Android reale non profilato. Audit docs/pdf-detail-quality.md. Nessuna APK né push.
