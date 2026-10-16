import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/external_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ExternalDocuments.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('online.xournal.mobile/documents'),
          null,
        );
  });

  test(
    'Android drains pending PDF activations and enables warm intents',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ExternalDocuments.channel, (call) async {
            methods.add(call.method);
            return [
              {'uri': 'content://provider/document/42', 'name': 'Lezione.pdf'},
            ];
          });
      expect((await ExternalDocuments.pending()).single['name'], 'Lezione.pdf');
      expect(
        (await ExternalDocuments.pending(listen: true)).single['uri'],
        'content://provider/document/42',
      );
      expect(methods, ['getInitialDocuments', 'listen']);
    },
  );

  test(
    'Denied external URI propagates without creating an empty note',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('online.xournal.mobile/documents'),
            (_) async => throw PlatformException(code: 'read_denied'),
          );
      await expectLater(
        ExternalDocuments.importPdf({
          'uri': 'content://provider/document/42',
          'name': 'Lezione.pdf',
        }),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
