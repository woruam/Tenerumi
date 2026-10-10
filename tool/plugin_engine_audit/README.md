# Audit isolato del precedente motore

Questo progetto **non è una dipendenza dell'app**. Riproduce con un file temporaneo innocuo il caricamento di moduli esterni consentito da FJS 3.2.0, anche con i builtin disabilitati. Non usa dati reali dell'utente.

Da questa cartella esegui `flutter pub get`, imposta `PLUGIN_FJS_LIBRARY` al percorso assoluto della libreria nativa verificata e poi esegui `flutter test`. La libreria Windows della verifica originale era `build/plugin-test-native/fjs.dll` nella radice del repository. Il percorso relativo della prova rispecchia l'ambiente Windows della verifica originale; per ripetere da questa cartella usare il percorso relativo calcolato dal test.

Il test viene saltato esplicitamente se la libreria non è disponibile. FJS è assente dal `pubspec.yaml` dell'app e dai suoi percorsi di esecuzione. Non copiare questo motore nel prodotto: per un futuro backend servono loader chiuso e isolamento del sistema operativo, come indicato in `docs/PLUGIN_SECURITY.md`.
