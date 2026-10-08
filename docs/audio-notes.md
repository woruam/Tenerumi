# Audio sincronizzato negli appunti OSI

## Utilizzo
Aprire Audio appunto (microfono nella toolbar), scegliere Registra audio e concedere il permesso microfono. Scrivere normalmente: penna, evidenziatore e forme conservano l’intervallo della registrazione. Ferma registrazione aggiunge l’audio all’appunto. Salva e uscita dall’app finalizzano la registrazione prima del salvataggio o della richiesta di chiusura.

Nel pannello scegliere una registrazione, mettere in pausa/riprendere, spostare il cursore o fermare l’ascolto. L’overlay ciano segue i tempi dei campioni originali di penna/evidenziatore; per forme riconosciute/generate l’avanzamento geometrico viene distribuito sull’intervallo dell’input. Nei silenzi senza scrittura non viene evidenziato un tratto. L’aggiornamento è a 10 Hz e usa la posizione restituita dal player Android. Non è una sincronizzazione a precisione di singolo campione audio.

Attivare Ascolta dal tratto, chiudere il pannello e toccare con la punta della penna un tratto collegato. La riproduzione parte dall’inizio di quel tratto e continua nella registrazione. Scegliere un normale strumento disattiva questa modalità. Pan touch, pulsanti della stylo, pressione e gomma mantengono il percorso input esistente.

## Persistenza e limiti
- Registrazione/riproduzione native disponibili su Android; sulle altre piattaforme i comandi sono disabilitati, i dati audio nel documento restano conservati.
- AAC mono in contenitore M4A, 22.050 Hz, 48 kbit/s; massimo 120 minuti/48 MiB per registrazione e 128 MiB compressi di audio per appunto. Per iniziare una nuova registrazione viene riservata la capienza massima di 48 MiB.
- Audio compresso incorporato nel file XOPP, insieme agli ID e ai tempi dei tratti: riapertura, esportazione, recovery dopo finalizzazione e copia/incolla tra appunti conservano l’associazione.
- I metadati audio sono estensioni OSI (`osipp-audio`, attributi dei tratti). Non viene promessa riproduzione in Xournal++ desktop. L’ispirazione funzionale è la registrazione mentre si scrive e il suo strumento Play Object: [manuale Xournal++](https://github.com/xournalpp/xournalpp/wiki/User-Manual/d682c9284055575d14b18a31b6076b73d965939a).
- Audio ancora in registrazione resta temporaneamente su disco: un arresto improvviso del processo prima della finalizzazione può perderlo. Salvare arresta e incorpora la registrazione; il recupero di una registrazione non finalizzata dopo crash non è implementato.

## Audit memoria e lifecycle
Nessuna elaborazione PCM, buffer audio o chiamata di piattaforma nel percorso dei movimenti della penna. Durante la registrazione si aggiunge solo un intero temporale per campione. I dati compressi sono immutabili e condivisi da snapshot/clipboard; undo conserva i piccoli link temporali senza duplicare l’audio. La serializzazione XML/base64 e il passaggio al worker producono copie temporanee, quindi il limite di 128 MiB non è un limite al picco totale di RAM.

Un solo recorder/player nativo e una coda di operazioni tra appunti. Timer cancellati dopo pausa/completamento, cambio proprietario e chiusura; coda azzerata quando vuota per non trattenere zone/controller. I risultati tardivi dopo dispose non aggiornano notifier disposti e la chiusura di una scheda non rilascia il recorder di un’altra. Preferenze asincrone ignorate dopo dispose. Clipboard svuotata alla chiusura della workspace.

Il recorder viene fermato in background, sui limiti e sugli errori; il player viene sospeso in background e su perdita del focus audio. Permessi concessi prima di onResume attendono il ritorno in primo piano. MediaRecorder/MediaPlayer sono rilasciati in chiusura/cambio registrazione; focus audio abbandonato e file temporanei eliminati. Preparazione asincrona del player e I/O su worker; notifiche di errore non completano due volte la stessa richiesta. I file temporanei residui del solo registratore OSI sono ripuliti al successivo avvio. Riferimento piattaforma: [Android MediaRecorder](https://developer.android.com/media/platform/mediarecorder).

L’overlay ha un RepaintBoundary proprio: la timeline non ridisegna PDF e inchiostro statico, non cambia geometria/colori salvati e non entra nell’anteprima/esportazione. Culling sull’area visibile e maschera delle cancellazioni anche nell’evidenziazione.

## Verifica eseguita
- 147 test Flutter passati, inclusi 9 nuovi test audio: round trip attraverso isolate, metadati malformati, bytes condivisi/sola lettura, clone e gomma, switch tra schede, stop/dispose, permesso negato, avvio pendente, posizione del player, pressione/cancel, modalità ascolto, copia/incolla/undo e overlay progressivo. [Log](validation/audio-full-tests.txt).
- Compilazione Kotlin Android riuscita: [log](validation/audio-android-compile.txt). Restano gli avvisi preesistenti della toolchain Gradle/AGP/Kotlin e di plugin terzi.
- Analisi Dart: nessun errore o warning; gli info di stile sono riportati in [log](validation/audio-analyze.txt).
- Screenshot telefono con font e tema OSI: [pannello e avanzamento del tratto](validation/audio-timeline-panel.png).

Questi controlli non sostituiscono un profilo heap su hardware. Non è stato registrato/ascoltato audio attraverso un microfono reale durante questa sessione, né misurato il picco di RAM su Android. Nessun APK prodotto da questa verifica.

## Prova sul dispositivo
1. Creare un appunto, negare il primo permesso: nessun crash o tratto perso. Ritentare dopo aver consentito il microfono nelle impostazioni Android.
2. Registrare una frase e scrivere tre tratti a intervalli diversi, variando pressione, evidenziatore e pulsanti stylo. Fermare e ascoltare; verificare cursore, ordine dei tratti e silenzi.
3. Cercare con slider e Ascolta dal tratto. Mettere in pausa, cancellare una parte, controllare che non ricompaia nell’overlay; provare undo/redo.
4. Salvare/esportare, chiudere e riaprire il XOPP; ascoltare e copiare/incollare un tratto in un’altra scheda.
5. Registrare e passare in background, bloccare lo schermo, chiudere l’appunto e cambiare registrazione tra schede: verificare arresto microfono, conservazione audio finalizzato e assenza di riproduzione doppia.
6. Con Android Studio Memory Profiler, ripetere start/stop/play/seek/chiusura 50 volte e osservare heap dopo GC, recorder/player e file cache. Confrontare scrittura rapida con audio spento/acceso e verificare picco RAM in salvataggio vicino al limite.
