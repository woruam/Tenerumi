import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'XppFile.dart';
import 'compat/file_picker_cross.dart';

/// OS file activations use the same bounded PDF importer as the file picker.
class ExternalDocuments {
  static const channel = MethodChannel(
    'online.xournal.mobile/external_documents',
  );

  static Future<List<Map<String, String>>> pending({
    bool listen = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return [];
    final documents = await channel.invokeListMethod<dynamic>(
      listen ? 'listen' : 'getInitialDocuments',
    );
    return (documents ?? [])
        .map((entry) => Map<String, String>.from(entry as Map))
        .toList();
  }

  static Future<XppFile> importPdf(Map<String, String> document) async {
    final location = document['uri']!;
    final source = await FilePickerCross.fromInternalPath(
      path: location.startsWith('file:')
          ? Uri.parse(location).toFilePath()
          : location,
    );
    // Android provider URIs often have no extension. The original display name
    // belongs to the embedded attachment; it is never used as a storage path.
    final pdf = FilePickerCross(
      source.toUint8List(),
      path: document['name'] ?? source.path,
    );
    return XppFile.importPdf(pdf: pdf);
  }
}
