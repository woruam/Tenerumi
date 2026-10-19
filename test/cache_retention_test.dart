import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/src/decoded_image_cache.dart';

Future<ui.Image> decoded(
  WidgetTester tester,
  DecodedImageCache cache,
  Uint8List bytes,
) async {
  ui.Image? image;
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      image = cache.lookup(bytes);
      if (image != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  expect(image, isNotNull);
  return image!;
}

void main() {
  testWidgets(
    'retention tracks byte identity and mutations without losing shared images',
    (tester) async {
      final cache = DecodedImageCache(maxEntries: 2);
      addTearDown(cache.dispose);
      final first = Uint8List.fromList(kTransparentImage);
      final replacement = Uint8List.fromList(kTransparentImage);
      final sources = [first];
      final owner = Object(), other = Object();
      cache.retain(owner, sources);
      final firstImage = await decoded(tester, cache, first);
      cache.retain(other, [first]);
      cache.retain(owner, sources);
      expect(cache.lookup(first), same(firstImage));

      sources[0] = replacement;
      cache.retain(owner, sources);
      final replacementImage = await decoded(tester, cache, replacement);
      expect(cache.entryCount, 2);
      cache.release(other);
      expect(firstImage.debugDisposed, isTrue);
      expect(replacementImage.debugDisposed, isFalse);
      expect(cache.entryCount, 1);
      cache.retain(owner, sources);
      expect(cache.lookup(replacement), same(replacementImage));

      cache.clear();
      expect(replacementImage.debugDisposed, isTrue);
      cache.retain(owner, sources);
      final reloaded = await decoded(tester, cache, replacement);
      expect(reloaded.debugDisposed, isFalse);
      cache.release(owner);
      expect(reloaded.debugDisposed, isTrue);
      expect(cache.byteCount, 0);
      await tester.pump();
    },
  );

  testWidgets('pending decode survives changed owners with bounded resources', (
    tester,
  ) async {
    final cache = DecodedImageCache(maxBytes: 8, maxEntries: 2);
    addTearDown(cache.dispose);
    final first = Uint8List.fromList(kTransparentImage);
    final second = Uint8List.fromList(kTransparentImage);
    final owner = Object();
    cache.retain(owner, [first]);
    cache.lookup(first);
    cache.retain(owner, [first, second]);
    final firstImage = await decoded(tester, cache, first);
    final secondImage = await decoded(tester, cache, second);
    cache.retain(owner, [first, second]);
    await tester.pump();
    expect(cache.lookup(first), same(firstImage));
    expect(cache.lookup(second), same(secondImage));
    expect(cache.byteCount, lessThanOrEqualTo(8));
    cache.release(owner);
    expect(firstImage.debugDisposed, isTrue);
    expect(secondImage.debugDisposed, isTrue);
    expect(cache.byteCount, 0);
  });

  testWidgets('retention consumes each source iterable only once', (
    tester,
  ) async {
    final cache = DecodedImageCache();
    addTearDown(cache.dispose);
    final bytes = Uint8List.fromList(kTransparentImage);
    final owner = Object();
    Iterable<Uint8List> once() {
      var iterations = 0;
      return Iterable.generate(1, (_) {
        if (++iterations > 1) throw StateError('Iterable consumed twice');
        return bytes;
      });
    }

    cache.retain(owner, once());
    final image = await decoded(tester, cache, bytes);
    cache.retain(owner, once());
    expect(cache.lookup(bytes), same(image));
    cache.release(owner);
    expect(image.debugDisposed, isTrue);
  });
}
