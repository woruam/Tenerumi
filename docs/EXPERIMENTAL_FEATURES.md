# Profili di compilazione

Lo stesso ramo contiene le funzioni pubbliche e quelle ancora sperimentali.
`lib/src/app_features.dart` definisce due costanti di compilazione, entrambe
disattivate per impostazione predefinita:

| Opzione | Funzioni incluse quando vale `true` |
| --- | --- |
| `OSI_ENABLE_PLUGINS` | Gestore e runtime plugin, Pomodoro, flashcard Anki, OCR Android |
| `OSI_ENABLE_BACKUP` | Creazione e ripristino manuale di archivi degli appunti |

Il **Pomodoro rimane un plugin**. Disabilitare i plugin esclude anche la sua
interfaccia e il timer. I flag non modificano il salvataggio automatico, il
recupero degli appunti o l'esportazione ordinaria di file XOPP e PDF.

## Compilazione pubblica

I comandi Flutter standard usano già il profilo pubblico. Per renderlo
esplicito, come nella CI:

```sh
flutter build apk --release --dart-define=OSI_ENABLE_PLUGINS=false --dart-define=OSI_ENABLE_BACKUP=false
```

Resta necessaria la [firma di produzione](RELEASE_SIGNING.md). Non utilizzare
un APK debug come artefatto di rilascio.

Le costanti impediscono l'avvio del controller plugin, l'accesso alle sue
schermate e ai dialog di backup. Nelle compilazioni ottimizzate il codice
irraggiungibile viene eliminato dal compilatore. Su Android, Gradle legge
lo stesso flag ed esclude anche sorgenti OCR, canale nativo e dipendenza MLKit.
L'infrastruttura condivisa per esportare PDF resta inclusa.

## Sviluppo sperimentale

```sh
flutter run --dart-define=OSI_ENABLE_PLUGINS=true --dart-define=OSI_ENABLE_BACKUP=true
flutter test --dart-define=OSI_ENABLE_PLUGINS=true --dart-define=OSI_ENABLE_BACKUP=true
```

Le due opzioni sono indipendenti: si può abilitare solo quella su cui si lavora.
Cambiare i flag richiede di ricompilare e riavviare l'app. Il codice sorgente
sperimentale rimane visibile nel repository. I test diretti dei moduli possono
continuare a verificarli anche quando il punto di ingresso dell'app li esclude.

Le preferenze dei plugin già installati restano conservate, ma non vengono
caricate nel profilo pubblico. Anche flashcard e allegati già presenti nei
documenti vengono mantenuti al salvataggio, per evitare perdita di dati.

## Backup manuale

Con `OSI_ENABLE_BACKUP=true`, aprire **Impostazioni → Crea Backup → Prepara
backup**, poi **Esporta backup**. Per importare su un altro dispositivo:
**Impostazioni → Ripristina Backup → Scegli backup → Ripristina appunti**.
Il ripristino aggiunge copie degli appunti; ripeterlo crea altre copie.

Gli archivi manuali non effettuano sincronizzazione. Sono supportati fino a
10000 appunti e 512 MB compressi. Include tag, preferiti, immagini, PDF,
registrazioni audio e flashcard; gli allegati mancanti vengono segnalati.

## Plugin per lo studio

Con `OSI_ENABLE_PLUGINS=true`, dalla sezione **Plugin** si possono attivare
Pomodoro e Anki. Sono inizialmente disattivati e la scelta viene conservata.
Disattivando Pomodoro il pannello e l'icona scompaiono e il timer si ferma.

Per Anki, **Doppia selezione** acquisisce prima il titolo e poi la risposta.
**Flashcard dell'appunto** consente di modificare il set ed esportarlo. Il set
è conservato nel documento XOPP. **Esporta per Anki** produce uno ZIP con
`flashcard.txt`, immagini e istruzioni; **Esporta JSON** conserva i dati OSI
e non è un formato di importazione Anki.

I plugin personalizzati usano workflow JSON. JavaScript resta disabilitato
anche nel profilo sperimentale. Vedi la [guida plugin](../PLUGIN_GUIDE.md) e
il [modello di sicurezza](PLUGIN_SECURITY.md).

Riferimenti: [costanti di compilazione Dart](https://dart.dev/libraries/core/environment-declarations),
[sorgenti Android per variante](https://developer.android.com/build/build-variants).
