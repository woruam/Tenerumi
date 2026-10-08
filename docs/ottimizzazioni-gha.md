# Interventi G, H e A — completati il 9 ottobre 2026

Implementati nell’ordine richiesto su `main`. L’analisi originale rimane riferita allo snapshot 1d1baa7; le sue misure di provenienza non sono state ricalcolate retroattivamente.

## G — rimozione del legacy

Verificati i riferimenti nel codice, nei test e negli entrypoint. Rimossi 11 file non raggiunti dal grafo di import: i tre adattatori `conditional/open_file/*` e otto widget obsoleti. Rimossi anche `XppPageContentWidget`, il contratto `XppContent.render()` e i quattro metodi che restituivano esclusivamente segnaposto. Il rendering corrente usa già `paintToCanvas()` e rimane quello attivo. Le preview degli sfondi tramite `XppBackground.render()` sono conservate.

Eliminato `RichTextField`, mai istanziato: il suo controller e FocusNode privi di dispose non possono essere riattivati accidentalmente. La vecchia bottom sheet è stata rimossa nella fase H dopo aver trasferito l’unico simbolo ancora utilizzato, `EditingTool`.

Beneficio: meno codice obsoleto e percorsi duplicati da mantenere. Non viene attribuito un aumento di FPS alla sola rimozione del codice inattivo.

## H — modello strumenti

`EditingTool` è ora in `lib/src/editing_tool.dart`, senza import Flutter o dipendenze dai widget. Sono conservati ordine e nomi delle 17 identità. I consumer e i test importano il modulo di dominio; l’interfaccia corrente degli strumenti continua a funzionare.

Penna, evidenziatore e whiteout usano le proprietà ereditate da `XppStroke`, evitando la duplicazione di `tool`, `points`, `color` ed `editingTool`. Restano le stesse firme dei costruttori, proprietà mutabili e factory `newStroke()`. È preservato anche il default **osservabile** precedente `editingTool == null`: i vecchi campi nelle sottoclassi nascondevano il valore assegnato dal costruttore della base. Non è stata introdotta una modifica silenziosa a questo comportamento.

Verificati clone profondo dei punti, tipo concreto, proprietà modificate, XML, forme e tagli gomma. Le immagini e gli allegati rimangono condivisi come prima; nessuna modifica al formato file.

## A — geometria in un passaggio

`getOffset()` e `bottomRight` calcolano entrambe le coordinate in un unico passaggio invece di due. Per tratti a mano libera e forme non smussate, `bounds()` raccoglie minimi, massimi e raggio massimo nello stesso passaggio invece di cinque. Sono preservate le regole di pressione e larghezza, comprese quelle dell’evidenziatore.

Il ramo delle forme curve resta identico: mantiene il calcolo del percorso Bézier, la sua eventuale estensione oltre i punti e l’inflazione dello spessore. Non è stata aggiunta alcuna cache: sostituire un punto, aggiungerlo alla lista, tradurre o ridimensionare il tratto viene osservato al calcolo successivo, senza invalidazioni o risorse persistenti aggiuntive.

La prova su una lista strumentata di 10.000 campioni registra **50.002 accessi** per l’oracolo di riferimento a cinque scansioni e **10.001 accessi** per il nuovo `bounds()`, con rettangolo identico: circa l’80% di accessi in meno. Il conteggio riguarda gli accessi alla lista nel test, non un tempo CPU o un incremento di FPS su Android.

## Verifiche

- Fase G: 13 test input/export passati.
- Fase H: 27 test modello, selezione, gomma e audio passati.
- Fase A: 16 test geometria, gomma a zoom e selezione passati.
- Suite completa finale: **174 test passati**. Comprende stylo, palm rejection, zoom, pressione, gomma, undo/redo, livelli, pagine, schede/sessione, plugin, registrazione/ascolto e salvataggi/export.
- Confronto geometrico deterministico: 360 configurazioni distribuite fra tutti gli strumenti e forme, verificate prima/dopo traslazione, scala, sostituzione e aggiunta di punti; null/vuoti e forme curve inclusi.
- Analisi `lib test`: nessun errore o warning; 180 informazioni di stile del codice rimasto.
- PDF esportato riaperto con Poppler a 288 dpi: 52 curve vettoriali, sei clip gomma, opacità dell’evidenziatore e campioni di colore conservati. Confronto col canvas riuscito.

Log e dati riproducibili: `docs/validation/gha-*.txt`, `gha-point-visits.json`; casi di regressione in `test/stroke_model_geometry_test.dart`.

## Ambito e limiti

B, C, D, E, F, I e J non sono stati implementati. Non sono state cambiate invalidazioni delle miniature, cache dei tratti o delle immagini, formato/storico undo, serializzazione degli allegati, carta del PDF o gestione degli handle thumbnail. Nessun APK o push. Il miglioramento di fluidità percepita sul tablet resta da misurare in profile/release su hardware reale; questo intervento dimostra equivalenza funzionale nei test e riduzione strutturale del lavoro geometrico.
