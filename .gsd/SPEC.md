Status: FINALIZED

Correggere le criticità operative richieste: culling canvas, PDF su richiesta con cache limitata e associazioni persistenti, salvataggi sicuri, protezione di tutte le schede, input touch configurabile, compatibilità Web, griglia responsive, serializzazione asincrona. Test di regressione e istruzioni ripetibili per gli agent.

Status: FINALIZED
Follow-up: separare drag divisore e gesture documenti preservando posizione/zoom; ridurre latenza anteprima penna senza perdere campioni; richiedere refresh massimo a risoluzione costante su Android; menu toolbar Salva/Apri file sul documento con focus; aggiornare toolchain Android compatibile con SDK locale e verificare warning residui.

## Seguito penna e gomma - 2026-10-06
Status: FINALIZED
Il tratto definitivo deve conservare la geometria arrotondata dell'anteprima, pressione e campioni. La gomma pixel cancella l'area effettiva anche fra campioni radi, con salvataggio e undo/redo. Aggiungere test e prove visive. Nessuna build autorizzata.
