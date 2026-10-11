# Soluzioni applicate — ASTRA

Data: **10 ottobre 2026**. Riferimento: [ANALISIASTRA.MD](ANALISIASTRA.MD), analisi della revisione `4bb6aa05c2894f3f9cdfdc1e8863b23c1d0ac546`.

La prima fase riguarda **A01–A04**. La seconda fase, descritta dopo, comprende **A05–A15, A18, undo e autosave** secondo la richiesta successiva. Il rapporto originale conserva le evidenze della revisione precedente; questo file descrive le correzioni e le verifiche successive, senza dichiarare risolti i rilievi rimasti fuori ambito.

## A01 — Quote del runtime JSON

**Correzione applicata.** L'interpolazione costruisce una lista di segmenti e verifica la lunghezza cumulativa **prima** di concatenarli. Sorgente e risultato devono rispettare il limite di **65.536 caratteri**. Liste e mappe non vengono più convertite implicitamente in testo: una conversione ricorsiva potrebbe allocare una stringa enorme prima del controllo.

Il validatore condiviso conta i byte UTF-8 senza creare una seconda copia codificata delle stringhe. Risultati intermedi, letture `var`, contesto iniziale, assegnazioni `set`, variabili dei cicli e risultati delle azioni sono soggetti a quote. L'ambiente viene validato nella sua interezza prima di sostituire una variabile: **24 MiB contabilizzati, 100.000 nodi e profondità massima 64**. Gli argomenti delle API mantengono il limite precedente di 12 MiB.

Per gli aggregati il conteggio è incrementale, evitando di riesaminare tutta la lista dopo ogni aggiunta. Le occorrenze ripetute di una struttura condivisa contano ciascuna nel budget; il riferimento condiviso non consente di aggirare quote di nodi o profondità. Le liste/oggetti creati dalle espressioni hanno massimo 10.000 elementi. `join`, `replace` e `split` controllano la crescita prima dell'operazione. Restano attivi i limiti preesistenti di passi, tempo e annullamento.

Le stringhe dei dati restituiti dalle API possono essere più grandi del limite del testo, entro la quota complessiva: possono essere passate come valori tipizzati con `var`, ma non espanse tramite interpolazione. Questo mantiene utilizzabili i dati base64 delle funzioni di rendering/OCR.

**File principali:** [runtime](lib/plugins/plugin_runtime.dart), [validatore](lib/plugins/plugin_limits.dart).

**Regressioni:** il raddoppio di 40.000 caratteri viene rifiutato e la variabile precedente rimane intatta; conversioni di mappe, sostituzioni esplosive, split eccessivi, aggregati condivisi/profondi, ambiente con variabili multiple e risultati API eccessivi vengono rifiutati. Nessuna azione documentale è eseguita dalla prova di interpolazione.

## A02 — Letture, decompressione e parsing con budget

**Correzione applicata.** La lettura dei file avviene a blocchi, contando i byte effettivi prima di aggiungerli al buffer; il valore di dimensione dichiarato dal provider non è sufficiente. Per gli URI Android selezionati viene utilizzato il lettore nativo dell'app, che applica la quota durante la lettura. La stessa quota attraversa il canale Flutter ed è verificata anche sulla risposta. Lo storage locale e il fallback Web verificano rispettivamente stream e dati/base64.

È stato introdotto un decoder comune in [bounded_archive.dart](lib/src/bounded_archive.dart). Il limite viene controllato prima delle scritture dell'inflater, comprese le copie LZ77. Il GZIP usa esplicitamente il decoder Dart con verifica del checksum/trailer, anche sul Web; più membri GZIP condividono il budget di output.

Lo ZIP viene esaminato prima di qualunque espansione: indice centrale, numero e lunghezza dei metadati, header locali, coerenza dei nomi/flag/metodo, cifratura, tipo di file, duplicati e percorsi ammessi. Link e directory vengono respinti senza decodificarne il contenuto. Sono accettati soltanto STORE e DEFLATE; archivi multi-volume e ZIP64 vengono respinti. Le dimensioni dichiarate sono limiti preventivi, poi confrontati con dimensioni effettive e checksum. Nessuna voce viene estratta sul filesystem.

**Dettaglio rilevante della dipendenza:** il wrapper `ZLibDecoderWeb` costruiva internamente un buffer completo prima di copiarlo nel nostro output limitato. È stato sostituito con `Inflate.stream(..., output: outputLimitato)`, che scrive direttamente nell'output controllato. Anche [plugin_package.dart](lib/plugins/plugin_package.dart) utilizza ora questo decoder comune con le proprie quote precedenti; il blocco dei plugin JavaScript resta invariato.

Il parser XML legge eventi progressivi e materializza **un figlio della radice per volta**, per esempio una pagina, invece dell'intero DOM. Rifiuta DOCTYPE e strutture eccessive, contabilizza anche nodi sconosciuti e verifica il base64 prima di decodificarlo. Anteprime, allegati, immagini, audio e immagini delle flashcard partecipano al budget dei media. Gli allegati duplicati sono rifiutati. Il JSON di manifest/flashcard ha un controllo preventivo della profondità; la tolleranza dei campi opzionali corrotti rimane, ma non nasconde il superamento delle quote.

### Quote documentali

Le quote non sono configurabili dal documento o dal plugin; i parametri Dart sono riservati al codice host e ai test.

| Risorsa | Appunto singolo | Intero backup in lettura |
|---|---:|---:|
| File compresso selezionato | 128 MiB | ZIP 513 MiB |
| Output ZIP cumulativo | — | 512 MiB |
| XML GZIP espanso | 256 MiB | 512 MiB cumulativi |
| Media decodificati/riservati | 128 MiB | 256 MiB cumulativi |
| Eventi XML | 250.000 | 500.000 cumulativi |
| Pagine | 10.000 | 20.000 cumulative |
| Livelli | 50.000 | 100.000 cumulativi |
| Punti, incluse cancellature | 1.000.000 | 2.000.000 cumulativi |

La profondità XML massima è 16; quella del JSON opzionale/manifest è 32. Sono consentiti al massimo 32 attributi per elemento, con nomi fino a 128 caratteri e valori fino a 1 MiB. Il testo di un evento ordinario è limitato a 16 MiB; i payload media restano soggetti alle quote complessive. Il manifest ZIP ha massimo 8 MiB e sono ammesse soltanto `manifest.json` e `notes/<numero>.xopp`, con massimo 10.001 voci.

