# Analisi ASTRA — stabilità, integrità dei dati e sicurezza di OSI

Data: **10 ottobre 2026**. Revisione analizzata: **`4bb6aa05c2894f3f9cdfdc1e8863b23c1d0ac546`**. Il repository era pulito all'inizio dell'analisi. Questo intervento aggiunge il rapporto e prove diagnostiche; **non corregge il codice dell'app**.

## Esito e priorità

L'app contiene diverse protezioni utili, ma non è ancora sufficientemente robusta per trattare indistintamente documenti, backup e plugin come dati ostili. I problemi più urgenti sono i limiti aggirabili del runtime JSON, la decompressione non limitata, l'accesso implicito ad allegati locali e alcuni percorsi di perdita/sostituzione dei recuperi. **Non è stata dimostrata esecuzione arbitraria di codice nativo, compromissione del sistema operativo o riattivazione di JavaScript nell'app attuale.** Il blocco JavaScript non elimina le vulnerabilità del codice che interpreta dati e workflow.

Priorità: **P1** = correggere prima di considerare affidabile il relativo ingresso o distribuire la funzione interessata; **P2** = intervento successivo, con rischio concreto ma più circoscritto. Non sono punteggi CVSS. «Riprodotto» indica una prova sintetica limitata; «statico» indica un percorso verificato nel codice, il cui impatto operativo richiede ulteriori prove.

| ID | Priorità | Criticità | Evidenza |
|---|---|---|---|
| A01 | P1 | Interpolazione JSON senza limite preventivo: crescita della memoria anche senza permessi | Riprodotto |
| A02 | P1 | GZIP/XOPP e ZIP backup: decompressione e parsing senza budget completo | Statico + espansione limitata riprodotta |
| A03 | P1 | Dimensioni e coordinate importate non validate | Riprodotto |
| A04 | P1 | File locali incorporati nel backup tramite riferimenti di sfondo non autorizzati | Riprodotto |
| A05 | P1 | Sovrascrittura Android tramite provider non atomica; salvataggio manuale senza nuovo checkpoint preventivo | Statico |
| A06 | P1 | Identificativi uguali fanno sostituire/eliminare il recupero di un altro file | Riprodotto |
| A07 | P1 | Indici critici nelle preferenze, senza transazione durevole e recupero degli orfani | Statico |
| A08 | P1 | Cache immagini con limite superabile dalle risorse visibili | Riprodotto su scala minima |
| A09 | P2 | Registrazioni temporanee eliminate prima della persistenza documentale | Statico |
| A10 | P1 | Contenuti Xournal non supportati scartati senza avviso, poi risalvati | Riprodotto |
| A11 | P1 | Flashcard: limite in lettura assente in scrittura, possibile perdita al riavvio | Statico |
| A12 | P1 | Ripristino workspace preferisce sempre il checkpoint, anche se più vecchio | Riprodotto |
| A13 | P1 | CI Web cancella il bootstrap PDF; mancano controlli automatici obbligatori | Statico |
| A14 | P1 distribuzione | APK release firmato con configurazione debug | Statico |
| A15 | P2 | Preferenze corrotte possono rendere indisponibili libreria e recuperi | Statico |
| A16 | P2 | Import PDF annullati trattenuti in memoria fino alla chiusura del controller | Statico |
| A17 | P2 | Avvio Web dipendente da codice remoto CDN, senza fallback locale | Statico |
| A18 | P2 | Backup/export mantengono molte rappresentazioni complete contemporaneamente | Statico |

## Metodo, copertura e limiti

Sono stati esaminati: importazione/serializzazione XOPP, allegati PDF e immagini, salvataggi locali e Android SAF, autosave e sessioni, backup, flashcard, audio nativo, cache e undo, runtime/permessi/rete dei plugin, manifest Android, configurazione di compilazione, bootstrap Web e documentazione. Le letture sono state guidate dagli ingressi esterni e dai punti di allocazione, scrittura, cancellazione e rilascio delle risorse; non costituiscono una verifica formale di ogni riga o di tutte le dipendenze native.

Verifiche eseguite in questa analisi:

- **44 test superati**: 9 prove ASTRA, più 35 test esistenti nei gruppi `plugin_security_test`, `plugin_javascript_test`, `note_backup_test`, `document_storage_test`. [Log](docs/validation/astra-audit-probes.txt).
- Le prove ASTRA confermano **8 comportamenti problematici**, con un controllo positivo aggiuntivo sul rifiuto di un checksum GZIP corrotto. Il probe di decompressione espande soltanto 1 MiB; non è stato provocato deliberatamente un OOM.
- Analisi statica Dart dell'intero progetto: **0 errori, 0 warning, 181 informazioni di stile/deprecazione**. [Log](docs/validation/astra-audit-analyze.txt). Questi controlli non rilevano automaticamente difetti logici o confini di sicurezza incompleti.
- Inventario testuale Xournal sui file tracciati: **610 righe**, esclusi `pubspec.lock`, file binari e precedenti log in `docs/validation/`. [Inventario](docs/validation/astra-xournal-references.txt).

Le [prove ASTRA](tool/astra_audit_test.dart) sono intenzionalmente separate dalla normale cartella `test`: i test dei difetti passano quando il comportamento osservato è presente, **non certificano che sia sicuro**. Dopo una correzione vanno trasformati in regressioni che richiedono rifiuto, conservazione dei dati o rispetto del limite. Riproduzione: `flutter test --no-pub tool/astra_audit_test.dart test/plugin_security_test.dart test/plugin_javascript_test.dart test/note_backup_test.dart test/document_storage_test.dart --reporter expanded`.

