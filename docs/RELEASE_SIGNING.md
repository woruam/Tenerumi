# Firma e continuità degli aggiornamenti

Gli APK release richiedono una chiave stabile di produzione. La configurazione non usa mai la chiave debug come fallback. Conservare una copia cifrata e verificata del keystore fuori dal repository e limitare l’accesso alla distribuzione.

## Prima distribuzione su Windows

Dalla cartella del progetto, eseguire una sola volta:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/configure_release.ps1
```

Lo script usa il JDK disponibile (oppure quello di Android Studio), genera una chiave RSA a 3072 bit valida per 10000 giorni, crea una password casuale e configura automaticamente il fingerprint SHA-256. La password non viene mostrata né passata negli argomenti dei processi. I file sono protetti con ACL Windows e ignorati da Git: `android/keystore/osi-production.jks`, il certificato pubblico e `android/key.properties`. Quest’ultimo contiene le password: custodirlo insieme al keystore, con una copia cifrata fuori dal repository e dalle cartelle pubbliche. Lo script conserva le configurazioni presenti e rifiuta di sostituire un keystore esistente.

Poi compilare normalmente:

```sh
flutter build apk --release
```

L’APK è `build/app/outputs/flutter-apk/app-release.apk`. Non rigenerare la chiave per gli aggiornamenti. Un eventuale APK debug precedente usa una firma diversa: il passaggio alla release non equivale automaticamente a un aggiornamento compatibile.

Per provare l’app senza predisporre la firma release, usare `flutter build apk --debug`; l’APK è `build/app/outputs/flutter-apk/app-debug.apk`. Gli avvisi sulle versioni Gradle/AGP/Kotlin non sono l’errore «Firma release non configurata» e il flag che salta la verifica delle dipendenze non risolve l’assenza della chiave.

## Configurazione di una chiave esistente e CI

In locale usare `android/key.properties` (ignorato da Git), con `storeFile`, `storePassword`, `keyAlias`, `keyPassword`, `certSha256`. In CI usare l’ambiente protetto `production`, approvazioni e i segreti `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_CERT_SHA256`. Il workflow controlla il certificato dell’APK prima di caricare l’artefatto. I segreti non sono disponibili alle pull request.

Le proprietà possono essere fornite tramite le variabili `OSIPP_RELEASE_STOREFILE`, `OSIPP_RELEASE_STOREPASSWORD`, `OSIPP_RELEASE_KEYALIAS`, `OSIPP_RELEASE_KEYPASSWORD`, `OSIPP_RELEASE_CERTSHA256`. Confrontare SHA-256 con un valore attendibile ottenuto dal certificato ufficiale. Lo script `scripts/check_distribution.py --apk … --apksigner …` blocca un certificato differente o debug.

Prima della prima release determinare come sono firmate le installazioni già distribuite: una nuova chiave non consente automaticamente di aggiornare APK precedenti firmati debug. Non suggerire disinstallazione senza un backup esportato, verificato e ripristinabile. Per gli store usare la loro gestione delle chiavi e rotazione supportata; per APK diretti pianificare e provare la catena di firma e l’aggiornamento sul dispositivo. Mantenere applicationId e directory dei dati fino a una migrazione documentata. Non generare automaticamente una nuova chiave a ogni build.

Riferimento: [documentazione Android sulla firma](https://developer.android.com/studio/publish/app-signing).
