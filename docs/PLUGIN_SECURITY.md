# Sicurezza ed estensibilità dei plugin

Revisione: 10 ottobre 2026. Documentazione operativa: [guida plugin](../PLUGIN_GUIDE.md). È stata verificata la guida nel repository; la wiki GitHub separata non è risultata accessibile (`Repository not found`). Questo documento non presume di aver aggiornato una wiki remota.

## Esito

Il sistema disponeva già di permessi per azione, copie dei contenuti, commit finale, undo e limiti di elaborazione. Non era però adatto a codice JavaScript ostile. La dipendenza FJS 3.2.0 comprende un fallback per moduli dal filesystem: una prova con un file temporaneo innocuo ha caricato un modulo esterno anche usando `JsBuiltinOptions()` senza builtin. Non abbiamo dimostrato esecuzione di una libreria nativa o lettura arbitraria di qualsiasi formato; il caricamento di sorgenti esterni basta comunque a invalidare il confine promesso.

**Il motore è stato rimosso dalle dipendenze dell'app. JavaScript viene rifiutato nel controller prima di creare la sessione; anche i precedenti runner sono bloccati.** Non esistono preferenze, permessi, flag del manifest, interruttori o runner sostituibili per abilitarlo nell'app distribuita. Un plugin JavaScript può essere conservato per conversione, ma non eseguito. La prova del vecchio motore è in un progetto separato, non incluso nel prodotto.

## Problemi corretti

| Problema | Correzione e prova |
| --- | --- |
| Import JavaScript esterno al pacchetto | Rimozione FJS/bridge dalle dipendenze; blocco controller e runner; tentativi con permessi completi e preferenze/flag di bypass rifiutati |
| ZIP corrotti, nomi duplicati, link e dimensioni dichiarate false | Lettura dei metadati prima della decompressione, percorsi consentiti, niente link/directory/cifratura, CRC esplicito; output DEFLATE limitato durante la decompressione |
| Default o scelte invalidi provocavano errori nella UI | Tipi/default validati, scelte uniche e limitate prima di costruire il modulo |
| Limiti dei testi aggirabili tramite azioni host | Controlli sulle azioni di inserimento e modifica, budget cumulativo di testi/immagini e punti |
| Scala ripetuta poteva produrre geometrie enormi | Controllo dei limiti sul risultato della trasformazione; sessione invalidata su errore |
| Annullamento attendeva un provider pendente | Gara tra esecuzione, annullamento e deadline; sessione invalidata immediatamente, client e dialoghi del plugin chiusi, risultati tardivi scartati |
| Permessi/default modificabili dopo la validazione | Manifest profondamente immutabile e copia dei permessi registrati; dati JSON controllati alle API |
| HTTPS consentiva indirizzi interni o DNS modificabile | Solo host dichiarati, IP pubblici verificati e connessione all'IP verificato, TLS per l'host originale, niente proxy/redirect/header di routing; test IPv4, IPv6 e risposte DNS miste |
| Installazione/aggiornamento senza riepilogo preventivo | Consenso con accessi e server richiesti prima di installare ogni versione |
| Stato Anki malformato poteva rompere la vista | Lettura tollerante dei dati legacy e controllo dello stato persistito |

La rete dei plugin sul Web è disabilitata: il browser non permette questa verifica e il vincolo DNS. LaTeX e OCR hanno esempi JSON; i plugin integrati Pomodoro e flashcard continuano a funzionare. Gli esempi JavaScript storici non costituiscono un percorso alternativo di esecuzione.

## Cosa protegge questo modello

Un file plugin è un dato interpretato dal nucleo: può combinare soltanto azioni registrate, autorizzate e validate. Non può registrare codice Dart, chiamare shell, aprire un percorso arbitrario o caricare librerie native. Gli export passano dal selettore; letture di file richiedono la scelta dell'utente. Permessi e server vengono controllati anche durante l'esecuzione, non soltanto mostrati nella UI.

Errori e cancellazione scartano le modifiche preparate al documento e allo stato. Il cambio di documento/livello o una modifica concorrente impediscono il commit. Le richieste già inviate e altri effetti esterni non possono essere ritirati: il plugin con permessi sui dati e sulla rete può trasmetterli al server autorizzato. Il consenso non rende quel server affidabile e `state` non è un deposito cifrato.