Una prima compilazione si è fermata ed è stata riavviata. Nel primo run completato l'ipotesi sul checksum GZIP nativo è stata smentita: il decoder ha rifiutato il file, quindi quella segnalazione è stata esclusa e il test è diventato un controllo positivo. Il [log diagnostico iniziale](docs/validation/astra-audit-test-diagnostic.txt) conserva questo passaggio; il risultato definitivo è il log dei 44 test.

Non sono stati eseguiti fuzzing prolungato, profilazione heap/RSS su telefono, interruzione di alimentazione, test con provider cloud reali, penetration test di APK installato, scansione completa degli advisory delle dipendenze o test dell'artefatto Web CI. Non si attribuiscono CVE o vulnerabilità native senza prova. I 209 test e l'ispezione APK citati in `docs/PLUGIN_SECURITY.md` sono evidenze della revisione precedente, non una nuova esecuzione della suite completa in questo intervento.

## Criticità dettagliate

### A01 — Il runtime JSON può costruire stringhe oltre i limiti

**Evidenza:** `lib/plugins/plugin_runtime.dart:116–125` restituisce subito il risultato di `replaceAllMapped` per una stringa. Il controllo a 65.536 caratteri, presente dopo gli operatori e dentro `join`/`replace`, non attraversa questo ramo. `set` a riga 251 conserva il risultato senza un budget complessivo delle variabili. Anche la conversione implicita di liste/mappe in stringa va considerata un'allocazione.

**Prova:** un manifest valido senza permessi imposta una stringa di 40.000 caratteri e la raddoppia due volte tramite interpolazione. Il runtime accetta **160.000 caratteri**. Fermiamo qui il test: ulteriori raddoppi possono richiedere allocazioni enormi prima del controllo successivo del tempo. Il timer non interrompe una singola operazione sincrona già iniziata.

**Impatto:** un plugin JSON installato ed eseguito può bloccare l'interfaccia o esaurire la memoria; non serve riattivare JavaScript. Il fatto che una successiva API rifiuti l'argomento non protegge l'allocazione già avvenuta.

**Correzione proposta:** interpolatore con conteggio preventivo dei segmenti e output limitato; vietare conversioni ricorsive implicite non limitate; budget di byte/nodi/profondità dell'intero ambiente delle variabili e dei risultati intermedi. Applicare gli stessi vincoli a `set`, `var`, risultati delle azioni e operazioni su liste. Un worker può migliorare la reattività, ma non sostituisce quote prima dell'allocazione.

**Regressioni:** raddoppi di stringhe, liste annidate/condivise, interpolazione di mappe, variabili multiple al limite; rifiuto prima della crescita, annullamento tempestivo, nessuna modifica al documento.

### A02 — Decompressione non limitata agli ingressi documentali e backup

**Evidenza:** `lib/src/compat/file_picker_cross.dart:64` legge interamente il file scelto; `DocumentStorage.kt:35` usa `readBytes()` sullo stream. `XppFile.dart:206–230` decomprime tutto il GZIP, crea stringa e DOM XML, poi decodifica gli allegati base64. Mancano budget applicativi per XML espanso, profondità, pagine, livelli, punti, immagini e allegati complessivi.

`note_backup.dart:223` usa `ZipDecoder.decodeBytes` **prima** dei controlli sulle voci. Nella dipendenza locale `archive 4.3.0`, `lib/src/codecs/zip_decoder.dart:62–66` legge/decomprime il contenuto dei link simbolici durante questo passaggio. Il successivo rifiuto dei link arriva quindi tardi. Per le voci normali il controllo usa `entry.size`, dichiarato nell'archivio; `readBytes()` a riga 243 alloca prima del confronto con la lunghezza reale. Infine ogni voce `.xopp` introduce un secondo livello GZIP non limitato. Il limite di 512 MiB dello ZIP non è un limite alla RAM né al contenuto XML risultante.

**Prova limitata:** meno di 4 KiB di GZIP vengono accettati e producono oltre 1 MiB di testo XML. La prova mostra l'amplificazione; la mancanza del tetto si verifica nel codice. Non è stata eseguita una bomba che saturi il dispositivo.

**Correzione proposta:** lettura a blocchi con massimo reale; prima i metadati ZIP, poi rifiuto di link, duplicati, cifratura e percorsi inattesi; stream di decompressione con output limitato anche quando le dimensioni dichiarate mentono. Riutilizzare l'approccio già adottato in `plugin_package.dart`, con budget adatti ai documenti. Applicare limiti cumulativi a tutti gli strati, parsing XML progressivo e cancellazione del lavoro. Validare il risultato prima di consegnarlo a UI/decoder nativi.

**Regressioni:** ZIP con dimensione falsa e link compresso, GZIP annidato, XML profondo, milioni di punti/elementi, allegati duplicati e base64 eccessivo; rifiuto entro memoria/tempo misurati. Il checksum GZIP corrotto è già rifiutato nel test nativo: non è un difetto confermato. Verificare separatamente il decoder Web.

### A03 — Geometria importata non finita o smisurata

**Evidenza:** `XppFile.dart:237–240`, `322–360`, `390–395`; `XppPageSize.dart:7` non impone invarianti. `double.parse` accetta anche valori non finiti. Le restrizioni geometriche dei plugin non proteggono l'import XOPP.

