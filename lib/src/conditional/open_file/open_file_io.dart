import 'dart:io';
import 'dart:typed_data';

import 'package:xournalpp/src/compat/file_picker_cross.dart';

FilePickerCross openFileByUri(String url, String extension) {
  Uint8List bytes = File(url).readAsBytesSync();
  return (FilePickerCross(bytes,
      path: url, type: FileTypeCross.custom, fileExtension: extension));
}
