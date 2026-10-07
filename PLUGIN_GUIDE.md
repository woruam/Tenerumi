# Creare plugin per OSIpp

Il sistema plugin permette di aggiungere comandi, moduli di inserimento, generatori di contenuti, strumenti preimpostati e automazioni eseguite su richiesta. Puoi iniziare senza codice con il creatore guidato, combinare azioni in un workflow JSON, oppure scrivere **JavaScript con moduli ES, funzioni, algoritmi e async/await** per plugin complessi. Si distribuiscono come file `.osiplugin.json` o pacchetti `.osiplugin`, senza ricompilare l'app.

L'API comprende formule LaTeX, file generici, flashcard Anki, OCR locale Android, richieste HTTPS e interfacce a più passaggi. Le funzioni native ulteriori si possono integrare tramite l'SDK. Il runtime JavaScript funziona nell'app Android e desktop; sul Web restano disponibili i workflow JSON. Non esiste un sistema che aggiunga automaticamente qualsiasi nuovo sensore o libreria nativa: la logica del plugin è dinamica, le capacità del dispositivo passano attraverso le API host.

## Primo plugin senza scrivere codice

1. Tocca l'icona a forma di puzzle **Plugin**, nella libreria o nella barra del documento.
2. Tocca **Crea plugin**.
3. Scrivi un nome e scegli cosa deve fare: inserire testo, disegnare un riquadro, preparare un evidenziatore oppure mostrare un messaggio.
4. Per il testo puoi usare `${today}`, che viene sostituito dalla data del dispositivo.
5. Tocca **Installa**. Apri il riquadro del plugin e tocca il suo comando.
6. Scegli la pagina, completa gli eventuali campi e tocca **Esegui**.

I comandi modificano il documento dal quale hai aperto il gestore, compreso il pannello attivo in modalità affiancata. La pagina proposta è l'ultima con cui hai interagito; puoi sceglierne un'altra. Dal gestore aperto nella libreria puoi creare e installare plugin, ma per eseguirli serve aprire un documento.

**Esempi** offre Timbro data, Planner settimanale, Strumenti studio, **Formule LaTeX**, **Flashcard per Anki** e **OCR immagini**. I file importabili e i sorgenti sono in [`examples/plugins`](examples/plugins). Il planner usa cicli e si adatta alle dimensioni del foglio. I preset dimostrano come ricordare dati fra riavvii.

Puoi disattivare un plugin con l'interruttore, modificarlo con **Modifica JSON**, salvarne una copia con **Condividi file** o rimuoverlo con **Rimuovi**. La rimozione elimina anche i suoi dati privati, ma non gli elementi che ha già inserito negli appunti. I plugin non vengono incorporati nei documenti XOPP: i contenuti creati vengono salvati come normali testi, forme, immagini o tratti e restano leggibili senza il plugin.

## Plugin programmabili: da poche righe a progetti complessi

Un pacchetto è un archivio ZIP rinominato `.osiplugin`, con `manifest.json` e uno o più file `.js`. Il gestore importa anche un unico JSON contenente `modules`, utile per modificarlo nell'app. Gli esempi avanzati includono entrambe le forme e le cartelle sorgente.

`manifest.json`:

```json
{
  "apiVersion": 1,
  "id": "mio.studio",
  "name": "Assistente studio",
  "version": "1.0.0",
  "runtime": "javascript",
  "entry": "main.js",
  "permissions": ["document.write", "ui"],
  "commands": [{"id": "inserisci", "label": "Inserisci formula", "handler": "inserisci"}]
}
```

`main.js`:

```javascript
export async function inserisci(context) {
  const dati = await osipp.call('ui.form', {
    title: 'Formula',
    fields: [{id:'formula', label:'LaTeX', type:'text', required:true, multiline:true}]
  });
  if (!dati) return; // L'utente ha chiuso il modulo.
  const png = await osipp.call('latex.render', {text:dati.formula, size:24});
  await osipp.call('image.add', {...png, x:40, y:40});
}
```