**Prova:** pagina con `width="Infinity"` e `height="-1"` accettata. Altri input comprendono `NaN`, dimensioni enormi, testo con font size negativo e coordinate incoerenti. Il parser può anche produrre un documento senza pagine.

**Impatto:** errori di layout/rendering, conversioni numeriche non valide, blocchi. I pittori in `XppBackground.dart:325–459` iterano in proporzione alle dimensioni logiche: un limite alla risoluzione finale del PNG non limita questi cicli.

**Correzione proposta:** modello validato con dimensioni finite, positive e limitate, coordinate/spessori finiti e intervalli definiti; massimo di pagine/elementi/punti e almeno una pagina valida. Disegnare griglie soltanto nell'area visibile, con numero massimo di primitive. Respingere il documento con un messaggio utile prima di montarlo.

**Regressioni:** infinito, NaN, zero, negativi, grandi valori finiti, numero dispari di coordinate, PDF con pagine fuori intervallo; nessun crash del renderer.

### A04 — Un riferimento XOPP può includere un file locale estraneo nel backup

**Evidenza:** `note_backup.dart:141–163` usa `filename` dello sfondo come percorso assoluto/relativo e legge il contenuto senza selezione aggiuntiva, verifica del tipo o confine di directory. `canvas_controller.dart:536–558` segue analogamente i riferimenti PDF; `934–942` li incorpora al salvataggio. `internal_storage_io.dart:16` accetta direttamente percorsi con separatori.

**Prova:** nota con sfondo `pixmap` riferito a un innocuo `.txt` temporaneo. `NoteBackup.create()` include il marker e `inspect()` lo restituisce in `pdfAttachments`. Non è necessario che il contenuto sia un'immagine valida. Il test non legge file personali.

**Prerequisiti e impatto:** la vittima importa/conserva la nota e crea o condivide il backup; il processo deve avere accesso al percorso. Su desktop valgono i privilegi dell'utente; Android mantiene la propria sandbox e i grant ai provider. È una **lettura/incorporazione non autorizzata dal contenuto del documento**, non una prova di accesso oltre i permessi del sistema o di invio automatico in rete.

**Correzione proposta:** i percorsi nel documento devono essere riferimenti non attendibili, mai autorizzazioni. Preferire allegati interni identificati per ID/hash; per esterni usare il selettore e conservare una concessione locale separata dal file importato. Per risorse relative autorizzate, canonicalizzazione e confine della cartella inclusi link/reparse point; bloccare risoluzione implicita di percorsi assoluti, `..`, UNC e URI arbitrarie. Una sola verifica MIME non basta.

**Regressioni:** marker esterno, percorso relativo verso parent, UNC, alias/link, `content://` non concesso; backup con sole risorse esplicitamente associate, messaggio sugli allegati mancanti.

### A05 — Salvataggi Android non atomici tramite ContentResolver

**Evidenza:** `android/app/src/main/kotlin/online/xournal/mobile/DocumentStorage.kt:43–48` apre il documento con modalità `wt` e scrive direttamente. Il provider può troncare il contenuto prima del completamento. Il percorso locale usa invece un temporaneo e rename (`internal_storage_io.dart:28–36`).

`CanvasController.flushAutosave()` salva prima il recupero (`233`) e poi l'originale (`241`), una protezione utile. `_saveFile()` però serializza e scrive l'originale (`944–980`) senza creare necessariamente un checkpoint aggiornato: la prima modifica può essere salvata manualmente prima che scatti il timer. Dopo successo rimuove il recupero (`1001`). `retain` restituisce un bool che `exportToStorage()` non utilizza per segnalare l'impossibilità di mantenere il grant.

**Impatto:** arresto, errore di provider o memoria esaurita durante una sovrascrittura possono lasciare l'originale incompleto; la disponibilità di un checkpoint aggiornato non è garantita in tutti i percorsi. Non è stato simulato un arresto su provider Android reale. La documentazione di [ContentResolver](https://developer.android.com/reference/android/content/ContentResolver#openOutputStream(android.net.Uri,%20java.lang.String)) specifica modalità e comportamento dipendente dal provider.

**Correzione proposta:** completare e rendere durevole un checkpoint privato prima di **ogni** scrittura esterna; mantenerlo finché il documento scritto non è verificato secondo le capacità del provider. Usare documento temporaneo/sostituzione soltanto dove supportati e mantenere journal/versione precedente negli altri casi. Distinguere «copia esportata» da «percorso riapribile», gestendo il grant fallito.

**Regressioni:** errore a metà stream, chiusura app durante write, grant revocato, provider remoto offline, quota esaurita; dopo riavvio deve esistere almeno una versione completa verificabile.

### A06 — Collisioni degli ID nei recuperi

**Evidenza:** `XppFile.dart:50–56` conserva un `osipp-id` valido proveniente dal file. `AutosaveStore.save():44–74` identifica la voce precedente esclusivamente con quell'ID e ne cancella il file. `remove()` usa lo stesso criterio. Anche `WorkspaceSession.restore():57` seleziona per ID.

**Prova:** due note con lo stesso ID e percorsi diversi; salvando il secondo checkpoint rimane una sola voce e il precedente file di recupero viene eliminato. Succede anche senza attacco, copiando un `.xopp` o usando una copia esportata.

**Correzione proposta:** distinguere identità interna della voce di libreria dall'ID portabile del documento; assegnare nuova identità alle copie e ai conflitti. La chiave del recupero deve identificare la specifica istanza/origine autorizzata. Non usare un attributo importato come autorità per cancellare una risorsa locale. Migrare gli indici esistenti senza eliminarne versioni non riconciliate.

