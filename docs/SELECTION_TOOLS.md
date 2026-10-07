# Evidenziatore, lazo e appunti

L'evidenziatore usa ora lo spessore impostato per la geometria sia dell'anteprima sia del tratto salvato, senza variazioni con la pressione. Prima il renderer imponeva sempre un diametro di 5, ignorando lo spessore memorizzato. Non vengono riscritti i dati dei documenti esistenti.

## Uso con la penna

1. Attivare il lazo e circondare gli elementi da selezionare.
2. La barra offre **Elimina**, **Copia**, **Sposta** e **Fine**, con icone e descrizioni. I comandi funzionano anche con la penna quando il canvas intercetta le gesture per impedire lo scorrimento accidentale.
3. Toccare **Sposta**, poi trascinare sul foglio per spostare la selezione. È possibile anche trascinare direttamente all'interno della selezione usando il lazo. Il punto nell'angolo in basso a destra permette il ridimensionamento.
4. Toccare **Copia**, poi **Fine**. Tenere la punta ferma sul foglio per circa mezzo secondo, sollevarla e toccare **Incolla**. La pressione prolungata non salva un punto di inchiostro. Muovere la penna durante l'attesa conserva il normale comportamento di disegno.
5. Dopo l'incolla, gli elementi sono selezionati e pronti per essere spostati. **Fine** chiude la selezione senza cancellare gli elementi.

La copia conserva tratti, testo, immagini e formule. Gli appunti sono interni all'app e condivisi fra pagine e documenti della stessa workspace; non persistono dopo la chiusura della workspace. Ogni incolla crea elementi indipendenti dall'originale e dalle altre copie. Eliminazione, incolla, spostamento e ridimensionamento sono annullabili; un trascinamento crea una sola voce nella cronologia, mentre copiare o chiudere la selezione non crea modifiche.

## Verifica

`test/selection_tools_test.dart` riproduce il riconoscitore della penna usato dal canvas reale e verifica spessore raster dell'evidenziatore a pressioni diverse, comandi del lazo con penna, spostamento e incolla a zoom 1x/2,5x, annulla/ripristina, copie indipendenti fra documenti, annullamento della pressione prolungata con movimento e incolla/spostamento nella modalità di navigazione.

La suite completa passa 70 test e include anche i controlli di continuità fra anteprima e tratto definitivo, conservazione dei campioni ad alta frequenza, gomma, salvataggio, memoria, zoom e workspace. L'analisi non rileva errori o avvisi; restano 197 informazioni sullo stile del codice storico. Le prove finali sono salvate in `docs/validation/selection-tools-tests.txt`, `selection-tools-analyze.txt` e `selection-tools-android-build.txt`. Il test con penna è simulato: la risposta della penna fisica e del palmo richiede ancora una prova sul dispositivo.

La build APK release è riuscita (54,9 MB): `build/app/outputs/flutter-apk/app-release.apk`. Restano i warning già rilevati sulla futura incompatibilità delle versioni di Gradle/AGP/Kotlin, descritti in `DEPENDENCY_UPGRADE.md`; non impediscono questa compilazione.
