package dev.jumpingfox.chameleon

import android.app.Activity
import android.content.Context
import android.media.MediaCodecList
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.SubtitleView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * ExoPlayer, the app's second video engine (mpv, through media_kit, is the first). It plays
 * Dolby Vision as Dolby Vision, through Android's own Dolby Vision decoder, which mpv can't use,
 * and is the fallback for files mpv can't open.
 *
 * Dart (lib/features/player/engine/exo_engine.dart) drives it on "chameleon/exo" and hears
 * back on "chameleon/exo/events": maps with whichever of position, duration, playing,
 * buffering, completed, tracks, subtitle, video and error changed.
 *
 * The picture goes to VideoSurface's view, behind Flutter. Text subtitles are sent to Dart and
 * drawn there, in the style from Settings; picture subtitles (PGS, VobSub) are drawn by a
 * SubtitleView just above the video, since they can't be sent as text.
 */
@OptIn(UnstableApi::class)
class ExoEngine(private val activity: Activity, messenger: BinaryMessenger, private val surface: VideoSurface) :
    Player.Listener {
    private val channel = MethodChannel(messenger, "chameleon/exo")
    private val handler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var player: ExoPlayer? = null
    private var subtitles: SubtitleView? = null

    private var uri: String? = null
    private var headers: Map<String, String> = emptyMap()

    /** Subtitle files added from the server, by address. Part of the media item, so adding one reloads it. */
    private val sideloaded = mutableListOf<MediaItem.SubtitleConfiguration>()

    /** A subtitle file to switch to as soon as it's loaded. */
    private var pendingSubtitle: String? = null

    private val ticker = object : Runnable {
        override fun run() {
            val p = player ?: return
            send("position" to p.currentPosition, "buffer" to p.bufferedPosition)
            handler.postDelayed(this, 250)
        }
    }

    init {
        EventChannel(messenger, "chameleon/exo/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
            }

            override fun onCancel(arguments: Any?) {
                events = null
            }
        })
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "support" -> result.success(support())
                "create" -> {
                    create(call.argument<Boolean>("passthrough") ?: true)
                    result.success(null)
                }
                "open" -> {
                    open(
                        call.argument<String>("uri")!!,
                        call.argument<Map<String, String>>("headers") ?: emptyMap(),
                        (call.argument<Number>("start") ?: 0).toLong(),
                        call.argument<Boolean>("play") ?: true,
                    )
                    result.success(null)
                }
                "play" -> {
                    player?.play()
                    result.success(null)
                }
                "pause" -> {
                    player?.pause()
                    result.success(null)
                }
                "seek" -> {
                    player?.seekTo((call.argument<Number>("position") ?: 0).toLong())
                    result.success(null)
                }
                "stop" -> {
                    player?.stop()
                    result.success(null)
                }
                "selectTrack" -> {
                    select(call.argument<String>("type")!!, call.argument<Int>("group")!!, call.argument<Int>("track")!!)
                    result.success(null)
                }
                "disableSubtitles" -> {
                    disableSubtitles()
                    result.success(null)
                }
                "addSubtitle" -> {
                    addSubtitle(
                        call.argument<String>("uri")!!,
                        call.argument<String>("language"),
                        call.argument<String>("title"),
                    )
                    result.success(null)
                }
                "dispose" -> {
                    dispose()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── What this device can do ──

    /**
     * Whether there's a Dolby Vision decoder, and which audio formats have decoders here, as
     * mime types. The player only hands a file to ExoPlayer when it can play it.
     */
    private fun support(): Map<String, Any> {
        val types = mutableSetOf<String>()
        for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
            if (info.isEncoder) continue
            types += info.supportedTypes.map { it.lowercase() }
        }
        return mapOf(
            "dolbyVision" to ("video/dolby-vision" in types),
            "audio" to types.filter { it.startsWith("audio/") },
        )
    }

    // ── Playing ──

    private fun create(passthrough: Boolean) {
        if (player != null) return
        val renderers = object : DefaultRenderersFactory(activity) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioOutputPlaybackParameters: Boolean,
            ): AudioSink? {
                // Without passthrough: stereo PCM is all the output is said to take, so surround
                // is decoded here rather than sent on untouched.
                if (passthrough) return super.buildAudioSink(context, enableFloatOutput, enableAudioOutputPlaybackParameters)
                @Suppress("DEPRECATION")
                return DefaultAudioSink.Builder(context)
                    .setAudioCapabilities(AudioCapabilities.DEFAULT_AUDIO_CAPABILITIES)
                    .build()
            }
        }.setEnableDecoderFallback(true)
        val exo = ExoPlayer.Builder(activity, renderers).build()
        exo.addListener(this)
        player = exo
        surface.onViewChanged = { view -> attachTo(view) }
        surface.onPlaced = { params -> subtitles?.layoutParams = params }
        attachTo(surface.view)
    }

    /** Draws on [view], VideoSurface's view, with picture subtitles in a view just above it. */
    private fun attachTo(view: SurfaceView?) {
        val exo = player ?: return
        val content = surface.content()
        subtitles?.let { content.removeView(it) }
        subtitles = null
        if (view == null) {
            exo.clearVideoSurface()
            return
        }
        exo.setVideoSurfaceView(view)
        val overlay = SubtitleView(activity)
        content.addView(overlay, content.indexOfChild(view) + 1, FrameLayout.LayoutParams(view.layoutParams as FrameLayout.LayoutParams))
        subtitles = overlay
    }

    private fun open(uri: String, headers: Map<String, String>, startMs: Long, play: Boolean) {
        val exo = player ?: return
        this.uri = uri
        this.headers = headers
        sideloaded.clear()
        pendingSubtitle = null
        exo.setMediaSource(mediaSource(), startMs)
        exo.playWhenReady = play
        exo.prepare()
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    private fun mediaSource() = DefaultMediaSourceFactory(
        DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(headers)
            .setAllowCrossProtocolRedirects(true),
    ).createMediaSource(
        MediaItem.Builder()
            .setUri(Uri.parse(uri))
            .setSubtitleConfigurations(sideloaded.toList())
            .build(),
    )

    private fun addSubtitle(url: String, language: String?, title: String?) {
        val exo = player ?: return
        if (sideloaded.none { it.id == url }) {
            val mime = when (url.substringBefore('?').substringAfterLast('.').lowercase()) {
                "vtt" -> "text/vtt"
                "ass", "ssa" -> "text/x-ssa"
                else -> "application/x-subrip"
            }
            sideloaded += MediaItem.SubtitleConfiguration.Builder(Uri.parse(url))
                .setId(url)
                .setMimeType(mime)
                .setLanguage(language)
                .setLabel(title)
                .build()
            // Reloads in place, carrying on from where it is.
            val position = exo.currentPosition
            val playing = exo.playWhenReady
            exo.setMediaSource(mediaSource(), position)
            exo.playWhenReady = playing
            exo.prepare()
        }
        pendingSubtitle = url
        selectPendingSubtitle()
    }

    private fun selectPendingSubtitle() {
        val url = pendingSubtitle ?: return
        val exo = player ?: return
        for (group in exo.currentTracks.groups) {
            if (group.type != C.TRACK_TYPE_TEXT) continue
            for (i in 0 until group.length) {
                if (group.getTrackFormat(i).id?.contains(url) == true) {
                    pendingSubtitle = null
                    exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                        .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                        .build()
                    return
                }
            }
        }
    }

    private fun select(type: String, groupIndex: Int, track: Int) {
        val exo = player ?: return
        val group = exo.currentTracks.groups.getOrNull(groupIndex) ?: return
        val trackType = if (type == "audio") C.TRACK_TYPE_AUDIO else C.TRACK_TYPE_TEXT
        pendingSubtitle = null
        exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(trackType, false)
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, track))
            .build()
    }

    private fun disableSubtitles() {
        val exo = player ?: return
        pendingSubtitle = null
        exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            .build()
    }

    private fun dispose() {
        handler.removeCallbacks(ticker)
        player?.removeListener(this)
        player?.release()
        player = null
        subtitles?.let { surface.content().removeView(it) }
        subtitles = null
        surface.onViewChanged = null
        surface.onPlaced = null
    }

    // ── Telling Dart ──

    private fun send(vararg values: Pair<String, Any?>) {
        events?.success(mapOf(*values))
    }

    override fun onPlaybackStateChanged(state: Int) {
        val exo = player ?: return
        send(
            "buffering" to (state == Player.STATE_BUFFERING),
            "completed" to (state == Player.STATE_ENDED),
            "duration" to exo.duration.takeIf { it != C.TIME_UNSET },
            "position" to exo.currentPosition,
        )
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        send("playing" to playWhenReady)
    }

    override fun onVideoSizeChanged(size: VideoSize) {
        if (size.width == 0 || size.height == 0) return
        send(
            "video" to mapOf(
                "width" to size.width,
                "height" to size.height,
                "pixelRatio" to size.pixelWidthHeightRatio.toDouble(),
            ),
        )
    }

    override fun onCues(cues: CueGroup) {
        send("subtitle" to cues.cues.mapNotNull { it.text?.toString() })
        // Picture subtitles can't go to Dart as text: shown natively.
        subtitles?.setCues(cues.cues.filter { it.bitmap != null })
    }

    override fun onTracksChanged(tracks: Tracks) {
        selectPendingSubtitle()
        val list = mutableListOf<Map<String, Any?>>()
        for ((g, group) in tracks.groups.withIndex()) {
            val type = when (group.type) {
                C.TRACK_TYPE_AUDIO -> "audio"
                C.TRACK_TYPE_TEXT -> "subtitle"
                C.TRACK_TYPE_VIDEO -> "video"
                else -> continue
            }
            for (i in 0 until group.length) {
                val format: Format = group.getTrackFormat(i)
                list += mapOf(
                    "type" to type,
                    "group" to g,
                    "track" to i,
                    // Subtitle files added from the server are known by their address.
                    "url" to sideloaded.firstOrNull { format.id?.contains(it.id ?: "\u0000") == true }?.id,
                    "language" to format.language,
                    "title" to format.label,
                    "codec" to (format.sampleMimeType ?: format.codecs),
                    "channels" to format.channelCount.takeIf { it != Format.NO_VALUE },
                    "selected" to group.isTrackSelected(i),
                    "supported" to group.isTrackSupported(i),
                    "default" to ((format.selectionFlags and C.SELECTION_FLAG_DEFAULT) != 0),
                )
            }
        }
        send("tracks" to list)
    }

    override fun onPlayerError(error: PlaybackException) {
        send("error" to (error.message ?: error.errorCodeName))
    }
}