Decompressione e importazione hanno controlli cooperativi del tempo a 30 secondi; la verifica delle note di un backup controlla anche un budget cumulativo di due minuti. Il superamento interrompe il lavoro e non consegna alla UI un documento parziale. Questi controlli non interrompono istantaneamente un'operazione nativa o una lettura bloccata nel provider.

**File principali:** [quote/parser](lib/src/document_limits.dart), [importazione](lib/src/XppFile.dart), [backup](lib/src/note_backup.dart), [selettore](lib/src/compat/file_picker_cross.dart), [lettore Android](android/app/src/main/kotlin/online/xournal/mobile/DocumentStorage.kt).

**Regressioni:** GZIP da 1 MiB respinto con quota di 64 KiB, checksum/trailer corrotti, membri concatenati, ZIP con dimensioni false e link compresso, output che conserva la lunghezza precedente al tentativo di superamento, stream cancellato dopo l'eccesso, canale Android limitato, XML profondo/eccessivo, quote su pagine/livelli/punti/media e allegati duplicati.

## A03 — Geometria validata e griglie limitate

**Correzione applicata.** I numeri importati devono essere finiti e rientrare in intervalli espliciti. Le pagine devono avere dimensioni comprese tra **0,01 e 20.000 punti**, e il documento deve contenere almeno una pagina valida direttamente sotto la radice. Le coordinate sono comprese fra **−100.000 e +100.000**; gli spessori fra **0 e 1.000**; i font importati fra **0,01 e 1.000 punti**. Lo spessore zero rimane valido per i punti di pressione nulla. Le cancellature hanno coordinate validate e raggio positivo limitato.

Immagini e formule richiedono rettangoli coerenti. Il segnaposto storico delle formule OSI, `right=bottom=0`, viene riconosciuto e normalizzato in un rettangolo finito limitato, per mantenere riapribili i documenti prodotti dall'app. Tratti con coordinate dispari/incomplete, valori non finiti o quantità incoerenti di spessori vengono respinti.

Gli indici PDF vengono verificati sia nell'importazione sia rispetto al numero reale di pagine prima di `getPage`; le dimensioni native vengono validate prima del rendering o della creazione di texture, compreso lo zoom di dettaglio. Pagine e documenti nativi vengono chiusi nei blocchi `finally` anche in caso di rifiuto.

I pittori delle righe/griglie lavorano sull'area visibile intersecata con la pagina. Per le matrici di punti il passo aumenta quando necessario, con obiettivo di circa **180.000 primitive** nell'area disegnata. Il numero di righe delle griglie lineari è limitato anche dalle dimensioni ammesse in importazione. Un clip vuoto/non finito non alimenta i cicli.

**File principali:** [importazione](lib/src/XppFile.dart), [controlli PDF](lib/src/PdfImage.dart), [controller](lib/controllers/canvas_controller.dart), [texture PDF](lib/widgets/pdf_zoom_detail.dart), [sfondi](lib/src/XppBackground.dart).

**Regressioni:** NaN/infinito, zero/negativi e dimensioni grandi, testo/rettangoli/spessori/cancellature invalidi, coordinate dispari e pagine PDF fuori intervallo. Le coordinate negative valide e le formule legacy restano supportate. Un canvas di conteggio verifica il lavoro della griglia su una pagina 20.000 × 20.000 senza allocare un'immagine di quella dimensione.

## A04 — Riferimenti documentali senza autorizzazione al filesystem

**Correzione applicata.** `filename` degli sfondi è trattato come **chiave opaca di un allegato incorporato**. Apertura, rendering, preview, export e backup non trasformano questa chiave in un percorso da leggere, né richiamano un callback esterno fornito al parser. Sono stati rimossi anche il recupero PDF automatico per titolo dalle preferenze e il fallback su filesystem del vecchio widget PDF.

L'appunto con sfondo esterno mancante mostra **«Seleziona allegato di sfondo»**, anche sulla tela infinita. L'utente sceglie il file con il selettore; l'app incorpora i byte e riutilizza la chiave originale. Nel caso PDF viene controllata la presenza delle pagine richieste. L'associazione verifica che il documento/pagina non siano stati sostituiti durante il selettore e marca il documento come modificato. Dopo il salvataggio i byte viaggiano insieme all'appunto e al backup.

Non viene concessa una cartella autorizzata né conservato un percorso esterno da seguire in futuro: la risorsa selezionata viene incorporata. Non serve pertanto una risoluzione/canonicalizzazione di `..`, UNC, link o `content://` provenienti dal documento; tali stringhe non autorizzano alcuna lettura. Gli accessi espliciti ai documenti scelti e alla libreria dell'app rimangono disponibili.

Un backup segnala gli appunti con allegati mancanti nell'elenco degli elementi non disponibili; se nessun appunto è disponibile, non produce un backup. Per includere uno sfondo esterno bisogna associarlo e salvare la nota prima di creare il backup. I vecchi collegamenti PDF conservati soltanto per titolo richiedono una nuova selezione/importazione esplicita.

**File principali:** [controller](lib/controllers/canvas_controller.dart), [parser/associazione](lib/src/XppFile.dart), [editor](lib/pages/CanvasPage.dart), [sfondi](lib/src/XppBackground.dart), [backup](lib/src/note_backup.dart).

**Regressioni:** marker locale innocuo escluso dal backup, nessuna chiamata al callback per riferimenti assoluti/relativi/UNC/URI, pulsante presente nell'editor finito/infinito, risorsa esplicitamente associata conservata nel backup e riaperta senza consultare il file originario. Il test di trasferimento tra dispositivi usa ora un'associazione esplicita.

## Verifiche e limiti della prima fase A01–A04

- **233 test della suite completa superati**, inclusi **24 nuovi test A01–A04**: [log](docs/validation/astra-fix-full-test.txt).
- **63 test mirati superati** dopo l'ultimo affinamento del conteggio della profondità del runtime: [log](docs/validation/astra-fix-regressions.txt). Comprendono i probe originali A01–A04, ora trasformati in regressioni di rifiuto. I probe A06/A08/A10/A12 continuano a documentare difetti fuori ambito; il loro superamento non indica una correzione di quei difetti.
- Analisi Dart: **0 errori, 0 warning, 178 informazioni di stile/deprecazione**: [log](docs/validation/astra-fix-analyze.txt).
- Compilazioni **Android debug e Web riuscite**, incluso il dry run Wasm: [Android](docs/validation/astra-fix-android-build.txt), [Web](docs/validation/astra-fix-web-build.txt). Android segnala gli aggiornamenti futuri richiesti per Gradle/AGP/Kotlin; le versioni non sono state cambiate in questo intervento. Non è stata eseguita una prova dell'app su dispositivo fisico o nel browser.
- Un'esecuzione intermedia della suite ha incontrato il blocco Windows di una PNG generata dal test Pomodoro (errore 1224); il [log diagnostico](docs/validation/astra-fix-full-test-diagnostic.txt) è conservato. La ripetizione in sequenza ha superato tutti i test. Il test Pomodoro e la sua funzione applicativa non sono stati modificati.

