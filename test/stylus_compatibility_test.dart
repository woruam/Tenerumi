import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/stylus_profile.dart';
import 'package:xournalpp/widgets/PointerListener.dart';

Future<void> hardware(
  WidgetTester tester,
  String method, [
  Object? args,
]) async {
  final done = Completer<void>();
  tester.binding.channelBuffers.push(
    PointerListenerState.platform.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) => done.complete(),
  );
  await done.future;
  await tester.pump();
}

Future<void> line(
  WidgetTester tester,
  int pointer, {
  int buttons = 0,
  ui.PointerDeviceKind kind = ui.PointerDeviceKind.stylus,
}) async {
  await tester.sendEventToBinding(
    PointerDownEvent(
      pointer: pointer,
      kind: kind,
      position: const Offset(40, 40),
      buttons: buttons,
      pressure: .5,
    ),
  );
  await tester.sendEventToBinding(
    PointerMoveEvent(
      pointer: pointer,
      kind: kind,
      position: const Offset(100, 40),
      buttons: buttons,
      pressure: .5,
    ),
  );
  await tester.sendEventToBinding(
    PointerUpEvent(
      pointer: pointer,
      kind: kind,
      position: const Offset(100, 40),
    ),
  );
  await tester.pump();
}

Future<void> mount(
  WidgetTester tester, {
  StylusProfile profile = StylusProfile.automatic,
  required List<XppStroke> strokes,
  required List<Offset> erased,
  required List<EditingTool> actions,
  String primaryAction = 'eraser',
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: PointerListener(
        stylusProfile: profile,
        buttonDownAction: primaryAction,
        toolData: const {
          ui.PointerDeviceKind.stylus: EditingTool.STYLUS,
          ui.PointerDeviceKind.invertedStylus: EditingTool.ERASER,
          ui.PointerDeviceKind.mouse: EditingTool.STYLUS,
        },
        color: Colors.black,
        onToolChanged: actions.add,
        onNewContent: (content) => strokes.add(content! as XppStroke),
        filterEraser: ({coordinates, previousCoordinates, radius}) {
          if (coordinates != null) erased.add(coordinates);
        },
        child: const SizedBox(width: 300, height: 300),
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'existing installations keep automatic profile and both button mappings',
    () async {
      SharedPreferences.setMockInitialValues({
        'buttonDownAction': 'highlighter',
        'buttonUpAction': 'eraser',
      });
      final controller = CanvasController(autosaveEnabled: false)
        ..init(XppFile.empty());
      await Future<void>.delayed(Duration.zero);
      expect(controller.stylusProfile, StylusProfile.automatic);
      expect(controller.buttonDownAction, 'highlighter');
      expect(controller.buttonUpAction, 'eraser');
      controller.dispose();
      expect(
        StylusProfile.fromPreference('future-profile'),
        StylusProfile.automatic,
      );
    },
  );

  testWidgets('single button holds eraser across a stroke and returns to pen', (
    tester,
  ) async {
    final strokes = <XppStroke>[],
        erased = <Offset>[],
        actions = <EditingTool>[];
    await mount(
      tester,
      profile: StylusProfile.singleButton,
      strokes: strokes,
      erased: erased,
      actions: actions,
    );
    await tester.sendEventToBinding(
      const PointerHoverEvent(
        kind: ui.PointerDeviceKind.stylus,
        position: Offset(40, 40),
        buttons: kPrimaryStylusButton,
      ),
    );
    await line(tester, 101, buttons: kPrimaryStylusButton);
    expect(erased, isNotEmpty);
    expect(strokes, isEmpty);
    expect(actions, isEmpty); // Hover does not permanently change the toolbar.
    await tester.sendEventToBinding(
      const PointerHoverEvent(
        kind: ui.PointerDeviceKind.stylus,
        position: Offset(40, 40),
        buttons: 0,
      ),
    );
    await line(tester, 102);
    expect(strokes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'single button ignores missing second button and Redmi-only shortcuts',
    (tester) async {
      final strokes = <XppStroke>[],
          erased = <Offset>[],
          actions = <EditingTool>[];
      await mount(
        tester,
        profile: StylusProfile.singleButton,
        strokes: strokes,
        erased: erased,
        actions: actions,
      );
      await line(tester, 103, buttons: kSecondaryStylusButton);
      await hardware(tester, 'redmiPenPageDown');
      await hardware(tester, 'redmiPenPageUp');
      expect(actions, isEmpty);
      expect(erased, isEmpty);
      expect(strokes, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'single standard key works without motion button flags and release restores pen',
    (tester) async {
      final strokes = <XppStroke>[],
          erased = <Offset>[],
          actions = <EditingTool>[];
      await mount(
        tester,
        profile: StylusProfile.singleButton,
        strokes: strokes,
        erased: erased,
        actions: actions,
      );
      await tester.sendEventToBinding(
        const PointerHoverEvent(
          kind: ui.PointerDeviceKind.stylus,
          position: Offset(40, 40),
        ),
      );
      await hardware(tester, 'stylusButton', {'button': 1, 'pressed': true});
      await tester.sendEventToBinding(
        const PointerDownEvent(
          pointer: 104,
          kind: ui.PointerDeviceKind.stylus,
          position: Offset(40, 40),
        ),
      );
      await hardware(tester, 'stylusButton', {'button': 1, 'pressed': false});
      await tester.sendEventToBinding(
        const PointerMoveEvent(
          pointer: 104,
          kind: ui.PointerDeviceKind.stylus,
          position: Offset(100, 40),
        ),
      );
      await tester.sendEventToBinding(
        const PointerUpEvent(
          pointer: 104,
          kind: ui.PointerDeviceKind.stylus,
          position: Offset(100, 40),
        ),
      );
      expect(erased, isNotEmpty);
      expect(strokes, isEmpty); // Mid-stroke release does not change its tool.
      await line(tester, 105);
      expect(strokes, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final nativeFirst in [false, true]) {
    testWidgets(
      'motion and standard key produce one toggle, native first: $nativeFirst',
      (tester) async {
        final strokes = <XppStroke>[],
            erased = <Offset>[],
            actions = <EditingTool>[];
        await mount(tester, strokes: strokes, erased: erased, actions: actions);
        await tester.sendEventToBinding(
          const PointerHoverEvent(
            kind: ui.PointerDeviceKind.stylus,
            position: Offset(40, 40),
          ),
        );
        Future<void> hover(int buttons) => tester.sendEventToBinding(
          PointerHoverEvent(
            kind: ui.PointerDeviceKind.stylus,
            position: const Offset(40, 40),
            buttons: buttons,
          ),
        );
        if (nativeFirst)
          await hardware(tester, 'stylusButton', {
            'button': 1,
            'pressed': true,
          });
        await hover(kPrimaryStylusButton);
        if (!nativeFirst)
          await hardware(tester, 'stylusButton', {
            'button': 1,
            'pressed': true,
          });
        expect(actions, [EditingTool.ERASER]);
        await hardware(tester, 'stylusButton', {'button': 1, 'pressed': false});
        await hover(0);
        await hardware(tester, 'stylusButton', {'button': 1, 'pressed': true});
        await hover(kPrimaryStylusButton);
        expect(actions, [EditingTool.ERASER, EditingTool.STYLUS]);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'focus reset releases standard key and mouse right button does not erase',
    (tester) async {
      final strokes = <XppStroke>[],
          erased = <Offset>[],
          actions = <EditingTool>[];
      await mount(
        tester,
        profile: StylusProfile.singleButton,
        strokes: strokes,
        erased: erased,
        actions: actions,
      );
      await tester.sendEventToBinding(
        const PointerHoverEvent(
          kind: ui.PointerDeviceKind.stylus,
          position: Offset(40, 40),
        ),
      );
      await hardware(tester, 'stylusButton', {'button': 1, 'pressed': true});
      await hardware(tester, 'stylusButtonsReset');
      await line(tester, 106);
      await line(
        tester,
        107,
        kind: ui.PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      expect(erased, isEmpty);
      expect(strokes, hasLength(2));
      await line(tester, 108, kind: ui.PointerDeviceKind.invertedStylus);
      expect(erased, isNotEmpty);
      expect(strokes, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('single button can be assigned to highlighter', (tester) async {
    final strokes = <XppStroke>[],
        erased = <Offset>[],
        actions = <EditingTool>[];
    await mount(
      tester,
      profile: StylusProfile.singleButton,
      primaryAction: 'highlighter',
      strokes: strokes,
      erased: erased,
      actions: actions,
    );
    await line(tester, 109, buttons: kPrimaryStylusButton);
    expect(strokes.single.tool, XppStrokeTool.HIGHLIGHTER);
    await line(tester, 110);
    expect(strokes.last.tool, XppStrokeTool.PEN);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'phone settings save single-button layout without exposing a second action',
    (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = ThemeController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: const MaterialApp(home: OpenPage(restoreWorkspace: false)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      final profile = find.byKey(const ValueKey('stylus-profile-setting'));
      await tester.ensureVisible(profile);
      await tester.pumpAndSettle();
      await tester.tap(profile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Un tasto (S Pen e simili)').last);
      await tester.pumpAndSettle();
      expect(find.text('Tasto 2 (secondario / superiore)'), findsNothing);
      expect(find.text('Tasto laterale'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StylusProfile.preferenceKey), 'singleButton');
      final controller = CanvasController(autosaveEnabled: false)
        ..init(XppFile.empty());
      await tester.pump();
      expect(controller.stylusProfile, StylusProfile.singleButton);
      controller.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
    },
  );
}
