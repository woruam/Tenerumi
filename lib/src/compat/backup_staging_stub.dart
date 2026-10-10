import 'dart:typed_data';

const supportsDiskStaging = false;
Future<String> createStaging() =>
    throw UnsupportedError('Staging non disponibile');

class StagedZipWriter {
  StagedZipWriter(String root);
  String get path => throw UnsupportedError('Staging non disponibile');
  Future<void> add(String name, Uint8List bytes) =>
      throw UnsupportedError('Staging non disponibile');
  Future<void> close() async {}
}

Future<Map<String, dynamic>> inspectArchive(String path) =>
    throw UnsupportedError('Staging non disponibile');
Future<Uint8List> readStaged(String path) =>
    throw UnsupportedError('Staging non disponibile');
Future<void> disposeStaging(String root) async {}
Future<void> copyToPath(String source, String destination) =>
    throw UnsupportedError('Staging non disponibile');
Future<String> writeStream(Stream<List<int>> stream, int maxBytes) =>
    throw UnsupportedError('Staging non disponibile');
