Wave 1: storage e serializzazione; navigazione e input; rendering e PDF (attività indipendenti).
Wave 2: integrazione, test unitari/widget, analisi e build Web.
Wave 3: documentare prove, limiti e ulteriori criticità.

Follow-up Wave 1: split/reflow; anteprima ink; toolbar; Android (indipendenti).
Wave 2: integrazione + regressioni + analisi + APK; documentare misure richieste su 90/120Hz.

## Seguito penna/gomma
Wave 1: geometria condivisa e gomma pixel persistente in parallelo, con test mirati.
Wave 2: integrazione, test Flutter e prove visive. Nessuna build.

## Gomma sotto zoom
Una wave: rendering sottratto e invalidazione layer; regressione raster con zoom fisso; analisi statica senza build. Test Flutter sospesi per precedente rifiuto cache SDK.

## Stabilita gomma
Una wave: sostituzione motore maschera e collisione, riduzione allocazioni; test stress predisposti e analisi statica. Nessuna build; runner test Flutter ancora bloccato da precedente rifiuto SDK.

## Dipendenze richieste
Singola fase: cinque constraint, controlli API/null safety, pub get, analyze e correzioni indotte. Nessuna build.

## Estetica Pomodoro
1. Centralizzare tema e superfici; uniformare componenti e rimuovere blur.
2. Verificare analisi, regressioni e screenshot; documentare limiti prestazioni.

## Libreria grigia dopo salvataggio
1. Riprodurre errore nel percorso di avvio reale con metadati data.
2. Correggere e verificare anteprime e riapertura persistita con regressioni e screenshot.

## Tag e identita OSI
1. Modello e persistenza tag, scelta/creazione/riassegnazione UI.
2. Branding OSI e Info app con versione reale.
3. Test di creazione, salvataggio, riapertura, filtri e screenshot.

Tag e identita OSI: implementazione e verifica completate (138 test e screenshot).
