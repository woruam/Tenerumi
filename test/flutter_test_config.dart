import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:xournalpp/src/critical_data.dart';
import 'package:xournalpp/src/autosave_store.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previous;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('osipp-test-');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(root.path);
    CriticalData.inMemoryForTests = true;
    CriticalData.resetTestQueue();
    AutosaveStore.resetTestQueue();
    CriticalData.warnings.clear();
  });
  tearDown(() async {
    PathProviderPlatform.instance = previous;
    await root.delete(recursive: true);
  });
  await testMain();
}
