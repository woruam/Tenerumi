# Qualità PDF — 2026-10-08

## Causa e correzione
L’export precedente convertiva tutta la pagina in PNG con scala massima 2 (circa 144 dpi). Il PDF perdeva quindi la geometria originale disponibile nel file XOPP. La visualizzazione interna riduceva ulteriormente ogni pagina a un milione di pixel.

Il nuovo export conserva penna ed evidenziatore a mano libera come geometria PDF: stessi cerchi e quadrilateri della pressione usati dal canvas, riempimento unico per tratto, colori e opacità dell’evidenziatore. Le cancellature sono clip locali al tratto, con intersezione dei complementi delle primitive: tagli sovrapposti non fanno ricomparire l’inchiostro. L’ordine dei contenuti e dei livelli visibili è conservato.

Testi, formule, immagini e forme geometriche continuano a usare i painter esistenti per fedeltà. Le sequenze di questi contenuti vengono rasterizzate su sfondo trasparente, ritagliate agli ingombri effettivi e portate fino a scala 4 (288 dpi), entro quattro milioni di pixel e 4096 pixel per lato. I testi vengono misurati con lo stesso layout/font del painter, comprese righe multiple. Carta e sfondi esterni mantengono il raster limitato della pagina. La risoluzione originale di una fotografia o di un PDF già rasterizzato non può essere recuperata.

Il renderer interno ora divide quattro milioni di pixel fra le pagine montate, con scala massima 4. Cache PNG, serializzazione delle richieste e rilascio delle risorse rimangono invariati. L’assemblaggio e la compressione del PDF continuano nel worker; il codice UI cede periodicamente il controllo durante l’export. Codec, immagini, picture e misure del testo vengono rilasciati in finally; i dati vettoriali non introducono cache permanenti o listener.

## Verifiche
- Suite completa: 170 test passati, compresi input stylo, gesti, schede, audio, salvataggi e contenuti misti.
- Test del renderer con backend controllato: tre pagine dividono il budget di quattro milioni di pixel; export usa quattro milioni per pagina; tutte le pagine e i documenti nativi vengono chiusi, anche dopo sospensione durante apertura.
- Analisi dei file definitivi: nessun errore o warning; 22 informazioni sullo stile/import esistente.
- PDF campione riaperto con Poppler a 288 dpi e confrontato col canvas: geometria vettoriale presente (52 curve), sei clip gomma, opacità 0.5, livelli nascosti esclusi, pressione e ordine rispettati. Differenza media per canale inferiore a 0.28 su 255; campioni di colore entro due unità. Testo multilinea incluso.

Prova riproducibile: eseguire i test export e poi `docs/validation/check_pdf_quality.py` con Poppler, Pillow e pypdf disponibili. Artefatti e log in `docs/validation/pdf-quality-*`.

La visualizzazione interna resta raster e limitata in memoria: a ingrandimenti estremi può apparire meno nitida del canvas XOPP. La geometria dei nuovi PDF mantiene invece la nitidezza in lettori che renderizzano il vettoriale al livello di zoom richiesto. Prova su tablet Android reale ancora necessaria; nessun APK costruito. I PDF esportati prima della correzione vanno riesportati dalla nota XOPP per beneficiare del cambiamento.
