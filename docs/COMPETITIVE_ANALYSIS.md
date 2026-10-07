# OSIpp: confronto con Goodnotes, Jnotes e Notein

Data: 7 ottobre 2026. Analisi delle SPEC e del codice attuale; le funzioni dei concorrenti sono documentate dai produttori, non verificate con prove comparative su dispositivi. Disponibilità, lingue, piattaforme e abbonamenti possono differire. Priorità e difficoltà qui indicate sono valutazioni progettuali.

## Da dove parte il progetto

**Aggiornamento successivo al confronto:** canvas infinito, autosalvataggio con recupero e livelli gestibili sono stati implementati su richiesta. Le valutazioni del gap riportate sotto fotografano lo stato precedente a questo intervento; per lo stato aggiornato e i limiti consulta [la documentazione delle tre funzioni](CANVAS_WORKSPACE.md).

La [SPEC principale](../SPEC.md) descrive un quaderno per stilo, PDF, file XOPP, tag, Pomodoro, personalizzazione e documenti affiancati. `.gsd/SPEC.md` registra soprattutto interventi di stabilità e prestazioni. Nessuna delle due descrive completamente le aggiunte recenti: selezione/copia/spostamento, incolla con pressione prolungata, esportazione PDF e sistema plugin avanzato. Prima di pianificare nuove funzioni conviene riallineare la SPEC al prodotto, mantenendo separati requisiti, implementazioni e prove su hardware.

Il progetto ha già una base interessante: lavoro locale, formato modificabile XOPP, PDF annotati, penna/gomma/forme, schede e split, clipboard condivisa e Pomodoro. Il sistema plugin aggiunge workflow guidati, JavaScript modulare, LaTeX composto, export TSV per Anki, OCR locale Android, moduli e HTTPS. Non considero quindi “aggiungere OCR”, “aggiungere flashcard” o “aggiungere lo split” nuove feature: sono già presenti, seppure con livelli di integrazione diversi.

## Cosa emerge dai concorrenti