Puoi suddividere la logica in `lib/parser.js`, `lib/cards.js` e altri moduli, importandoli con `import { funzione } from './lib/parser.js'`. Sono disponibili JavaScript, array, oggetti, classi, JSON, matematica, espressioni regolari e Promise. Le librerie JavaScript possono essere incluse come sorgenti ES oppure raccolte in un bundle; non viene installato automaticamente npm. Librerie che dipendono da DOM, Node.js, processi o moduli nativi non funzionano direttamente.

Per creare il file distribuibile dal repository:

```powershell
dart tool/package_plugin.dart percorso/cartella mio-plugin.osiplugin
```

In alternativa comprimi `manifest.json` e i file JavaScript alla radice dello ZIP e rinomina l'estensione. Sono ammessi percorsi relativi come `lib/cards.js`; percorsi assoluti e `..` vengono rifiutati. Non aggiungere una cartella esterna allo ZIP. Il comando di confezionamento valida il pacchetto; la sintassi JavaScript e l'esistenza della funzione esportata sono verificate dal motore quando esegui il comando.

`handler` identifica una funzione esportata dal modulo `entry` (predefinito `main.js`). Riceve `context.input`, `context.page`, `context.today` e, con `document.read`, `context.document`. Gli `inputs` del manifest funzionano anche per JavaScript. Usa `await osipp.call(nome, argomenti)` per tutte le API della tabella seguente e per quelle del workflow. I valori sono JSON. Non avviare chiamate senza `await`: una funzione deve terminare solo dopo le proprie operazioni.

### API per plugin complessi

| Azione | Argomenti e risultato | Permessi |
| --- | --- | --- |
| `capabilities` | Restituisce `actions`, `javascript`, `ocr`; controlla i servizi disponibili | nessuno |
| `ui.form` | `title`, `fields`, `submitLabel`; restituisce i valori o `null`. Campi come gli `inputs`, con `multiline:true` per testi lunghi. Puoi concatenare più moduli e calcolarne i campi dinamicamente | `ui` |
| `ui.preview` | `title`, `type` (`text`, `latex`, `image`), `text` o `base64`; restituisce `true` con Continua, `false`/`null` con Annulla | `ui` |
| `latex.render` | `text` LaTeX, `size` 8–128, `color` `#RRGGBB`; restituisce PNG trasparente `{base64,width,height}` | nessuno |
| `files.open` | `type:'image'` opzionale, `encoding:'utf8'` opzionale; restituisce `{name,base64,text?}` oppure `null`. Solo file scelti esplicitamente nel selettore | `files.read` |
| `files.export` | `name` e `text` UTF-8 oppure `base64`; prepara un file da salvare dopo il successo del comando | `export` |
| `anki.export` | `cards:[{front,back,tags?}]`, `deck`, `name`; prepara TSV UTF-8 con intestazioni Anki, HTML e separatori correttamente codificati; restituisce `{count}` | `export` |
| `content.image` | `id` dell'immagine; restituisce `{base64}` | `document.read` |
| `page.render` | `index` opzionale; restituisce PNG `{base64,width,height}` della pagina, inclusi gli sfondi e le modifiche preparate dal plugin nella pagina corrente | `document.read` |
| `document.pages` | Elenco `{index,width,height,layers,infinite}` delle pagine | `document.read` |
| `ocr.recognize` | Immagine in `base64`; restituisce `{text,blocks:[{text,x,y,width,height,lines}]}` | `ocr` |
| `http.request` | `url`, `method` (GET/POST/PUT/PATCH/DELETE), `headers`, `body` testuale; restituisce `{status,headers,text,base64}` | `network` |

LaTeX viene composto matematicamente tramite Flutter Math e inserito come immagine: frazioni, radici e simboli vengono disegnati, non mostrati come codice. Le formule si conservano in PDF/XOPP senza il plugin. Per un editor di formule che ricordi il sorgente, conserva anche il LaTeX tramite `state.set`; l'immagine da sola non contiene un sorgente modificabile. È supportato il sottoinsieme matematico del renderer, non la compilazione di un documento TeX completo.

