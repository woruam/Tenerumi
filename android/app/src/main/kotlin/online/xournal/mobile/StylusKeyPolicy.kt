package online.xournal.mobile

/** Pure mapping, testable without a pen or Android runtime. */
object StylusKeyPolicy {
    // Android KeyEvent constants. The standard barrel keys were added in API 34;
    // integer values also allow the mapping to run on our older supported APIs.
    fun button(keyCode: Int): Int? = when (keyCode) {
        93, 308 -> 1 // PAGE_DOWN (Redmi), STYLUS_BUTTON_PRIMARY
        92, 309 -> 2 // PAGE_UP (Redmi), STYLUS_BUTTON_SECONDARY
        else -> null
    }

    fun isLegacy(keyCode: Int): Boolean = keyCode == 92 || keyCode == 93

    fun shouldDispatch(keyCode: Int, action: Int, repeatCount: Int): Boolean =
        button(keyCode) != null && (
            (action == 0 && repeatCount == 0) || // ACTION_DOWN, first press only
            (action == 1 && !isLegacy(keyCode)) // ACTION_UP for temporary tools
        )
}
