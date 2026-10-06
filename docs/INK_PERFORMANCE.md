# Scrittura e latenza

L'anteprima della penna aggiorna soltanto il proprio layer di pittura. Ogni evento aggiunge un segmento al percorso, senza ricostruire i widget della pagina e senza ricalcolare l'intera geometria con `perfect_freehand`. Flutter raggruppa le richieste di pittura nello stesso frame: gli eventi ricevuti rimangono tutti nel tratto salvato, anche quando la penna produce più campioni dei frame disponibili.

L'anteprima e il tratto definitivo condividono la stessa geometria di capsule con estremità e giunzioni arrotondate e la stessa curva di raggio dipendente dalla pressione. Al rilascio non si ricostruisce più un outline diverso con `perfect_freehand`: i campioni mantengono la stessa forma visibile. Le forme geometriche esplicitamente selezionate conservano il loro rendering dedicato. L'evidenziatore viene disegnato con un unico riempimento per evitare accumuli di trasparenza fra segmenti sovrapposti.

## Regressioni

`flutter test test/ink_preview_test.dart test/pointer_input_test.dart`

Il test invia 400 campioni in 10 frame simulati da 8,333 ms, verifica che il delegate di pittura rimanga identico, che pressione e campioni rimangano nel documento e che l'annullamento ripulisca il tratto senza salvare punti obsoleti. È una verifica del comportamento, non un benchmark del dispositivo.

## Prove sul dispositivo

Usare una build profile, scegliere 90/120 Hz nelle impostazioni del dispositivo, provare tratti lunghi a pressione variabile su pagina vuota e PDF, poi in split screen. Osservare i frame UI/raster in Flutter DevTools; a 120 Hz il budget di un frame è circa 8,33 ms, a 90 Hz circa 11,11 ms. Confrontare traiettoria della punta e tratto, palmo, pinch e pulsanti della penna. Ripetere con risparmio energetico acceso e spento.

Non vengono inventati campioni mancanti, né usati campioni predittivi o una superficie nativa Android front-buffer. Sono conservati gli eventi consegnati dal motore Flutter; driver, pannello, motore e compositore contribuiscono alla latenza. Il percorso ancora deve essere rasterizzato e cresce con la lunghezza del tratto. Una richiesta di refresh elevato non garantisce 120 fps: il sistema può limitare la modalità e il rispetto del budget richiede misure su hardware reale.
