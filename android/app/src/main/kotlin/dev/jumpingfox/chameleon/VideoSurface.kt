package dev.jumpingfox.chameleon

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * A surface for the hardware decoder to draw the video on directly, behind the Flutter view
 * (which is see-through where the video shows). Unlike a Flutter texture, which is redrawn by
 * Flutter in SDR, the display gets the decoder's frames as they are: HDR10, HLG and HDR10+ come
 * through as HDR, and the TV switches its picture mode to match.
 *
 * Dart (lib/core/platform/video_surface.dart) asks for it with "attach", places it over the
 * video's area with "place", and lets it go with "detach". Whenever the surface appears or
 * goes away (the app going to the background takes it away), Dart hears "surface" with mpv's
 * handle to it, or 0.
 */
class VideoSurface(private val activity: Activity, messenger: BinaryMessenger) : SurfaceHolder.Callback {
    private val channel = MethodChannel(messenger, "chameleon/video_surface")
    private val handler = Handler(Looper.getMainLooper())
    /** The surface's view while attached. ExoPlayer (ExoEngine) draws on it directly. */
    var view: SurfaceView? = null
        private set

    /** Told whenever the view is attached (with it) or taken away (with null). */
    var onViewChanged: ((SurfaceView?) -> Unit)? = null

    /** Told where the video now sits, so other views can follow it (ExoPlayer's picture subtitles). */
    var onPlaced: ((FrameLayout.LayoutParams) -> Unit)? = null

    /** mpv's handle to the surface: a JNI global reference to it, or 0 while there's none. */
    private var ref = 0L

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "attach" -> {
                    attach()
                    result.success(ref)
                }
                "place" -> {
                    place(
                        call.argument<Int>("left")!!,
                        call.argument<Int>("top")!!,
                        call.argument<Int>("width")!!,
                        call.argument<Int>("height")!!,
                    )
                    result.success(null)
                }
                "detach" -> {
                    detach()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun attach() {
        if (view != null) return
        val surface = SurfaceView(activity)
        surface.holder.addCallback(this)
        // Behind everything else, so the Flutter view stays on top. Full screen until placed.
        content().addView(surface, 0, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        view = surface
        onViewChanged?.invoke(surface)
    }

    /** Puts the surface at [left], [top], [width] × [height] physical pixels of the Flutter view. */
    private fun place(left: Int, top: Int, width: Int, height: Int) {
        val surface = view ?: return
        // The Flutter view normally fills the content view, but measure in case it doesn't.
        val flutter = activity.findViewById<View>(FlutterActivity.FLUTTER_VIEW_ID)
        val origin = IntArray(2).also { flutter?.getLocationInWindow(it) }
        val contentOrigin = IntArray(2).also { content().getLocationInWindow(it) }
        val params = FrameLayout.LayoutParams(width.coerceAtLeast(1), height.coerceAtLeast(1), Gravity.TOP or Gravity.START).apply {
            // Negative when the video is zoomed to fill the screen: the parts off screen are cut off.
            leftMargin = left + origin[0] - contentOrigin[0]
            topMargin = top + origin[1] - contentOrigin[1]
        }
        surface.layoutParams = params
        onPlaced?.invoke(FrameLayout.LayoutParams(params))
    }

    private fun detach() {
        val surface = view ?: return
        onViewChanged?.invoke(null)
        view = null
        content().removeView(surface) // surfaceDestroyed follows, which lets go of the handle
    }

    fun content(): FrameLayout = activity.findViewById(android.R.id.content)

    override fun surfaceCreated(holder: SurfaceHolder) {
        ref = MediaKitAndroidHelper.newGlobalObjectRef(holder.surface)
        channel.invokeMethod("surface", ref)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        val old = ref
        ref = 0
        channel.invokeMethod("surface", 0L)
        // mpv lets go of it once Dart hears it's gone, or when the player is destroyed (media_kit
        // does that 5 seconds after it's disposed). Only then can the handle go too.
        if (old != 0L) handler.postDelayed({ MediaKitAndroidHelper.deleteGlobalObjectRef(old) }, 10_000)
    }
}