Le quote descrivono dati espansi/strutture contabilizzate, **non un tetto alla RAM del processo**. Buffer, stringhe UTF-16, DOM di una pagina, copie tra isolate e risorse native possono coesistere. Non sono stati eseguiti OOM intenzionali, profili heap su telefoni, fuzzing prolungato o prove su provider Android cloud reali. A08 e A18 non erano compresi nella prima fase; gli interventi successivi sono descritti sotto. Il parser progressivo evita il DOM completo ma conserva ancora in memoria il testo XML entro la quota.

Per le modifiche future: applicare le quote prima delle allocazioni, contare anche gli output effettivi e tutti gli strati annidati, mantenere separate le chiavi importate dalle autorizzazioni locali, validare geometria e indici prima delle API native, chiudere risorse nei percorsi d'errore e mantenere le regressioni ostili. Le quote vanno calibrate con misure su dispositivi reali senza trasformarle in preferenze controllabili dal plugin o dal file importato.

## Seconda fase: A05–A15, A18, undo e autosave

Intervento richiesto successivamente, nello stesso checkout: A05, A06, A07, A10, A11, A12 e A15; A13 e A14; A08, A09 e A18; ottimizzazione di undo e autosave. Le correzioni A01–A04 sono conservate. A16 è toccato nei percorsi PDF necessari a questi interventi; non viene dichiarata una risoluzione generale di ogni altro rilievo dell’analisi. Non sono stati creati commit né pubblicate release.

### A05 — Checkpoint prima di ogni salvataggio e verifica della destinazione

Il salvataggio manuale congela il documento prima delle attese esterne e crea un checkpoint privato completo, anche con autosave disabilitato. Se una modifica arriva durante la scrittura, resta da salvare e non entra retroattivamente nello snapshot. L’autosave compatta prima nel recupero e poi scrive l’originale.

Il percorso esterno viene considerato salvato soltanto dopo verifica SHA-256 dei byte riletti. Su Android un nuovo URI deve anche concedere accesso persistente; un download Web o un export non riapribile conserva il recupero e richiede una nuova copia per i salvataggi successivi. Le hash vengono calcolate per stream, senza caricare un secondo file completo. Prima di sovrascrivere un originale esistente viene confrontata la sua hash con quella all’apertura/ultimo salvataggio verificato; un conflitto protegge l’originale e lascia il checkpoint.

Questo non rende atomico un provider Android che supporta solo troncamento e scrittura: in caso di interruzione l’originale può essere incompleto, ma il checkpoint privato è già stato confermato. Il recupero non viene eliminato per un semplice risultato positivo del picker.

**File:** [controller](lib/controllers/canvas_controller.dart), [picker/verifica](lib/src/compat/file_picker_cross.dart), [provider Android](android/app/src/main/kotlin/online/xournal/mobile/DocumentStorage.kt), [recuperi](lib/src/autosave_store.dart).

### A06 — Identità locale separata da quella importata

`documentId` rimane portabile; `localId` è generato sul dispositivo e non viene serializzato nel documento importabile. La chiave di recupero comprende l’origine normalizzata e l’identità dell’istanza locale, oppure la sola identità locale per una bozza. Due file con lo stesso ID XML, e due istanze contemporanee dello stesso percorso, conservano recuperi separati. La libreria e la sessione conservano l’identità locale per ritrovare recuperi e audio dopo il riavvio. Rimozioni e selezioni non usano l’ID XML come autorizzazione.

**File:** [modello](lib/src/XppFile.dart), [recuperi](lib/src/autosave_store.dart), [sessione](lib/src/workspace_session.dart), [libreria](lib/src/recent_documents.dart).

### A07 e A15 — Archivio durevole, generazioni, orfani e metadati corrotti

Libreria, tag, workspace e puntatori ai recuperi passano attraverso una coda di transazioni. SharedPreferences resta una sorgente di migrazione, senza cancellare l’originale legacy. Su dispositivo il commit contiene schema, payload e checksum: viene scritto con flush in un file temporaneo e rinominato, conservando tre generazioni. Nel Web stato attuale e precedente vengono aggiornati nella stessa transazione IndexedDB; i documenti e i recuperi sono blob binari, evitando documenti base64 nelle preferenze.

Prima del commit dell’indice, ogni checkpoint ha un manifesto durevole. La scansione dei manifesti ritrova un checkpoint completo anche se il processo termina prima di aggiornare l’indice. La libreria dispone anche di manifesti per origine, e un ripristino registra le destinazioni pianificate prima di scriverle: al riavvio i file completi di un ripristino interrotto vengono riconciliati. Queste scansioni riguardano l’archivio gestito; non cercano documenti in cartelle esterne arbitrarie.

Un commit corrotto viene conservato in quarantena e si prova la generazione precedente. JSON troncato, profondità eccessiva, tipi errati e singoli record danneggiati non cancellano i record validi. Gli elementi invalidi vengono isolati e l’indice pulito viene confermato, evitando di riscrivere continuamente la stessa quarantena. Tag e catalogo delle rimozioni sono validati separatamente. La libreria mostra gli avvisi; un errore di apertura non lascia una eccezione non gestita nella schermata.

La pulizia è successiva al commit: conserva tutti i riferimenti delle generazioni di metadati e almeno due manifesti per recupero. Segue anche i riferimenti dei frammenti e degli allegati del journal. Le scritture di blob e il relativo commit hanno una lease serializzata; i nuovi file nativi hanno inoltre un intervallo di grazia. Una struttura incoerente rinvia la pulizia. Le rimozioni sono tombstone fino a quando non rimangono riferimenti storici, e vengono poi compattate. Se il payload più recente è danneggiato, il ripristino prova una generazione precedente e lo segnala.

Quote esplicite: metadati nativi 24 MiB per commit, Web 16 MiB, archivio nativo dei recuperi circa 1 GiB con margine per i metadati. Il raggiungimento di una quota è un errore visibile, non un’autorizzazione a cancellare recuperi. Il flush/rename non costituisce una garanzia contro ogni guasto hardware o perdita di alimentazione; occorrono backup su un altro dispositivo.

