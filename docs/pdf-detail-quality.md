# Nitidezza PDF e README OSI — 9 ottobre 2026

## Problema e correzione

L’export precedente manteneva vettoriali i tratti a mano libera, ma rasterizzava carta, forme e testo. Inoltre il lettore ingrandiva sempre lo stesso bitmap della pagina, anche quando il PDF conteneva tracciati vettoriali nitidi.

Ora i tratti, compresi whiteout, forme poligonali e curve Catmull–Rom, sono vettoriali. Rimangono pressione, colore, opacità dell’evidenziatore, cancellature locali sovrapposte e ordine dei layer visibili. Le immagini inserite e gli sfondi immagine utilizzano direttamente i dati originali senza una seconda rasterizzazione della pagina.

I fogli semplici, a righe, a quadretti e i due modelli OSI utilizzano geometria vettoriale. Il puntinato classico resta raster con un budget: il modello storico ha circa 160.000 punti su A4 e generarli separatamente appesantirebbe l’export. Non è stata cambiata la sua spaziatura.

Il testo latino con Inter, Open Sans e VT323 usa font incorporati, con linee e baseline misurate dal renderer Flutter. Su Android il testo Sans/Roboto può incorporare il font di sistema `/system/fonts/Roboto-Regular.ttf`: se non è leggibile, l’export conserva il fallback raster. Caricamento e disponibilità dei font sono memorizzati solo per la singola esportazione. Font sconosciuti, tabulazioni e caratteri non coperti dal percorso vettoriale mantengono il fallback per conservare la resa. La rasterizzazione dei glifi può differire leggermente tra Flutter e un lettore PDF.

## Zoom e risorse

Il lettore nativo aggiorna il dettaglio dopo 180 ms di pausa nei movimenti, alla densità di pixel del dispositivo. Renderizza soltanto la regione visibile, con un piccolo margine, tramite `PdfPageTexture.updateRect`. Non usa il ritaglio di `PdfPage.render`, che su Android prima alloca un’immagine dell’intera pagina.

Ogni dettaglio è limitato a circa 2 milioni di pixel e 2048 pixel per lato. Durante una sostituzione può esistere anche il dettaglio precedente (circa 16 MiB complessivi di pixel RGBA nel caso limite per pagina, oltre al bitmap base e alle risorse del plugin). I limiti possono ridurre il dettaglio su schermi molto grandi: non vengono allocati bitmap proporzionali al quadrato dello zoom.

Il documento di dettaglio è indipendente dalla coda del bitmap base. La pagina sorgente viene chiusa prima dell’aggiornamento della texture. Risultati superati da un nuovo zoom o dalla chiusura vengono scartati e liberati. Timer, listener, observer, texture correnti e sostituite e documenti vengono rilasciati; il rilascio prosegue anche se la texture nativa produce un errore. In background vengono liberati i dettagli, che vengono ricreati al ritorno. Il dettaglio è `IgnorePointer` e non aggiunge gesti alla penna. Sulle piattaforme senza texture resta il bitmap base.

## Limiti

Il contenuto originale dei PDF importati viene ancora rasterizzato nell’export, con il budget già presente di 4 milioni di pixel. Le scansioni e le immagini non acquistano informazioni mancanti. Formule e fallback raster non restano nitidi a ingrandimento illimitato. Una conservazione vettoriale dei PDF importati richiede un percorso dedicato di importazione delle loro risorse PDF, assente nell’attuale libreria di generazione.

Per beneficiare del nuovo export occorre riesportare il documento `.xopp`; un vecchio PDF sfocato non può essere ricostruito automaticamente. Non è stata eseguita una profilazione su un tablet Android reale né prodotta una nuova APK.

## Verifica

- Suite completa Flutter (179 test) e analisi statica (nessun errore o warning, 180 info preesistenti): risultati in `validation/pdf-detail-full-tests.txt` e `validation/pdf-detail-analyze-verified.txt`.
- Test dello zoom: budget anche a zoom 100 con densità 4, debounce, rendering per regione, chiusura della pagina prima dell’update, sospensione/ripresa e chiusura durante rendering con errore di rilascio.
- Export: fixture con pressione, evidenziatore, erasure sovrapposte, layer nascosto; fixture con carta, poligono, curva e testo accentato. Quest’ultima non contiene immagini PDF; il testo è estraibile. Un’immagine 8×8 mantiene la risoluzione 8×8 nell’export.
- Confronto indipendente Poppler a 288 dpi con il canvas Flutter e controlli pypdf: `validation/check_pdf_quality.py` e `validation/check_pdf_vector_shapes.py`, con JSON e immagini nella stessa cartella. Controlli su colori, cancellature e ordine passati; nessuna soglia è stata allentata nel confronto precedente.
- README riscritto per OSI 0.5.0+31, con funzioni, limiti audio/PDF, requisiti e comandi di build attuali, attribuzione e licenza. Rimosse indicazioni di download/store, badge e istruzioni del progetto upstream.
