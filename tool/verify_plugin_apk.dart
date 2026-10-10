import 'dart:io';

import 'package:archive/archive.dart';

/// Inspect metadata only; APK contents are never extracted or executed.
void main(List<String> args) {
  final path = args.isEmpty
      ? 'build/app/outputs/flutter-apk/app-release.apk'
      : args.single;
  final directory = ZipDirectory()
    ..read(InputMemoryStream(File(path).readAsBytesSync()));
  final blocked = directory.fileHeaders
      .where(
        (f) => RegExp(
          r'fjs|quickjs|rust_bridge',
          caseSensitive: false,
        ).hasMatch(f.filename),
      )
      .toList();
  final lines = [
    'APK: $path',
    'Engine/bridge entries found: ${blocked.length}',
    'Native libraries:',
    ...directory.fileHeaders
        .where(
          (f) => f.filename.startsWith('lib/') && f.filename.endsWith('.so'),
        )
        .map((f) => f.filename),
  ];
  File('docs/validation/plugin-security-apk-inspection.txt')
      .writeAsStringSync('${lines.join('\n')}\n');
  stdout.writeln(lines.join('\n'));
  if (blocked.isNotEmpty) exitCode = 1;
}
