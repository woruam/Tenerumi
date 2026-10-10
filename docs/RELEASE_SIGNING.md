# Firma e continuità degli aggiornamenti

Gli APK release richiedono una chiave stabile di produzione. La configurazione non usa mai la chiave debug come fallback. Conservare una copia cifrata e verificata del keystore fuori dal repository e limitare l’accesso alla distribuzione.

In locale usare `android/key.properties` (ignorato da Git), con `storeFile`, `storePassword`, `keyAlias`, `keyPassword`, `certSha256`. In CI usare l’ambiente protetto `production`, approvazioni e i segreti `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_CERT_SHA256`. Il workflow controlla il certificato dell’APK prima di caricare l’artefatto. I segreti non sono disponibili alle pull request.

Le proprietà possono essere fornite tramite le variabili `OSIPP_RELEASE_STOREFILE`, `OSIPP_RELEASE_STOREPASSWORD`, `OSIPP_RELEASE_KEYALIAS`, `OSIPP_RELEASE_KEYPASSWORD`, `OSIPP_RELEASE_CERTSHA256`. Confrontare SHA-256 con un valore attendibile ottenuto dal certificato ufficiale. Lo script `scripts/check_distribution.py --apk … --apksigner …` blocca un certificato differente o debug.

Prima della prima release determinare come sono firmate le installazioni già distribuite: una nuova chiave non consente automaticamente di aggiornare APK precedenti firmati debug. Non suggerire disinstallazione senza un backup esportato, verificato e ripristinabile. Per gli store usare la loro gestione delle chiavi e rotazione supportata; per APK diretti pianificare e provare la catena di firma e l’aggiornamento sul dispositivo. Mantenere applicationId e directory dei dati fino a una migrazione documentata. Non generare automaticamente una nuova chiave a ogni build.

Riferimento: [documentazione Android sulla firma](https://developer.android.com/studio/publish/app-signing).
