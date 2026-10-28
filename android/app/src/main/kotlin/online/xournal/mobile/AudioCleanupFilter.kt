package online.xournal.mobile

import kotlin.math.*

/** Conservative lecture cleanup. Never inserts/deletes samples or silences tap windows. */
object AudioCleanupFilter {
    fun process(samples: ShortArray, sampleRate: Int, tapTimesMs: IntArray,
                reduceNoise: Boolean, reduceTaps: Boolean): ShortArray {
        require(sampleRate in 8000..96000)
        if (samples.isEmpty() || (!reduceNoise && !reduceTaps)) return samples.copyOf()
        val original = DoubleArray(samples.size) { samples[it].toDouble() }
        val output = original.copyOf()
        if (reduceTaps) removeImpulses(original, output, sampleRate, tapTimesMs)
        if (reduceNoise) reduceSteadyNoise(output, sampleRate)
        return ShortArray(output.size) { output[it].roundToInt().coerceIn(-32768, 32767).toShort() }
    }

    private fun removeImpulses(input: DoubleArray, output: DoubleArray, rate: Int, taps: IntArray) {
        val halfRepair = max(2, rate * 3 / 1000)
        var repairedUntil = -1
        for (time in taps.filter { it >= 0 }.distinct().sorted()) {
            val center = (time.toLong() * rate / 1000).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            val lo = max(1, center - rate * 30 / 1000)
            val hi = min(input.size - 2, center + rate * 65 / 1000)
            if (lo >= hi) continue
            var peak = lo
            for (i in lo..hi) if (abs(input[i] - input[i - 1]) > abs(input[peak] - input[peak - 1])) peak = i
            if (peak <= repairedUntil) continue
            // Estimate speech/background from both sides, excluding the impact.
            var energy = 0.0; var count = 0
            val radius = rate * 70 / 1000
            for (i in max(1, peak - radius)..min(input.lastIndex, peak + radius)) {
                if (abs(i - peak) < halfRepair * 3) continue
                val delta = input[i] - input[i - 1]
                energy += delta * delta; count++
            }
            val baseline = sqrt(energy / max(1, count))
            val impulse = abs(input[peak] - input[peak - 1])
            // Ordinary syllables and steady fricatives must not become holes.
            if (impulse < max(1200.0, baseline * 8)) continue
            val left = max(0, peak - halfRepair); val right = min(input.lastIndex, peak + halfRepair)
            val a = input[left]; val b = input[right]
            for (i in left..right) {
                val t = (i - left).toDouble() / max(1, right - left)
                val blend = .88 * sin(PI * t).pow(2)
                output[i] = input[i] * (1 - blend) + (a + (b - a) * t) * blend
            }
            repairedUntil = right
        }
    }

    private fun reduceSteadyNoise(data: DoubleArray, rate: Int) {
        // 70 Hz Butterworth high-pass: rumble is reduced without a telephone
        // voice band, automatic gain changes or removal of distant speech.
        val w = 2 * PI * 70 / rate; val c = cos(w); val alpha = sin(w) / sqrt(2.0)
        val a0 = 1 + alpha
        val b0 = (1 + c) / (2 * a0); val b1 = -(1 + c) / a0
        val a1 = -2 * c / a0; val a2 = (1 - alpha) / a0
        var x1 = 0.0; var x2 = 0.0; var y1 = 0.0; var y2 = 0.0
        for (i in data.indices) {
            val x = data[i]; val y = b0 * x + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
            data[i] = y; x2 = x1; x1 = x; y2 = y1; y1 = y
        }
        // A soft gate only on quiet, noise-like frames. Voiced/distant speech
        // bypasses it; the gain never reaches zero and changes are smoothed.
        val frame = max(1, rate / 50)
        val levels = DoubleArray((data.size + frame - 1) / frame)
        val crossings = DoubleArray(levels.size)
        for (f in levels.indices) {
            val lo = f * frame; val hi = min(data.size, lo + frame)
            var sum = 0.0; var zeroes = 0
            for (i in lo until hi) {
                sum += data[i] * data[i]
                if (i > lo && (data[i] >= 0) != (data[i - 1] >= 0)) zeroes++
            }
            levels[f] = sqrt(sum / (hi - lo)); crossings[f] = zeroes.toDouble() / (hi - lo)
        }
        val sorted = levels.sorted(); val floor = sorted[sorted.size / 10]
        var gain = 1.0
        val rise = 1 - exp(-1.0 / (rate * .003))
        val fall = 1 - exp(-1.0 / (rate * .04))
        for (i in data.indices) {
            val f = i / frame
            val quietNoise = floor < 650 && levels[f] <= floor * 1.5 && crossings[f] > .24
            val target = if (quietNoise) .5 else 1.0
            val smoothing = if (target > gain) rise else fall
            gain += (target - gain) * smoothing
            data[i] *= gain
        }
    }
}
