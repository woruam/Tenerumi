# Libreria grigia e schede non cliccabili - 2026-10-08

## Causa riprodotta
All'avvio reale S.load imposta Intl.defaultLocale ma non carica i simboli date. documentModifiedLabel usava DateFormat senza inizializzazione: LocaleDataException durante la costruzione della DocumentLibraryCard quando modifiedAt era presente. Le nuove note acquisiscono subito una data; quelle precedenti la ricevono dal caricamento metadati. La scheda non viene costruita e quindi non può mostrare anteprima o rispondere al tap; in release gli ErrorWidget appaiono grigi.

La precedente verifica visiva inizializzava tutte le date solo nel test, mascherando l'errore. Rimossa quell'inizializzazione: il test fallisce prima della correzione, con 8 eccezioni nelle schede (library-grey-reproduction.txt).

## Correzione
Il formato numerico fisso dd/MM/yyyy HH:mm viene costruito direttamente da DateTime.toLocal(), con padding numerico. Nessun caricamento globale, rete o lavoro asincrono aggiuntivo. Rimangono invariati formato, timezone locale, gestione data mancante/non valida, archiviazione documenti e tema.

## Verifica
17 test mirati passati: regressioni libreria/anteprime, tema Pomodoro senza inizializzazione date speciale, date sotto en/de/pt/it_IT, percorso reale di avvio e riapertura.
La nuova regressione prepara un vecchio .xopp senza metadati anteprima, ne attende il caricamento lazy, lo apre e verifica contenuto e origine; crea una nota dalla home, aggiunge un tratto, salva tramite menu, riavvia l'app e riapre il file persistito. Verificati assenza ErrorWidget, due immagini effettivamente decodificate, pixel rossi della preview salvata e tratto riaperto. Screenshot home e nota controllati visivamente.
Analisi complessiva senza errori/warning; informazioni sullo stile storico. Analisi finale dei file modificati nel log library-grey-final-analyze.txt. git diff --check superato.

## Limiti
Riproduzione e correzione verificate con Flutter su host, non con l'APK sul telefono. Per applicare la correzione al dispositivo occorre ricompilare e reinstallare l'APK aggiornato. Non è stata eseguita una nuova build APK.
