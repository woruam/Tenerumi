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