Le flashcard dell'esempio sono conservate per plugin, con comandi Aggiungi, Importa JSON ed Esporta. In Anki importa `flashcard.tsv` tramite **File → Importa**. È un formato di importazione testuale, non un pacchetto `.apkg` né una sincronizzazione con AnkiConnect. Puoi scrivere plugin con conversioni più elaborate o integrazioni con server tramite le API. Riferimento: [importazione testuale Anki](https://docs.ankiweb.net/manual/importing/text-files).

L'OCR incorporato usa il modello latino ML Kit **offline su Android**; non invia immagini a server. L'esempio legge una foto, permette di correggere il risultato e inserisce testo nel foglio. Per riconoscere una pagina usa `page.render` seguito da `ocr.recognize`. Il riconoscimento della scrittura a mano dipende dalla qualità del modello e dell'immagine. Per altre lingue, modelli avanzati o piattaforme puoi implementare un provider remoto con `http.request`, oppure aggiungere un provider nativo tramite `PluginHost.ocr`. Riferimento: [ML Kit Text Recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2/android).

Per rete dichiara anche `"networkHosts":["api.mioservizio.it"]` nel manifest. Sono accettati soltanto HTTPS sulla porta 443 e gli host esatti dichiarati, senza wildcard, credenziali nell'URL o redirect automatici. Un servizio OCR/AI remoto può essere chiamato con POST; l'utente deve sapere nel nome/descrizione del plugin quali dati saranno inviati. Le credenziali in `state` non sono un deposito cifrato: non distribuire chiavi segrete nel sorgente e preferisci token limitati. Errori e risposte HTTP devono essere gestiti dal codice del plugin.

### Esecuzione, annullamento e piattaforme

