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
import java.util.concurrent.Executors

/** One microphone/player, disk-backed AAC, no PCM buffers or pointer-event hooks. */
class NoteAudio(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "online.xournal.mobile/audio")
    private val worker = Executors.newSingleThreadExecutor()
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
    private var recordingFile: File? = null
    private var playbackFile: File? = null
    private var started = 0L
    private var duration = 0
    private var pending: MethodChannel.Result? = null
    private var grantedPending: MethodChannel.Result? = null
    private var closed = false
    private var foreground = true
    private val limit = 12 * 1024 * 1024L

    init {
        // Only our disposable files, never document files.
        activity.cacheDir.listFiles()?.filter { it.name.startsWith("osi-audio-") }?.forEach { it.delete() }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        if (pending != null || recorder != null || recordingFile != null) {
                            result.error("busy", "Registrazione già attiva", null)
                        } else if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            pending = result
                            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 7401)
                        } else start(result)
                    }
                    "stop" -> {
                        finishRecording()
                        val file = recordingFile
                        val length = duration
                        recordingFile = null
                        worker.execute {
                            try {
                                val bytes = if (file != null && file.length() in 1..limit) file.readBytes() else null
                                activity.runOnUiThread { result.success(if (bytes == null) null else mapOf("bytes" to bytes, "duration" to length)) }
                            } catch (e: Exception) {
                                activity.runOnUiThread { result.error("audio", "Impossibile leggere la registrazione", null) }
                            } finally { file?.delete() }
                        }
                    }
                    "play" -> {
                        releasePlayer()
                        if (recorder != null) throw IllegalStateException("Ferma prima la registrazione")
                        val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException()
                        if (bytes.size > 32 * 1024 * 1024) throw IllegalArgumentException()
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
                    "release" -> { finishRecording(); recordingFile?.delete(); recordingFile = null; releasePlayer(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("audio", e.message ?: "Errore audio", null) }
        }
    }

    @Suppress("DEPRECATION")
    private fun start(result: MethodChannel.Result) {
        if (closed || !foreground) { result.error("cancelled", "Apri l’app per registrare", null); return }
        releasePlayer()
        val file = File.createTempFile("osi-audio-record-", ".m4a", activity.cacheDir)
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
            media.setMaxDuration(30 * 60 * 1000)
            media.setMaxFileSize(limit)
            media.setOutputFile(file.absolutePath)
            media.setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED || what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) interrupt()
            }
            media.setOnErrorListener { _, _, _ -> interrupt() }
            media.prepare(); media.start()
            started = SystemClock.elapsedRealtime(); duration = 0
            result.success(null)
        } catch (e: Exception) {
            recorder = null; media.release(); file.delete(); recordingFile = null
            result.error("audio", "Microfono non disponibile", null)
        }
    }
    fun permissionResult(request: Int, grants: IntArray): Boolean {
        if (request != 7401) return false
        val result = pending ?: return true
        pending = null
        if (!closed && grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            if (foreground) start(result) else grantedPending = result
        }
        else result.error("permission", "Permesso microfono negato", null)
        return true
    }
    private fun finishRecording() {
        val media = recorder ?: return
        recorder = null
        duration = (SystemClock.elapsedRealtime() - started).toInt()
        try { media.stop() } catch (e: RuntimeException) { recordingFile?.delete() }
        finally { media.reset(); media.release() }
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
        grantedPending?.let { grantedPending = null; start(it) }
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
        finishRecording(); recordingFile?.delete(); recordingFile = null
        releasePlayer(); channel.setMethodCallHandler(null); worker.shutdown()
    }
}
