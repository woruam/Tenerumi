# Creare plugin per OSIpp

Il sistema plugin permette di aggiungere comandi, moduli di inserimento, generatori di contenuti, strumenti preimpostati e automazioni eseguite su richiesta. Puoi iniziare con il creatore guidato oppure combinare azioni, cicli ed espressioni in un workflow JSON. I plugin operativi si distribuiscono come file `.osiplugin.json`, senza ricompilare l'app. JavaScript è sospeso per sicurezza e non può essere riattivato dall'utente.

L'API comprende formule LaTeX, file generici, export Anki, OCR locale Android, richieste HTTPS su Android/desktop e interfacce a più passaggi. Le funzioni native ulteriori si integrano tramite l'SDK, nel codice verificato dell'app. I workflow funzionano anche sul Web; le capacità del dispositivo passano attraverso API host con permessi e limiti.

## Primo plugin senza scrivere codice

1. Tocca l'icona a forma di puzzle **Plugin**, nella libreria o nella barra del documento.
2. Tocca **Crea plugin**.
3. Scrivi un nome e scegli cosa deve fare: inserire testo, disegnare un riquadro, preparare un evidenziatore oppure mostrare un messaggio.
4. Per il testo puoi usare `${today}`, che viene sostituito dalla data del dispositivo.
5. Tocca **Installa**. Apri il riquadro del plugin e tocca il suo comando.
6. Scegli la pagina, completa gli eventuali campi e tocca **Esegui**.

I comandi modificano il documento dal quale hai aperto il gestore, compreso il pannello attivo in modalità affiancata. La pagina proposta è l'ultima con cui hai interagito; puoi sceglierne un'altra. Dal gestore aperto nella libreria puoi creare e installare plugin, ma per eseguirli serve aprire un documento.

**Esempi** offre Timbro data, Planner settimanale, Strumenti studio, **Formule LaTeX** e **OCR immagini** in JSON. Timer e flashcard si attivano come plugin integrati. I file importabili sono in [`examples/plugins`](examples/plugins). Il planner usa cicli e si adatta al foglio; i preset dimostrano la persistenza fra riavvii.

Puoi disattivare un plugin con l'interruttore, modificarlo con **Modifica JSON**, salvarne una copia con **Condividi file** o rimuoverlo con **Rimuovi**. La rimozione elimina anche i suoi dati privati, ma non gli elementi che ha già inserito negli appunti. I plugin non vengono incorporati nei documenti XOPP: i contenuti creati vengono salvati come normali testi, forme, immagini o tratti e restano leggibili senza il plugin.

## Workflow sicuri e API estensibili

**JavaScript è sospeso per sicurezza.** La verifica del motore FJS 3.2.0 ha riprodotto l'importazione di un modulo locale esterno al pacchetto anche con i builtin disabilitati. Il motore è stato rimosso dalle dipendenze dell'app. Non esistono impostazioni, permessi o flag nel manifest per riattivarlo. I vecchi plugin JavaScript possono essere conservati, modificati ed esportati, ma i loro comandi non vengono eseguiti. Per LaTeX e OCR il gestore offre esempi JSON equivalenti e il pulsante **Usa l’esempio JSON sicuro** per sostituire un vecchio esempio.

I plugin nuovi usano workflow JSON: cicli, condizioni, espressioni, variabili, moduli e API host possono essere combinati per costruire strumenti di studio, generatori, conversioni e integrazioni. Nessun tema o tipo di idea è vietato; le capacità disponibili e i limiti di risorse sono invece espliciti. Una capacità mancante si aggiunge al nucleo tramite l'SDK e viene poi combinata liberamente dai plugin. Un plugin distribuito non può introdurre da solo una nuova libreria nativa, un accesso di sistema o un interprete.

I file `.osiplugin.json` sono il formato operativo. I pacchetti `.osiplugin` dei vecchi esempi JavaScript sono conservati come materiale storico: importarli non consente di eseguirli. Il confezionatore può verificarne il formato, non certificare la sicurezza del loro codice. Le nuove copie JSON di LaTeX/OCR si trovano in `examples/plugins`.

