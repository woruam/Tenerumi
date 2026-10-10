import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';

import 'package:xournalpp/plugins/plugin_examples.dart';

Future<void> main() async {
  final directory = Directory('examples/plugins');
  await directory.create(recursive: true);
  for (var index = 0; index < pluginExamples.length; index++) {
    final id = pluginExamples[index]['id'];
    await File('${directory.path}/$id.osiplugin.json')
        .writeAsString('${workflowExampleSource(index)}\n');
    if (pluginExamples[index]['runtime'] == 'javascript') {
      final manifest = Map<String, dynamic>.of(pluginExamples[index]);
      final modules = manifest.remove('modules') as Map;
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            const JsonEncoder.withIndent('  ').convert(manifest),
          ),
        );
      final sourceDirectory = Directory('${directory.path}/$id');
      await sourceDirectory.create(recursive: true);
      await File('${sourceDirectory.path}/manifest.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
      for (final module in modules.entries) {
        archive.addFile(
          ArchiveFile.string(module.key as String, module.value as String),
        );
        await File('${sourceDirectory.path}/${module.key}')
            .writeAsString(module.value as String);
      }
      await File('${directory.path}/$id.osiplugin')
          .writeAsBytes(ZipEncoder().encode(archive));
    }
  }
}
