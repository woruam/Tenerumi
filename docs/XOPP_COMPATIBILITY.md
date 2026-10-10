# Compatibilità Xournal/Xournal++ e protezione degli originali

OSI scrive XOPP GZIP/XML con `fileversion="4"`. L’importazione non equivale a una implementazione completa del formato Xournal++.

| Contenuto | Comportamento OSI |
| --- | --- |
| Pagine finite, dimensioni e livelli | Importati entro le quote documentali; i livelli OSI possono avere nome, visibilità e blocco |
| Penna ed evidenziatore | Punti, larghezze, colore e geometria supportati; i tratti OSI possono includere forma, curve, maschere di cancellazione e collegamenti audio |
| Testo e immagini | Importati nei tipi del modello OSI; attributi ignoti rendono l’apertura protetta |
| Sfondi solidi supportati | Tinta, righe, griglia, punti e varianti OSI; uno stile sconosciuto viene segnalato |
| Sfondi PDF e pixmap | Riferimenti trattati come nomi di allegati, mai come autorizzazioni a leggere percorsi esterni. Per risorse mancanti occorre una selezione esplicita |
| Allegati incorporati OSI | Conservati in `pdf-attachment`; usati anche per rendere portabili gli sfondi |
| Cancellature Xournal, whiteout e strumenti sconosciuti | Non garantiti nel modello OSI: avviso e obbligo di salvare una copia |
| Elementi, attributi o versioni non supportati | Segnalati nel report di importazione; niente autosave sull’originale |
| Audio, flashcard, anteprima e metadati OSI | Estensioni applicative. Xournal/Xournal++ non sono tenuti a interpretarli. Un recupero parziale di audio o flashcard viene segnalato |

L’editor mostra gli avvisi e protegge il percorso di origine. Una copia salvata dall’editor contiene il modello che OSI è riuscita a interpretare; non promette un round trip completo degli elementi sconosciuti. Il backup con staging conserva invece i byte XOPP originali delle note compatibili con i requisiti di portabilità, incluse le parti non interpretate, e avvisa dell’apertura protetta. L’export PDF rappresenta il contenuto visualizzato da OSI e non conserva estensioni Xournal sconosciute.

`osipp-id` è un identificativo portabile. Non concede accesso a file, recuperi o audio locali. L’identità locale è generata sul dispositivo e conservata nell’archivio applicativo.

Le flashcard JSON sono un formato OSI per backup e modifica. Per Anki viene prodotto il bundle con testo UTF-8 separato da tab e media: il JSON OSI non viene presentato come formato nativo Anki.

Quando si aggiunge il supporto a un nuovo elemento, servono fixture XOPP, prove import/export, quote prima dell’allocazione e una decisione esplicita sulla conservazione degli attributi. Gli avvisi possono essere rimossi soltanto dopo aver verificato che il contenuto venga conservato.
