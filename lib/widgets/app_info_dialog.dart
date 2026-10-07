import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> showOsiAppInfo(BuildContext context) async {
  String version = '0.5';
  String? build;
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) {
      version = info.version.endsWith('.0')
          ? info.version.substring(0, info.version.length - 2)
          : info.version;
    }
    build = info.buildNumber;
  } catch (_) {
    // Metadata can be unavailable on unsupported hosts or in previews.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Info app'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OSI', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            Text('Versione $version'),
            if (build != null && build.isNotEmpty) Text('Build $build'),
            const SizedBox(height: 16),
            const Text('Versione in sviluppo'),
            const SizedBox(height: 8),
            const Text(
              'Appunti digitali, disegno e annotazioni PDF. Organizza i tuoi documenti con tag, usa il canvas e studia con il timer Pomodoro.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Basata su Xournal++ Mobile. Compatibile con documenti .xopp. Licenza EUPL-1.2.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'OSI',
            applicationVersion: version,
          ),
          child: const Text('Licenze'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}