**Regressioni:** copie aperte insieme, Salva con nome, stesso ID su percorsi diversi, cancellazione di una copia, restore backup e riapertura della medesima nota.

### A07 — Preferenze usate come indice critico senza recupero transazionale

**Evidenza:** `autosave_store.dart:69–74` aggiorna un indice in SharedPreferences e cancella il vecchio checkpoint; `recent_documents.dart:72–115` aggiorna tag e libreria con due operazioni e rollback in memoria; `note_backup.dart:338–388` esegue rollback solo su eccezioni intercettate. Il processo può terminare tra file, indice e cancellazioni. Non è presente qui un journal durevole né una scansione dei checkpoint orfani al riavvio.

La [documentazione SharedPreferences](https://pub.dev/packages/shared_preferences) avverte che il ritorno della scrittura non garantisce persistenza su disco e sconsiglia dati critici. Passare alla variante Async da solo non fornisce una transazione fra documenti, indice e file.

**Impatto:** file ancora presenti ma non raggiungibili dalla libreria; indice che punta al checkpoint già eliminato; importazioni interrotte non riconciliate. Nel Web anche i byte degli appunti ripristinati/recuperi sono stringhe base64 nelle preferenze (`internal_storage_generic.dart:34–45`), quindi dipendono da quota e durata dello storage del browser.

**Correzione proposta:** archivio transazionale per metadati e journal delle operazioni, protocollo di commit dei file e recupero al riavvio. Conservare generazioni precedenti finché il commit non è durevole; garbage collection separata. Su Web usare storage adatto ai blob, transazioni e gestione esplicita della quota; un download resta un backup esterno, non può essere verificato come una scrittura locale.

**Regressioni:** arresto dopo ogni fase di restore/salvataggio, indici persi, scrittura preferenze fallita, orfani recuperabili, nessun rollback che cancelli file già appartenenti a un commit completato.

### A08 — Limite della cache immagini non rigido

**Evidenza:** `decoded_image_cache.dart:23–24` configura 32 MiB ma nessuna `maxDimension` per la cache condivisa; `84–90` decodifica a dimensione originale in assenza di quel parametro. `_trim():129–132` interrompe l'espulsione quando tutte le immagini sono pinned. `XppPageStack.dart:44–51` trattiene le immagini dei livelli visibili della pagina.

**Prova:** con budget di 1 byte, una PNG 1×1 pinned resta in cache usando 4 byte. La prova conferma la semantica del tetto superabile; non misura un OOM reale. Un'immagine 12.000×12.000 richiede circa 576 MB solo per i pixel RGBA, indipendentemente dalla piccola dimensione compressa.

**Correzione proposta:** validare dimensioni prima della decodifica; budget totale delle immagini attive, risoluzione proporzionata a viewport/zoom, tiled decode o sostituti a risoluzione inferiore quando necessario. Non espellere una risorsa mentre viene dipinta: serve una politica di qualità/pinning compatibile con il tetto, non soltanto un LRU più piccolo.

**Regressioni:** molte immagini nella stessa pagina, immagini enormi compresse, split view, zoom, apertura/chiusura ripetuta. Misurare heap Dart **e memoria nativa/GPU**. Il rilascio dell'ultima proprietà svuota la cache nel test: questo è consumo non limitato in uso, non un leak permanente già dimostrato.

### A09 — Audio non ancora confermato cancellato dal temporaneo

**Evidenza:** `NoteAudio.kt:58` elimina all'avvio tutti i file cache `osi-audio-*`; `77–81` legge il file e lo elimina dopo aver accodato la risposta al canale; `208` lo elimina alla chiusura. In Dart l'audio entra nel documento solo dopo `stop` (`note_audio_controller.dart:174–203`) e viene poi serializzato dall'autosave.

**Impatto:** un arresto tra registrazione, risposta Dart e checkpoint può perdere la registrazione; la pulizia del successivo avvio impedisce un recupero dell'eventuale file rimasto. Un contenitore audio non finalizzato può inoltre essere irrecuperabile: non si promette di recuperare qualunque interruzione.

**Correzione proposta:** directory di staging durevole con ID nota/registrazione e stato, registrazioni segmentate/finalizzate periodicamente, ACK dal salvataggio prima della cancellazione. Recuperare o segnalare segmenti orfani al riavvio; cache di playback separata e liberamente eliminabile.

**Regressioni:** process death durante registrazione, subito dopo stop e prima/dopo ACK, cambio scheda, permesso negato, errore del microfono e spazio esaurito, su dispositivo reale.

### A10 — Import Xournal lossy senza protezione dell'originale

**Evidenza:** `XppFile.dart:371–379` ignora stroke `eraser` e tool sconosciuti; i cicli importano soltanto i tipi riconosciuti. `fileversion` non viene verificato in lettura. Il serializer ricrea il documento dai tipi conservati e dichiara versione 4. Lo sfondo `pixmap` ha inoltre `render() => Container()` (`XppBackground.dart:86`), pur venendo serializzato.

**Prova:** un tratto eraser valido come struttura XML scompare da modello e round trip. L'importazione non emette un avviso. Dopo una modifica, l'autosave può sovrascrivere il percorso originale con la versione priva dei contenuti non gestiti.

**Correzione proposta:** report di compatibilità all'import, preservazione dei nodi ignoti quando sicura oppure apertura protetta con obbligo di salvare una copia. Evitare l'autosave sull'originale se l'import è lossy. Dichiarare puntualmente cosa supporta OSI rispetto a Xournal/Xournal++, comprese estensioni OSI, sfondi, cancellature, audio e flashcard.

**Regressioni:** corpus reale di documenti Xournal/Xournal++, versioni future, nodi sconosciuti, eraser e pixmap; nessuna perdita silenziosa dopo modifica/salvataggio.

### A11 — Le flashcard salvabili possono superare il limite del lettore

**Evidenza:** `CanvasController.saveFlashcard():141–150` limita il numero a 10.000, ma non i byte cumulativi. `XppFile.toXmlDocument():521` serializza tutte le schede. `NoteFlashcard.decode():47–50` interrompe la lettura quando la somma dei testi JSON supera **64 MiB**; schede invalide vengono saltate senza report. Ogni lato può includere un crop PNG codificato base64.

**Impatto:** un set creato regolarmente può essere scritto e poi riaperto con meno schede. La stessa perdita può avvenire durante la preparazione/ispezione di un backup, perché passa dal lettore ordinario. Non è stato creato un set da oltre 64 MiB nella prova, per evitare allocazioni inutili.

**Correzione proposta:** contratto unico di limiti per creazione, modifica, import e salvataggio; conta preventiva dei byte serializzati, limite dei crop e deduplicazione media. In alternativa formato paginato per set grandi. Il lettore deve distinguere «documento completo» da «recupero parziale», non troncare senza avviso.

**Regressioni:** soglia esatta e oltre soglia, modifiche che aumentano un lato, migrazione, round trip e backup con verifica del conteggio e contenuto di ogni scheda.

### A12 — Recupero obsoleto preferito a un originale più recente

**Evidenza:** `workspace_session.dart:57–76` prova prima il recupero e legge l'originale soltanto se il recupero fallisce. Non confronta revisione, timestamp o contenuto. Il risultato viene marcato `recovered`; `CanvasController.init():397` lo marca modificato, avviando l'autosave.

**Prova:** checkpoint del 1 gennaio e originale dello stesso documento del 2 gennaio: il workspace ripristina quello del 1 gennaio. Può capitare quando un file viene modificato esternamente dopo la chiusura o dopo una pulizia dei recuperi non riuscita. Il successivo autosave può propagare la versione vecchia sull'originale.

**Correzione proposta:** riconciliazione tra generazioni, origine e hash/revisione; date come indizio, non unica autorità. In caso di conflitto conservare entrambe le copie e far scegliere prima di scrivere sull'originale. Un recupero non verificato non deve autorizzare una sovrascrittura automatica.

**Regressioni:** file modificato da un altro dispositivo, orologio diverso, checkpoint vecchio, errori di pulizia, origine non accessibile e ID duplicati.

### A13 — La pipeline Web elimina configurazione necessaria

**Evidenza:** `.github/workflows/build.yml:39` elimina `web` e lo rigenera. `web/index.html:13–17` contiene l'inizializzazione di `pdfjsLib`, assente nel template standard. La dipendenza locale `pdfx 2.11.0`, `lib/src/renderer/web/pdfjs.dart:25–28`, richiede quella variabile globale. La pipeline non contiene un ripristino equivalente né test del PDF. Windows e Linux sono anch'essi rigenerati, quindi personalizzazioni future andrebbero perse.

**Impatto atteso:** artefatto compilato con successo ma apertura PDF Web non funzionante. Non è stato distribuito o provato in browser un nuovo artefatto CI durante questa analisi.

**Correzione proposta:** versionare i runner/configurazioni mantenuti, evitando rigenerazione distruttiva a ogni build; smoke test del vero artefatto con PDF sintetico. Aggiungere PR gate con analyze, test, regressioni di sicurezza e verifica dell'assenza del vecchio motore. Fissare versione Flutter, privilegio minimo del token CI e riferimenti immutabili delle azioni.

### A14 — Firma release di sviluppo

**Evidenza:** `android/app/build.gradle:40–45` usa `signingConfigs.debug` anche in release; il workflow pubblica quell'APK come artefatto.

**Impatto:** identità e continuità degli aggiornamenti non gestite come distribuzione di produzione; runner effimeri possono usare chiavi differenti, impedendo aggiornamenti in-place. Non significa che ogni debug keystore abbia la stessa chiave privata, né dimostra che un estraneo possa già firmare un aggiornamento valido.

**Correzione proposta:** chiave release stabile e protetta, segreti CI con accesso minimo, verifica del certificato atteso nell'artefatto, piano di rotazione e aggiornamento senza disinstallazione/perdita degli appunti. Bloccare pubblicazione con firma debug. Riferimento: [firma delle app Android](https://developer.android.com/studio/publish/app-signing).

### A15 — Indici corrotti non isolati

**Evidenza:** `RecentDocuments.list():44–48` e `AutosaveStore.list():35–38` eseguono JSON decode/cast senza recupero locale; il secondo assume anche `time` intero. `OpenPage._loadRecentFiles():144–146` dipende da entrambi senza catch. `WorkspaceSession.restore()` intercetta l'errore ma può così rinunciare all'intero ripristino.

**Impatto:** un record o JSON corrotto rende indisponibile l'intera lista, pur con `.xopp` intatti. Non è necessariamente un exploit remoto: può seguire una migrazione o una scrittura incompleta.

**Correzione proposta:** schema versionato, validazione per record, quarantena del dato originale, ricostruzione dell'indice da archivio/journal e UI di recupero. Non sostituire silenziosamente un indice invalido con una lista vuota e sovrascriverlo.

**Regressioni:** JSON troncato, tipo sbagliato, un record guasto tra record sani, preview invalida, migrazione interrotta.

### A16 — PDF annullati conservati inutilmente

**Evidenza:** `canvas_controller.dart:682` inserisce i byte in `_pdfSources` prima del dialogo; `703` ritorna su annullamento senza rimuoverli. L'eliminazione complessiva avviene in `dispose():451`. Import ripetuti con percorsi diversi accumulano byte anche senza aggiungere pagine.

**Correzione proposta:** mantenere i byte nella variabile locale fino alla conferma; trasferire la proprietà solo all'inserimento, eliminare staging su annullamento/errore, deduplicare gli allegati. Testare dieci import annullati verificando che i buffer trattenuti ritornino al livello iniziale. È ritenzione legata alla vita della scheda, non un leak permanente dimostrato dopo dispose.

### A17 — Dipendenza di avvio Web dal CDN

**Evidenza:** `web/index.html:13–20` importa PDF.js 4.6.82 da jsDelivr e soltanto dopo avvia Flutter. Il worker e le cMap sono anch'essi remoti; non c'è fallback nel file. Una rete indisponibile può impedire l'avvio anche delle funzioni che non usano PDF.

**Sicurezza:** codice remoto caricato nella pagina partecipa al suo contesto applicativo. Il pin della versione è utile ma non equivale a ospitare e verificare il pacchetto. Nessun advisory specifico di PDF.js è stato verificato qui: non si afferma che questa versione contenga una particolare CVE. Le intestazioni del server di pubblicazione non sono state esaminate.

**Correzione proposta:** dipendenze Web servite insieme all'app e aggiornate con lock/hash, avvio separato dal caricamento PDF, Content Security Policy adeguata e test offline/cache. Il JavaScript necessario al prodotto Web va distinto dal runtime dei plugin: bloccare quest'ultimo non significa eliminare tutto il JavaScript della pagina.

### A18 — Backup ed export con picchi di memoria elevati

**Evidenza:** `NoteBackup.create():46–121` conserva tutte le note decodificate; `encode():173–197` mantiene anche tutti i payload; `_encode()` costruisce l'archivio completo. `inspect():301–329` mantiene payload e note, mentre `restore()` crea ulteriori snapshot. `document_export.dart:87–94` copia tutte le pagine prima di preparare l'export e conserva le parti fino alla generazione del PDF.

**Impatto:** archivi perfettamente legittimi entro 512 MiB possono superare la RAM disponibile per copie, XML/base64, modello e immagini. Un isolate non ha un limite di memoria separato dal processo. Su Web `compute` usa l'event loop corrente, come documentato da [Flutter](https://api.flutter.dev/flutter/foundation/compute.html), quindi non garantisce che questa elaborazione lasci libera la UI.

**Correzione proposta:** pipeline per nota/pagina verso staging su disco, manifesto incrementale, budget globale RAM/temporanei, progresso e annullamento; snapshot consistenti senza duplicare tutta la libreria. Dimensioni massime del formato e budget di lavoro devono essere separati.

**Regressioni:** librerie crescenti e PDF con media ripetuti, dispositivo con poca RAM, annullamento e quota disco; verificare contenuto del backup e picco RSS, non solo durata o FPS.

## Plugin e documentazione: cosa resta valido

- JavaScript viene rifiutato prima della sessione (`plugin_controller.dart:588`); i runner in `plugin_script.dart` e `plugin_script_native.dart` sollevano sempre errore. FJS non compare nelle dipendenze dell'app. Il vecchio motore nel progetto forense `tool/plugin_engine_audit` non è una funzione distribuibile dell'app.
- I test esistenti di blocco JavaScript, permessi, pacchetti ZIP, annullamento e indirizzi di rete continuano a passare. La rete usa host dichiarati, HTTPS, verifica degli IP, connessione all'IP verificato, nessun redirect e limiti delle risposte. Non è stato trovato un nuovo bypass di queste verifiche in questo audit.
- I workflow modificano una copia e verificano la revisione prima del commit. `extendApi` resta codice del nucleo compilato, con i privilegi dell'app: ogni nuova API deve essere sottoposta alla stessa analisi degli ingressi.
- La frase «limiti di elaborazione» va precisata: **A01 dimostra che i limiti attuali non coprono tutte le allocazioni**. La guida non dovrebbe essere letta come garanzia di isolamento assoluto. Dopo la correzione servono test adversariali anche per il DSL, non soltanto per JavaScript.
- `PLUGIN_GUIDE.md` e `docs/PLUGIN_SECURITY.md` sono documentazione locale verificabile. La wiki remota non è stata riletta in questo audit; il precedente rapporto ne documenta l'inaccessibilità. Non si dichiara aggiornata o completa una wiki remota non verificata.
- L'estensibilità può essere ampia nelle funzionalità, ma non deve includere capacità illimitate su memoria, rete, filesystem o codice nativo. Nuove capacità vanno aggiunte come API ristrette, con permessi e budget verificabili.

L'utente che modifica il binario o ricompila una propria variante è fuori dal confine del software distribuito: non è possibile impedire in assoluto al proprietario del dispositivo di eseguire altro software. L'obiettivo verificabile è che **file, manifest, preferenze e UI dell'app ufficiale non possano abilitare un runtime vietato**.

## Rimandi a Xournal / Xournal++

L'[inventario completo](docs/validation/astra-xournal-references.txt) riporta percorso, riga e testo per i file tracciati nell'ambito descritto. Non è una ricerca nei binari compilati, nella cronologia Git o in tutte le dipendenze scaricate. I riferimenti hanno ruoli diversi:

| Categoria | Riferimenti verificati | Indicazione |
|---|---|---|
| Nome del pacchetto Dart | `pubspec.yaml:1`, import `package:xournalpp/` in app e test | Nome tecnico; rinomina coordinata, non sostituzione cieca |
| Classe applicazione | `lib/main.dart:14–36`, `XournalppMobile` | Retaggio interno, rinominabile insieme ai riferimenti |
| Identità Android | `android/app/build.gradle:20,33`, package Kotlin `online.xournal.mobile` | Cambiare applicationId crea una diversa identità applicativa: pianificare migrazione e accesso ai vecchi appunti |
| Canali nativi | `MainActivity.kt:16`, `DocumentStorage.kt:14`, `NoteAudio.kt:20`, `PluginOcr.kt:14` e controparti Dart | Cambiare in entrambi i lati; non sono automaticamente ingressi IPC esposti ad altre app |
| Directory dei dati | `internal_storage_io.dart:8`, sottocartella `xournalpp` | Non rinominare senza migrazione verificata e fallback: altrimenti i file sembrano scomparsi |
| Formato documentale | `XppFile.dart:210,488`, radice `xournal`; `504`, URL storico nel titolo; modelli `Xpp*` | Mantenere la radice per compatibilità. Il testo del titolo è metadato statico, non una richiesta HTTP automatica |
| UI e traduzioni | `widgets/app_info_dialog.dart:40`, `lib/l10n/intl_{en,de,pt}.arb`, `lib/generated/` | L'attribuzione della derivazione è utile. Separare branding OSI da descrizioni legacy; modificare le sorgenti e rigenerare le traduzioni |
| Distribuzione/documenti | `.github/workflows/build.yml:26,44,64,82`, `COME-COMPILARE.md`, `README.md:90`, `SPEC.md`, `ARCHITECTURE.md` | I nomi artefatto sono ancora `xournalpp-mobile-*`; la guida di compilazione conserva link/nomi del progetto precedente |
| Provenienza | `scripts/audit_upstream.py`, `docs/analisi-provenienza-e-ottimizzazioni.md`, `LICENSE` | Conservare storia e attribuzioni; la precedente percentuale di somiglianza descrive un altro commit, non questa revisione |
| Compatibilità e commenti | `ShapeRecognizer.dart`, `XppBackground.dart`, `docs/audio-notes.md`, `DOCUMENT_EXPORT.md`, `TESTING.md`, `PIXEL_ERASER.md`, test XOPP | Rimandi funzionali; non implicano compatibilità completa delle estensioni OSI con altri editor |
| Residui build | `.gitignore` contiene `debian/xournalpp-mobile`; runner desktop generati non tracciati | Verificare anche nome prodotto, eseguibile e metadati del pacchetto finale quando si stabilizzano i runner |

Non ho eliminato attribuzioni o cambiato licenze. Non ho rifatto il confronto quantitativo con upstream né verificato online la disponibilità attuale dei link storici: questo inventario riguarda il progetto locale. I riferimenti a Xournal, da soli, non costituiscono una vulnerabilità.

## Riscritture e ottimizzazioni consigliate

Le proposte seguenti derivano dal codice attuale; non sono promesse di un guadagno già misurato. Alcune risolvono anche criticità sopra descritte.

| Intervento | Evidenza e beneficio atteso | Vincoli e misura del risultato |
|---|---|---|
| Undo per operazioni/dati immutabili | `canvas_controller.dart:1305–1360`, `content_snapshot.dart:7–23`: ogni snapshot clona tutti i punti della pagina; fino a 50 copie | Evitare copia integrale per singolo tratto; conservare semantica di gomma/livelli/plugin. Misurare latenza al primo punto, heap e undo/redo su pagine dense |
| Autosave incrementale + allegati separati | `flushAutosave():229–233`, `XppFile.dart:485–533`: ricostruzione XML/base64/GZIP di tutta la nota dopo modifiche | Journal del contenuto, media immutabili per hash, checkpoint compattati. Prima garantire recupero dopo crash; non sacrificare portabilità del backup |
| Backup/import per stream | A02/A18; attualmente intera libreria e payload in RAM | Memoria di lavoro quasi indipendente dal numero di note; verificare conteggi/hash e rollback dopo interruzione |
| Cache immagini a risoluzione adattiva | A08; decode originale e pinning superano il tetto | Budget globale per entrambe le viste, anteprime a bassa risoluzione e dettaglio su richiesta; misurare RSS/GPU e qualità |
| Import PDF con un solo handle | `XppFile.importPdf():96–119` chiama `pdfPageSize` per pagina; `PdfImage.dart:35` riapre il documento ogni volta | Aprire una volta, visitare pagine serialmente, chiudere in finally. Il percorso `_insertPdfAt` già usa un approccio diverso: unificare gli ingressi ed evitare duplicazione |
| Griglie visibili/riutilizzabili | Cicli in `XppBackground.dart`; export già tratta il dotted come raster limitato | Disegnare solo il clip, shader/pattern ripetibile o livello di dettaglio. Il canvas infinito richiede limiti indipendenti dall'estensione logica |
| Miniature per revisione della pagina | `widgets/document_navigator.dart` confronta `pluginRevision` globale | Invalidare solo pagine interessate; includere undo, sfondi, livelli e inserimenti. Contare render delle miniature, non soltanto rebuild widget |
| Export PDF con media deduplicati | `document_export.dart:87–94` e raccolta `exportPages` | Evitare snapshot duplicati e immagini identiche ripetute; mantenere il percorso vettoriale già esistente. Misurare dimensione PDF, RSS e qualità/stampa |
| Ricerca della libreria indicizzata | `RecentDocuments` e `AutosaveStore` riscrivono JSON completo con preview base64 | Database/indice separato dalle miniature; query e aggiornamenti per record, ricostruibilità e transazioni |
| Proprietà esplicita dei buffer PDF | A16, `_pdfSources` e `pdfAttachments` | Trasferire proprietà alla conferma e deduplicare per contenuto; verificare import annullato/fallito e chiusura scheda |

Sono già presenti virtualizzazione delle pagine, cache PDF con limiti, rilascio esplicito di numerosi `ui.Image`, codec, picture, PDF page/document, e guardie su risultati asincroni. Non conviene riscriverli indiscriminatamente. Il precedente rapporto di provenienza descrive ottimizzazioni già implementate, incluse parti dell'export e della geometria: le sue righe e percentuali non vanno riutilizzate come situazione corrente.

## Best practice e criteri per le modifiche future

1. **Un contratto di dati unico.** Ogni dato salvabile deve poter essere riletto integralmente. Limiti condivisi per creazione, import, plugin, clipboard, flashcard, audio e backup; migrazioni versionate e test di round trip.
2. **Dati esterni senza autorità implicita.** Un ID, percorso, MIME, nome ZIP o dimensione dichiarata non autorizza accessi/cancellazioni né sostituisce la verifica effettiva. I grant locali devono stare fuori dal documento importato.
3. **Limiti prima delle allocazioni.** Budget per input compresso, output espanso, alberi, geometria, immagini decodificate e risultato cumulativo. Timeout e isolate non sostituiscono questi controlli.
4. **Salvataggio come protocollo.** Staging durevole → verifica → commit → aggiornamento indice → pulizia differita. Conservare almeno una generazione precedente e riconciliare gli orfani all'avvio. Mai cancellare l'unica copia in base a un attributo importato.
5. **Conflitti conservativi.** Distinguere modifica esterna, copia dello stesso documento e recupero pendente; mantenere entrambe le versioni quando la precedenza non è certa.
6. **Proprietà e cancellazione esplicite.** Ogni risorsa nativa/timer/subscription/job ha un proprietario e un punto di chiusura; rifiutare risultati tardivi, deduplicare lavori e pulire staging di operazioni annullate. Profilare anche memoria nativa e file temporanei.
7. **Capacità dei plugin ristrette.** Tutte le API validano permesso, sessione, input/output, effetto cumulativo e deadline. Niente valutatori generici, shell o loader come scorciatoie. Una nuova API compilata è nuovo codice privilegiato da revisionare.
8. **Decoder aggiornati e ingressi ridotti.** Inventario/SBOM con versioni risolte, controllo advisory automatizzato e test su documenti sintetici malformati. Per elaborazioni native particolarmente esposte valutare isolamento di processo dove la piattaforma lo consente; non promettere un confine che non esiste.
9. **Trasparenza sull'import parziale.** Contenuti non supportati o corrotti devono produrre un avviso e protezione dell'originale. Un backup non può dichiararsi completo se il lettore ha scartato schede/audio/elementi senza conteggio.
10. **Distribuzione riproducibile.** SDK e dipendenze risolte fissati, azioni CI ristrette, test obbligatori su PR, chiavi release protette, controllo dei binari distribuiti. Testare il prodotto generato, non soltanto il codice sorgente.
11. **Riservatezza dei backup.** L'attuale ZIP contiene dati leggibili, comprese registrazioni e flashcard; non equivale a un archivio cifrato. Se richiesta cifratura, usare un formato autenticato e librerie mantenute, con gestione chiavi e prove di recupero. Definire anche la politica Android di backup/trasferimento di sistema e lo storage Web.
12. **Test distruttivi confinati.** Fault injection e fuzzing in processi/dispositivi di test con dati sintetici, limiti di memoria/tempo e nessun accesso a file personali. Inserire regressioni per ogni difetto risolto, evitando test che riflettano solo l'implementazione.

## Ordine di lavoro suggerito

1. Chiudere **A01–A04**: limiti realmente applicati ai workflow/documenti e autorizzazione degli allegati. Sono ingressi che possono essere influenzati da contenuti esterni.
2. Proteggere i dati con **A05–A07, A10–A12, A15**: checkpoint durevoli, identità e conflitti, import non distruttivo, simmetria dei limiti e recupero degli indici.
3. Prima della distribuzione, correggere **A13–A14** e provare i reali artefatti Android/Web. Consolidare anche il caricamento Web di A17.
4. Ridurre memoria e recuperare operazioni interrotte con **A08–A09, A16, A18**, poi intervenire su undo e autosave incrementale con benchmark e prove di crash.

Il criterio di completamento non è soltanto «i test passano»: serve dimostrare che input ostili vengono rifiutati entro un budget, che un'interruzione lascia una copia completa recuperabile e che gli artefatti distribuiti conservano le protezioni verificate.