| Azione host | Argomenti e risultato | Permessi |
| --- | --- | --- |
| `capabilities` | `actions`, `javascript:false`, `ocr`; controlla i servizi disponibili | nessuno |
| `ui.form` | `title`, `fields`, `submitLabel`; valori o `null`. Campi validati come gli `inputs`; `multiline:true` per testi | `ui` |
| `ui.preview` | `title`, `type` (`text`, `latex`, `image`), `text`/`base64`; `true`, `false` o `null` | `ui` |
| `latex.render` | `text`, `size` 8–128, `color` `#RRGGBB`; PNG `{base64,width,height}` | nessuno |
| `files.open` | `type:'image'`, `encoding:'utf8'` opzionali; `{name,base64,text?}` o `null`. Solo file scelti dall'utente | `files.read` |
| `files.export` | `name`, `text` UTF-8 o `base64`; prepara un export dopo il successo | `export` |
| `anki.export` | `cards:[{front,back,tags?}]`, `deck`, `name`; TSV UTF-8 con HTML codificato e intestazioni Anki, `{count}` | `export` |
| `content.image` | `id` immagine; `{base64}` | `document.read` |
| `page.render` | `index` opzionale; PNG `{base64,width,height}`, sfondi e contenuti preparati inclusi | `document.read` |
| `document.pages` | Elenco `{index,width,height,layers,infinite}` | `document.read` |
| `ocr.recognize` | Immagine `base64`; `{text,blocks}`. OCR locale su Android | `ocr` |
| `http.request` | HTTPS `url`, `method`, `headers`, `body`; `{status,headers,text,base64}` | `network` |

Le formule sono renderizzate con Flutter Math, non compilate come documenti TeX completi. Per conservarne anche il sorgente usa `state.set`. L'OCR locale Android usa ML Kit offline; per altri provider puoi combinare `page.render`, moduli e HTTPS. Le immagini vengono validate prima di passare al renderer/OCR.

