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
