import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';

XppStroke _line() => XppStrokePen(
  color: Colors.black,
  points: [
    XppStrokePoint(x: 0, y: 50, width: 5),
    XppStrokePoint(x: 200, y: 50, width: 5),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '4000 straight eraser events retain one exact sweep and shared samples',
    () {
      final original = _line();
      var stroke = original;
      Offset? previous;
      for (var i = 0; i < 4000; i++) {
        final position = Offset(i * .04, 50);
        final result = stroke.eraseAlong(
          coordinates: position,
          previousCoordinates: previous,
          radius: 2,
        );
        if (result.affected) stroke = result.newContent.single as XppStroke;
        previous = position;
      }
      expect(stroke.erasures, hasLength(1));
      expect(stroke.points, same(original.points));
      expect(stroke.erasures.single.start, const Offset(0, 50));
      expect(stroke.erasures.single.end.dx, closeTo(159.96, 1e-6));
      expect(stroke.containsVisibleInk(const Offset(100, 50)), isFalse);
      expect(stroke.containsVisibleInk(const Offset(180, 50)), isTrue);
      stroke.translate(const Offset(10, 0));
      expect(original.points!.first.offset, const Offset(0, 50));
      expect(stroke.points!.first.offset, const Offset(10, 50));
    },
  );

  test(
    'stationary eraser events do not accumulate masks or mark another change',
    () {
      final erased =
          _line()
                  .eraseWhere(coordinates: const Offset(50, 50), radius: 3)
                  .newContent
                  .single
              as XppStroke;
      for (var i = 0; i < 4000; i++) {
        expect(
          erased
              .eraseWhere(coordinates: const Offset(50, 50), radius: 3)
              .affected,
          isFalse,
        );
      }
      expect(erased.erasures, hasLength(1));
    },
  );

  test('reversals and turns retain their true circular sweeps', () {
    final first = StrokeErasure(const Offset(0, 0), const Offset(10, 0), 2);
    expect(
      first.canMerge(const StrokeErasure(Offset(10, 0), Offset(20, 0), 2)),
      isTrue,
    );
    expect(
      first.canMerge(const StrokeErasure(Offset(10, 0), Offset(5, 0), 2)),
      isFalse,
    );
    expect(
      first.canMerge(const StrokeErasure(Offset(10, 0), Offset(10, 10), 2)),
      isFalse,
    );
    expect(first.contains(const Offset(5, 1)), isTrue);
    expect(first.contains(const Offset(5, 3)), isFalse);
  });

  test('invalid eraser input never reaches native path rendering', () {
    final stroke = _line();
    expect(stroke.eraseWhere(coordinates: null).affected, isFalse);
    expect(
      stroke
          .eraseWhere(coordinates: const Offset(double.nan, 50), radius: 2)
          .affected,
      isFalse,
    );
    expect(
      stroke
          .eraseWhere(
            coordinates: const Offset(50, 50),
            radius: double.infinity,
          )
          .affected,
      isFalse,
    );
  });
}
