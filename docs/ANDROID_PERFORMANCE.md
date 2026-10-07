# Android: refresh rate, penna e build

## Implementazione

L'Activity richiede il modo del display con refresh maggiore alla risoluzione
corrente. La richiesta viene rinnovata al resume, al ritorno del focus e quando
cambia il display; il listener viene disiscritto al pause. Android e il produttore
possono limitarla per risparmio energetico, temperatura o impostazioni utente.
La selezione 60/90/120 Hz è coperta da test JVM in `DisplayModePolicyTest`.

Al DOWN di stilo o gomma viene richiesto `requestUnbufferedDispatch` sul
`FlutterView`, prima di inoltrare normalmente l'evento. Il touch conserva il
dispatch standard. Si riduce il batching Android dell'input; non si aggiungono
eventi sintetici o duplicati. Questa modifica non implementa il front buffer
Jetpack Ink o la predizione del movimento e non garantisce una latenza hardware.

## Toolchain

- SDK corrente: Flutter 3.47.6, Dart 3.13.5. Risultati aggiornati in
  [DEPENDENCY_UPGRADE.md](DEPENDENCY_UPGRADE.md); i log precedenti sotto
  descrivono le verifiche con il vecchio SDK.
- AGP 8.12.1, Kotlin Gradle Plugin 2.2.20, wrapper Gradle 8.14, target JVM 17
  per l'app. AGP 8.12.1 soddisfa anche il requisito di package_info_plus.
- Plugin aggiornati: desktop_drop 0.8.4, dynamic_color 2.1.0,
  package_info_plus 10.2.2, pdfx 2.11.0.

Built-in Kotlin richiede **Flutter 3.47 o successivo e AGP 9+** secondo la
[guida ufficiale Flutter](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers).
Con AGP 8.12.1 si conserva KGP e `android.builtInKotlin=false`.
Flutter 3.47.6 segnala la futura dismissione di Gradle 8.14, AGP 8.12.1 e
KGP 2.2.20; questi avvisi restano visibili e non vengono aggirati.
La migrazione a Gradle 9.1+, AGP 9.0.1+ e built-in Kotlin richiede una
verifica dedicata dei plugin Android. I nuovi plugin supportano la migrazione
futura, ma applicano ancora KGP quando built-in Kotlin è disabilitato.

La verifica Gradle identifica `:printing:compileDebugJavaWithJavac` come origine
dei tre warning Java 8: printing 5.14.3 compilava a source/target 8 con JDK 21.
La dipendenza inutilizzata `printing` è stata rimossa: il progetto usa `pdfx`
per la rasterizzazione e non invoca più le API del plugin di stampa.
Anche desktop_drop 0.8.4 dichiara target 8, ma il suo task Java è `NO-SOURCE`
e non emette quei warning. Il progetto non nasconde il warning e non forza
target diversi nei moduli di terzi.
Gradle 8.14 segnala inoltre che il proprio Kotlin incorporato 2.0.21 differisce
da KGP 2.2.20 nell'included build Flutter; il log conserva questa segnalazione.
I messaggi di tree shaking delle icone sono normali ottimizzazioni della release.

## Verifica ripetibile

Stato di questa sessione: dipendenze finali risolte correttamente. La prima
build e i test debug sono stati interrotti per rimuovere `printing` ed eseguire
le verifiche in sequenza. La richiesta di avvio della build APK finale è stata
rifiutata (`Rejected("rejected by user")`); **APK finale e test JVM non sono
verificati**. I log con suffisso `-cancelled` documentano tentativi interrotti,
non risultati positivi. Eseguire lo script seguente per completare la verifica.

Eseguire `flutter build apk --release` per verificare l'intero grafo Android.
Lo script `scripts/verify-android.ps1 -JavaHome '<cartella JDK>'` esegue
dipendenze, APK release e test JVM in sequenza, interrompendosi al primo errore.
Per i test JVM: da `android`, `./gradlew.bat :app:testReleaseUnitTest` con JDK 17
o successivo. I risultati XML sono in `build/app/test-results/testReleaseUnitTest`.
La build e le dipendenze vengono registrate in `docs/validation/android-*.txt`.

Su un dispositivo reale, usare una build **profile o release** e abilitare il
refresh alto nelle impostazioni del sistema. Controllare il refresh effettivo
con l'overlay Android e i tempi UI/raster in Flutter DevTools: budget 11,1 ms
a 90 Hz e 8,3 ms a 120 Hz. Ripetere a 60 Hz come confronto.

Provare tratti lunghi con pressione variabile su una pagina vuota e una pagina
PDF già rasterizzata, poi su un documento con migliaia di tratti. Ruotare il
dispositivo, cambiare app e riaprire, collegare eventualmente un display esterno.
Verificare palmo, gomma, pulsanti e pinch zoom, senza tratti doppi o punti persi.
Per misurare la latenza penna/schermo serve una ripresa ad alta frequenza:
il numero di Hz selezionato e i test JVM non misurano la latenza end-to-end.

Fonti: [compatibilità AGP](https://developer.android.com/build/releases/agp-8-12-0-release-notes),
[input stilo Android](https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/advanced-stylus-features),
[preferenza modo display](https://developer.android.com/reference/android/view/WindowManager.LayoutParams#preferredDisplayModeId).