**Goodnotes** collega ricerca, conversione della grafia e assistenza sui contenuti; offre inoltre ripasso con ripetizione dilazionata. La documentazione più recente presenta lavagna infinita, diagrammi e collaborazione. La disponibilità concreta va distinta per dispositivo e piano. Fonti: [AI e ricerca](https://www.goodnotes.com/ai), [Smart Learn](https://support.goodnotes.com/hc/en-us/articles/7353742985487-Study-with-Smart-Learn), [nuovi formati e collaborazione](https://support.goodnotes.com/hc/en-us/articles/13724030806927-What-s-new-for-the-September-launch).

**Jnotes** descrive ricerca nella grafia, registrazioni sincronizzate agli appunti, cartelle multilivello, backup Google Drive e strumenti di studio. Per il confronto considero queste capacità dichiarate; non assumo prestazioni, accuratezza OCR o una sincronizzazione automatica completa. Fonte: [scheda pubblicata dallo sviluppatore su Google Play](https://play.google.com/store/apps/details?id=com.jideos.jnotes.overseas.google).

**Notein** mette in evidenza canvas infinito, link bidirezionali, indice e livelli; il centro assistenza descrive anche audio, righello, commenti e materiali riutilizzabili. Sono riferimenti particolarmente pertinenti a un quaderno Android. Fonti: [funzioni](https://www.notein.ai/features), [pagina standard e canvas infinito](https://help.notein.ai/category/getting-started/standard-note-vs-infinite-canvas?lang=en), [strumenti editor](https://help.notein.ai/category/editor-tools?lang=en), [creazione e salvataggio automatico](https://help.notein.ai/category/getting-started/creating-a-new-notebook?lang=en).

## Gap verificati nel codice

| Area | Stato di OSIpp | Evidenza |
| --- | --- | --- |
| Ricerca | Il pulsante nella libreria non esegue azioni; manca ricerca globale nei contenuti | `lib/pages/OpenPage.dart`, `onPressed: () {}` del pulsante Search |
| Organizzazione | Tag predefiniti e file recenti; nessuna libreria gerarchica completa individuata | `OpenPage.dart`, filtro `selectedTag` |
| Recupero | Salvataggio manuale e protezione della chiusura presenti; nessun autosalvataggio/recupero da arresto individuato | `canvas_controller.dart`, `workspace_controller.dart`, `unsaved_document_dialog.dart` |
| Livelli | Il modello XOPP contiene più livelli; manca un gestore con nomi, visibilità e blocco | `lib/src/XppLayer.dart`; scrittura corrente sul primo livello |
| Navigazione | Schede, pagine e split presenti; nessun sistema di link fra note, backlinks o indice personale individuato | modello `XppContent`, controller e UI di navigazione |
| Studio | Flashcard testuali esportabili per Anki tramite plugin; niente ripasso interno, occlusioni o collegamento alla selezione | `lib/plugins/plugin_examples.dart`, `plugin_services.dart` |
| Audio | Pomodoro presente, ma nessuna registrazione audio associata ai tratti individuata | `PomodoroTimer.dart`, modello dei contenuti |
| PDF esportato | Il PDF viene composto come immagini di pagina; testo non selezionabile e inchiostro non vettoriale | `lib/src/document_export.dart` |
| Canvas | Pagine con dimensioni definite; lo scorrimento di più pagine non equivale a una superficie infinita | `XppPageSize.dart`, `virtual_page_column.dart` |

“Non individuato” indica il risultato dell'ispezione del codice applicativo, non una prova esaustiva su tutte le piattaforme. I livelli del formato non equivalgono a livelli gestibili nell'editor; OCR su richiesta non equivale a un indice ricercabile della libreria.

## Feature proposte, con priorità

### 1. Autosalvataggio locale, recupero e cronologia — prima priorità

Salvare copie di recupero senza chiedere una destinazione a ogni modifica. Dopo un arresto, proporre il recupero dei documenti aperti, compresi quelli mai salvati. Conservare alcune versioni e consentire di confrontarle/ripristinarle. Questo completa i salvataggi sicuri già implementati e riprende la continuità d'uso del salvataggio automatico descritto da [Notein](https://help.notein.ai/category/getting-started/creating-a-new-notebook?lang=en).

**Prima versione:** salvataggio differito dopo il gesto, copia locale atomica, recupero dopo riavvio e indicazione dell'ultimo salvataggio. La chiusura non deve lasciare un file parziale; undo/redo e tratti in corso vanno trattati coerentemente. **Complessità:** medio-alta. **Sede:** nucleo dell'app; provider cloud in un secondo momento. Backup e sincronizzazione sono due problemi distinti.

### 2. Ricerca unica in quaderni, PDF e testo riconosciuto — prima priorità

Scrivere “derivata” e trovare la pagina giusta, con anteprima e salto al risultato. Partire da titolo e testi digitati, poi indicizzare il testo dei PDF e i risultati OCR. Il riconoscimento affidabile della grafia richiede un provider adatto: l'OCR di immagini già aggiunto non garantisce automaticamente questo risultato. Riferimenti: [ricerca Goodnotes](https://www.goodnotes.com/ai), [OCR Search Jnotes](https://play.google.com/store/apps/details?id=com.jideos.jnotes.overseas.google).

**Prima versione:** il pulsante ricerca funziona; risultati divisi per documento e pagina. L'indice si aggiorna solo per le pagine cambiate, senza bloccare la penna. **Complessità:** media per testi/titoli, alta per PDF/grafia. **Sede:** indice e navigazione nel nucleo; riconoscitori come provider/plugin.

### 3. Livelli usabili — seconda priorità

Separare “PDF”, “Appunti”, “Correzioni” e “Soluzioni”; nascondere o bloccare un livello. In particolare, una gomma non dovrebbe modificare contenuti in un livello bloccato. [Notein](https://help.notein.ai/category/editor-tools?lang=en) documenta mostra/nascondi, blocco e riordino.

**Prima versione:** livello attivo, nomi, visibilità, blocco e riordino, applicati anche a selezione, undo e plugin. **Complessità:** media-alta: il modello è già stratificato, ma gli strumenti scrivono sul primo livello. **Sede:** nucleo e nuove API per i plugin.

### 4. Link fra pagine, segnalibri e rimandi di ritorno — seconda priorità

Collegare una dimostrazione alla pagina del teorema, una nota al PDF sorgente o una voce di planner alla giornata. Toccare un rimando apre la pagina; i backlinks mostrano chi rimanda alla nota. I link bidirezionali e gli indici sono documentati da [Notein](https://www.notein.ai/features).

**Prima versione:** segnalibri nominati e collegamenti interni che sopravvivono a rinomina e riordino delle pagine. **Complessità:** media. **Sede:** identità stabili e navigazione nel nucleo; generatori di indici/planner come plugin. Nomi e indici numerici da soli non sono identificatori sufficientemente stabili.

### 5. “Seleziona e studia”: flashcard visive e occlusioni — seconda priorità

Selezionare con il lazo una definizione, formula o figura e crearne una scheda. Coprire parti di un diagramma per interrogarsi, ritrovare la pagina originale e ripassare una coda giornaliera. Il ripasso dilazionato è il riferimento di [Goodnotes Smart Learn](https://support.goodnotes.com/hc/en-us/articles/7353742985487-Study-with-Smart-Learn).

**Prima versione:** selezione → fronte/retro con immagine, modifica e riferimento alla pagina; export Anki con media come sviluppo successivo. Il TSV attuale conserva solo testo: non basta per trasferire immagini o occlusioni. **Complessità:** media per il flusso; medio-alta per media e ripasso. **Sede:** plugin di studio, con API `selection.read`/render della regione e riferimenti persistenti da aggiungere al nucleo.

### 6. Audio sincronizzato alla scrittura — terza priorità

Durante la lezione registrare e scrivere; toccando una nota, riascoltare quel momento. È una capacità dichiarata da [Jnotes](https://play.google.com/store/apps/details?id=com.jideos.jnotes.overseas.google) e descritta fra gli strumenti [Notein](https://help.notein.ai/category/editor-tools?lang=en).

**Prima versione:** registrazione, pausa/ripresa, marcatori associati a pagine/tratti e riproduzione dal marcatore. Gestire permesso microfono, interruzioni e persistenza degli allegati. La trascrizione può arrivare dopo. **Complessità:** alta. **Sede:** acquisizione e temporizzazione nel nucleo; trascrizione/riassunti come plugin.

### 7. PDF di qualità documentale — seconda priorità

Conservare testo del PDF originale, link e nitidezza dell'inchiostro, anziché rasterizzare l'intera pagina. È un miglioramento derivato dal limite verificato in OSIpp, non un giudizio sulla qualità dei PDF esportati dai concorrenti.

**Prima versione:** preservare le pagine PDF originali e aggiungere annotazioni, verificando separatamente gomma, trasparenze e immagini. Offrire l'export raster come percorso compatibile. **Complessità:** alta: richiede un motore di composizione/modifica PDF appropriato. **Sede:** nucleo dell'export, riutilizzabile dai plugin.

### 8. Canvas infinito e diagrammi con collegamenti — terza priorità

Per mappe concettuali e brainstorming, una superficie che cresce in entrambe le direzioni con minimappa, nodi e frecce agganciate. Riferimenti: [canvas Notein](https://help.notein.ai/category/getting-started/standard-note-vs-infinite-canvas?lang=en), [lavagna e diagrammi Goodnotes](https://support.goodnotes.com/hc/en-us/articles/13724030806927-What-s-new-for-the-September-launch).

**Prima versione:** un tipo di documento distinto, navigazione e export per regione. La libertà di spostarsi oltre il bordo di una pagina non è sufficiente; servono rendering per zone e un formato coerente. **Complessità:** alta. **Sede:** canvas nel nucleo; generatori di mappe e diagrammi come plugin.

## Aggiunte più piccole ma utili

- **Cartelle multilivello, tag modificabili, preferiti e modelli personali:** migliorano subito la libreria attuale. Riferimenti: [organizzazione Jnotes](https://play.google.com/store/apps/details?id=com.jideos.jnotes.overseas.google), [template Notein](https://www.notein.ai/features). Non riproporre come nuova funzione gli sfondi a righe/griglia già presenti.
- **Biblioteca di elementi:** salvare una selezione come simbolo, sticker o schema riutilizzabile; utile per circuiti, matematica e planner. Riferimento: [strumenti Notein](https://help.notein.ai/category/editor-tools?lang=en). Richiede una biblioteca persistente, oltre alla clipboard temporanea già presente.
- **Righello e allineamento:** il riconoscimento delle forme esiste; mancano guide persistenti, agganci e distribuzione ordinata degli oggetti. Non sostituire gli attuali strumenti geometrici.
- **Editor di formule modificabili:** il plugin LaTeX compone immagini corrette, ma il sorgente non è un elemento matematico editabile del foglio. Conservare sorgente e anteprima permette riapertura e modifica.
- **Catalogo e laboratorio plugin:** esempi navigabili, controllo della compatibilità, editor a blocchi per workflow e anteprima su un documento temporaneo. Valorizza il sistema appena aggiunto senza imporre codice agli utenti meno esperti.

## Ordine di sviluppo consigliato

1. Riallineare la SPEC; autosalvataggio/recupero; ricerca di base e libreria.
2. Livelli, link e identità persistenti; export PDF che preserva l'originale.
3. Selezione → flashcard e biblioteca di elementi; API per plugin di studio.
4. Audio e canvas infinito; provider AI opzionali a valle di testo e riferimenti disponibili.

**Scelta consigliata per il prossimo ciclo: autosalvataggio + ricerca + livelli.** Sono funzioni utili quotidianamente e rendono più solidi i plugin successivi. Una chat AI o riassunti possono essere plugin avanzati, ma l'indicizzazione, il recupero del lavoro e l'accesso coerente ai documenti devono essere garantiti dall'app.

Due aspetti della SPEC esistente meritano inoltre una verifica dedicata: ripristino della workspace dopo riavvio e due viste dello stesso quaderno. Il controller mantiene la workspace in memoria e forza due documenti distinti quando attiva lo split. Questo non certifica i due casi più ampi descritti nella SPEC; non li tratto come nuove idee da aggiungere, ma come requisiti da precisare o completare.

Non sono state implementate le feature proposte né modificati i requisiti per considerarle approvate. Questa analisi è il documento di valutazione per la prossima roadmap.
