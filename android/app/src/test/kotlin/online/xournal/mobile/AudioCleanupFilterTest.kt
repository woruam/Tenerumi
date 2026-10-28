package online.xournal.mobile

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.*
import java.util.Random

class AudioCleanupFilterTest {
    private val rate = 22050
    private fun voice() = ShortArray(rate) { (5000 * sin(2 * PI * 220 * it / rate)).toInt().toShort() }
    private fun rms(data: ShortArray, start: Int = 0): Double =
        sqrt(data.drop(start).map { it.toDouble().pow(2) }.average())

    @Test fun disabledFiltersPreserveEverySample() {
        val data = voice()
        assertArrayEquals(data, AudioCleanupFilter.process(data, rate, intArrayOf(200), false, false))
    }

    @Test fun penContactAttenuatesImpulseWithoutRemovingTimeOrChangingSurroundingSpeech() {
        val data = voice(); val at = rate / 2
        data[at] = 28000
        val result = AudioCleanupFilter.process(data, rate, intArrayOf(500), false, true)
        assertEquals(data.size, result.size)
        assertTrue(abs(result[at].toInt()) < abs(data[at].toInt()) * .25)
        for (i in data.indices) if (abs(i - at) > rate / 100)
            assertEquals("speech sample $i", data[i], result[i])
        assertEquals(28000, data[at].toInt()) // The original input remains untouched.
    }

    @Test fun contactWithoutImpulseDoesNotSuppressDistantVoice() {
        val data = voice()
        assertArrayEquals(data, AudioCleanupFilter.process(data, rate, intArrayOf(100, 400, 700), false, true))
    }

    @Test fun clicksOutsidePenContactsAreNotMistakenForPenNoise() {
        val data = voice(); data[rate * 3 / 4] = 28000
        assertArrayEquals(data, AudioCleanupFilter.process(data, rate, intArrayOf(100), false, true))
    }

    @Test fun duplicateInvalidAndEdgeContactsDoNotChangeLengthOrOverflow() {
        val data = ShortArray(90); data[2] = 30000
        val result = AudioCleanupFilter.process(data, rate,
            intArrayOf(-10, 0, 0, Int.MAX_VALUE), false, true)
        assertEquals(data.size, result.size)
    }

    @Test fun steadyQuietHissIsReducedWithoutHardGating() {
        val random = Random(5)
        val data = ShortArray(rate) { (random.nextGaussian() * 180).toInt().toShort() }
        val result = AudioCleanupFilter.process(data, rate, intArrayOf(), true, false)
        val ratio = rms(result, rate / 4) / rms(data, rate / 4)
        assertTrue("noise gain $ratio", ratio in .35.. .7)
        assertTrue(result.any { it != 0.toShort() })
    }

    @Test fun lectureVoiceStaysAudibleAndRumbleIsAttenuated() {
        val speech = voice()
        val filteredSpeech = AudioCleanupFilter.process(speech, rate, intArrayOf(), true, false)
        assertTrue(rms(filteredSpeech, rate / 4) / rms(speech, rate / 4) > .95)
        val hum = ShortArray(rate) { (4000 * sin(2 * PI * 30 * it / rate)).toInt().toShort() }
        val filteredHum = AudioCleanupFilter.process(hum, rate, intArrayOf(), true, false)
        assertTrue(rms(filteredHum, rate / 4) / rms(hum, rate / 4) < .25)
    }

    @Test fun silenceAndTinyBuffersRemainValid() {
        for (length in listOf(0, 1, 2, 20, rate)) {
            val data = ShortArray(length)
            assertArrayEquals(data, AudioCleanupFilter.process(data, rate, intArrayOf(0), true, true))
        }
    }
}
