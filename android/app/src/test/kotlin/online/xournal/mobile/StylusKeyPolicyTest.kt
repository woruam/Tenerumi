package online.xournal.mobile

import org.junit.Assert.*
import org.junit.Test

class StylusKeyPolicyTest {
    @Test fun mapsStandardButtonsAndExistingRedmiKeys() {
        assertEquals(1, StylusKeyPolicy.button(308))
        assertEquals(2, StylusKeyPolicy.button(309))
        assertEquals(1, StylusKeyPolicy.button(93))
        assertEquals(2, StylusKeyPolicy.button(92))
        assertFalse(StylusKeyPolicy.isLegacy(308))
        assertTrue(StylusKeyPolicy.isLegacy(93))
    }

    @Test fun standardKeysHaveOnePressAndOneReleaseWithoutRepeats() {
        assertTrue(StylusKeyPolicy.shouldDispatch(308, 0, 0))
        assertFalse(StylusKeyPolicy.shouldDispatch(308, 0, 1))
        assertTrue(StylusKeyPolicy.shouldDispatch(308, 1, 0))
        assertFalse(StylusKeyPolicy.shouldDispatch(308, 2, 0))
    }

    @Test fun redmiKeepsTheSingleToggleOnFirstDown() {
        assertTrue(StylusKeyPolicy.shouldDispatch(93, 0, 0))
        assertFalse(StylusKeyPolicy.shouldDispatch(93, 0, 2))
        assertFalse(StylusKeyPolicy.shouldDispatch(93, 1, 0))
    }

    @Test fun keyboardAndRemoteButtonsAreNotMistakenForBarrelButtons() {
        for (key in listOf(29, 66, 85, 310, 311)) {
            assertNull(StylusKeyPolicy.button(key))
            assertFalse(StylusKeyPolicy.shouldDispatch(key, 0, 0))
        }
    }
}