**File:** [transazioni e raccolta](lib/src/critical_data.dart), [backend nativo](lib/src/compat/critical_backend_io.dart), [backend Web](lib/src/compat/critical_backend_web.dart), [libreria](lib/src/recent_documents.dart), [tag](lib/src/note_tags.dart).

### A10 — Apertura protetta dei documenti interpretati parzialmente

L’importazione registra versioni, elementi, attributi, strumenti e sfondi non supportati, e recuperi parziali di audio/flashcard. Gli avvisi sono deduplicati e limitati. L’editor li mostra e impone di salvare una copia; l’autosave non sovrascrive l’originale. Gli elementi ignoti non vengono reinseriti indiscriminatamente nel modello. Il backup nativo con staging conserva i byte originali della nota, quando gli allegati richiesti sono incorporati, e segnala l’apertura protetta.

Il contratto è documentato in [XOPP_COMPATIBILITY.md](docs/XOPP_COMPATIBILITY.md): estensioni OSI, sfondi, cancellature, audio, flashcard e differenza fra copia del modello e conservazione dell’originale.

### A11 — Limiti delle flashcard simmetrici

Creazione/modifica, serializzazione XOPP, JSON ed export Anki usano la stessa validazione: massimo 10.000 schede, 64 MiB conteggiati sui JSON effettivi UTF-8, ritaglio massimo 8 MiB, pagine e ID validi, senza duplicati. La modifica viene validata sull’insieme risultante prima di mutare il documento. Il lettore controlla la base64 prima della decodifica e segnala un recupero parziale, proteggendo l’originale. I limiti documentali complessivi continuano ad applicarsi agli allegati delle schede.

**File:** [flashcard](lib/src/note_flashcards.dart), [controller](lib/controllers/canvas_controller.dart), [XOPP](lib/src/XppFile.dart).

### A12 — Riconciliazione delle versioni senza scegliere solo per data

Il workspace legge anche l’originale. Contenuti identici non producono una copia inutile; un recupero basato sulla hash dell’originale può ripristinare le modifiche locali. Se l’origine è cambiata o la relazione non è dimostrabile, vengono conservate entrambe le versioni e il recupero resta una copia protetta. I vecchi checkpoint senza hash sono ancora leggibili quando manca l’originale. Non parte un autosave distruttivo appena si apre un recupero.

Il backup conserva originale e recupero diversi, incluso il percorso Web, invece di scartarne uno per timestamp. Le versioni coincidenti sono deduplicate quando il confronto ne dimostra l’identità.

### A13 e A14 — Pipeline e firma di distribuzione

Il workflow non rigenera né cancella il progetto Web prima della compilazione. Flutter è fissato alla versione verificata localmente; le Actions sono fissate a SHA di commit, con permessi minimi e credenziali Git non persistenti. Analisi, suite completa, controllo delle dipendenze/motori JavaScript vietati e integrità degli asset PDF sono prerequisiti delle build. I runner Windows/Linux sono versionati; non vengono ricreati distruttivamente in CI.

PDF.js e i suoi CMap sono locali, accompagnati da licenza e checksum. Il bootstrap avvia Flutter anche se il modulo PDF fallisce. La build Web usa risorse Flutter locali e la pipeline esegue lo smoke test sul sito compilato: avvio, pagina PDF, archivio IndexedDB e persistenza binaria dopo ricaricamento, con richieste esterne bloccate.

Le build ordinarie producono APK debug chiaramente separati. La release è manuale, in ambiente protetto `production`, e richiede keystore, credenziali e SHA-256 atteso del certificato. Il controllo blocca chiavi mancanti, certificati inattesi e certificati Android Debug; non esiste fallback debug. L’APK viene ricontrollato prima del caricamento. Nessuna chiave privata è stata aggiunta al repository. [RELEASE_SIGNING.md](docs/RELEASE_SIGNING.md) descrive conservazione della chiave e continuità degli aggiornamenti, incluse le installazioni precedentemente firmate debug.

L’assenza di JavaScript nei plugin nativi resta applicata da runtime e controlli di distribuzione; il JavaScript necessario alla versione Web e a PDF.js non aggiunge una possibilità di attivare plugin JavaScript.

### A08 — Cache immagini con ammissione e qualità adattiva

La cache condivisa fra entrambe le viste applica un massimo di 64 voci e 32 MiB di pixel decodificati anche alle immagini visibili. Prima di decodificare controlla dimensioni originali, calcola una risoluzione compatibile con il budget e verifica i pixel effettivi. Le risorse nuove attendono o mostrano un segnaposto se tutte le voci sono occupate; il pinning non autorizza a superare il tetto. L’arrivo di nuovi proprietari può ridurre la risoluzione delle risorse già presenti dopo il frame corrente. Il rilascio dell’ultimo proprietario svuota la cache; una decodifica tardiva non la ricrea.

Anteprime di libreria, ritagli flashcard e sfondi immagine usano la stessa cache. Anche i percorsi raster/PDF controllano le dimensioni prima della decodifica e dividono il budget fra le immagini. Il limite della cache non include tutti i buffer temporanei del decoder, le risorse PDF, il modello documentale o la memoria GPU del processo.

**File:** [cache](lib/src/decoded_image_cache.dart), [widget](lib/widgets/bounded_image.dart), [export](lib/src/document_export.dart).

### A09 — Registrazioni conservate fino al checkpoint confermato

Android salva i segmenti AAC in `filesDir/osi-audio-staging`, con manifesti associati all’identità locale. All’avvio viene eliminata soltanto la cache di playback. Stop, chiusura e lettura del canale non eliminano una registrazione. Il segmento viene rimosso solo dopo un ACK successivo al checkpoint durevole che include quell’audio; un ACK fallito lascia lo staging.

Ogni 30 secondi il registratore finalizza un segmento e Dart avvia il successivo. Dopo un’interruzione vengono recuperati i segmenti pronti; la schermata iniziale espone le note con audio da riconciliare. La scansione restituisce metadati e i byte vengono letti un segmento alla volta, con limiti per segmento/appunto/staging. Le registrazioni non finalizzate restano sul disco e vengono segnalate, senza prometterne la decodificabilità. Gli errori di stop, flush e manifesti non devono propagarsi dal callback periodico o dal ciclo di vita e far terminare l’app.

Limite funzionale attuale: un tratto iniziato prima e finito dopo la rotazione del segmento non riceve un unico collegamento audio continuo. L’inchiostro e i segmenti audio restano conservati; la sincronizzazione di quel tratto richiede un futuro modello con più segmenti per collegamento. L’ultimo segmento non finalizzato può richiedere recupero esterno dopo un arresto improvviso.

