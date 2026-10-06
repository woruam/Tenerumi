# Penna e gomma pixel

Il tratto libero definitivo usa la stessa geometria arrotondata dell'anteprima:
capsule incrementali con pressione, senza ricostruzione diversa al rilascio.
Le cache sono limitate a 64 tratti e 25.000 campioni per cache.

La gomma pixel sottrae una punta circolare lungo il segmento tra gli eventi
ricevuti, anche quando il tratto contiene solo due punti distanti. Cancella
tutti i tratti sovrapposti nell'area attraversata senza coprire il PDF o altri
contenuti. Il valore Grandezza Gomma indica il diametro: il raggio e' meta'.
Una gesture produce una sola operazione annullabile; il reset funziona anche
su cancellazione dell'evento e sulle gomme hardware o attivate dal pulsante.

I tagli sono dati geometrici indipendenti nei documenti e negli snapshot,
trasformati insieme al tratto. Il parser conserva anche le proprieta' delle
forme. Le pagine PDF esportate con tagli usano un layer inchiostro trasparente
rasterizzato, fino a 2x e 4096 pixel sul lato maggiore, per conservare le
cancellazioni; gli altri limiti dell'esportazione storica restano in TESTING.md.

## Portabilita'

L'app salva i tagli nell'attributo `osipp-erasures` dei tratti .xopp. La riapertura
in questa app conserva le cancellazioni. Xournal++ desktop e altri editor che
ignorano questa estensione potrebbero mostrare l'inchiostro originale; usare
l'esportazione PDF per condividere il risultato visivo delle cancellazioni.

## Regressioni senza build dell'app

```powershell
flutter test --no-pub test/ink_round_continuity_test.dart test/pixel_eraser_test.dart test/ink_preview_test.dart test/pointer_input_test.dart
```

Quattro nuovi test confrontano la rasterizzazione della penna/evidenziatore
prima e dopo il rilascio, estremita' arrotondate e invalidazione della cache.
Otto nuovi test coprono punta circolare, segmenti radi, sweep, sovrapposizioni,
bordi del tratto, undo/redo, salvataggio/riapertura, trasformazioni, sfondo e
gesti reali down/move/up/cancel. Generano le immagini
`docs/validation/ink-round-continuity.png` e `pixel-eraser.png` durante l'esecuzione.

I nuovi test e le immagini non sono stati eseguiti/generati in questa sessione:
Flutter richiede accesso alla cache dell'SDK esterna al workspace e la richiesta
di autorizzazione e' stata rifiutata. Nessuna build dell'app e' stata eseguita.
Il controllo della sintassi e la formattazione dei nove file Dart sono riusciti.
L'analisi statica di `lib` e `test` e' riuscita senza errori o warning;
rimangono informazioni sullo stile. Il log e'
`docs/validation/ink-eraser-analyze.txt`. Non sostituisce i test di rendering.
