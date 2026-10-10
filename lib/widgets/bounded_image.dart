import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xournalpp/src/decoded_image_cache.dart';

/// Previews and backgrounds use the same bounded native-image budget as ink media.
class BoundedImage extends StatefulWidget {
  const BoundedImage(
    this.bytes, {
    super.key,
    this.fit = BoxFit.contain,
    this.height,
    this.width,
    this.fallback,
  });
  final Uint8List bytes;
  final BoxFit fit;
  final double? width, height;
  final Widget? fallback;
  @override
  State<BoundedImage> createState() => _BoundedImageState();
}

class _BoundedImageState extends State<BoundedImage> {
  @override
  void initState() {
    super.initState();
    DecodedImageCache.shared.retain(this, [widget.bytes]);
    DecodedImageCache.shared.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(BoundedImage old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes))
      DecodedImageCache.shared.retain(this, [widget.bytes]);
  }

  @override
  void dispose() {
    DecodedImageCache.shared.removeListener(_changed);
    DecodedImageCache.shared.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = DecodedImageCache.shared.lookup(widget.bytes);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: image == null
          ? (widget.fallback ?? const Icon(Icons.image_outlined))
          : RawImage(image: image, fit: widget.fit),
    );
  }
}
