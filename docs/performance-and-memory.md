# Reattività, export e memoria — 8 ottobre 2026

## Cause e modifiche

Durante ogni trasformazione VirtualPageColumn scansionava tutte le pagine e ricreava quelle visibili. Inoltre il painter dei livelli dichiarava sempre necessario ridipingere. Ora le posizioni vengono calcolate quando cambia il layout; una ricerca binaria individua il piccolo intervallo visibile. I widget cambiano solo entrando/uscendo dal viewport o per modifiche del documento. I callback vengono accorpati una volta per frame e non si ripetono per movimenti nello stesso intervallo. Il painter usa la revisione esplicita dell’inchiostro per gomma/undo/nuovi tratti; non ridipinge per una semplice ricostruzione del genitore. La percentuale di zoom si aggiorna separatamente dalla tela.

Il file XOPP mantiene gzip/XML e tutti i metadati. La compressione ora usa livello 1 e restituisce direttamente Uint8List, evitando due copie intermedie. È lossless, ma i file possono occupare più spazio. Se un checkpoint della stessa revisione e data è disponibile, Salva riusa i bytes e l’anteprima senza ripetere rasterizzazione/compressione. Se nel frattempo cambia il documento, manca il checkpoint o vanno incorporati PDF esterni, si prepara un nuovo snapshot. Errori di scrittura continuano a lasciare le modifiche da salvare; scritture locali restano temporanee/flush/rename, provider Android resta su task queue in background.

Per PDF l’assemblaggio, decodifica PNG e compressione PDF sono spostati in un worker, separato dall’interfaccia. La risoluzione dei fogli esportati rimane invariata (scala fino a 2×, budget 4 milioni di pixel). Le immagini vengono decodificate alla risoluzione necessaria al risultato, evitando originali enormi in memoria quando inutili. La pittura viene suddivisa con pause ogni 64 elementi per dare spazio agli eventi UI. Non cambiano livelli visibili, erasure, testi/formule, sfondi o ordine delle pagine.

Durante lo scorrimento lo stesso PDF sorgente resta aperto fra pagine adiacenti, anziché ricopiarlo e riaprirlo ogni volta. Si mantiene un solo handle per tela visibile, distinto da miniature e export. Anche l’export conserva un solo handle per sorgente consecutiva. Ogni pagina nativa viene chiusa prima della successiva; cambio documento, sospensione, errori ed export finale chiudono i documenti. Chiusure tardive attendono la coda di rendering senza interrompere una pagina in uso. Un’apertura completata dopo la sospensione non avvia un rendering superato.

## Audit risorse

XppImage manteneva ui.Image nel modello senza dispose e il caricamento iniziale registrava un ImageStreamListener senza rimuoverlo. Ora il caricamento legge soltanto le dimensioni tramite descriptor/buffer, rilasciati in finally, senza listener permanente né decodifica completa. Le immagini renderizzate appartengono a una cache della tela: dati sorgente come riferimenti deboli, decodifiche serializzate. Nell’editor si conserva la risoluzione originale, quindi lo zoom delle immagini non perde dettaglio; per export/anteprime la decodifica resta proporzionata all’output. Quando un’immagine è pronta il painter riceve un repaint: non occorre più muovere la pagina per togliere il placeholder.

Cache target 16 voci/32 MiB di pixel: si eliminano le risorse non in uso. Le immagini necessarie alle pagine montate sono protette dall’eviction, per evitare cicli di decodifica e placeholder su pagine con molte immagini. **Il target è morbido per il contenuto visibile**: molte immagini nella stessa pagina possono superarlo. Smontando una pagina si liberano gli handle non più usati; chiudendo l’ultima tela si svuota la cache. Descriptor, buffer, codec e risultati decodificati dopo una chiusura sono rilasciati esplicitamente. Il test conferma sia Image.debugDisposed sia mancata ricomparsa in cache dopo decode tardivo.

TextPainter di testo/formule viene ora rilasciato in finally; il controller del dialogo formula viene smaltito dopo la chiusura della route. Le code completate per recovery e PDF vengono azzerate a riposo. Non vengono conservati payload XOPP grandi come cache RAM aggiuntiva: il riuso legge il checkpoint su disco e conserva soltanto una piccola anteprima.

Non è una certificazione di assenza di qualsiasi leak o OOM. Rimangono cache raster/immagini di Flutter, snapshot undo, audio compresso e copie temporanee XML/base64/worker. La quota audio da 128 MiB non limita il picco totale di RAM. Il rendering richiede memoria per il contenuto visibile, specialmente foto grandi o molti fogli simultanei.

## Risultati riproducibili

- 169 test Flutter passati: input reale della stylo a zoom, pressione Incolla, gomma a 1×/2,5×/5×, audio, layer, PDF/export, schede, lifecycle e recupero. Nuove prove per immagini pronte senza movimento, dispose/cache/decode tardivi, riuso byte per byte del checkpoint e handle PDF condivisi/chiusi in ordine.
- Documento sintetico con 10.000 pagine, 300 piccoli pan: zero ricostruzioni aggiuntive delle pagine visibili, zero notifiche ripetute dell’intervallo. L’ingresso in un’altra pagina monta correttamente il nuovo foglio. Vedi docs/validation/performance-scroll.json.
- Compressione isolata, 25 pagine/2.500 tratti, mediana di 5 esecuzioni desktop JIT: livello 6 1322 µs, livello 1 530 µs (circa 2.5×). Gzip 3001 contro 6856 bytes; XML decompresso identico. Il contenuto molto ripetitivo rende questa misura un esempio, non una previsione dei tempi di file reali. Vedi docs/validation/performance-xopp.json.
- Analisi lib/test: nessun errore o warning; restano info di stile. Compilazione Android :app:compileDebugKotlin riuscita. Nessun APK o push.

## Verifica sul telefono

Non era disponibile un dispositivo Android collegato. Per misurare la fluidità usare build profile/release e osservare tempi UI/raster, non soltanto una build debug. Ripetere pan/zoom su note lunghe e PDF scansiti, registrare p50/p95 di save XOPP/PDF e profilo heap dopo cicli di apertura/chiusura. Provare anche più immagini visibili, note da 128 MiB audio e passaggio in background durante export. Le misure desktop sopra non rappresentano FPS, frame time o tempo totale Android.
