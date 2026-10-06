# Stato della correzione operativa — 2026-10-06

SPEC finalizzata; wave implementazione e integrazione completate.

## Modifiche

- Canvas con culling nelle coordinate della scena e dimensioni del pannello; zoom conservato fra schede; dispose esplicito.
- Raster PDF su richiesta, coda seriale, cache limitata, risultati obsoleti ignorati, risorse PDF chiuse in finally, allegati e associazioni per pagina persistenti.
- Percorsi multipiattaforma e origine conservata; salvataggio atomico, asincrono, con esito esplicito; modifiche successive allo snapshot restano pendenti; titoli duplicati separati.
- Protezione di ogni scheda con PopScope e prompt indipendenti dal montaggio del canvas.
- Disegno touch configurabile e pinch senza tratti accidentali; penna hardware instradata al listener interagito.
- Undo/redo con snapshot profondi; parser corretto per indici sparsi, whitespace, numerazione PDF ed entità testuali.
- Griglia responsive, configurazione Web, suite e script di verifica.

## Prove

30 test passati nella suite completa. Build Web JavaScript riuscita. Analisi senza errori/avvisi; rimangono informazioni sullo stile del codice storico. Screenshot della libreria a 380dp in docs/validation/open-page-phone.png. I log e il collaudo dello script sono in docs/validation/.

## Limiti e prossime verifiche

Consultare docs/TESTING.md per interoperabilità degli allegati con Xournal++ desktop, worker Web, fedeltà dell'esportazione PDF e prove su hardware. Non è presente .git, quindi non sono stati prodotti commit. Non considerare i test di culling una misura del picco memoria Android.

## Seguito: split, penna, toolbar e Android

Implementati blocco delle gesture e reflow ancorato durante il ridimensionamento
split, anteprima incrementale della penna, menu impostazioni con Salva/Apri file,
richiesta del refresh massimo e dispatch non bufferizzato dello stilo su Android.
Aggiornati AGP/Kotlin e plugin; rimosso printing inutilizzato, origine dei warning
Java 8. Adattata la nuova palette dynamic_color a ThemeData Flutter.

Suite aggiornata: 42 test superati. Analisi: nessun errore o warning, 215 informazioni
sullo stile. Dipendenze finali risolte. Le richieste di autorizzazione per APK e
Web finali sono state rifiutate; build finali e test JVM non verificati. I risultati
Web precedenti sopra indicati non certificano questa revisione. Stato dettagliato
in docs/validation/followup-status.md; procedure in docs/TESTING.md e
docs/ANDROID_PERFORMANCE.md. Misure su dispositivo ancora necessarie per latenza
e refresh effettivo. Il warning futuro KGP rimane con Flutter 3.44.1; la migrazione
ufficiale richiede Flutter 3.47+ e AGP 9+.
