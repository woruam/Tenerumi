# Penna e gomma pixel

Il tratto libero definitivo usa la stessa geometria arrotondata dell'anteprima:
capsule incrementali con pressione, senza ricostruzione diversa al rilascio.
La cache dell'inchiostro e' limitata a 64 tratti e 25.000 campioni.

La gomma pixel sottrae una punta circolare lungo il segmento tra gli eventi
ricevuti, anche quando il tratto contiene solo due punti distanti. Cancella
tutti i tratti sovrapposti nell'area attraversata senza coprire il PDF o altri
contenuti. Il valore Grandezza Gomma indica il diametro: il raggio e' meta'.
Una gesture produce una sola operazione annullabile; il reset funziona anche
su cancellazione dell'evento e sulle gomme hardware o attivate dal pulsante.

Il rendering dei tratti cancellati usa una maschera alpha `dstOut` su un layer
isolato per il singolo tratto e limitato alla clip visibile. Non usa `Path.combine`
ne' conserva le geometrie native delle versioni precedenti dei tagli: evita il
costo crescente delle operazioni booleane che poteva bloccare il thread principale.
La maschera non tocca il PDF o gli altri contenuti; include solo i tagli visibili.
Tagli rettilinei consecutivi vengono compattati senza approssimare le curve;
i contatti ripetuti nella stessa area non aggiungono tagli identici. I punti
rimangono condivisi durante la cancellazione e vengono copiati prima di
trasformarli. I rettangoli dei tratti sono memorizzati soltanto durante il gesto.
Ogni modifica notifica esplicitamente il painter del layer e invalida il suo
contenuto anche se la pagina e il layer mantengono la stessa identita'. Lo zoom
e la posizione della pagina non devono cambiare per mostrare le cancellazioni.

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
flutter test --no-pub test/eraser_zoom_repaint_test.dart
flutter test --no-pub test/eraser_stability_test.dart
```

Quattro nuovi test confrontano la rasterizzazione della penna/evidenziatore
prima e dopo il rilascio, estremita' arrotondate e invalidazione della cache.
Otto nuovi test coprono punta circolare, segmenti radi, sweep, sovrapposizioni,
bordi del tratto, undo/redo, salvataggio/riapertura, trasformazioni, sfondo e
gesti reali down/move/up/cancel. Generano le immagini
`docs/validation/ink-round-continuity.png` e `pixel-eraser.png` durante l'esecuzione.
Tre regressioni aggiuntive verificano il primo frame di cancellazione a zoom
fisso 1x, 2,5x e 5x mentre la penna e' ancora appoggiata, due gesti successivi e
undo. Generano `eraser-zoom-1.0.png`, `eraser-zoom-2.5.png`, `eraser-zoom-5.0.png`.

I nuovi test e le immagini non sono stati eseguiti/generati in questa sessione:
Flutter richiede accesso alla cache dell'SDK esterna al workspace e la richiesta
di autorizzazione e' stata rifiutata. Nessuna build dell'app e' stata eseguita.
Il controllo della sintassi e la formattazione dei nove file Dart sono riusciti.
L'analisi statica di `lib` e `test` e' riuscita senza errori o warning;
rimangono informazioni sullo stile. Il log e'
`docs/validation/ink-eraser-analyze.txt`. Non sostituisce i test di rendering.
