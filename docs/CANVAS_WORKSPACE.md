# Canvas infinito, autosalvataggio e livelli

Aggiornamento del 7 ottobre 2026. Le tre funzioni sono implementate e verificate con analisi e test. Non è stata effettuata una build dell'app per questo intervento.

## Canvas infinito

In **Nuovo Appunto**, attiva **Canvas infinito** e scegli il modello di sfondo. Il documento contiene una superficie continua: puoi scrivere, cancellare, selezionare, spostare e incollare in qualsiasi direzione, comprese coordinate negative. I documenti esistenti mantengono le loro pagine.

Il dito sposta il canvas in entrambi gli assi anche al 100%; due dita consentono lo zoom. Quando è attiva la scrittura con il dito, usa due dita per navigare. La rotella del mouse cambia lo zoom. Il canvas usa una superficie grande quanto la finestra e scarta dal disegno gli elementi fuori dall'area visibile; non alloca una pagina o un'immagine gigantesca. Lo zoom resta tra 10% e 1000%.

La modalità infinita e le coordinate originali sono salvate nel file XOPP. Il PDF viene invece ritagliato sull'insieme dei contenuti visibili, con un margine di 24 punti. I livelli nascosti non allargano il ritaglio. Il raster del PDF conserva il limite di circa quattro milioni di pixel: contenuti distribuiti su un'area molto vasta possono risultare poco dettagliati nell'esportazione.

Il pulsante per aggiungere pagine è disabilitato nei canvas infiniti. I PDF importati vengono aperti in una scheda separata nel workspace. Il punto di vista resta indipendente per le schede del workspace; alla riapertura del documento si riparte dall'origine. Le estensioni `osipp-infinite` sono specifiche di OSIpp: altri lettori XOPP possono ignorarle e mostrare solo il rettangolo della pagina standard.

## Autosalvataggio e recupero

L'autosalvataggio parte dopo due secondi senza modifiche, oppure dopo dieci secondi di modifiche continue. Passare l'app in background o chiudere un controller richiede anche una scrittura delle modifiche ancora pendenti. La chiusura improvvisa del processo può perdere le modifiche non ancora scritte: il sistema non promette il recupero di ogni evento di penna.

Ogni salvataggio produce prima una copia XOPP completa, con i livelli e gli allegati incorporati nel documento. Il nome del nuovo checkpoint è distinto da quello precedente; l'indice viene aggiornato soltanto dopo la scrittura completa. La vecchia copia viene eliminata successivamente. Le operazioni sull'indice sono serializzate anche tra schede diverse.

- **Documento già salvato, piattaforma nativa:** viene aggiornato anche il file originale, incluso un URI Android con permesso di scrittura. La nota viene considerata salvata soltanto se la revisione scritta coincide ancora con quella attuale.
- **Nota senza destinazione:** resta disponibile la copia di recupero; **Salva** permette di scegliere o creare la destinazione definitiva.
- **Web:** la copia di recupero è conservata nelle preferenze locali del browser; l'esportazione del file resta esplicita. Il limite di spazio del browser può impedire di salvare documenti grandi. L'errore viene mostrato nella toolbar.

Nella schermata iniziale, **Ripristina copia automatica** apre l'ultima copia di ogni documento. Il ripristino riattiva lo stato di modifiche da salvare, così un originale più vecchio non viene confuso con il contenuto recuperato. Puoi eliminare una copia con conferma. **Chiudi senza salvare** annulla le scritture pendenti e rimuove il recupero; non può annullare modifiche già salvate automaticamente nel file originale. Un salvataggio manuale completo rimuove la copia ormai superata.

L'icona accanto ai livelli mostra lo stato e l'ora dell'ultimo autosalvataggio; premendola puoi richiedere un tentativo immediato. Un errore mantiene le modifiche non salvate e, quando già scritta, la copia di recupero. Le copie locali non sono un backup remoto e possono essere perse cancellando i dati dell'app o del browser.

## Livelli gestibili

Apri **Livelli** nella toolbar. Il pannello consente di:

- aggiungere un livello e sceglierlo come attivo;
- rinominare, nascondere/mostrare e bloccare/sbloccare;
- portare avanti o indietro un livello;
- eliminare un livello e il suo contenuto, dopo conferma.

La lista mostra in alto il livello più vicino all'osservatore. Il documento conserva almeno un livello. Visibilità, blocco, nome e ordine vengono salvati nel file XOPP; il livello attivo è mantenuto durante la sessione per ciascuna pagina. L'ordine XML va dal fondo verso la cima.

Penna, evidenziatore, gomma, lazo e incolla operano soltanto sul livello attivo. Un livello nascosto o bloccato non è modificabile. Gli altri livelli rimangono visibili quando previsto, ma la selezione e la gomma non li attraversano. Annulla/ripeti conserva l'intero stato dei livelli della pagina, comprese le operazioni di gestione; resta il limite di cinquanta snapshot. L'annullamento di un'operazione non rappresenta un override del blocco: ripristina lo stato precedente del documento.

I plugin leggono e modificano il livello attivo della pagina richiesta. Le scritture su un livello nascosto o bloccato falliscono prima della conferma della transazione. Cambiare livello durante l'esecuzione rende obsoleta la transazione. Il contesto `page` espone anche `infinite`, `layerIndex` e `layerName`; `document.pages` espone `infinite`.

## Verifiche

I test dedicati coprono coordinate negative e molto distanti, zoom e pan, rendering/export, round trip XOPP, blocco dei livelli, gestione dei livelli su telefono, annulla/ripeti, scritture dei plugin, autosalvataggio realmente attivato dal timer, sovrascrittura dell'originale e recupero dopo errori/disposal.

I risultati sono in `docs/validation/canvas-workspace-tests.txt` e `docs/validation/canvas-workspace-analyze.txt`. Non sono state effettuate build APK, desktop o web. Restano da provare su un dispositivo reale i gesti della penna e le condizioni di arresto del sistema operativo/provider Android.
