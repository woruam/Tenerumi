Status: FINALIZED

Correggere le criticità operative richieste: culling canvas, PDF su richiesta con cache limitata e associazioni persistenti, salvataggi sicuri, protezione di tutte le schede, input touch configurabile, compatibilità Web, griglia responsive, serializzazione asincrona. Test di regressione e istruzioni ripetibili per gli agent.

Status: FINALIZED
Follow-up: separare drag divisore e gesture documenti preservando posizione/zoom; ridurre latenza anteprima penna senza perdere campioni; richiedere refresh massimo a risoluzione costante su Android; menu toolbar Salva/Apri file sul documento con focus; aggiornare toolchain Android compatibile con SDK locale e verificare warning residui.

## Seguito penna e gomma - 2026-10-06
Status: FINALIZED
Il tratto definitivo deve conservare la geometria arrotondata dell'anteprima, pressione e campioni. La gomma pixel cancella l'area effettiva anche fra campioni radi, con salvataggio e undo/redo. Aggiungere test e prove visive. Nessuna build autorizzata.

## Gomma sotto zoom - 2026-10-06
Status: FINALIZED
La gomma deve mostrare la cancellazione nel prossimo frame anche a zoom elevato senza pan/dezoom. Usare geometria inchiostro sottratta invece clip GPU e invalidare esplicitamente il layer dopo modifiche. Test raster con trasformazione stabile, due cancellazioni consecutive e undo. Nessuna build.

## Stabilita gomma - 2026-10-06
Status: FINALIZED
Eliminare Path.combine da input e rendering gomma; cancellare con maschera alpha isolata per tratto, con layer limitato alla clip visibile. Hit test geometrico, compattazione esatta tagli collineari/ridondanti, niente copia punti per campione. Conservare penna/forme, undo, PDF e persistenza. Regressioni stress e alpha. Nessuna build.

## Dipendenze richieste - 2026-10-06
Status: FINALIZED
Aggiornare solo archive4.3.0, file_picker13.1.0, google_fonts8.2.1, pdf3.13.1, xml7.0.1 nei constraint diretti. Mantenere intl/material_ui/vector_math. Verificare path nullable, nodi XML mancanti, font e manifest. Eseguire pub get e analyze, nessun upgrade globale o build.

## Estetica Pomodoro - 2026-10-07
Status: FINALIZED
Uniformare libreria, navigazione, toolbar e menu al Pomodoro con superfici opache, bordi sottili e forme continue. Conservare personalizzazione e funzioni. Eliminare blur sul canvas, isolare repaint timer e verificare layout e interazioni.

## Libreria grigia dopo salvataggio - 2026-10-08
Status: FINALIZED
Riprodurre e correggere schede e area home grigie dopo salvataggio, apertura documenti persistiti e anteprime. Verificare avvio reale senza inizializzazione date esclusiva dei test, riapertura file precedenti e appena salvati, rendering PNG. Conservare file e stile leggero.

## Tag e identita OSI - 2026-10-08
Status: FINALIZED
Scelta tag nella creazione note, tag personalizzati persistiti e riassegnazione delle note esistenti. Tag conservati in snapshot/salvataggi e filtri home. Rinominare superfici pubbliche e label Android/Web in OSI senza cambiare applicationId o storage. Versione 0.5 (pacchetto 0.5.0+31) e Info app funzionante con versione, build e descrizione. Verificare regressioni, persistenza e layout telefono.

## Audio sincronizzato - 2026-10-08
Status: FINALIZED
Registrazione Android su azione esplicita, audio portabile negli appunti, tempi per tratto, ascolto interno con evidenziazione e seek dal tratto. Preservare input e strumenti, undo/redo, snapshot e autosave. Limiti memoria, arresto in background, rilascio risorse, test e audit documentati.

## Eliminazione note dalla home - 2026-10-08
Status: FINALIZED
Pressione prolungata apre azioni Cambia tag/Elimina; Elimina richiede conferma con nome. Annulla non modifica file/indice. Conferma cancella file e voce recente, copia recovery associata; aggiorna home. Errori visibili senza rimuovere voce se cancellazione file fallisce. Supporto Android content URI e storage locale/Web.

## Navigazione e continuita workspace - 2026-10-08
Status: FINALIZED
Pannello laterale non modale con livelli e miniature pagine lazy/cachate, selezione rapida e inserimento prima/dopo pagina attiva per note e PDF. Icone penna/evidenziatore nel colore scelto, pagine squadrate e pressione Incolla 1100ms. Autogenerazione nelle sole note finite native quando inchiostro raggiunge zona inferiore o gesto verso alto a fine documento; nessuna catena di pagine vuote. Audio 120 minuti/48 MiB per registrazione/128 MiB per appunto. Apri libreria in nuova scheda senza home. Persistenza/ripristino sessione schede, focus, split e viewport in background/riavvio. Rejection palmo/stylo e stabilita pinch senza inerzia o salto al cambio numero dita. Verificare snapshot/PDF/undo/input/lifecycle e prove UI; documentare limiti fisici.

## Reattività e memoria - 2026-10-08
Status: FINALIZED
Ridurre lavoro per frame nello scorrimento senza cambiare input, palm rejection, zoom, livelli, audio o paginazione. Ridurre lavoro UI e duplicazioni nei salvataggi XOPP/PDF mantenendo contenuto, qualità e compatibilità. Cache native limitate con rilascio esplicito e callback tardivi innocui. Regressioni complete, misure riproducibili su dati sintetici e audit; non presentare misure desktop come prestazioni Android.

## Qualità PDF - 2026-10-08
Status: FINALIZED
Conservare nitidezza dei tratti esportati usando geometria vettoriale con pressione, trasparenza, tagli gomma e ordine livelli. Preservare contenuti misti e budget memoria del renderer. Regressioni export e audit; nessuna build APK.