Il modello considera plugin/pacchetti non attendibili e errori accidentali. Non promette assenza di vulnerabilità nel nucleo, nei decoder immagini, nell'OCR, in TLS o nel sistema operativo: occorrono manutenzione, test su file ostili, aggiornamenti e prove su dispositivo. Un utente che modifica e ricompila l'app o controlla il sistema operativo è fuori dal confine dell'app distribuita.

## Libertà creativa

Non imponiamo categorie di idee ammesse. Workflow, logica, geometrie, moduli, immagini, OCR, persistenza ed export possono essere combinati. Il confine è sulle capacità di sistema e sul consumo di risorse. Nuovi strumenti, eventi, pannelli o provider si aggiungono come API nel codice verificato dell'app, con permessi specifici, limiti, timeout, gestione delle risorse e regressioni; poi possono essere combinati dai plugin distribuiti senza ricompilare ogni plugin.

`extendApi` è un punto di estensione per sviluppatori del nucleo, non una funzione del manifest. Un'estensione compilata ha i privilegi dell'app e deve essere verificata come il resto del prodotto. Non deve introdurre `eval`, shell, interpreti generici, URL/percorso arbitrari o un modo di eludere i permessi. Deve modificare la sessione preparata, verificare `active` dopo ogni attesa e liberare risorse con `cleanup`/`PluginHost.close`.

## Requisiti per un eventuale nuovo motore

Riattivare JavaScript richiede una nuova implementazione e una nuova build, non un'opzione utente:

1. Loader chiuso ai soli moduli del pacchetto, senza filesystem, librerie native, bytecode non attendibile o fallback.
2. Processo/servizio isolato dal sistema operativo, senza privilegi dell'app e senza accesso diretto a file, rete, credenziali o bridge Flutter. Un isolate Dart da solo non è un confine di sicurezza per codice nativo.
3. Protocollo di messaggi limitato; ogni capacità resta nel nucleo e verifica permessi, dimensioni, sessione e consenso. Nessun oggetto/controller del nucleo viene consegnato al motore.
4. Deadline e limiti di CPU/memoria applicati anche dal supervisore; crash o blocco del motore devono terminare solo quel processo.
5. Distribuzione verificata, gestione degli aggiornamenti e test di import esterni, fuga dal sandbox, IPC, esaurimento risorse, crash e rollback su ogni piattaforma supportata. Le piattaforme prive di isolamento restano senza quel runtime.

QuickJS offre controlli di [memoria, stack e interruzioni](https://bellard.org/quickjs/quickjs.html); sono utili ma non sostituiscono il confine del sistema operativo. La [documentazione FJS](https://pub.dev/packages/fjs) descrive le capacità native dei builtin: disabilitarli non aveva rimosso il loader esterno nella versione verificata. Queste fonti non costituiscono una certificazione della sicurezza del prodotto.

## Evidenze e manutenzione

Prova del precedente motore: [log](validation/plugin-loader-audit.txt) e progetto isolato `tool/plugin_engine_audit`. Regressioni di produzione: `test/plugin_security_test.dart`, `plugin_javascript_test.dart`, `plugin_system_test.dart`, `advanced_plugin_test.dart`. Log: [test mirati](validation/plugin-security-focused-tests.txt), [suite completa](validation/plugin-security-all-tests.txt), [analisi](validation/plugin-security-analyze.txt), [dipendenze](validation/plugin-security-dependencies.txt).

Prima di distribuire verificare l'assenza di FJS e del bridge nella lista delle dipendenze e nell'APK, eseguire la suite completa e provare su Android fisico OCR, file picker, annullamento, ripartenza e conservazione dei plugin. Nessuna build precedente al blocco deve essere descritta come protetta da questa revisione.

Verifica della revisione: **209 test superati**, analisi senza errori o warning (181 informazioni di stile preesistenti). Build Android release riuscita; il [controllo dell'APK](validation/plugin-security-apk-inspection.txt) non rileva FJS, QuickJS o bridge. La [schermata da telefono](validation/plugin-security-disabled-js.png) mostra i comandi JavaScript sospesi. Le prove su dispositivo fisico indicate sopra restano da eseguire.
