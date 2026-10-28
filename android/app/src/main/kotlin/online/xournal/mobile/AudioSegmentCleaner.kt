package online.xournal.mobile

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.SystemClock
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.min

/** Bounded off-main-thread AAC cleanup. The durable original is never replaced. */
object AudioSegmentCleaner {
    data class Result(val bytes: ByteArray, val applied: Boolean)
    private const val MAX_PCM_BYTES = 4 * 1024 * 1024
    private const val TIMEOUT_US = 10000L
    private data class Pcm(val samples: ShortArray, val rate: Int, val durationUs: Long)

    fun clean(source: File, cache: File, noise: Boolean, taps: Boolean, times: IntArray): Result {
        if (!noise && (!taps || times.isEmpty())) return Result(source.readBytes(), true)
        val deadline = SystemClock.elapsedRealtime() + 10000
        var temporary: File? = null
        return try {
            val pcm = decode(source, deadline)
            val filtered = AudioCleanupFilter.process(pcm.samples, pcm.rate, times, noise, taps)
            if (pcm.samples.contentEquals(filtered)) return Result(source.readBytes(), true)
            checkTime(deadline)
            temporary = File.createTempFile("osi-audio-clean-", ".m4a", cache)
            encode(filtered, pcm.rate, temporary, deadline)
            val verifier = MediaExtractor()
            try {
                verifier.setDataSource(temporary.path)
                check(verifier.trackCount == 1)
                val format = verifier.getTrackFormat(0)
                check(format.getString(MediaFormat.KEY_MIME) == "audio/mp4a-latm")
                // No trim/time stretching: only normal AAC packet padding may differ.
                check(abs(format.getLong(MediaFormat.KEY_DURATION) - pcm.durationUs) <= 150000)
            } finally { verifier.release() }
            check(temporary.length() in 1..(48L * 1024 * 1024))
            Result(temporary.readBytes(), true)
        } catch (_: Exception) {
            Result(source.readBytes(), false)
        } finally { temporary?.delete() }
    }

    private fun checkTime(deadline: Long) {
        check(SystemClock.elapsedRealtime() <= deadline) { "Audio processing deadline" }
    }

    private fun decode(source: File, deadline: Long): Pcm {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(source.path)
            val track = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            check(format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == 1)
            val duration = format.getLong(MediaFormat.KEY_DURATION)
            check(duration in 1..90000000)
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val codec = MediaCodec.createDecoderByType(requireNotNull(format.getString(MediaFormat.KEY_MIME)))
            decoder = codec
            format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            codec.configure(format, null, null, 0); codec.start()
            val output = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inputEnded = false; var outputEnded = false
            while (!outputEnded) {
                checkTime(deadline)
                if (!inputEnded) {
                    val index = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (index >= 0) {
                        val buffer = requireNotNull(codec.getInputBuffer(index)); buffer.clear()
                        val count = extractor.readSampleData(buffer, 0)
                        if (count < 0) {
                            inputEnded = true
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        } else {
                            codec.queueInputBuffer(index, 0, count, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val decodedFormat = codec.outputFormat
                    check(decodedFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == 1)
                    rate = decodedFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    if (decodedFormat.containsKey(MediaFormat.KEY_PCM_ENCODING))
                        check(decodedFormat.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_16BIT)
                } else if (index >= 0) {
                    try {
                        if (info.size > 0) {
                            check(output.size() + info.size <= MAX_PCM_BYTES)
                            val buffer = requireNotNull(codec.getOutputBuffer(index))
                            buffer.position(info.offset); buffer.limit(info.offset + info.size)
                            val chunk = ByteArray(info.size); buffer.get(chunk); output.write(chunk)
                        }
                        outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    } finally { codec.releaseOutputBuffer(index, false) }
                }
            }
            val bytes = output.toByteArray(); check(bytes.isNotEmpty() && bytes.size % 2 == 0)
            val samples = ShortArray(bytes.size / 2)
            ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(samples)
            return Pcm(samples, rate, duration)
        } finally {
            try { decoder?.stop() } catch (_: Exception) {}
            decoder?.release(); extractor.release()
        }
    }

    private fun encode(samples: ShortArray, rate: Int, target: File, deadline: Long) {
        val codec = MediaCodec.createEncoderByType("audio/mp4a-latm")
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            val format = MediaFormat.createAudioFormat("audio/mp4a-latm", rate, 1)
            format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            format.setInteger(MediaFormat.KEY_BIT_RATE, 48000)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE); codec.start()
            val writer = MediaMuxer(target.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = writer
            var track = -1; var position = 0; var inputEnded = false; var outputEnded = false
            val info = MediaCodec.BufferInfo()
            while (!outputEnded) {
                checkTime(deadline)
                if (!inputEnded) {
                    val index = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (index >= 0) {
                        val buffer = requireNotNull(codec.getInputBuffer(index)); buffer.clear()
                        val count = min(samples.size - position, buffer.remaining() / 2)
                        val timestamp = position.toLong() * 1000000 / rate
                        buffer.order(ByteOrder.LITTLE_ENDIAN)
                        for (i in position until position + count) buffer.putShort(samples[i])
                        position += count
                        inputEnded = position == samples.size
                        codec.queueInputBuffer(index, 0, count * 2, timestamp,
                            if (inputEnded) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                    }
                }
                val index = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    check(!muxerStarted)
                    track = writer.addTrack(codec.outputFormat); writer.start(); muxerStarted = true
                } else if (index >= 0) {
                    try {
                        if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                            check(muxerStarted)
                            val buffer = requireNotNull(codec.getOutputBuffer(index))
                            buffer.position(info.offset); buffer.limit(info.offset + info.size)
                            // Preserve the encoder's PTS (including priming),
                            // rather than rebasing/clamping each AAC packet.
                            writer.writeSampleData(track, buffer, info)
                        }
                        outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    } finally { codec.releaseOutputBuffer(index, false) }
                }
            }
            check(muxerStarted); writer.stop(); muxerStarted = false
        } finally {
            if (muxerStarted) try { muxer?.stop() } catch (_: Exception) {}
            muxer?.release()
            try { codec.stop() } catch (_: Exception) {}
            codec.release()
        }
    }
}
