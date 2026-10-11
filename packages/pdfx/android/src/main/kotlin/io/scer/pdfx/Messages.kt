package io.scer.pdfx

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import android.util.SparseArray
import android.view.Surface
import androidx.annotation.RequiresApi
import dev.flutter.pigeon.Pigeon
import io.flutter.BuildConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import io.flutter.view.TextureRegistry.SurfaceProducer.Callback
import io.scer.pdfx.resources.DocumentRepository
import io.scer.pdfx.resources.PageRepository
import io.scer.pdfx.resources.RepositoryItemNotFoundException
import io.scer.pdfx.utils.CreateRendererException
import io.scer.pdfx.utils.randomFilename
import io.scer.pdfx.utils.toFile
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.lang.RuntimeException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
class Messages(private val binding : FlutterPlugin.FlutterPluginBinding,
               private val documents: DocumentRepository,
               private val pages: PageRepository) : Pigeon.PdfxApi {

    private val surfaceProducers: SparseArray<TextureRegistry.SurfaceProducer> = SparseArray()
    private val documentStatesPerSurface: SparseArray<Pigeon.UpdateTextureMessage> = SparseArray()
    private val textureJobs = mutableMapOf<Int, Int>()

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "osi-pdf-render").apply { isDaemon = true }
    }
    @Volatile private var disposed = false

    private fun openDocument(result: Pigeon.Result<Pigeon.OpenReply>,
                             open: () -> Pair<ParcelFileDescriptor, PdfRenderer>) {
        if (disposed) {
            result.error(PdfRendererException("pdf_renderer", "Renderer closed", null))
            return
        }
        worker.execute {
            try {
                val pair = open()
                main.post {
                    if (disposed) {
                        try { pair.second.close() } finally { pair.first.close() }
                        result.error(PdfRendererException("pdf_renderer", "Renderer closed", null))
                    } else {
                        val document = documents.register(pair)
                        result.success(Pigeon.OpenReply().apply {
                            id = document.id
                            pagesCount = document.pagesCount.toLong()
                        })
                    }
                }
            } catch (error: Exception) {
                main.post { result.error(PdfRendererException("pdf_renderer", "Can't open PDF: ${error.message}", null)) }
            } catch (error: OutOfMemoryError) {
                main.post { result.error(PdfRendererException("pdf_renderer", "PDF exceeds available memory", null)) }
            }
        }
    }

    override fun openDocumentData(message: Pigeon.OpenDataMessage, result: Pigeon.Result<Pigeon.OpenReply>) =
        openDocument(result) { openDataDocument(message.data!!) }

    override fun openDocumentFile(message: Pigeon.OpenPathMessage, result: Pigeon.Result<Pigeon.OpenReply>) =
        openDocument(result) { openFileDocument(File(message.path!!)) }

    override fun openDocumentAsset(message: Pigeon.OpenPathMessage, result: Pigeon.Result<Pigeon.OpenReply>) =
        openDocument(result) { openAssetDocument(message.path!!) }

    fun dispose() {
        if (disposed) return
        disposed = true
        for (index in 0 until surfaceProducers.size()) {
            surfaceProducers.valueAt(index).setCallback(null)
            surfaceProducers.valueAt(index).release()
        }
        surfaceProducers.clear()
        documentStatesPerSurface.clear()
        textureJobs.clear()
        val oldPages = pages.takeAll()
        val oldDocuments = documents.takeAll()
        worker.execute {
            for (page in oldPages) { try { page.close() } catch (_: Exception) {} }
            for (document in oldDocuments) { try { document.close() } catch (_: Exception) {} }
        }
        worker.shutdown()
    }

    override fun closeDocument(message: Pigeon.IdMessage) {
        try {
            val id = message.id
            val document = documents.take(id!!)
            // Texture work already queued for this document finishes first.
            worker.execute { try { document.close() } catch (error: Exception) {
                Log.w("pdf_renderer", "Document close failed", error)
            } }
        } catch (e: NullPointerException) {
            throw PdfRendererException("pdf_renderer", "Need call arguments: id!", null)
        } catch (e: RepositoryItemNotFoundException) {
            throw PdfRendererException("pdf_renderer", "Document not exist in documents repository", null)
        } catch (e: Exception) {
            throw PdfRendererException("pdf_renderer", "Unknown error", null)
        }
    }

    // One bounded metadata reply instead of two platform round trips per page.
    fun pageSizes(documentId: String?, result: MethodChannel.Result) {
        val document = try { documents.get(requireNotNull(documentId)) } catch (error: Exception) {
            result.error("pdf_metadata", "Document unavailable", null)
            return
        }
        if (disposed) { result.error("pdf_metadata", "Renderer closed", null); return }
        worker.execute {
            try {
                val count = document.pagesCount
                require(count in 1..10000) { "Too many PDF pages" }
                val sizes = ArrayList<Double>(count * 2)
                for (number in 1..count) {
                    if (disposed) throw IllegalStateException("Renderer closed")
                    document.openPage(number).use { page ->
                        require(page.width in 1..20000 && page.height in 1..20000) { "Invalid PDF dimensions" }
                        sizes.add(page.width.toDouble())
                        sizes.add(page.height.toDouble())
                    }
                }
                main.post { result.success(sizes) }
            } catch (error: Exception) {
                main.post { result.error("pdf_metadata", "Cannot inspect PDF: ${error.message}", null) }
            } catch (error: OutOfMemoryError) {
                main.post { result.error("pdf_metadata", "PDF exceeds available memory", null) }
            }
        }
    }

    override fun getPage(message: Pigeon.GetPageMessage, result: Pigeon.Result<Pigeon.GetPageReply>) {
        val document = try { documents.get(message.documentId!!) } catch (error: Exception) {
            result.error(PdfRendererException("pdf_renderer", "Document unavailable", null))
            return
        }
        worker.execute {
            var page: PdfRenderer.Page? = null
            try {
                val opened = document.openPage(message.pageNumber!!.toInt())
                page = opened
                val reply = Pigeon.GetPageReply().apply {
                    width = opened.width.toDouble()
                    height = opened.height.toDouble()
                }
                if (message.autoCloseAndroid == true) {
                    opened.close()
                    page = null
                }
                val retained = page
                main.post {
                    if (disposed) {
                        try { retained?.close() } catch (_: Exception) {}
                        result.error(PdfRendererException("pdf_renderer", "Renderer closed", null))
                    } else {
                        if (retained != null) reply.id = pages.register(document.id, retained).id
                        result.success(reply)
                    }
                }
                page = null // Ownership transferred to the main-thread repository.
            } catch (error: Exception) {
                main.post { result.error(PdfRendererException("pdf_renderer", "Can't open PDF page: ${error.message}", null)) }
            } catch (error: OutOfMemoryError) {
                main.post { result.error(PdfRendererException("pdf_renderer", "PDF exceeds available memory", null)) }
            } finally { page?.close() }
        }
    }

    override fun renderPage(
        message: Pigeon.RenderPageMessage,
        result: Pigeon.Result<Pigeon.RenderPageReply>
    ) {
        val resultResponse = Pigeon.RenderPageReply()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val pageId = message.pageId ?: run {
                    result.error(PdfRendererException("pdf_renderer", "Page ID is null", null))
                    return@launch
                }

                val width = message.width?.toInt() ?: run {
                    result.error(PdfRendererException("pdf_renderer", "Width is null", null))
                    return@launch
                }

                val height = message.height?.toInt() ?: run {
                    result.error(PdfRendererException("pdf_renderer", "Height is null", null))
                    return@launch
                }

                val format = message.format?.toInt() ?: 1
                val backgroundColor = message.backgroundColor
                val color = backgroundColor?.let { Color.parseColor(it) } ?: Color.TRANSPARENT

                val crop = message.crop ?: false
                val cropX = if (crop) message.cropX?.toInt() ?: 0 else 0
                val cropY = if (crop) message.cropY?.toInt() ?: 0 else 0
                val cropH = if (crop) message.cropHeight?.toInt() ?: 0 else 0
                val cropW = if (crop) message.width?.toInt() ?: 0 else 0

                val quality = message.quality?.toInt() ?: 100
                val forPrint = message.forPrint ?: false

                val page = pages.get(pageId)

                val tempOutFileExtension = when (format) {
                    0 -> "jpg"
                    1 -> "png"
                    2 -> "webp"
                    else -> "jpg"
                }

                val tempOutFolder = File(binding.applicationContext.cacheDir, "pdf_renderer_cache").apply {
                    mkdirs()
                }

                val tempOutFile = File(tempOutFolder, "$randomFilename.$tempOutFileExtension")

                //  background thread render
                val pageImage = page.render(
                    file = tempOutFile,
                    width = width,
                    height = height,
                    background = color,
                    format = format,
                    crop = crop,
                    cropX = cropX,
                    cropY = cropY,
                    cropW = cropW,
                    cropH = cropH,
                    quality = quality,
                    forPrint = forPrint,
                )

                withContext(Dispatchers.Main) {
                    resultResponse.path = pageImage.path
                    resultResponse.width = pageImage.width.toLong()
                    resultResponse.height = pageImage.height.toLong()
                    result.success(resultResponse)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error(PdfRendererException("pdf_renderer", "Unexpected error", e))
                }
            } catch (e: OutOfMemoryError) {
                withContext(Dispatchers.Main) {
                    result.error(PdfRendererException("pdf_renderer", "PDF exceeds available memory", null))
                }
            }
        }
    }

    override fun closePage(message: Pigeon.IdMessage) {
        try {
            val id = message.id!!
            pages.close(id)
        } catch (e: NullPointerException) {
            throw PdfRendererException("pdf_renderer", "Need call arguments: id!", null)
        } catch (e: RepositoryItemNotFoundException) {
            throw PdfRendererException("pdf_renderer", "Page not exist in pages repository", null)
        } catch (e: Exception) {
            throw PdfRendererException("pdf_renderer", "Unknown error", null)
        }
    }

    override fun registerTexture(): Pigeon.RegisterTextureReply {
        val surfaceProducer = binding.textureRegistry.createSurfaceProducer()
        val id = surfaceProducer.id().toInt()
        surfaceProducers.put(id, surfaceProducer)

        surfaceProducer.setCallback(object : Callback {
            override fun onSurfaceAvailable() {
                documentStatesPerSurface[id]?.let { documentUpdate ->
                    onDocumentOrSurfaceChanged(
                        surfaceProducer.surface,
                        documentUpdate,
                        result = null,
                    )
                }
            }

            override fun onSurfaceCleanup() {
                // ignore - Surface is used once to draw bitmap
            }
        })

        val result = Pigeon.RegisterTextureReply()
        result.id = id.toLong()
        return result
    }

    override fun updateTexture(
        message: Pigeon.UpdateTextureMessage,
        result: Pigeon.Result<Void>
    ) {
        val texId = message.textureId!!.toInt()
        val surfaceProducer = surfaceProducers[texId]
        val texWidth = message.textureWidth!!.toInt()
        val texHeight = message.textureHeight!!.toInt()
        if ((texWidth != 0 || texHeight != 0) &&
            (texWidth !in 1..4096 || texHeight !in 1..4096 || texWidth.toLong() * texHeight > 4000000)) {
            result.error(PdfRendererException("pdf_renderer", "Texture exceeds pixel budget", null))
            return
        }
        if (texWidth != 0 && texHeight != 0) {
            surfaceProducer.setSize(texWidth, texHeight)
        }
        documentStatesPerSurface.put(texId, message)
        onDocumentOrSurfaceChanged(surfaceProducer.surface, message, result)
    }

    private fun onDocumentOrSurfaceChanged(
        surface: Surface,
        message: Pigeon.UpdateTextureMessage,
        result: Pigeon.Result<Void>?,
    ) {
        if (disposed) return
        val textureId = message.textureId!!.toInt()
        // Surface creation/resizing may re-enter while its requested render is
        // already running. Do not rasterize the same complex page twice.
        if (result == null && (textureJobs[textureId] ?: 0) > 0) return
        // Repository access and SurfaceProducer changes remain on the platform
        // thread; PDF parsing, bitmap allocation and rasterization do not.
        val document = try { documents.get(message.documentId!!) } catch (error: Exception) {
            result?.error(PdfRendererException("pdf_renderer", "Document already closed", null))
            return
        }
        textureJobs[textureId] = (textureJobs[textureId] ?: 0) + 1
        worker.execute {
            var bitmap: Bitmap? = null
            try {
                val width = message.width!!.toInt()
                val height = message.height!!.toInt()
                require(width in 1..4096 && height in 1..4096 && width.toLong() * height <= 4000000) {
                    "Texture exceeds pixel budget"
                }
                if (disposed || !surface.isValid) throw IllegalStateException("Surface released")
                document.openPage(message.pageNumber!!.toInt()).use { page ->
                    val fullWidth = message.fullWidth ?: page.width.toDouble()
                    val fullHeight = message.fullHeight ?: page.height.toDouble()
                    require(fullWidth.isFinite() && fullHeight.isFinite() && fullWidth > 0 && fullHeight > 0)
                    val matrix = Matrix().apply {
                        setValues(floatArrayOf((fullWidth / page.width).toFloat(), 0f, -message.sourceX!!.toFloat(),
                            0f, (fullHeight / page.height).toFloat(), -message.sourceY!!.toFloat(), 0f, 0f, 1f))
                    }
                    val rendered = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    bitmap = rendered
                    message.backgroundColor?.let { rendered.eraseColor(Color.parseColor(it)) }
                    page.render(rendered, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    val x = message.destinationX!!.toInt()
                    val y = message.destinationY!!.toInt()
                    val canvas = surface.lockCanvas(Rect(x, y, x + width, y + height))
                    try { canvas.drawBitmap(rendered, x.toFloat(), y.toFloat(), null) }
                    finally { surface.unlockCanvasAndPost(canvas) }
                }
                main.post { result?.success(null) }
            } catch (error: Exception) {
                main.post { result?.error(PdfRendererException("pdf_renderer", "Texture render failed: ${error.message}", null)) }
            } catch (error: OutOfMemoryError) {
                main.post { result?.error(PdfRendererException("pdf_renderer", "PDF exceeds available memory", null)) }
            } finally {
                bitmap?.recycle()
                main.post {
                    val remaining = (textureJobs[textureId] ?: 1) - 1
                    if (remaining <= 0) textureJobs.remove(textureId)
                    else textureJobs[textureId] = remaining
                }
            }
        }
    }

    override fun resizeTexture(
        message: Pigeon.ResizeTextureMessage,
        result: Pigeon.Result<Void>
    ) {
        val texId = message.textureId!!.toInt()
        val width = message.width!!.toInt()
        val height = message.height!!.toInt()
        val tex = surfaceProducers[texId]
        if (width !in 1..4096 || height !in 1..4096 || width.toLong() * height > 4000000) {
            result.error(PdfRendererException("pdf_renderer", "Texture exceeds pixel budget", null))
            return
        }
        tex?.setSize(width, height)
        result.success(null)
    }

    override fun unregisterTexture(message: Pigeon.UnregisterTextureMessage) {
        val id = message.id!!.toInt()
        val surfaceProducer = surfaceProducers[id]
        surfaceProducer?.setCallback(null)
        surfaceProducer?.release()
        surfaceProducers.remove(id)
        documentStatesPerSurface.remove(id)
    }

    private fun openDataDocument(data: ByteArray): Pair<ParcelFileDescriptor, PdfRenderer> {
        val temporary = File.createTempFile("pdfx-", ".pdf", binding.applicationContext.cacheDir)
        try {
            temporary.writeBytes(data)
            return openFileDocument(temporary)
        } finally {
            // Android retains the open descriptor after unlinking this private copy.
            temporary.delete()
        }
    }

    private fun openAssetDocument(assetPath: String): Pair<ParcelFileDescriptor, PdfRenderer> {
        val temporary = File.createTempFile("pdfx-", ".pdf", binding.applicationContext.cacheDir)
        try {
            val path = binding.flutterAssets.getAssetFilePathByName(assetPath)
            binding.applicationContext.assets.open(path).use { it.toFile(temporary) }
            return openFileDocument(temporary)
        } finally { temporary.delete() }
    }

    private fun openFileDocument(file: File): Pair<ParcelFileDescriptor, PdfRenderer> {
        Log.d("pdf_renderer", "OpenFileDocument. File: " + file.path)
        val fileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        return if (fileDescriptor != null) {
            try {
                Pair(fileDescriptor, PdfRenderer(fileDescriptor))
            } catch (error: Throwable) {
                fileDescriptor.close()
                throw error
            }
        } else throw CreateRendererException()
    }
}

class PdfRendererException internal constructor(code: String?, message: String?, details: Any?) :
    RuntimeException(message) {
    private val code: String?
    private var details: Any? = null

    companion object {
        private const val TAG = "PdfRendererException#"
    }

    init {
        if (BuildConfig.DEBUG && code == null) {
            io.flutter.Log.e(TAG, "Parameter code must not be null.")
        }
        this.code = code
        if (details != null) {
            this.details = details
        }
    }
}

fun <R> Surface.use(block: (Surface) -> R): R {
    try {
        return block(this)
    }
    finally {
        this.release()
    }
}