Ogni comando JavaScript ha un motore QuickJS separato, memoria limitata a 64 MiB, stack di 512 KiB, massimo 2000 chiamate host e durata complessiva massima di due minuti. Il gestore offre **Annulla esecuzione**; l'interruzione nativa ferma anche cicli JavaScript infiniti. Le chiamate host sono serializzate. Il codice non riceve filesystem, processi, timer o rete nativi: usa le API esplicite dell'app. Il motore e i limiti evitano molti errori accidentali, ma non costituiscono isolamento tramite processo/OS per eseguire codice ostile: installa plugin di provenienza attendibile. Riferimento del motore: [FJS](https://pub.dev/packages/fjs).

Le modifiche al foglio e ai dati del plugin diventano effettive soltanto al successo. Un errore o una cancellazione le scarta, e un comando modifica il foglio con una sola azione Annulla. File esportati si salvano dopo la transazione; annullare un selettore file non annulla le modifiche già accettate. Richieste HTTP già inviate non sono annullabili e le API native già avviate possono completare in background; il loro risultato non viene applicato alla sessione terminata. Per lavori lunghi dividi il processo in comandi e salva progressi intermedi.

JSON funziona su tutte le piattaforme dell'app; JavaScript richiede Android o desktop; OCR locale richiede Android. Un'API `latex.render`, `ui.form` o `files.open` richiede un `PluginHost`, che il gestore fornisce automaticamente. In test o altre integrazioni puoi passare provider propri a `PluginController.execute(..., host: PluginHost(...))`. Per nuovi widget interattivi, sensori, librerie native o hook della penna occorre aggiungere capacità compilate nell'app; non promettiamo che codice JavaScript possa creare automaticamente qualsiasi nuova funzione nativa.

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

I campi disponibili sono `text`, `number`, `boolean` e `choice`. `required` impone la compilazione; `default` propone il valore iniziale. `choice` richiede una lista non vuota di stringhe in `options`. Massimo 32 campi per comando. Per numeri e booleani definisci un valore iniziale coerente; un `number` deve essere finito, un `boolean` è `true` o `false`.

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
- Workflow JSON: massimo 2000 step, 100.000 valutazioni e circa 2 secondi di elaborazione effettiva; l'attesa delle API asincrone non consuma questo budget. Ogni 100 step il runtime cede il controllo all'interfaccia. Ogni chiamata asincrona ha un timeout massimo di due minuti.
- Annidamento step massimo 24; espressioni massimo 32 livelli; lista di un ciclo massimo 1000 elementi.
- Testi generati massimo 65.536 caratteri; massimo 20 messaggi da 4096 caratteri; dati privati massimo 64 KiB.
- Massimo 10.000 elementi nella pagina per un'inserzione plugin, 10.000 punti per `stroke.add`, liste costruite con `append` massimo 10.000 elementi. Immagini decodificate massimo 4 milioni di pixel.
- Numeri dei parametri host finiti, con valore assoluto massimo 100.000; spessori limitati a 0,1–512; testo 1–512; fattore di scala maggiore di zero e massimo 100. Posizioni fuori dal foglio sono possibili: usa `page.width`/`height` per produrre contenuti visibili.
- File: massimo 8 MiB ciascuno; fino a 8 export per comando, massimo 16 MiB totali. OCR: immagini massimo 4 milioni di pixel; timeout 45 secondi. HTTP: richieste/risposte massimo 8 MiB, timeout 20 secondi per risposta o inattività del flusso.
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

`test/plugin_system_test.dart` verifica formato e permessi, esempi, cicli e condizioni, trasformazioni, persistenza, disattivazione, aggiornamento, disinstallazione, rollback, limiti di elaborazione, conflitti con modifiche dell'utente, immagini valide/corrotte e uso dell'editor su telefono da 380dp. La suite completa continua a controllare penna, lazo, gomma, memoria, documenti e PDF/XOPP.

Per aggiornare i file degli esempi dopo una modifica a `plugin_examples.dart`, esegui:

```powershell
dart tool/generate_plugin_examples.dart
flutter test
flutter analyze --no-fatal-infos
```

Le prove di questa revisione sono in `docs/validation/plugins-tests.txt`, `plugins-analyze.txt` e `plugins-android-build.txt`. Il selettore file Android e la conservazione dei plugin dopo il riavvio sul dispositivo richiedono anche una prova fisica.

La suite avanzata include `advanced_plugin_test.dart` e `plugin_javascript_test.dart`. I test JavaScript usano il motore nativo reale: per prepararli su Windows esegui `powershell -ExecutionPolicy Bypass -File tool/prepare_plugin_tests.ps1 -FlutterRoot C:\src\flutter`, poi `flutter test`. Il download usa il controllo di firma di Cargokit. Senza libreria nativa i quattro test JavaScript sono esplicitamente saltati, non simulati; puoi indicare un percorso diverso con la variabile d'ambiente `PLUGIN_FJS_LIBRARY`.

Verifica del 7 ottobre 2026: **103 test complessivi superati**, compresi **4 test con JavaScript reale**, moduli ES, chiamate asincrone, rollback, permessi e interruzione di un ciclo infinito. LaTeX produce PNG di formule reali; Anki, pacchetti, OCR tramite provider controllabile e raster della pagina sono verificati. Log aggiornati: `docs/validation/advanced-plugins-all-tests.txt`, `advanced-plugins-analyze-final.txt`, `advanced-plugins-build-final.txt`, `advanced-plugins-web-build.txt`. L'OCR nativo e i selettori file devono ancora essere provati su dispositivo Android fisico. I warning sulla futura versione minima di Gradle/AGP/Kotlin sono quelli già descritti in `docs/DEPENDENCY_UPGRADE.md`.

Analisi finale: zero errori e warning, 196 informazioni di stile. Build APK release riuscita (**117,8 MB**, include motore JavaScript e modello OCR), in `build/app/outputs/flutter-apk/app-release.apk`; build Web release riuscita. La build Web esegue i workflow JSON, non il motore JavaScript nativo.
