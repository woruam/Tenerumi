import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xournalpp/plugins/plugin_package.dart';

/// dart tool/package_plugin.dart path/to/plugin output.osiplugin
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Uso: dart tool/package_plugin.dart cartella output.osiplugin',
    );
  }
  final directory = Directory(args[0]).absolute;
  final archive = Archive();
  await for (final file in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (file is! File) continue;
    final name = file.absolute.path
        .substring(directory.path.length + 1)
        .replaceAll('\\', '/');
    if (name != 'manifest.json' && !name.endsWith('.js')) continue;
    final bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  final bytes = ZipEncoder().encode(archive);
  final plugin = decodePluginPackage(Uint8List.fromList(bytes));
  await File(args[1]).writeAsBytes(bytes);
  stdout.writeln(
    'Creato ${args[1]} (${plugin.name}, ${plugin.commands.length} comandi)',
  );
}
