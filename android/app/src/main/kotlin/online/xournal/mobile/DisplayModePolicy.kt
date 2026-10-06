package online.xournal.mobile

internal data class RefreshMode(val id: Int, val width: Int, val height: Int, val hz: Float)

internal object DisplayModePolicy {
    // Retain resolution so a refresh request cannot resize the document surface.
    fun select(width: Int, height: Int, modes: List<RefreshMode>): RefreshMode? =
        modes.filter { it.width == width && it.height == height && it.hz > 0 && it.hz.isFinite() }
            .maxByOrNull { it.hz }
}
