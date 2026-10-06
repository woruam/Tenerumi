# Divisore e geometria del documento

`SplitResizeScope` segnala il trascinamento del divisore ai canvas. Dal pointer down al rilascio/cancellazione i documenti ignorano i nuovi gesti; pan, pinch e doppio tap sono disabilitati. Ricreare il solo `InteractiveViewer` interrompe anche un'eventuale inerzia precedente senza sostituire il `TransformationController` del documento.

La larghezza della pagina resta stabile durante il drag: il pannello si ridimensiona ma il documento non ricalcola continuamente altezze e posizione delle pagine. Al termine si applica il nuovo fit alla larghezza, conservando la pagina e la frazione di pagina che si trovavano in cima alla vista. I margini e le distanze fra pagine rimangono costanti; zoom e contenuti non cambiano. Se la cima era nella distanza fra pagine, viene preservata la stessa distanza.

Il rapporto del divisore viene aggiornato a partire dal valore corrente del controller, evitando di perdere aggiornamenti quando arrivano più eventi prima di un frame. Lo split verticale conserva la larghezza delle pagine e non produce alcun reflow orizzontale.

`split_resize_test.dart` esercita canvas reali in entrambe le orientazioni: verifica matrice e geometria congelate durante il drag, ripristino delle gesture e posizione logica conservata dopo il rilascio. Il test puro include pagine con proporzioni diverse.
