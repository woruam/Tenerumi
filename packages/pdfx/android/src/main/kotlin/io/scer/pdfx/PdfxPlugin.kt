package io.scer.pdfx

import android.annotation.TargetApi
import android.os.Build
import androidx.annotation.NonNull
import dev.flutter.pigeon.Pigeon
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.scer.pdfx.resources.DocumentRepository
import io.scer.pdfx.resources.PageRepository

/**
 * PdfxPlugin
 */
@TargetApi(Build.VERSION_CODES.LOLLIPOP)
class PdfxPlugin : FlutterPlugin {
    private val documents = DocumentRepository()
    private val pages = PageRepository()
    private var messages: Messages? = null
    private var metadata: MethodChannel? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val handler = Messages(flutterPluginBinding, documents, pages)
        messages = handler
        metadata = MethodChannel(flutterPluginBinding.binaryMessenger, "online.xournal.mobile/pdf-metadata").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "pageSizes") handler.pageSizes(call.argument<String>("documentId"), result)
                else result.notImplemented()
            }
        }
        Pigeon.PdfxApi.setup(
            flutterPluginBinding.binaryMessenger,
            handler
        )
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Pigeon.PdfxApi.setup(binding.binaryMessenger, null)
        metadata?.setMethodCallHandler(null)
        metadata = null
        messages?.dispose()
        messages = null
    }
}

