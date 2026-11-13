import 'dart:typed_data';

Future<Map<String, dynamic>> readState() =>
    throw UnsupportedError('Storage non disponibile');
Future<void> writeState(Map<String, dynamic> state) =>
    throw UnsupportedError('Storage non disponibile');
Future<void> quarantine(String raw) =>
    throw UnsupportedError('Storage non disponibile');
Future<String> putBlob(Uint8List bytes) =>
    throw UnsupportedError('Storage non disponibile');
Future<Uint8List> getBlob(String key) =>
    throw UnsupportedError('Storage non disponibile');
Future<String?> blobFilePath(String key) async => null;
Future<void> stageRecovery(Map<String, dynamic> entry) =>
    throw UnsupportedError('Storage non disponibile');
Future<List<Map<String, dynamic>>> stagedRecoveries() =>
    throw UnsupportedError('Storage non disponibile');

Future<bool> hasBlob(String hash) =>
    throw UnsupportedError('Storage non disponibile');
Future<List<Map<String, dynamic>>> retainedStates() =>
    throw UnsupportedError('Storage non disponibile');
Future<void> compact(Set<String> live, List<Map<String, dynamic>> retained) =>
    throw UnsupportedError('Storage non disponibile');
final warnings = <String>[];

Future<void> stageLibrary(Map<String, dynamic> entry) =>
    throw UnsupportedError('Storage non disponibile');
Future<List<Map<String, dynamic>>> libraryCandidates() =>
    throw UnsupportedError('Storage non disponibile');
Future<void> forgetLibrary(String path) =>
    throw UnsupportedError('Storage non disponibile');
