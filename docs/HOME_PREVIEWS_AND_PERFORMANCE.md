# Anteprime, ultima modifica e prestazioni

La home mostra nella scheda di ogni nota l'anteprima della prima pagina e la data di ultima modifica nel fuso orario locale, con formato giorno/mese/anno e ora. Le note nuove hanno una data fin dalla creazione; le modifiche al contenuto la aggiornano. Salvataggio e autosalvataggio persistono data e anteprima nel documento XOPP e nell'elenco dei recenti, conservando tag e preferiti.

Le anteprime includono sfondi, scrittura e livelli visibili. Per il canvas infinito viene ritagliata l'area occupata dai contenuti visibili. Il rendering funziona anche per documenti non montati nell'editor e limita l'immagine a 320 pixel sul lato maggiore e 100.000 pixel complessivi. Questi limiti riguardano solo le miniature: la qualità dell'esportazione PDF rimane invariata.

Per le vecchie note senza questi dati, la home legge i metadati e genera l'anteprima solo per le schede montate, un documento alla volta. La data contenuta nel documento ha precedenza; altrimenti viene usata la data del file, quando disponibile. Alcuni provider Android non espongono tale informazione: in questo caso appare "Data non disponibile". File o sfondi esterni non accessibili mantengono un'icona senza impedire l'apertura della home. La migrazione aggiorna l'elenco dei recenti senza riscrivere i documenti originali.

## Ottimizzazioni

- Il salvataggio congela una sola copia del documento prima delle operazioni asincrone e serializza quella stessa copia. Le modifiche successive non entrano accidentalmente nel salvataggio in corso.
- Le miniature vengono decodificate una volta per aggiornamento della scheda e la cache conserva fino a 32 risultati di metadati, senza trattenere documenti o risorse PDF aperte.
- Il canvas infinito riutilizza limiti geometrici e origini degli elementi durante pan e zoom. Una revisione del contenuto invalida la cache; spostamenti, gomma, undo e modifiche ai livelli continuano quindi a ridisegnare la geometria aggiornata.
- Gli scritti riutilizzano l'origine già calcolata durante il rendering, evitando una seconda scansione dei punti.

## Verifica

`test/library_preview_test.dart` verifica persistenza e snapshot, nuove note vuote, tag e preferiti, migrazione delle note, date dei provider Android, miniature PDF non montati, livelli nascosti e coordinate negative, layout su telefono e invalidazione della geometria. La suite comprende inoltre le regressioni esistenti su salvataggio concorrente, input, gomma, selezione, livelli, esportazione e plugin.

Nel test della cache, 100 richieste della stessa geometria effettuano un solo calcolo per revisione. Il test del canvas verifica che il pan non ripeta quel calcolo e che una modifica del contenuto lo invalidi. Questo misura il lavoro evitato, non gli FPS su un dispositivo reale.

Non sono state effettuate build dell'app. I risultati finali di test e analisi sono in `docs/validation/library-preview-status.md`.
