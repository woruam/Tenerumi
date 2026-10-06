import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/globals.dart';

void main() {
  testWidgets('library fits a 380dp phone and preserves readable cards',
      (tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await (FontLoader('Open Sans')
            ..addFont(rootBundle.load('fonts/Open Sans/OpenSans-Regular.ttf')))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.kRecentFiles: jsonEncode(List.generate(
          8,
          (i) => {
                'name': 'Appunti di lezione ${i + 1}',
                'path': '',
                'tag': 'Appunti',
                'favorite': false,
              })),
    });
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: ChangeNotifierProvider(
            create: (_) => ThemeController(),
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                    brightness: Brightness.dark,
                    useMaterial3: true,
                    fontFamily: 'Open Sans'),
                home: OpenPage()))));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Appunti di lezione 1'), findsOneWidget);
    expect(find.text('Appunti di lezione 2'), findsOneWidget);
    final cardSize = tester.getSize(find.byType(Card).first);
    expect(cardSize.width, greaterThanOrEqualTo(150));
    expect(tester.takeException(), isNull);
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final output = File('docs/validation/open-page-phone.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    });
    await tester.drag(find.byType(GridView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Appunti di lezione 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
