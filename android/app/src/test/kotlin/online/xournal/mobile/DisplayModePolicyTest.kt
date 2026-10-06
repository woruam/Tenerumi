package online.xournal.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DisplayModePolicyTest {
    @Test fun chooses120HzWithoutChangingResolution() {
        val modes = listOf(
            RefreshMode(1, 1080, 2400, 60f),
            RefreshMode(2, 1080, 2400, 90f),
            RefreshMode(3, 1080, 2400, 120f),
            RefreshMode(4, 720, 1600, 144f)
        )
        assertEquals(3, DisplayModePolicy.select(1080, 2400, modes)?.id)
    }

    @Test fun retains60HzOnOlderDisplays() {
        assertEquals(1, DisplayModePolicy.select(1080, 2400,
            listOf(RefreshMode(1, 1080, 2400, 60f)))?.id)
    }

    @Test fun ignoresInvalidRatesAndMissingResolutions() {
        assertNull(DisplayModePolicy.select(1080, 2400,
            listOf(RefreshMode(1, 720, 1600, 120f), RefreshMode(2, 1080, 2400, Float.NaN))))
    }
}
