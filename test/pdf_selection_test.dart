import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/pdf_selection.dart';
import 'package:xournalpp/src/selection_clipboard.dart';
import 'package:xournalpp/widgets/PointerListener.dart';

import 'document_export_test.dart' show solidPng;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'PDF lasso crop preserves document geometry and transparent corners',
    () async {
      final png = await solidPng(Colors.red);
      final crop = await cropPdfSelection(png, const Size(80, 80), const [
        Offset(10, 10),
        Offset(70, 10),
        Offset(10, 70),
      ]);
      expect(crop!.bounds(), const Rect.fromLTRB(10, 10, 70, 70));
      final codec = await ui.instantiateImageCodec(crop.data!);
      final image = (await codec.getNextFrame()).image;
      try {
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(pixels[3], 255);
        expect(pixels[pixels.length - 1], 0);
        final clipboard = SelectionClipboard()..copy([crop]);
        final pasted =
            clipboard.pasteAt(const Offset(100, 120)).single as XppImage;
        expect(pasted.bounds(), const Rect.fromLTRB(100, 120, 160, 180));
        expect(pasted.data, same(crop.data));
      } finally {
        image.dispose();
        codec.dispose();
      }
    },
  );

  Future<void> mount(
    WidgetTester tester,
    SelectionClipboard clipboard,
    Future<XppImage?> Function(List<Offset>) copy, {
    Object? identity,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PointerListener(
              key: const ValueKey('pdf-input'),
              readOnly: true,
              selectionIdentity: identity,
              clipboard: clipboard,
              onCopyPdfRegion: copy,
              toolData: const {ui.PointerDeviceKind.stylus: EditingTool.SELECT},
              getPageContent: () => [],
              child: const SizedBox(width: 300, height: 260),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> circle(WidgetTester tester) async {
    final origin = tester.getTopLeft(find.byKey(const ValueKey('pdf-input')));
    final gesture = await tester.startGesture(
      origin + const Offset(40, 70),
      kind: ui.PointerDeviceKind.stylus,
    );
    for (final point in const [
      Offset(125, 70),
      Offset(125, 125),
      Offset(40, 125),
      Offset(40, 70),
    ]) {
      await gesture.moveTo(origin + point);
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets(
    'empty locked PDF page offers background copy without ink mutation',
    (tester) async {
      final clipboard = SelectionClipboard();
      List<Offset>? polygon;
      await mount(tester, clipboard, (points) async {
        polygon = points;
        return XppImage(
          topLeft: const Offset(40, 70),
          bottomRight: const Offset(125, 125),
        );
      });
      await circle(tester);
      expect(find.byTooltip('Copia porzione PDF'), findsOneWidget);
      expect(find.byKey(const ValueKey('selection-delete')), findsNothing);
      expect(find.byKey(const ValueKey('selection-move')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('selection-copy-pdf')));
      await tester.pump();
      expect(polygon, hasLength(5));
      expect(clipboard.hasContent, isTrue);
    },
  );

  testWidgets(
    'changing page while PDF copy is pending leaves clipboard unchanged',
    (tester) async {
      final clipboard = SelectionClipboard();
      final pending = Completer<XppImage?>();
      await mount(tester, clipboard, (_) => pending.future, identity: 1);
      await circle(tester);
      await tester.tap(find.byKey(const ValueKey('selection-copy-pdf')));
      await tester.pump();
      await mount(tester, clipboard, (_) => pending.future, identity: 2);
      pending.complete(
        XppImage(topLeft: Offset.zero, bottomRight: const Offset(20, 20)),
      );
      await tester.pump();
      expect(clipboard.hasContent, isFalse);
      expect(find.byKey(const ValueKey('selection-copy-pdf')), findsNothing);
    },
  );
}
