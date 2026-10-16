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

## Reattività e memoria
1. Stabilizzare widget/painter delle pagine durante pan/zoom.
2. Compressione e assemblaggio export fuori UI; riuso checkpoint valido.
3. Immagini native limitate e rilascio listener/codec/callback.
4. Regressioni, benchmark, analisi e audit; commit.

Reattività e memoria: fasi 1–4 completate. 169 regressioni, benchmark strutturale/compressione, analyze senza errori/warning, Kotlin riuscito. Audit docs/performance-and-memory.md; misure Android hardware restano manuali.

## Qualità PDF
1. Export ibrido: inchiostro vettoriale e fallback fedele per contenuti speciali.
2. Migliorare risoluzione PDF visibile entro budget esistenti.
3. Regressioni, analisi e documentazione; commit.

Qualità PDF: fasi 1–3 completate e verificate; confronto indipendente PDF/canvas, suite completa e audit docs/pdf-quality.md.

## Analisi provenienza e ottimizzazioni
1. Identificare upstream e misurare file/righe/token.
2. Esaminare percorsi critici e semplificazioni senza regressioni.
3. Rapporto Markdown, dati riproducibili e verifica documentale; commit.

Analisi provenienza: fasi 1–3 completate; dati upstream acquisiti, rapporto e inventario verificati. Nessuna modifica all’app.

## Interventi G, H, A
1. G: controllare riferimenti e rimuovere componenti/adattatori legacy, placeholder render e RichTextField inattivo.
2. H: spostare EditingTool nel dominio, migrare import e unificare proprietà preservando semantica osservabile.
3. A: minimi/massimi/raggio con singolo passaggio; nessuna nuova cache.
4. Regressioni, misura strutturale, analisi e documentazione.

G/H/A: fasi 1–4 completate nell’ordine richiesto. Regressioni complete, misura strutturale e audit verificati.

## Nitidezza PDF e README OSI
1. Rendere vettoriali carta/forme/testi supportati e conservare immagini originali.
2. Vista PDF con dettaglio adattato al viewport, debounced e limitato.
3. README OSI e documentazione risultati.
4. Regressioni, analisi, compilazione native se necessaria e confronto Poppler; commit.

Nitidezza PDF/README: fasi 1–4 completate; export e viewport verificati, risorse native testate e limitazioni documentate.

## Esperienza di scrittura e navigazione — 2026-10-16
1. Analizzare gesti, geometria inchiostro, lifecycle schede e integrazione sistema.
2. Correggere penna minima, doppio tocco e dimensioni del menu incolla.
3. Aggiungere scorrimento rapido opzionale e contorno configurabile.
4. Conservare raster e immagini decodificate delle schede recenti con budget limitato.
5. Integrare apertura PDF dal sistema e progresso nell'icona Pomodoro.
6. Verificare regressioni, analisi, build Android e revisione indipendente.

Esperienza scrittura/navigazione: fasi 1–6 completate; 47 test mirati passati,
analisi senza errori/warning, APK Android finale compilato e revisione approvata.
Errore di serializzazione preesistente e limiti delle prove native documentati
in docs/validation/experience-status.md.

## Distribuzione essenziale e correzione testo XOPP — 2026-10-16
1. Esplorare raggiungibilità startup/UI e dipendenze native sperimentali.
2. Introdurre flag compile-time disattivati di default, mantenendo Pomodoro
   come plugin escluso dalla versione pubblica.
3. Escludere sorgenti/dipendenze OCR native, preservando dati e servizi base.
4. Correggere serializzazione testo/formule XOPP e testare i round-trip.
5. Allineare CI, test nei due profili, README e istruzioni.
6. Compilare release firmata e verificare codice incluso, firma e revisione.

Fasi 1–6 completate; suite pubblica e sperimentale superate, release ARM64
firmata con audit AOT/nativo. Risultati in docs/validation/release-profile-status.md.