**File:** [Android](android/app/src/main/kotlin/online/xournal/mobile/NoteAudio.kt), [controller audio](lib/controllers/note_audio_controller.dart), [recuperi](lib/src/autosave_store.dart).

### A18 — Backup e PDF con staging, limiti di lavoro e annullamento

Il flusso nativo di backup legge, valida e aggiunge una nota alla volta al ZIP su disco. L’import usa input ZIP da file, controlli preventivi e callback progressivi, estraendo solo nomi generati nell’archivio privato. L’ispezione conserva percorsi e metadati: il ripristino carica una nota alla volta e trattiene soltanto piccoli record per il commit finale. Non accumula tutti i modelli, le base64, i GZIP e un secondo ZIP completo contemporaneamente. Originali e recuperi in conflitto vengono inclusi entrambi.

Export e copia del backup sono per stream, con hash della destinazione; Android verifica anche il file scritto dal provider. Lo staging viene pulito nei percorsi di completamento/annullamento gestiti, mentre i file completi di un ripristino interrotto restano riconciliabili. L’annullamento è cooperativo fra note, non interrompe a metà la scrittura di una nota.

Budget nativi: nota compressa/media di lavoro 32 MiB, XML per nota 64 MiB, archivio 512 MiB e staging complessivo 1 GiB, inclusi residui di operazioni interrotte. I residui dopo una terminazione del processo non vengono cancellati indiscriminatamente; se esauriscono la quota occorre liberarli dopo verifica/recupero. Il percorso Web, privo di file di staging, ha un limite esplicito di 32 MiB per archivio e 64 MiB di dati espansi cumulativi; le note non incluse vengono segnalate.

Il PDF prepara le pagine su disco, deduplica le immagini, limita dimensioni/numero di pixel e scrive l’output attraverso uno stream su file. Il worker riceve percorsi anziché una seconda collezione completa di pagine e immagini. Sono applicati budget di lavoro e output; il grafo degli oggetti della libreria PDF resta comunque in RAM. Non è una promessa di memoria del processo costante per qualunque documento.

**File:** [backup](lib/src/note_backup.dart), [staging ZIP](lib/src/compat/backup_staging_io.dart), [PDF](lib/src/document_export.dart), [staging PDF](lib/src/compat/pdf_staging_io.dart), [dialogo](lib/widgets/note_backup_dialog.dart).

### Undo e autosave incrementale

I punti dei tratti sono buffer immutabili posseduti dal modello. Gli snapshot clonano lo stato mutabile dei tratti e le maschere, ma condividono la geometria invariata. Traslazione e ridimensionamento sostituiscono il buffer; non mutano le versioni conservate per undo/redo. Anche la gomma pixel può condividere la geometria e cambiare soltanto le maschere. Resta il limite di 50 passi; trasformazioni che cambiano tutti i punti producono necessariamente nuove geometrie nel modello attuale.

L’autosave dopo due secondi di inattività scrive un manifesto completo del journal e frammenti indirizzati dalla hash. I tratti immutabili invariati riusano il frammento; colore, maschere, collegamenti audio e trasformazioni invalidano il riuso. Gli allegati sono blob separati, senza ricodificarli in base64 nel journal. Il writer applica i limiti compatibili con il lettore; prima di riusare una hash verifica che il frammento esista ancora. Dopo dieci secondi, pausa/chiusura o salvataggio manuale viene preparato il checkpoint XOPP completo. Il salvataggio manuale può riusare un checkpoint della stessa revisione. I timer vengono cancellati alla chiusura, lasciando il flush esplicito.

La prova con 100.000 punti e 50 snapshot verifica un solo buffer di geometria e l’indipendenza dopo una trasformazione. La misura sul computer di test è in [astra-next-undo-measurement.json](docs/validation/astra-next-undo-measurement.json): è una misura dello snapshot e dell’RSS del processo di test, non della latenza della penna su Android. Le prove del journal verificano riuso, invalidazione, maschere, media, audio, flashcard, hash e fallback dopo corruzione.

**File:** [tratti](lib/layer_contents/XppStroke.dart), [snapshot](lib/src/content_snapshot.dart), [journal](lib/src/recovery_journal.dart), [controller](lib/controllers/canvas_controller.dart).

### Verifiche della seconda fase e prove ancora necessarie

Log riproducibili conservati in `docs/validation/astra-next-*`. Le regressioni dedicate sono in [astra_data_fixes_test.dart](test/astra_data_fixes_test.dart) e [astra_recovery_performance_test.dart](test/astra_recovery_performance_test.dart); i test esistenti sono stati adattati alla persistenza transazionale, all’identità locale, ai conflitti conservati e alle anteprime realmente decodificate.

Sono stati verificati build Android debug, build Web con dry run Wasm, smoke test del Web compilato senza richieste esterne, integrità degli asset PDF e assenza dei motori plugin vietati nell’APK. Le build release senza chiave e con certificato Android Debug configurato vengono rifiutate intenzionalmente. I log degli errori intermedi restano diagnostici: il risultato finale è riportato nei log di validazione conclusivi.

Risultati conclusivi:

- **254 test superati** nella [suite completa](docs/validation/astra-next-verified-tests.txt). Dopo l’ultimo affinamento della cache, **32 test mirati superati** in [verifica immagini e recupero](docs/validation/astra-next-image-verified.txt).
- [Analisi statica](docs/validation/astra-next-analyze-final.txt): **0 errori, 0 warning, 308 segnalazioni informative**; non vengono presentate come assenza di tutte le segnalazioni.
- [APK Android debug](docs/validation/astra-next-android-last.txt) e [Web release](docs/validation/astra-next-web-last.txt) compilati. Lo [smoke test Chromium](docs/validation/astra-next-browser-last.txt) verifica avvio, rendering PDF, stato e blob IndexedDB dopo ricaricamento e aggiornamento dello schema inizialmente bloccato da un’altra scheda, con risorse esterne bloccate.
- [Controllo dell’APK](docs/validation/astra-next-distribution-check.txt), [integrità PDF.js](docs/validation/astra-next-vendor-check.txt) e controllo del diff superati. Verificato il rifiuto della release [senza chiave](docs/validation/astra-next-release-refused.txt) e [con certificato Android Debug](docs/validation/astra-next-debug-certificate-refused.txt).

