package online.xournal.mobile

import android.Manifest
import android.content.pm.PackageManager
import android.content.Context
import android.media.AudioManager
import android.media.AudioFocusRequest
import android.os.Build
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import org.json.JSONObject
import org.json.JSONArray
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/** Disk-backed AAC capture; bounded cleanup runs separately from the next segment. */
class NoteAudio(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "online.xournal.mobile/audio")
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread({ android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND); task.run() }, "osi-audio-files")
    }
    private val cleanupWorker = Executors.newSingleThreadExecutor { task ->
        Thread({ android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND); task.run() }, "osi-audio-cleanup")
    }
    private var recorder: MediaRecorder? = null
    private var player: MediaPlayer? = null
    private var playerPrepared = false
    private var playResult: MethodChannel.Result? = null
    private val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change <= AudioManager.AUDIOFOCUS_LOSS && playerPrepared) player?.pause()
    }
    private fun completePlay(result: MethodChannel.Result, error: String? = null) {
        if (playResult !== result) return
        playResult = null
        if (error == null) result.success(null) else result.error("audio", error, null)
    }
    @Suppress("DEPRECATION")
    private fun focus(): Boolean {
        return if (Build.VERSION.SDK_INT >= 26) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setOnAudioFocusChangeListener(focusListener).build()
            focusRequest = request
            audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }
    private val staging = File(activity.filesDir, "osi-audio-staging").apply { mkdirs() }
    private val segmentHandler = Handler(Looper.getMainLooper())
    private var noteId = ""
    private var recordingId = ""
    private var reduceNoise = true
    private var reduceTaps = true
    private var startedUptime = 0L
    private val tapTimes = mutableListOf<Int>()
    fun stylusContact(eventUptime: Long) {
        if (recorder == null || !reduceTaps || tapTimes.size >= 256) return
        val elapsed = eventUptime - startedUptime
        if (elapsed >= 0 && elapsed <= 120 * 60 * 1000 &&
            (tapTimes.lastOrNull()?.let { elapsed - it >= 10 } ?: true)) tapTimes.add(elapsed.toInt())
    }
    private fun safeId(value: String) = value.matches(Regex("^[a-zA-Z0-9_-]{1,100}$"))
    private fun noteDirectory(id: String): File {
        require(safeId(id)) { "Invalid note identity" }
        return File(staging, id).apply { mkdirs() }
    }
    private fun manifest(file: File) = File(file.parentFile, file.nameWithoutExtension + ".json")
    private fun writeManifest(file: File, state: String, duration: Int = 0) {
        val data = JSONObject().put("schema", 1).put("noteId", file.parentFile!!.name)
            .put("id", file.nameWithoutExtension).put("state", state).put("duration", duration)
            .put("reduceNoise", reduceNoise).put("reduceTaps", reduceTaps)
            .put("tapTimes", JSONArray(tapTimes))
        val target = manifest(file)
        val temporary = File(target.path + ".tmp")
        FileOutputStream(temporary).use { it.write(data.toString().toByteArray(Charsets.UTF_8)); it.fd.sync() }
        check(temporary.renameTo(target)) { "Audio journal unavailable" }
    }
    private val rotate = Runnable {
        if (recorder != null) { finishRecording(); channel.invokeMethod("segmentReady", null) }
    }
    private var recordingFile: File? = null
    private var playbackFile: File? = null
    private var started = 0L
    private var duration = 0
    private var pending: MethodChannel.Result? = null
    private var grantedPending: MethodChannel.Result? = null
    private var closed = false
    private var foreground = true
    private val limit = 48 * 1024 * 1024L

    init {
        // Only playback cache is disposable. Unacknowledged microphone segments
        // are kept in filesDir, including evidence of unfinalized interruption.
        activity.cacheDir.listFiles()?.filter { it.name.startsWith("osi-audio-play-") || it.name.startsWith("osi-audio-clean-") }?.forEach { it.delete() }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        if (pending != null || recorder != null || recordingFile != null) {
                            result.error("busy", "Registrazione già attiva", null)
                        } else {
                            noteId = requireNotNull(call.argument<String>("noteId"))
                            recordingId = requireNotNull(call.argument<String>("id"))
                            reduceNoise = call.argument<Boolean>("reduceNoise") ?: true
                            reduceTaps = call.argument<Boolean>("reduceStylusTaps") ?: true
                            require(safeId(noteId) && safeId(recordingId))
                            if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            pending = result
                            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 7401)
                            } else start(result)
                        }
                    }
                    "stop" -> {
                        finishRecording()
                        val file = recordingFile
                        val length = duration
                        recordingFile = null
                        worker.execute {
                            try {
                                val bytes = if (file != null && file.length() in 1..limit && manifest(file).length() <= 4096 && JSONObject(manifest(file).readText()).optString("state") == "ready") file.readBytes() else null
                                val cleanup = file != null && bytes != null && cleanupRequested(JSONObject(manifest(file).readText()))
                                activity.runOnUiThread { result.success(if (bytes == null) null else mapOf("bytes" to bytes, "duration" to length, "cleanup" to cleanup)) }
                            } catch (e: Exception) {
                                activity.runOnUiThread { result.error("audio", "Impossibile leggere la registrazione", null) }
                            } // No ACK yet: the durable segment remains on disk.
                        }
                    }
                    "orphans" -> {
                        val notes = staging.listFiles()?.filter { it.isDirectory && safeId(it.name) }?.mapNotNull { dir ->
                            val count = dir.listFiles()?.count { it.extension == "json" } ?: 0
                            if (count == 0) null else mapOf("noteId" to dir.name, "count" to count)
                        } ?: emptyList()
                        result.success(notes)
                    }
                    "cleanSegment" -> {
                        val dir = noteDirectory(requireNotNull(call.argument<String>("noteId")))
                        val id = requireNotNull(call.argument<String>("id")); require(safeId(id))
                        cleanupWorker.execute {
                            try {
                                val file = File(dir, "$id.m4a"); val meta = manifest(file)
                                require(meta.length() in 1L..4096L && file.length() in 1..limit)
                                val data = JSONObject(meta.readText()); require(data.optString("state") == "ready")
                                val values = data.optJSONArray("tapTimes")
                                val taps = IntArray(minOf(values?.length() ?: 0, 256)) { values!!.optInt(it, -1) }
                                val cleaned = AudioSegmentCleaner.clean(file, activity.cacheDir,
                                    data.optBoolean("reduceNoise", false), data.optBoolean("reduceTaps", false), taps)
                                activity.runOnUiThread { result.success(mapOf("bytes" to cleaned.bytes, "applied" to cleaned.applied)) }
                            } catch (e: Exception) {
                                activity.runOnUiThread { result.error("audio", "Pulizia non disponibile: originale conservato", null) }
                            }
                        }
                    }
                    "recover" -> {
                        val dir = noteDirectory(requireNotNull(call.argument<String>("noteId")))
                        worker.execute {
                            try {
                                var total = 0L
                                val recovered = dir.listFiles()?.filter { it.extension == "json" && it.length() <= 4096 }?.take(10000)?.mapNotNull { meta ->
                                    try {
                                        val value = JSONObject(meta.readText())
                                        val id = value.getString("id")
                                        if (!safeId(id)) return@mapNotNull null
                                        val state = value.getString("state")
                                        val file = File(dir, "$id.m4a")
                                        if (state == "ready" && file.length() in 1..limit && total + file.length() <= 128 * 1024 * 1024L) {
                                            total += file.length()
                                            mapOf("id" to id, "state" to state, "duration" to value.getInt("duration"), "length" to file.length())
                                        } else mapOf("id" to id, "state" to "partial")
                                    } catch (_: Exception) { null }
                                } ?: emptyList()
                                activity.runOnUiThread { result.success(recovered) }
                            } catch (e: Exception) { activity.runOnUiThread { result.error("audio", "Recupero audio non disponibile", null) } }
                        }
                    }
                    "readSegment" -> {
                        val dir=noteDirectory(requireNotNull(call.argument<String>("noteId")))
                        val id=requireNotNull(call.argument<String>("id"));require(safeId(id))
                        worker.execute {
                            try {
                                val file=File(dir,"$id.m4a");val meta=manifest(file)
                                require(meta.length() in 1L..4096L && file.length() in 1..limit)
                                val value=JSONObject(meta.readText());require(value.optString("state")=="ready")
                                val bytes=file.readBytes();val ms=value.getInt("duration")
                                val cleanup = cleanupRequested(value)
                                activity.runOnUiThread {result.success(mapOf("bytes" to bytes,"duration" to ms,"cleanup" to cleanup))}
                            } catch(e: Exception) {activity.runOnUiThread {result.error("audio","Segmento non disponibile",null)}}
                        }
                    }
                    "ack" -> {
                        val dir = noteDirectory(requireNotNull(call.argument<String>("noteId")))
                        val ids = call.argument<List<String>>("ids") ?: emptyList()
                        require(ids.size <= 10000 && ids.all { safeId(it) })
                        worker.execute {
                            ids.forEach { id ->
                                val file = File(dir, "$id.m4a")
                                val meta = manifest(file)
                                try {
                                    if (meta.exists() && meta.length() <= 4096 && JSONObject(meta.readText()).optString("state") == "ready") {
                                        if (!file.exists() || file.delete()) meta.delete()
                                    }
                                } catch (_: Exception) { /* Preserve staging on failed ACK. */ }
                            }
                            activity.runOnUiThread { result.success(null) }
                        }
                    }
                    "play" -> {
                        releasePlayer()
                        if (recorder != null) throw IllegalStateException("Ferma prima la registrazione")
                        val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException()
                        if (bytes.size > 48 * 1024 * 1024) throw IllegalArgumentException()
                        val seek = call.argument<Int>("position") ?: 0
                        playResult = result
                        val file = File.createTempFile("osi-audio-play-", ".m4a", activity.cacheDir)
                        playbackFile = file
                        worker.execute {
                            try {
                                file.writeBytes(bytes)
                                activity.runOnUiThread {
                                    if (closed || !foreground || playbackFile != file) {
                                        file.delete(); completePlay(result, "Riproduzione annullata")
                                    } else try {
                                        val media = MediaPlayer()
                                        player = media
                                        media.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                                        media.setDataSource(file.absolutePath)
                                        media.setOnPreparedListener {
                                            playerPrepared = true
                                            if (!foreground || !focus()) {
                                                completePlay(result, "Audio non disponibile"); releasePlayer()
                                            } else {
                                                media.seekTo(seek.coerceIn(0, media.duration))
                                                media.start(); completePlay(result)
                                            }
                                        }
                                        media.setOnErrorListener { _, _, _ ->
                                            completePlay(result, "Audio non riproducibile"); releasePlayer(); true
                                        }
                                        media.prepareAsync()
                                    } catch (e: Exception) {
                                        completePlay(result, "Audio non riproducibile"); releasePlayer()
                                    }
                                }
                            } catch (e: Exception) {
                                file.delete()
                                activity.runOnUiThread { completePlay(result, "Impossibile aprire l’audio") }
                            }
                        }
                    }
                    "pause" -> { if (playerPrepared) player?.pause(); result.success(null) }
                    "resume" -> { if (playerPrepared && foreground && focus()) player?.start(); result.success(null) }
                    "seek" -> { player?.seekTo((call.argument<Int>("position") ?: 0).coerceAtLeast(0)); result.success(null) }
                    "position" -> result.success(mapOf("position" to (if (playerPrepared) player?.currentPosition ?: 0 else 0), "playing" to (playerPrepared && player?.isPlaying == true), "recording" to (recorder != null), "elapsed" to if (recorder != null) (SystemClock.elapsedRealtime() - started).toInt() else duration))
                    "release" -> { finishRecording(); recordingFile = null; releasePlayer(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("audio", e.message ?: "Errore audio", null) }
        }
    }

    @Suppress("DEPRECATION")
    private fun start(result: MethodChannel.Result) {
        if (closed || !foreground) { result.error("cancelled", "Apri l’app per registrare", null); return }
        releasePlayer()
        val dir = noteDirectory(noteId)
        val used = staging.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        check(used + limit <= 256 * 1024 * 1024L) { "Staging audio pieno: recuperare i segmenti precedenti" }
        val file = File(dir, "$recordingId.m4a")
        check(file.createNewFile()) { "Audio identity already exists" }
        tapTimes.clear()
        writeManifest(file, "recording")
        val media = MediaRecorder()
        recordingFile = file
        recorder = media
        try {
            media.setAudioSource(MediaRecorder.AudioSource.MIC)
            media.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            media.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            media.setAudioChannels(1)
            media.setAudioSamplingRate(22050)
            media.setAudioEncodingBitRate(48000)
            media.setMaxDuration(120 * 60 * 1000)
            media.setMaxFileSize(limit)
            media.setOutputFile(file.absolutePath)
            media.setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED || what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) interrupt()
            }
            media.setOnErrorListener { _, _, _ -> interrupt() }
            media.prepare(); media.start()
            segmentHandler.postDelayed(rotate, 30000)
            started = SystemClock.elapsedRealtime(); duration = 0
            startedUptime = SystemClock.uptimeMillis()
            result.success(null)
        } catch (e: Exception) {
            recorder = null; try { media.release() } catch (_: Exception) {}
            try { writeManifest(file, "partial") } catch (_: Exception) {}
            recordingFile = null
            result.error("audio", "Microfono non disponibile", null)
        }
    }
    private fun cleanupRequested(data: JSONObject): Boolean =
        data.optBoolean("reduceNoise", false) ||
            (data.optBoolean("reduceTaps", false) && (data.optJSONArray("tapTimes")?.length() ?: 0) > 0)
    fun permissionResult(request: Int, grants: IntArray): Boolean {
        if (request != 7401) return false
        val result = pending ?: return true
        pending = null
        if (!closed && grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            if (foreground) { try { start(result) } catch (e: Exception) { result.error("audio", e.message, null) } } else grantedPending = result
        }
        else result.error("permission", "Permesso microfono negato", null)
        return true
    }
    private fun finishRecording() {
        val media = recorder ?: return
        recorder = null
        segmentHandler.removeCallbacks(rotate)
        duration = (SystemClock.elapsedRealtime() - started).toInt()
        try {
            media.stop()
            recordingFile?.let { file ->
                FileOutputStream(file, true).use { it.fd.sync() }
                writeManifest(file, "ready", duration)
            }
        } catch (e: Exception) {
            recordingFile?.let { try { writeManifest(it, "partial", duration) } catch (_: Exception) {} }
        } finally {
            try { media.reset() } catch (_: Exception) {}
            try { media.release() } catch (_: Exception) {}
        }
    }
    @Suppress("DEPRECATION")
    private fun releasePlayer() {
        playResult?.let { completePlay(it, "Riproduzione annullata") }
        playerPrepared = false
        if (Build.VERSION.SDK_INT >= 26) focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        else audioManager.abandonAudioFocus(focusListener)
        focusRequest = null
        player?.apply { setOnPreparedListener(null); setOnErrorListener(null); release() }
        player = null; playbackFile?.delete(); playbackFile = null
    }
    fun resume() {
        foreground = true
        grantedPending?.let { grantedPending = null; try { start(it) } catch(e: Exception) {it.error("audio",e.message,null)} }
    }
    fun interrupt(leaving: Boolean = false) {
        if (leaving) foreground = false
        if (recorder != null) { finishRecording(); channel.invokeMethod("interrupted", null) }
        if (playerPrepared) player?.let { if (it.isPlaying) it.pause() } else releasePlayer()
    }
    fun close() {
        closed = true
        grantedPending?.error("cancelled", "Registrazione annullata", null); grantedPending = null
        pending?.error("cancelled", "Registrazione annullata", null); pending = null
        finishRecording(); recordingFile = null
        releasePlayer(); channel.setMethodCallHandler(null); worker.shutdown(); cleanupWorker.shutdown()
    }
}
