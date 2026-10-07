# Penna/gomma — 2026-10-06

Implementate geometria condivisa arrotondata e gomma circolare con sweep,
persistenza, undo e PDF trasparente sulle pagine cancellate. Aggiunti 12 test.

- Nessuna build APK/Web/desktop eseguita, come richiesto.
- Nuovi test non eseguiti: primo tentativo bloccato dall'accesso al lockfile
  della cache SDK (`ink-round-tests.txt`); autorizzazione per i soli test
  rifiutata con `Rejected("rejected by user")`. Nessun tentativo successivo.
- Formattazione e parsing dei nove file Dart riusciti (`ink-eraser-format.txt`).
- Analisi statica di `lib` e `test` riuscita (exit 0), senza errori o warning;
  restano informazioni sullo stile (`ink-eraser-analyze.txt`). Nessun risultato
  della suite precedente certifica questo seguito.
- Immagini di regressione predisposte nei test, non ancora generate.

Procedura e limite di portabilita' delle maschere .xopp in `docs/PIXEL_ERASER.md`.
