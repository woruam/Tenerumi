package online.xournal.mobile

import io.flutter.plugin.common.BinaryMessenger

/** Only compiled when OSI_ENABLE_PLUGINS=true. */
object OptionalFeatures {
    fun register(messenger: BinaryMessenger) {
        PluginOcr.register(messenger)
    }
}