Il backend IndexedDB chiude le connessioni quando cambia lo schema e gestisce il successo tardivo di una richiesta già segnalata come bloccata: chiude la connessione ricevuta senza completare due volte la stessa operazione. Le transazioni dell’app serializzano gli aggiornamenti nella singola istanza; non introducono un coordinatore fra processi desktop o più istanze Web concorrenti. La prova fra schede verifica il blocco dello schema, non la modifica simultanea dello stesso documento da due istanze.

Non è disponibile una chiave di produzione: nessun APK release firmato di produzione è stato generato e non è stata provata la continuità di aggiornamento delle installazioni reali. I runner desktop sono stati generati/versionati, ma non compilati localmente per ogni piattaforma. Restano da eseguire su dispositivi reali: arresti forzati ai confini blob/manifesto/commit/provider, permessi SAF revocati e provider cloud, registrazione e recupero dopo terminazione del processo, profili heap/RSS/GPU in split screen, qualità delle immagini, latenza della penna e sessioni dense di trasformazioni undo. La sicurezza non viene dichiarata assoluta e le quote non equivalgono al limite dell’heap totale.

Per le modifiche future: mantenere indipendenti identità importate e autorizzazioni locali; non eliminare un payload prima del commit e della scadenza dei riferimenti storici; validare sia writer sia reader; confermare ACK solo dopo persistenza; limitare decode/output prima delle allocazioni; preservare gli originali nelle incompatibilità e nei conflitti; provare gli artefatti compilati, senza rigenerare configurazioni versionate; mantenere stabile la firma e verificare il certificato dell’APK; monitorare e aggiornare le dipendenze vendorizzate con integrità e regressioni. Una maggiore estensibilità dei plugin deve passare da API controllate, quote e transazioni, senza consentire l’attivazione di un motore JavaScript nativo.

## Aggiornamento dell’11 ottobre 2026 — Firma locale e APK release

Il blocco «Firma release non configurata» era il controllo previsto da A14, distinto dagli avvisi sulle versioni Gradle/AGP/Kotlin. Dopo la conferma che si tratta della prima distribuzione, è stata generata una chiave locale stabile e configurato il certificato atteso. Lo [script di configurazione Windows](scripts/configure_release.ps1) genera password casuali senza mostrarle, protegge i file con ACL, conserva le configurazioni presenti e rifiuta di sostituire un keystore esistente. Chiave e credenziali sono escluse da Git. Le istruzioni e la necessità di una copia sicura sono riportate nella [guida alla firma](docs/RELEASE_SIGNING.md).

Superati: [generazione e riesecuzione senza sostituire la chiave in Windows PowerShell 5](docs/validation/astra-signing-setup-2026-10-11.txt), [build debug](docs/validation/astra-build-debug-2026-10-11.txt), [build release](docs/validation/astra-build-release-2026-10-11.txt) e [verifica APK/certificato tramite apksigner](docs/validation/astra-release-verified-2026-10-11.txt). La release è firmata con la nuova chiave e nessun fallback debug. Gli avvisi sulle dipendenze Android restano; non sono stati disabilitati. Non sono stati effettuati push, pubblicazioni, installazioni o prove di aggiornamento su dispositivi reali. La precedente nota sull’assenza di una chiave descriveva la verifica del 10 ottobre, prima di questa configurazione.

## Aggiornamento dell’11 ottobre 2026 — Importazione PDF e salvataggio

La segnalazione riguarda file `.pdf` creati dalla versione precedente: rallentamento e crash durante l’apertura, poi scheda priva del PDF al riavvio. Il PDF specifico e un log del dispositivo non sono disponibili; le cause individuate nel codice e le correzioni verificabili sono descritte qui, senza dichiarare riprodotto quel crash.

### PDF conservato nella scheda e nel recupero

`loadPdfFresh` sostituiva l’istanza di `XppFile` posseduta dalla scheda: il controller mostrava il nuovo documento mentre il workspace conservava l’identità dell’appunto vuoto. Ora aggiorna la stessa istanza. L’importazione registra immediatamente pagine e allegato nel journal durevole, anche con autosave disattivato, prima di avviare il rendering delle pagine. La lettura iniziale delle dimensioni richiede comunque il parser PDF; non è possibile garantire recupero da un arresto del parser precedente al commit.

Durante il commit, le richieste del viewport vengono conservate e il dettaglio zoom non viene montato; dopo il commit parte il rendering delle pagine richieste. Il percorso alternativo `XppFile.importPdf` apre la sorgente una sola volta per leggere tutte le dimensioni. Le aperture dalla parte Dart sono serializzate prima del trasferimento alla piattaforma, per evitare molte copie native contemporaneamente in attesa. Gli sfondi della vista principale usano la cache condivisa delle immagini decodificate, con il budget già previsto da A08.

**File:** [controller](lib/controllers/canvas_controller.dart), [vista](lib/pages/CanvasPage.dart), [apertura PDF](lib/src/PdfImage.dart), [importazione](lib/src/XppFile.dart).

### Lavoro PDF su Android e rilascio delle risorse

È inclusa una copia locale dei sorgenti runtime di `pdfx` 2.11.0 con licenze originali e [registro delle modifiche](packages/pdfx/OSI_PATCHES.md). L’app la usa tramite dipendenza locale; le implementazioni delle altre piattaforme sono conservate.

Su Android, apertura, lettura delle dimensioni e rendering dei ritagli lavorano su una coda dedicata; risposte Flutter e gestione delle texture restano sul thread della piattaforma. Bitmap interi, ritagli e texture vengono riciclati in `finally`. Dimensioni e numero di pixel vengono limitati prima delle allocazioni raster e del ridimensionamento delle texture. Le chiusure dei documenti attendono i rendering in coda; callback tardivi, errori Java recuperabili di allocazione e riferimenti a documenti chiusi vengono gestiti. Lo stato delle texture viene rimosso al rilascio e le risorse native vengono drenate al distacco del motore.

Le copie PDF temporanee private vengono scollegate dopo l’apertura del descrittore, che resta valido su Android. Il file scelto dall’utente non viene eliminato. Il descrittore viene chiuso anche se il costruttore del renderer fallisce. Un errore nativo del motore PDF o una terminazione del processo da parte del sistema possono ancora richiedere diagnosi sul dispositivo: i limiti raster non equivalgono a un limite di memoria dell’intero parser o processo.

### Salvataggio con meno lavoro e copie temporanee

Un salvataggio ripetuto senza modifiche controlla l’originale e termina senza rigenerare anteprima, XML, compressione o riscrittura del provider. Il checkpoint durevole della stessa revisione può essere riusato anche quando il salvataggio manuale attende un autosave già in corso; non viene registrato una seconda volta se la copia verificata è già disponibile.