In **Plugin** si attivano anche **Timer Pomodoro** e **Flashcard per Anki**, implementati nel nucleo. Le flashcard native usano due selezioni per fronte e retro, hanno un set modificabile per appunto e vengono salvate nel documento, nel recupero automatico e nel backup. Il vecchio esempio Anki conserva dati per plugin: il pannello nativo permette di copiarli nel documento. Il suo JavaScript resta sospeso. Per importare in Anki usa testo e immagini secondo il [manuale Anki](https://docs.ankiweb.net/manual/importing/text-files); un JSON OSI è una copia dei dati, non un formato nativo Anki.

Per la rete dichiara `"networkHosts":["api.mioservizio.it"]`. Il gestore mostra permessi e server prima dell'installazione e di ogni aggiornamento. Le richieste accettano soltanto HTTPS sulla porta 443, host esatti, nessun redirect, credenziale nell'URL o header che alteri il routing. Su Android/desktop tutti gli indirizzi DNS devono essere pubblici: la connessione usa l'indirizzo verificato senza una seconda risoluzione e mantiene la verifica TLS del nome del server. Rete locale, loopback e indirizzi riservati sono esclusi. Sul Web `http.request` è indisponibile perché il browser non permette all'app di vincolare gli indirizzi DNS.

Un plugin con accessi a dati e rete può inviare quei dati ai server autorizzati: il consenso non garantisce l'onestà del server. Descrivi chiaramente i dati trasmessi. `state` non è cifrato: non distribuire segreti nel sorgente e preferisci token limitati. Richieste già inviate non possono essere ritirate. Timeout e cancellazione chiudono il client e impediscono di applicare risultati tardivi.

Il modello di minaccia, la verifica riproducibile e i requisiti per un futuro motore sono in [Sicurezza dei plugin](docs/PLUGIN_SECURITY.md). Non promettiamo immunità assoluta da exploit: anche parser e renderer del nucleo richiedono aggiornamenti e verifiche.

## Un esempio minimo JSON

Salva questo testo come `saluto.osiplugin.json`, poi usa **Importa**:

```json
{
  "apiVersion": 1,
  "id": "mia.saluto",
  "name": "Il mio primo plugin",
  "version": "1.0.0",
  "description": "Scrive un messaggio negli appunti.",
  "permissions": ["document.write"],
  "commands": [
    {
      "id": "scrivi",
      "label": "Scrivi sul foglio",
      "steps": [
        {
          "action": "text.add",
          "args": {
            "text": "Le mie idee — ${today}",
            "x": 40,
            "y": 50,
            "size": 20,
            "color": "#1565C0"
          }
        }
      ]
    }
  ]
}
```

`apiVersion` è la versione del protocollo e deve essere `1`. `id` identifica il plugin: 3–80 caratteri, inizia con una lettera minuscola e contiene lettere minuscole, cifre, punti, trattini o underscore. `name` e `version` sono testi obbligatori; `description` è facoltativo. Usa versioni come `1.0.0` e conserva lo stesso ID quando aggiorni un plugin. Un'importazione con un ID già presente viene rifiutata; per aggiornarlo usa **Modifica JSON**. L'aggiornamento conserva interruttore e dati privati.

`commands` contiene da 1 a 32 comandi. Ogni comando ha un `id` unico (lettera minuscola iniziale, cifre, underscore e trattini), una `label`, eventuali `inputs` e una lista `steps`. Gli errori di formato, azioni sconosciute e permessi mancanti vengono mostrati nell'editor prima dell'installazione.

## Moduli personalizzati

Un comando può chiedere informazioni all'utente:

```json
"inputs": [
  {"id": "titolo", "label": "Titolo", "type": "text", "required": true},
  {"id": "dimensione", "label": "Dimensione", "type": "number", "default": 20},
  {"id": "maiuscolo", "label": "Usa maiuscole", "type": "boolean", "default": false},
  {"id": "colore", "label": "Colore", "type": "choice", "options": ["#000000", "#1565C0"], "default": "#1565C0"}
]
```

I campi disponibili sono `text`, `number`, `boolean` e `choice`. `required` impone la compilazione; `default` propone un valore del tipo corretto. `choice` richiede da 1 a 256 stringhe uniche e un default presente in `options`. Massimo 32 campi per comando, etichette/opzioni di 240 caratteri. I numeri devono essere finiti e i booleani `true`/`false`; valori incompatibili vengono rifiutati prima di costruire l'interfaccia.

Usa `${input.titolo}` dentro una stringa oppure `{"var":"input.dimensione"}` per conservare il tipo numerico. Esempio:

```json
{"action":"text.add","args":{"text":"${input.titolo}","size":{"var":"input.dimensione"},"color":{"var":"input.colore"}}}
```

## Permessi e API disponibili

I plugin dichiarano ciò che utilizzano in `permissions`. Le azioni non dichiarate vengono rifiutate, anche durante l'esecuzione. Il gestore mostra l'accesso richiesto da ciascun plugin. I permessi non danno accesso a codice di sistema o a file arbitrari.

| Permesso | Consente |
| --- | --- |
| `document.read` | Titolo, numero di pagine e descrizione dei contenuti della pagina; `content.list` |
| `document.write` | Inserire, eliminare e trasformare contenuti nel livello attivo della pagina scelta |
| `tool.write` | Cambiare lo strumento e i preset penna/evidenziatore |
| `storage` | Leggere e scrivere i dati privati di quel plugin |
| `export` | Salvare file generici e Anki; PDF/XOPP richiedono anche `document.read` |
| `files.read` | Aprire file scelti dall'utente |
| `ui` | Mostrare moduli e anteprime |
| `ocr` | Riconoscere testo nelle immagini |
| `network` | Richieste HTTPS ai soli `networkHosts` dichiarati |

Tutte le coordinate e misure sono in **punti del foglio**, indipendenti dallo zoom. I colori sono `#RRGGBB` oppure `#AARRGGBB`. I valori predefiniti sono coordinate `(40,40)` e colore nero.

| Azione | Argomenti principali e risultato |
| --- | --- |
| `message` | `text`. Nessun permesso; mostra un messaggio al termine |
| `text.add` | `text`, `x`, `y`, `size` (16), `color`, `font` (`Sans`). Restituisce l'ID dell'elemento |
| `tex.add` | `text`, `x`, `y`, `size`, `color` (`#RRGGBB`). Renderizza LaTeX come immagine tramite `PluginHost.latex`; restituisce un ID |
| `image.add` | `base64` dei byte dell'immagine, `x`, `y`, `width`/`height` (100). Valida i byte prima di inserire; restituisce un ID |
| `stroke.add` | `points`: lista di oggetti `{"x":10,"y":20}`, `width` (2), `color`, `tool` (`pen` o `highlighter`), `shape` (true), `smooth` (false). Restituisce un ID |
| `shape.add` | `kind`: `rectangle`, `ellipse` o `line`; `x`, `y`, `width` (120), `height` (80), `strokeWidth` (2), `color`. Una linea termina in `(x+width,y+height)`; restituisce un ID |
| `content.list` | Nessun argomento. Restituisce una lista aggiornata di `id`, `type`, `text`, `x`, `y`, `width`, `height` dei contenuti in lavorazione |
| `content.delete` | `ids`: lista di ID oppure `"all"`. Elimina gli elementi indicati |
| `content.transform` | `ids`, `dx`/`dy` (0), `scale` (1), `anchorX`/`anchorY` (0). Prima scala, poi trasla |
| `text.update` | `id`, `text`. L'ID deve indicare un elemento di testo |
| `tool.set` | `tool`: `pen`, `highlighter`, `eraser`, `lasso`, `hand` o `text`; `width`/`color` facoltativi, applicati ai preset penna/evidenziatore |
| `state.get` | `key`. Restituisce il valore privato memorizzato, o null |
| `state.set` | `key`, `value` JSON. Memorizza il valore al completamento riuscito |
| `export.pdf` / `export.xopp` | Nessun argomento. Dopo il completamento apre il selettore del documento; massimo un export per comando |

Le scritture operano sul **livello attivo della pagina scelta**, come gli strumenti principali dell'app. Gli ID sono gli indici della lista di quel livello: dopo un'eliminazione gli indici successivi cambiano. Usa `content.list` per ottenere gli ID aggiornati. `document.contents` descrive invece lo stato iniziale del comando. Il contesto non contiene i byte degli allegati o delle immagini. `stroke.add` permette di generare tratti e poligoni propri; l'evidenziatore usa metà opacità e rispetta lo spessore indicato. Le forme sono contorni, non superfici riempite.

## Variabili, espressioni e logica

Contesto iniziale:

- `input.<id>`: valori del modulo.
- `today`: data del dispositivo in formato `YYYY-MM-DD`.
- `page.index`: indice da zero; `page.number`: numero da uno; `page.width` e `page.height`: dimensioni.
- `document.title`, `document.pageCount`, `document.contents`: disponibili solo con `document.read`.

`${percorso}` interpola una variabile nel testo; `{"var":"percorso"}` restituisce il suo valore senza convertirlo in stringa. I percorsi possono attraversare oggetti e liste, ad esempio `document.contents.0.text`. Una variabile inesistente restituisce null; nell'interpolazione diventa testo vuoto.

Per creare una variabile usa `set`. `as` su un'azione conserva il suo risultato. `input`, `page`, `document` e `today` sono nomi riservati.

```json
{"set":"dimensione","value":{"op":"div","args":[{"var":"page.width"},10]}}
```

Un'espressione usa `op` e `args`:

| Categoria | Operatori |
| --- | --- |
| Numeri | `add`, `sub`, `mul`, `div`, `mod`, `min`, `max`, `round`, `floor`, `ceil`, `abs`, `pow`, `sqrt`, `sin`, `cos`, `tan` |
| Confronti | `eq`, `ne`, `gt`, `gte`, `lt`, `lte` |
| Logica | `and`, `or`, `not`, `coalesce` |
| Testi | `concat`, `upper`, `lower`, `trim`, `replace`, `split`, `join` |
| Dati | `length`, `at`, `get`, `append` |

`add` e `mul` accettano più numeri; `sub`, `div`, `mod`, `min`, `max`, `pow` prendono due argomenti. Gli altri operatori matematici prendono un argomento; la trigonometria usa radianti. `eq`/`ne` sono adatti a valori semplici; non confrontano strutturalmente due oggetti o liste. `and`/`or` prendono booleani, `not` ne prende uno; una condizione viene considerata vera solo se restituisce `true`. `coalesce` restituisce il primo argomento non nullo.

`replace` prende testo, testo da cercare e sostituzione (ricerca letterale). `split` prende testo e separatore; `join` prende lista e separatore. `at` prende lista e indice; `get` prende oggetto e chiave; `append` restituisce una nuova lista con un valore aggiunto. `length` conta gli elementi di una lista o i caratteri di una stringa. Gli oggetti con chiavi `var` o `op` sono interpretati come espressioni: evita queste chiavi negli oggetti di dati da costruire direttamente.

### Condizioni

```json
{
  "if": {"var":"input.maiuscolo"},
  "then": [{"set":"titolo","value":{"op":"upper","args":[{"var":"input.titolo"}]}}],
  "else": [{"set":"titolo","value":{"var":"input.titolo"}}]
}
```

### Cicli

```json
{
  "repeat": 5,
  "as": "i",
  "steps": [
    {"action":"text.add","args":{"text":"Riga ${i}","x":40,"y":{"op":"add","args":[50,{"op":"mul","args":[{"var":"i"},30]}]}}}
  ]
}
```

`repeat` esegue un numero intero di iterazioni da 0 a 1000, con indice da zero. `forEach` scorre una lista:

```json
{"forEach":["Idea","Progetto","Risultato"],"as":"voce","steps":[{"action":"message","args":{"text":"${voce}"}}]}
```

La variabile del ciclo è ripristinata al termine; le altre variabili create negli step restano disponibili. I cicli possono essere annidati, nel rispetto del budget complessivo.

## Persistenza e comportamento in caso di errore

Esempio di contatore:

```json
[
  {"action":"state.get","args":{"key":"utilizzi"},"as":"precedenti"},
  {"action":"state.set","args":{"key":"utilizzi","value":{"op":"add","args":[1,{"op":"coalesce","args":[{"var":"precedenti"},0]}]}}}
]
```

I dati rimangono sul dispositivo, separati per plugin. Sono conservati fra riavvii, disattivazioni e aggiornamenti con lo stesso ID; non vengono inclusi nel file condiviso del plugin. La disinstallazione li elimina.

Le azioni modificano una copia della pagina. Solo quando l'intero comando riesce gli elementi vengono applicati al foglio, con **una sola operazione Annulla**. Un errore, un ID non valido, un'immagine corrotta o il superamento del budget non applicano le modifiche parziali. Se nel frattempo il documento cambia, il comando viene rifiutato per conservare il lavoro dell'utente.

Annulla/Ripristina riguarda gli elementi del foglio; i preset degli strumenti e i dati privati del plugin hanno una cronologia separata. L'esportazione è successiva alla transazione: annullare il selettore PDF/XOPP non annulla gli elementi appena creati. I messaggi compaiono soltanto dopo un'esecuzione riuscita. I plugin non si eseguono automaticamente all'avvio o durante i tratti della penna.

## Limiti della versione 1

- 32 plugin installati; JSON/pacchetto e sorgenti decompressi massimo 2 MiB; archivio locale complessivo massimo 8 MiB. Pacchetti: massimo 64 moduli JavaScript.
- Workflow JSON: massimo 2000 step/chiamate host, 100.000 valutazioni e circa 2 secondi di elaborazione effettiva; ogni 100 step cede il controllo all'interfaccia. L'intero comando, inclusa l'attesa delle API e dell'utente, dura al massimo due minuti. Annullamento, errori e timeout invalidano la sessione e impediscono nuove azioni o risultati tardivi.
- Annidamento step massimo 24; espressioni massimo 32 livelli; lista di un ciclo massimo 1000 elementi.
- Testi generati massimo 65.536 caratteri; massimo 20 messaggi da 4096 caratteri; dati privati massimo 64 KiB.
- Massimo 10.000 elementi nella pagina per un'inserzione plugin, 10.000 punti per `stroke.add`, 100.000 punti aggiunti per comando, liste con `append` massimo 10.000 elementi. Immagini decodificate massimo 4 milioni di pixel. Testi e immagini generati hanno un budget complessivo di 32 MiB, includendo la memoria dei pixel delle immagini inserite.
- Numeri dei parametri host finiti, con valore assoluto massimo 100.000; spessori limitati a 0,1–512; testo 1–512; fattore di scala maggiore di zero e massimo 100. Posizioni fuori dal foglio sono possibili: usa `page.width`/`height` per produrre contenuti visibili.
- File: massimo 8 MiB ciascuno; fino a 8 export per comando, massimo 16 MiB totali. OCR: immagini massimo 4 milioni di pixel; timeout 45 secondi. HTTP: richieste/risposte massimo 8 MiB, header massimo 16 KiB, timeout complessivo 20 secondi e risoluzione DNS 5 secondi. I dati che attraversano le API sono JSON con complessità limitata; trasformazioni che producono geometrie fuori dai limiti vengono rifiutate.
- UI tramite moduli e anteprime; niente shell o accesso generale al filesystem. Gli hook automatici della penna richiedono estensioni SDK.

Questi limiti mantengono reattiva l'app e rendono prevedibili gli errori. Per operazioni più grandi, dividi il lavoro in più comandi oppure aggiungi una capacità host specifica.

## SDK: estendere le capacità dell'app

L'API pubblica è in `lib/plugins/plugin_runtime.dart` e `lib/plugins/plugin_controller.dart`. `PluginApi.register` associa un nome, i permessi necessari e una funzione Dart; `PluginController.extendApi` permette di registrare capacità aggiuntive. La registrazione avviene anche durante la validazione, quando `session` è null: la funzione deve usare la sessione soltanto quando viene eseguita.

Esempio di estensione compilata nell'app:

```dart
final plugins = PluginController(extendApi: (api, session) {
  api.register('studio.heading', {'document.write'}, (args) {
    return session!.add(XppText(
      text: args['title'] as String? ?? 'Titolo',
      offset: const Offset(40, 40),
      size: 28,
      color: Colors.blue,
    ));
  });
});
```

Importa `PluginController`, `XppText` e Flutter Material, e usa quel controller nel provider principale in `lib/main.dart`. Poi il plugin JSON può usare:

```json
{"action":"studio.heading","args":{"title":"Una nuova idea"}}
```

Registra nomi unici, valida gli argomenti e modifica `session.content`/`session.state`, non direttamente il controller del canvas. Usa `session.add` per inserire; per una modifica diretta dei contenuti imposta `session.changed = true`. Le capacità personalizzate devono rispettare il budget, avere timeout per operazioni asincrone e liberare le risorse native. Effetti esterni prodotti da una funzione SDK non possono essere annullati dalla transazione del foglio: gestiscili esplicitamente nella capacità.

L'aggiunta di nuove capacità native richiede una build dell'app. Una volta pubblicata quell'API, i plugin JSON che la usano possono essere creati e distribuiti senza ulteriori build. Per nuovi nomi di permesso occorre anche estendere `pluginPermissions` e la documentazione; per cambiamenti incompatibili al protocollo va introdotta una nuova `apiVersion` con migrazione.

## Verifica e manutenzione

Le regressioni sono in `test/plugin_system_test.dart`, `advanced_plugin_test.dart`, `plugin_javascript_test.dart` e `plugin_security_test.dart`: validazione, permessi, esempi JSON, rollback, concorrenza, cancellazione, ZIP corrotti/duplicati, decompressione limitata, moduli con default errati, indirizzi DNS privati e tentativi di riattivare JavaScript. I test del blocco non richiedono una libreria nativa JavaScript.

Dopo una modifica agli esempi esegui `dart tool/generate_plugin_examples.dart`, `flutter test` e `flutter analyze --no-fatal-infos`. I log della revisione sono `docs/validation/plugin-security-focused-tests.txt`, `plugin-security-all-tests.txt`, `plugin-security-analyze.txt` e `plugin-security-dependencies.txt`.

L'audit del precedente motore è separato in `tool/plugin_engine_audit`; le sue dipendenze non appartengono all'app. Il test riproduce la falla usando solo un file temporaneo innocuo. La verifica originale è registrata in `docs/validation/plugin-loader-audit.txt`. Per ripeterla seguire il README di quella cartella; non reinserire FJS nelle dipendenze del prodotto.

Le verifiche storiche del 7 ottobre riguardavano il precedente runtime e non certificano la sicurezza della versione corrente. OCR nativo e selettori file richiedono anche prove su dispositivo Android fisico.

Verifica del 10 ottobre: **209 test superati**, nessun errore o warning nell'analisi e APK release compilato. Il controllo dei contenuti dell'APK non trova il motore JavaScript o il bridge. Queste verifiche chiudono i problemi riprodotti; non certificano l'assenza di ogni possibile exploit.
