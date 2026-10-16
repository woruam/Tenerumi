# Aprire un PDF con OSI

- **Android:** dopo aver installato la nuova APK, scegliere OSI dal menu
  **Apri con** di un PDF. Funziona anche con URI `content://` senza estensione
  e mentre l'app è già aperta. Il PDF viene importato come nota annotabile.
- **Windows:** avviare OSI almeno una volta dalla cartella definitiva.
  L'app registra il proprio percorso tra i programmi disponibili per i PDF
  per l'utente corrente. Non cambia il lettore PDF predefinito. Anche i
  percorsi con spazi sono supportati. Se si sposta l'app, avviarla nuovamente.
- **Linux:** la compilazione include `share/applications/osi.desktop` nel
  bundle. Dopo l'installazione nella destinazione definitiva, installare
  quel file con `desktop-file-install --dir="$HOME/.local/share/applications"`
  e aggiornare le associazioni con `update-desktop-database
  "$HOME/.local/share/applications"`. Il percorso `Exec` contiene la
  destinazione configurata durante la compilazione.

Il PDF originale resta separato dalla nota importata. Errori di lettura e PDF
non validi vengono segnalati nell'app.

Riferimenti:
- [Filtri intent Android](https://developer.android.com/guide/components/intents-filters)
- [Registrazione Apri con Windows](https://learn.microsoft.com/en-us/windows/win32/shell/how-to-include-an-application-on-the-open-with-dialog-box)
