# Esperienza di scrittura e navigazione — 16 ottobre 2026

Aggiornamento successivo: il problema XOPP menzionato sotto è stato corretto
e le suite dei due profili passano. Backup manuale e plugin, incluso Pomodoro,
sono ora esclusi dal profilo pubblico. Vedi `release-profile-status.md`.

Implementate le otto richieste: penna minima 0,1 con geometria realmente più
sottile; rimosso zoom da doppio tocco; menu Incolla 120×48 pixel logici sotto
zoom; barra laterale con preferenza persistente; bordo della pagina corrente
di un pixel sullo schermo e colore persistente; snapshot PDF delle due schede
recenti conservati prima dello smontaggio, incluso il primo fotogramma
decodificato; apertura PDF Android/Windows/Linux; icona Pomodoro progressiva.

La cache conserva al massimo quattro raster visibili per scheda inattiva,
due schede inattive e 32 MiB di raster complessivi. Le immagini decodificate
restano nel budget condiviso di 32 MiB. Renderer e texture PDF vengono
rilasciati normalmente. Le altre schede vengono renderizzate su richiesta.

## Verifiche

- Revisione indipendente completata senza problemi bloccanti residui.
- `experience-ui-cache-final.txt`: 10 test superati per primo fotogramma PDF,
  limiti cache, preferenze, barra, bordo e timer reale minimizzato.
- `experience-pen-gestures-final.txt`: 29 test superati per penna, pressione,
  geometria, selezione/incolla e gesti dopo il doppio tocco.
- `experience-external-palm-final.txt`: 8 test superati per attivazioni PDF,
  URI non leggibili e interazione penna/palmo/toolbar. Totale mirati: 47/47.
- `experience-analyze.txt`: analisi senza errori o warning; 317 informazioni
  di stile non bloccanti.
- `experience-android-build.txt`: compilazione APK debug riuscita.
- `experience-android-final.txt`: APK debug ricompilato con tutti gli ultimi
  interventi; manifest finale ispezionato in `experience-apk-manifest.txt`.
- Screenshot finali: `experience-pomodoro-style-*.png`.
- Le esecuzioni complete registrate includono una regressione già presente
  nel repository: `opening_performance_test.dart`, test `streamed XOPP
  preserves serializer metadata and escaped text`. Il serializzatore
  `XppText` fa escaping prima di passare il testo a `XmlText`; il loader
  restituisce entità ancora codificate. Questi file non sono stati modificati.
  Le altre anomalie d'integrazione emerse sono state corrette e ricontrollate.

## Limiti delle prove

La compilazione Windows si ferma alla richiesta Flutter di supporto ai link
simbolici/Modalità sviluppatore della macchina, prima della compilazione C++.
Il comando e l'esito sono in `experience-windows-build.txt`.
Nessuna prova su dispositivo fisico: il comportamento di Apri con e dello
stilo hardware va confermato installando l'APK. Su Windows serve avviare
l'app dalla cartella definitiva; Linux richiede l'installazione del file
desktop, come descritto in `../pdf-open-with.md`.