La serializzazione nativa comprime l’XML progressivamente: gli allegati PDF sono codificati in blocchi base64 da 48 KiB e le pagine vengono serializzate una alla volta. Si evita di costruire contemporaneamente il DOM completo, una base64 completa del PDF, l’intero testo XML e un ulteriore buffer UTF-8. Restano in memoria il modello, l’output compresso e il trasferimento al worker. Il percorso Web conserva un buffer XML completo per la libreria di compressione, con limite esplicito.

Gli hash dei grandi allegati procedono in blocchi da 256 KiB, cedendo il ciclo eventi fra i blocchi. Per la verifica della scrittura si riusa l’hash già calcolato. I controlli di integrità, conflitto con l’originale, compatibilità e recupero locale restano applicati; non si evita la verifica per velocizzare il salvataggio. Non viene dichiarata una misura della latenza reale su Android.

**File:** [compressione nativa](lib/src/compat/xml_compression_io.dart), [compressione Web](lib/src/compat/xml_compression_web.dart), [hash](lib/src/responsive_hash.dart), [verifica file](lib/src/compat/file_picker_cross.dart).

### Regressioni e verifiche

Le regressioni aggiunte in [performance_resources_test.dart](test/performance_resources_test.dart) verificano recupero della scheda e allegato prima del rendering, viewport richiesto durante l’importazione, aperture serializzate, una sola apertura per le dimensioni, equivalenza XML e riapertura degli allegati, hash corretto senza bloccare tutti gli eventi, riuso del checkpoint e assenza di riscrittura di un file invariato. Le prove del dettaglio PDF controllano zoom, budget e chiusura durante il rendering. I log finali sono in `docs/validation/pdf-save-*`; gli errori di compilazione intermedi restano documentati come diagnostica.

Risultati sul codice finale:

- [Suite completa](docs/validation/pdf-save-full-tests-2026-10-11.txt): **260 test superati**; [prove mirate PDF e salvataggio](docs/validation/pdf-save-final-focused-2026-10-11.txt): **18 test superati**.
- [Analisi statica di `lib` e `test`](docs/validation/pdf-save-analyze-final-2026-10-11.txt): **0 errori, 0 warning, 306 segnalazioni informative**.
- [APK release](docs/validation/pdf-save-android-release-2026-10-11.txt) compilato con firma di produzione locale; [verifica finale](docs/validation/pdf-save-release-verified-2026-10-11.txt) di certificato, assenza dei motori vietati e presenza della patch PDF nel DEX superata. Gli avvisi sulle versioni Gradle/AGP/Kotlin restano visibili.
- [Web release](docs/validation/pdf-save-web-2026-10-11.txt) e dry run Wasm riusciti; [smoke test del sito compilato](docs/validation/pdf-save-browser-2026-10-11.txt) superato per avvio, rendering PDF, persistenza binaria dopo ricaricamento e gestione dell’aggiornamento IndexedDB bloccato da un’altra scheda, con risorse esterne bloccate. [Integrità PDF.js](docs/validation/pdf-save-vendor-2026-10-11.txt) verificata.

I file di prova già versionati, rigenerati dalla suite, sono stati ripristinati alla versione iniziale per non introdurre aggiornamenti estranei; i nuovi risultati di verifica restano nei log dedicati. Non sono stati effettuati commit, push, pubblicazioni o installazioni.

Per confermare il problema segnalato, riprovare sul dispositivo il PDF originale, scorrere e ingrandire, mettere l’app in background, riaprirla e verificare pagine e annotazioni salvate. Nessuna prova su quel dispositivo è stata eseguita. Negli aggiornamenti futuri di `pdfx`, confrontare la patch locale con i sorgenti upstream, mantenere limiti e rilascio in caso di errore, preservare la barriera di persistenza prima del rendering e rieseguire le regressioni e le prove su PDF complessi.

## Aggiornamento dell’11 ottobre 2026 — Destinazione di esportazione PDF

Il messaggio «Errore esportazione PDF: Bad state: Destinazione backup non disponibile» proveniva dal controllo del risultato del selettore. Nell’implementazione Android installata (`android_file_picker` 2.0.1, usata da `file_picker` 13.1.0), il callback nativo restituiva `renamedUri.path`: un percorso come `/document/primary:Download/appunti.pdf`, privo di schema `content` e autorità del provider. Dart interpretava quel risultato come URI senza schema e il percorso di esportazione PDF/ZIP lo rifiutava. Convertirlo in un percorso filesystem o inventare l’autorità non permetterebbe un accesso corretto ai documenti.

È inclusa una [patch locale del selettore Android](packages/android_file_picker/OSI_PATCHES.md), con sorgenti runtime e licenza originali, collegata tramite override in `pubspec.yaml`. Il callback ora restituisce `renamedUri.toString()`, conservando schema, autorità e identificatori codificati. La correzione riguarda anche backup, export degli appunti e JSON che usano lo stesso selettore; non cambia il parser PDF o il formato degli appunti.

Il metodo condiviso è stato rinominato `exportStagedFile` ed è usato sia dal [controller PDF](lib/controllers/canvas_controller.dart) sia dal [dialogo backup](lib/widgets/note_backup_dialog.dart). Un tipo di URI non supportato ora segnala una destinazione di esportazione, evitando il riferimento errato ai backup. Restano il trasferimento dal file privato per stream, i controlli di integrità della destinazione e il rifiuto dei percorsi incompleti; non sono stati aggiunti permessi di accesso generale allo storage.

Le [regressioni dedicate](test/staged_export_test.dart) coprono il flusso completo controller → PDF di staging → provider, URI con accenti/spazi e slash codificati, backup su provider, copia e verifica su filesystem, annullamento senza scritture, rifiuto dei percorsi troncati ed export JSON con conservazione dell’URI. I provider sono simulati; resta da provare il selettore reale su Android, nei Download e con eventuali provider cloud. Negli aggiornamenti del selettore, verificare sia la compatibilità della versione forzata dall’override sia il contenuto del callback nativo prima di rimuovere la patch.

Verifiche concluse: **23 test superati** nella [suite PDF, export e backup](docs/validation/pdf-export-tests-2026-10-11.txt); [analisi statica](docs/validation/pdf-export-analyze-2026-10-11.txt) con **0 errori, 0 warning e 306 segnalazioni informative**; [APK release compilato](docs/validation/pdf-export-android-2026-10-11.txt) e [firma di produzione/controlli di distribuzione verificati](docs/validation/pdf-export-release-verified-2026-10-11.txt). L’[ispezione del bytecode Kotlin compilato](docs/validation/pdf-export-native-bytecode-2026-10-11.txt) conferma che il callback usa `Uri.toString()` prima di `finishWithSuccess`. I PDF di prova versionati rigenerati dai test sono stati ripristinati; nessuna installazione, pubblicazione o push è stata effettuata.

