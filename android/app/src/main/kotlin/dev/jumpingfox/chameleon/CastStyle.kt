package dev.jumpingfox.chameleon

import android.content.Context
import com.google.android.gms.cast.TextTrackStyle
import com.google.android.gms.cast.framework.CastContext
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Styles the subtitles on the Chromecast being cast to, like the app's own (see
 * lib/core/cast/cast_controller.dart). The Cast plugin doesn't pass styles on, so this sets
 * them on the current session with Google's Cast SDK directly.
 *
 * "set" takes: edge ("none", "outline", "dropShadow"), edgeColor, foreground and background
 * (ARGB ints), scale (1.0 = normal) and font, a generic family ("sansSerif", "serif",
 * "monospacedSansSerif", "monospacedSerif", "casual", "cursive", "smallCapitals"). It answers
 * false when nothing is being cast.
 */
class CastStyle(private val context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "chameleon/cast_style").setMethodCallHandler { call, result ->
            if (call.method != "set") return@setMethodCallHandler result.notImplemented()
            val client = try {
                @Suppress("DEPRECATION")
                CastContext.getSharedInstance(context).sessionManager.currentCastSession?.remoteMediaClient
            } catch (_: Exception) {
                null // no Cast here (no Google Play services)
            }
            if (client == null) return@setMethodCallHandler result.success(false)
            client.setTextTrackStyle(style(call.arguments as Map<*, *>))
            result.success(true)
        }
    }

    private fun style(args: Map<*, *>) = TextTrackStyle().apply {
        edgeType = when (args["edge"]) {
            "outline" -> TextTrackStyle.EDGE_TYPE_OUTLINE
            "dropShadow" -> TextTrackStyle.EDGE_TYPE_DROP_SHADOW
            else -> TextTrackStyle.EDGE_TYPE_NONE
        }
        (args["edgeColor"] as? Number)?.let { edgeColor = it.toInt() }
        (args["foreground"] as? Number)?.let { foregroundColor = it.toInt() }
        (args["background"] as? Number)?.let { backgroundColor = it.toInt() }
        (args["scale"] as? Number)?.let { fontScale = it.toFloat() }
        fontGenericFamily = when (args["font"]) {
            "serif" -> TextTrackStyle.FONT_FAMILY_SERIF
            "monospacedSansSerif" -> TextTrackStyle.FONT_FAMILY_MONOSPACED_SANS_SERIF
            "monospacedSerif" -> TextTrackStyle.FONT_FAMILY_MONOSPACED_SERIF
            "casual" -> TextTrackStyle.FONT_FAMILY_CASUAL
            "cursive" -> TextTrackStyle.FONT_FAMILY_CURSIVE
            "smallCapitals" -> TextTrackStyle.FONT_FAMILY_SMALL_CAPITALS
            else -> TextTrackStyle.FONT_FAMILY_SANS_SERIF
        }
        windowType = TextTrackStyle.WINDOW_TYPE_NONE
    }
}
