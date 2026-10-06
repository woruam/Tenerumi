# Stato verifica del seguito — 2026-10-06

- Suite Flutter: 42 test superati (`tests.txt`).
- Analisi Dart: nessun errore o warning; 215 informazioni sullo stile (`analyze.txt`).
- Split: 3 test superati (`split-resize-tests.txt`).
- Anteprima penna e input: 7 test superati.
- Dipendenze finali risolte; `printing` inutilizzato rimosso (`android-dependencies.txt`).

La suite completa e l'analisi includono l'adattatore dynamic_color; sono state
eseguite prima della sola rimozione della dipendenza inutilizzata printing.

Le build APK e Web finali non sono state avviate: entrambe le richieste di
autorizzazione hanno ricevuto `Rejected("rejected by user")`. I test JVM Android
non sono stati completati. Gli script `scripts/verify.ps1` e
`scripts/verify-android.ps1` consentono di ripetere le verifiche.

I log Android con suffisso `-cancelled` conservano tentativi interrotti.
`web-build.txt` conserva un tentativo fallito precedente alla correzione del
tipo ColorScheme. Nessuno di questi log è prova di una build finale riuscita.
L'APK eventualmente presente in build proviene da una compilazione precedente.

Refresh effettivo, tempi dei frame e latenza penna/schermo richiedono una prova
su hardware: i test a 120 Hz simulati non misurano queste prestazioni.
