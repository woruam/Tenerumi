# Estetica Pomodoro - 2026-10-07

Tema condiviso in lib/src/app_appearance.dart: pannelli opachi #101010, superfici #1A1A1A, bordo #292929, forme continue a raggio40. Accento predefinito #D71921; mantenuti colori dinamici, personalizzazione, nero OLED e stili icone. Anche il Pomodoro segue l'accento scelto nella fase lavoro; colori pausa invariati.

Uniformati libreria, drawer, schede documento, toolbar, menu strumenti, dialoghi, popup e pulsanti. Rimossi tutti i BackdropFilter dell'interfaccia. Impostazione icone con ChoiceChip che vanno a capo sui telefoni. Font VT323 e Inter inclusi localmente con licenze OFL (circa 1 MB totale), senza caricamento Google Fonts a runtime.

Timer racchiuso in RepaintBoundary; anello in un secondo boundary di 118x118, invalidato solo quando cambia il numero di puntini accesi o i colori. Paint riusato nel ciclo, rimosse trasparenza e ombra del pannello. Nessuna nuova animazione o dipendenza. Motore del disegno, virtualizzazione e cache documenti invariati.

## Verifica
- Suite completa: 133 test passati (pomodoro-style-all-tests.txt).
- Verifica finale timer/layout: test visivo ripetuto dopo isolamento anello e accento globale (pomodoro-style-visual-tests.txt).
- Analisi lib/test: nessun errore o warning, 199 informazioni stile esistenti (pomodoro-style-dart-analyze.txt).
- Screenshot verificati: libreria, impostazioni, workspace e menu penna a 380x800; workspace a 1100x800.
- git diff --check: superato.

## Limiti
I test verificano funzionamento, layout e assenza di filtri di sfocatura; non misurano frame time o latenza su Android. Il nuovo stile elimina lavoro di compositing e download font, ma le prestazioni effettive richiedono un profilo release sul dispositivo. Nessuna build APK effettuata.
