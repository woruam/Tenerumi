# Gomma sotto zoom — 2026-10-06

Sintomo confermato dall'utente: basta spostare la pagina o ridurre lo zoom per
vedere la cancellazione gia' effettuata, senza ripassare con la gomma.

Modifiche:

- Il tratto cancellato viene disegnato come inchiostro residuo, senza clipPath
  dell'inchiostro originale. Geometria e maschere restano in coordinate pagina.
- XppPageStack notifica direttamente il repaint del painter dopo le modifiche.
- didUpdateWidget sincronizza il modello di pagina e il rendering dello sfondo.
- Tre test raster predisposti a zoom fisso 1x, 2,5x, 5x verificano aggiornamento
  al primo frame, due gesti, undo e matrice invariata.

Nessuna build eseguita. Test e immagini non eseguiti/generati: resta valido il
precedente rifiuto dell'accesso alla cache SDK richiesto dal runner Flutter.
Formattazione/parser Dart riusciti e analisi statica di lib/test completata
con exit 0, senza errori o warning (restano informazioni sullo stile).
Log in `eraser-zoom-format.txt` e `eraser-zoom-analyze.txt`.
Corretto anche il colore della fixture raster precedente: il blu usato nei test
ora corrisponde ai valori RGBA attesi, evitando un falso fallimento.
