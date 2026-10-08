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

## Audio sincronizzato
1. Metadati immutabili e persistenza XOPP.
2. Backend Android e coordinamento lifecycle; associazione input e playback.
3. Pannello audio e overlay isolato.
4. Regressioni, prova visiva e audit risorse; commit.

Audio sincronizzato: completate le fasi 1–4; 147 test, Kotlin Android, analyze e prova visiva verificati. Profilazione hardware e prova microfono reale restano manuali, come documentato nell’audit.

## Eliminazione home
1. Menu su pressione prolungata e conferma.
2. Eliminazione storage/indice serializzata e refresh.
3. Test cancellazione/annullamento/errori/URI e prova visiva; commit.

Eliminazione home: fasi 1–3 completate e verificate con 150 test, analyze, compilazione Kotlin e screenshot.

## Navigazione workspace
1. Modello pagine/inserimento/auto-generazione, limiti audio e piccoli miglioramenti UI.
2. Side panel livelli/pagine e apertura libreria interna.
3. Gesti con palm rejection e persistenza sessione.
4. Test, compile, screenshot e audit regressioni; commit.

Navigazione workspace: fasi 1–4 completate. 161 test Flutter, compilazione Kotlin Android, analisi senza errori/warning e screenshot desktop/telefono; audit docs/workspace-navigation.md. Profilazione hardware e registrazione lunga rimangono prove manuali.
