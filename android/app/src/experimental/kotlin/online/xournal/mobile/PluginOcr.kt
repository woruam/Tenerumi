package online.xournal.mobile

import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/** Bundled Latin model: runs offline, no image is uploaded. */
object PluginOcr {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "online.xournal.mobile/ocr",
            StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") { result.notImplemented(); return@setMethodCallHandler }
                try {
                    val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
                    require(bytes.size <= 8 * 1024 * 1024) { "Image exceeds 8 MiB" }
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    require(bounds.outWidth > 0 && bounds.outHeight > 0 &&
                        bounds.outWidth.toLong() * bounds.outHeight <= 4_000_000) { "Image exceeds 4 megapixels or is invalid" }
                    val bitmap = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
                    val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                    recognizer.process(InputImage.fromBitmap(bitmap, 0))
                        .addOnSuccessListener { text ->
                            result.success(mapOf("text" to text.text, "blocks" to text.textBlocks.map { block ->
                                val box = block.boundingBox
                                mapOf("text" to block.text, "x" to box?.left, "y" to box?.top,
                                    "width" to box?.width(), "height" to box?.height(),
                                    "lines" to block.lines.map { it.text })
                            }))
                        }
                        .addOnFailureListener { error -> result.error("OCR_FAILED", error.message, null) }
                        .addOnCompleteListener { bitmap.recycle(); recognizer.close() }
                } catch (error: Exception) { result.error("OCR_FAILED", error.message, null) }
            }
    }
}
