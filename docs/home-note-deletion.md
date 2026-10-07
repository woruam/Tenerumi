# Eliminazione degli appunti dalla home

Tenere premuta la scheda di una nota per aprire il menu con Cambia tag ed Elimina. Elimina apre la conferma con il nome dell’appunto. Annulla o chiudere il popup lascia file e indice intatti. La conferma elimina il file XOPP (incluso l’audio incorporato), la voce recente e l’eventuale copia di recupero associata; la home ricarica elenco e filtri. Il pulsante tag sulla scheda e il tap per aprire la nota rimangono disponibili.

Gli aggiornamenti dell’indice sono serializzati con i salvataggi e gli arricchimenti delle anteprime. Se la cancellazione del file fallisce, la voce rimane nell’indice e viene mostrato un messaggio. Per i documenti Android content:// viene utilizzata l’API del provider [DocumentsContract.deleteDocument](https://developer.android.com/reference/android/provider/DocumentsContract#deleteDocument(android.content.ContentResolver,android.net.Uri)); provider senza permesso o supporto alla cancellazione possono rifiutare l’operazione. Nel browser si eliminano solo dati accessibili alla sessione e la voce della libreria, senza accesso ai file già scaricati fuori dall’app.

Verifica: 150 test Flutter passati, inclusi tre test nuovi su file/indice/recovery e fallimento, URI Android, menu/annullamento/conferma e aggiornamento della home. Analisi Dart senza errori o warning. Compilazione Kotlin Android riuscita; restano gli avvisi della toolchain preesistenti. Nessun APK generato né prova con provider Android reale.

Prove: [regressioni](validation/home-delete-full-tests.txt), [test dedicati](validation/home-delete-tests.txt), [analisi](validation/home-delete-analyze.txt), [compilazione Android](validation/home-delete-android.txt), [conferma sul telefono](validation/home-delete-confirmation.png).