## Aggiornamento dell’11 ottobre 2026 — Apertura PDF e XOPP

Sono stati ottimizzati tre passaggi del caricamento, mantenendo i formati, gli allegati, la geometria delle pagine, la pressione della penna, il recupero e i controlli sui documenti.

### XOPP: decompressione nativa limitata e lettura dei punti

La decompressione dei file XOPP sulle piattaforme native usa ora zlib tramite il decoder GZIP di Dart IO, alimentato in blocchi da 16 KiB. Il sink controlla i byte effettivamente prodotti prima di aggiungerli al buffer e mantiene il limite di tempo di 30 secondi. Il controllo dei byte compressi precede la decompressione; i limiti su XML, media, nodi, geometria e punti restano applicati dal lettore. Il parsing continua nel worker, e la hash dell’originale continua a essere calcolata per rilevare conflitti successivi.

Il decoder nativo, usato da solo, accetta alcuni trailer troncati. Questo comportamento è stato individuato dalla regressione di A02 durante lo sviluppo: prima della chiusura viene ora alimentato un membro GZIP vuoto valido, che forza il completamento e la verifica del membro precedente prima di riconoscere la nuova intestazione. Il membro di controllo non produce dati e non viene salvato nei file. Le prove verificano CRC, dimensioni effettive, tutte le troncature da uno a otto byte del trailer anche nei membri vuoti, e concatenazioni valide o oltre quota. Il percorso Web conserva il decoder Dart limitato già esistente. I buffer temporanei del codec e il modello restano parte della memoria del processo; il limite di output non è una promessa sull’heap totale.

Il parser dei tratti legge le coppie di coordinate in una sola scansione: evita la precedente scansione per contare, la lista completa delle stringhe delle coordinate e la successiva rilettura. Gli spessori vengono validati e convertiti una sola volta, conservando sia pressione variabile sia il riuso del primo spessore quando la lista è più corta. La quota viene controllata prima di allocare un altro punto; il controllo del tempo si ripete anche durante tratti lunghi. Coordinate incomplete, numeri non finiti e liste di spessori eccessive restano rifiutati.

**File:** [decompressione nativa](lib/src/compat/gzip_decode_io.dart), [selezione del decoder](lib/src/bounded_archive.dart), [parser XOPP](lib/src/XppFile.dart).

### PDF: dimensioni delle pagine con una sola risposta Android

L’importazione Android usa il canale privato `online.xournal.mobile/pdf-metadata` della patch locale `pdfx`: legge e chiude ogni pagina in sequenza sul worker esistente e restituisce tutte le dimensioni in una sola risposta. Prima erano necessari apertura e chiusura attraverso Flutter per ogni pagina, cioè due scambi per pagina. Si mantiene l’ispezione di tutte le pagine, con ordine e dimensioni originali, senza introdurre dimensioni provvisorie o perdere pagine.

Il lato nativo limita il risultato a 10.000 pagine e dimensioni di 20.000 unità; Dart ricontrolla lunghezza e valori della risposta. Gli errori chiudono il documento tramite il percorso già previsto. Le altre piattaforme e un canale non disponibile usano il percorso precedente. La copia durevole di recupero continua a precedere il rendering. Il parser del PDF deve comunque ispezionare le pagine, e il contenuto complesso resta da rasterizzare: il miglioramento riduce il lavoro di comunicazione, non elimina questi costi.

**File:** [metadati e fallback](lib/src/PdfImage.dart), [importazione](lib/controllers/canvas_controller.dart), [patch Android](packages/pdfx/OSI_PATCHES.md).

### Misure e verifiche

Nel test Windows desktop/JIT con allegato sintetico di 8 MiB e 20.000 punti a pressione variabile, dopo un giro di riscaldamento e tre misure, la mediana è passata da **121,024 ms a 74,302 ms** per lettura XOPP e costruzione del modello (circa **39% in meno**). La sola decompressione passa da **35,836 ms a 7,342 ms**. Dati e condizioni sono nei risultati [prima](docs/validation/opening-before-2026-10-11.json) e [dopo](docs/validation/opening-after-2026-10-11.json); il test finale è stato eseguito a build concluse per ridurre la competizione sulla CPU. I dati PDF del fixture sono un allegato opaco: non viene misurato il rendering né il tempo dal tap al primo frame. Queste misure non rappresentano la latenza su Android e possono variare con dispositivo, compressione, contenuti e provider.

Verifiche concluse:

- [Suite completa](docs/validation/opening-full-tests-2026-10-11.txt): **272 test superati**. Le [prove mirate](docs/validation/opening-focused-2026-10-11.txt) comprendono recupero, cache, PDF, zoom e limiti; le [prove finali del parser e del benchmark](docs/validation/opening-measurement-final-2026-10-11.txt) comprendono anche spaziature e liste di pressione parziali.
- [Analisi statica](docs/validation/opening-analyze-2026-10-11.txt): **0 errori, 0 warning e 306 segnalazioni informative**.
- [APK release definitivo](docs/validation/opening-android-2026-10-11.txt) compilato e [firma/controlli di distribuzione](docs/validation/opening-release-verified-2026-10-11.txt) verificati, inclusa la presenza del nuovo canale nel DEX e del parser/caller Dart nelle librerie AOT di ogni ABI.
- [Web release](docs/validation/opening-web-2026-10-11.txt), dry run Wasm e [smoke test Chromium](docs/validation/opening-browser-2026-10-11.txt) superati, inclusi PDF e persistenza IndexedDB dopo ricaricamento.

Le prove PDF verificano una sola risposta per dimensioni diverse, ordine delle pagine, fallback, rifiuto di dati incompleti/NaN e chiusura del documento. I file di prova versionati rigenerati dalla suite sono stati ripristinati. Non sono stati eseguiti commit, push o installazioni. Restano da misurare sul dispositivo reale il caricamento del PDF/XOPP dell’utente, il provider scelto e il primo rendering. Per le modifiche future, non sostituire il decoder senza provare trailer incompleti e concatenazioni, non indebolire le quote per guadagnare tempo e non mostrare geometrie provvisorie che possano modificare posizioni o proporzioni delle annotazioni.
