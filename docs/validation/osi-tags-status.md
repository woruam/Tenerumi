# OSI 0.5 e tag - 2026-10-08

## Modifiche
- Scelta tag nella creazione di una nota, inizializzata dal filtro attivo (oppure Appunti). Crea tag nella stessa finestra; nomi da 1 a 40 caratteri, spazi normalizzati, duplicati ignorati senza distinzione maiuscole, Tutti riservato al filtro.
- Catalogo personalizzato in SharedPreferences, con inclusione dei tag presenti nei documenti recenti. I tag restano disponibili anche annullando la creazione della nota.
- Cambia tag su ogni scheda (pulsante con icona etichetta o pressione prolungata). Aggiornamento seriale dei metadati, conservazione di anteprime e date; il filtro mostra la nuova categoria. Le modifiche nella libreria sono immediatamente persistenti; il tag viene copiato nel documento riaperto e incorporato nel prossimo salvataggio .xopp.
- Campo tag opzionale nel documento, snapshot e serializzazione via isolate. Attributo osipp-tag con escaping XML; file precedenti senza attributo restano compatibili e conservano il tag della libreria.
- Nome pubblico OSI in home, drawer, MaterialApp, launcher Android e titolo Web; creator OSI nei nuovi .xopp e PDF. ApplicationId online.xournal.mobile, directory di archiviazione, formato .xopp e chiavi esistenti conservati.
- Versione pacchetto 0.5.0+31 (buildNumber incrementato da 30). Info app mostra 0.5, build reale ottenuta da package_info_plus, stato in sviluppo, funzioni e credito/licenza del progetto originale. Entrambi i drawer usano lo stesso dialogo.
- Nessuna dipendenza nuova, sfocatura o animazione aggiuntiva. Piccolo catalogo locale; nessuna rilettura o riserializzazione documenti necessaria per filtrare.

## Verifica
138 test superati nella suite completa (osi-tags-all-tests.txt). Regressioni nuove per normalizzazione e duplicati, snapshot/round-trip con caratteri speciali, persistenza .xopp/metadata, creazione e selezione custom su telefono, Info app 0.5/build31. Esteso il test di salvataggio reale: creazione tag, salvataggio documento, riavvio, filtro, riassegnazione, altro riavvio e riapertura con il tag corretto; anteprime decodificate e contenuto verificati.
Analisi lib/test senza errori o warning (sole informazioni sul codice storico); log osi-tags-final-analyze.txt. git diff --check superato. Verificati screenshot a 380x800: nuovo appunto/tag, Info app e documento riassegnato con preview visibile.

## Utilizzo
Nuovo Appunto > Tag: scegli una categoria o premi Crea tag.
Per spostare una nota esistente: premi l'icona etichetta sulla scheda > scegli tag > Salva.
Menu laterale > Info App: nome, versione e build.

## Limiti
Nessuna nuova build APK o verifica su dispositivo eseguita. Per applicare nome launcher, versione e funzioni bisogna ricompilare e installare l'APK aggiornato. La descrizione delle funzionalita non implica stabilita di una versione finale.
