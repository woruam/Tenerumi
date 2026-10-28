/// Features that are still experimental are excluded from the public build.
/// Opt in explicitly with --dart-define for development and testing.
abstract final class AppFeatures {
  static const bool plugins = bool.fromEnvironment(
    'OSI_ENABLE_PLUGINS',
    defaultValue: false,
  );

  static const bool manualBackup = bool.fromEnvironment(
    'OSI_ENABLE_BACKUP',
    defaultValue: true,
  );
}
