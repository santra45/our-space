package com.ourspace.our_space_mobile

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.text.TextOutput
import androidx.media3.exoplayer.text.TextRenderer
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.mkv.MatroskaExtractor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors

@OptIn(UnstableApi::class)
private class WatchRenderersFactory(context: Context) : NextRenderersFactory(context) {
    override fun buildTextRenderers(
        context: Context,
        output: TextOutput,
        outputLooper: Looper,
        extensionRendererMode: Int,
        out: ArrayList<Renderer>,
    ) {
        out.add(TextRenderer(output, outputLooper))
    }
}

@OptIn(UnstableApi::class)
class WatchPlayerChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val players = HashMap<Long, WatchPlayer>()
    private val probes = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var nextId = 1L

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "create") {
            val url = call.argument<String>("url")
            if (url == null) {
                result.error("bad_url", "A link is needed", null)
                return
            }
            val id = nextId++
            val player = WatchPlayer(id, url)
            players[id] = player
            result.success(mapOf("id" to id, "textureId" to player.textureId))
            return
        }
        val id = call.argument<Number>("id")?.toLong()
        val player = id?.let { players[it] }
        if (player == null) {
            result.success(null)
            return
        }
        when (call.method) {
            "play" -> player.exo.play()
            "pause" -> player.exo.pause()
            "seek" -> player.exo.seekTo(call.argument<Number>("ms")?.toLong() ?: 0L)
            "speed" -> player.exo.playbackParameters =
                PlaybackParameters((call.argument<Number>("value")?.toFloat() ?: 1f).coerceIn(0.25f, 4f))
            "position" -> {
                result.success(mapOf("position" to player.exo.currentPosition, "buffered" to player.exo.bufferedPosition))
                return
            }
            "audio" -> player.select(C.TRACK_TYPE_AUDIO, call.argument<String>("track"))
            "subtitle" -> player.select(C.TRACK_TYPE_TEXT, call.argument<String>("track"))
            "dispose" -> {
                players.remove(id)
                player.release()
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        players.values.forEach { it.release() }
        players.clear()
        probes.shutdown()
    }

    private fun ignoresRanges(url: String): Boolean {
        var next = URL(url)
        for (hop in 0 until MAX_HOPS) {
            val connection = next.openConnection() as? HttpURLConnection ?: return false
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = PROBE_TIMEOUT_MS
                connection.readTimeout = PROBE_TIMEOUT_MS
                connection.setRequestProperty("User-Agent", USER_AGENT)
                connection.setRequestProperty("Range", "bytes=0-0")
                val code = connection.responseCode
                if (code !in 300..399) return code == HttpURLConnection.HTTP_OK
                next = URL(next, connection.getHeaderField("Location") ?: return false)
            } catch (e: IOException) {
                return false
            } finally {
                connection.disconnect()
            }
        }
        return false
    }

    private inner class WatchPlayer(private val id: Long, url: String) : Player.Listener, AnalyticsListener {
        private val surface = textures.createSurfaceProducer()
        private var needsSurface = false
        private var ready = false
        private var failed = false
        private var rangeless = false
        private var released = false

        val textureId: Long = surface.id()

        val exo: ExoPlayer = ExoPlayer.Builder(
            context,
            WatchRenderersFactory(context)
                .setEnableDecoderFallback(true)
                .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON),
        )
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                false,
            )
            .setHandleAudioBecomingNoisy(false)
            .build()

        init {
            surface.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    if (!needsSurface) return
                    exo.setVideoSurface(surface.surface)
                    needsSurface = false
                }

                override fun onSurfaceCleanup() {
                    exo.setVideoSurface(null)
                    needsSurface = true
                }
            })
            val first = surface.surface
            exo.setVideoSurface(first)
            needsSurface = first == null
            exo.addListener(this)
            exo.addAnalyticsListener(this)
            exo.playWhenReady = false
            val uri = Uri.parse(url)
            if (Util.inferContentType(uri) == C.CONTENT_TYPE_OTHER) {
                probes.execute {
                    val ignored = ignoresRanges(url)
                    Log.i(TAG, if (ignored) "server cannot jump" else "server can jump")
                    main.post { if (!released) open(uri, ignored) }
                }
            } else {
                open(uri, false)
            }
        }

        private fun open(uri: Uri, ignoresRanges: Boolean) {
            rangeless = ignoresRanges
            val extractors = DefaultExtractorsFactory()
            if (ignoresRanges) extractors.setMatroskaExtractorFlags(MatroskaExtractor.FLAG_DISABLE_SEEK_FOR_CUES)
            val data = DefaultDataSource.Factory(
                context,
                DefaultHttpDataSource.Factory()
                    .setUserAgent(USER_AGENT)
                    .setAllowCrossProtocolRedirects(true),
            )
            exo.setMediaSource(DefaultMediaSourceFactory(data, extractors).createMediaSource(MediaItem.fromUri(uri)))
            exo.prepare()
            send()
        }

        fun select(type: Int, track: String?) {
            val builder = exo.trackSelectionParameters.buildUpon()
            if (track == null) {
                builder.clearOverridesOfType(type).setTrackTypeDisabled(type, true)
            } else {
                val parts = track.split(":")
                val group = exo.currentTracks.groups.getOrNull(parts[0].toIntOrNull() ?: -1) ?: return
                val index = parts.getOrNull(1)?.toIntOrNull() ?: return
                if (group.type != type || index !in 0 until group.length) return
                builder.setTrackTypeDisabled(type, false)
                    .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, index))
            }
            exo.trackSelectionParameters = builder.build()
        }

        fun release() {
            released = true
            exo.removeListener(this)
            exo.removeAnalyticsListener(this)
            exo.release()
            surface.release()
        }

        private fun send() {
            val size = exo.videoSize
            val width = if (size.pixelWidthHeightRatio > 0f) size.width * size.pixelWidthHeightRatio else size.width.toFloat()
            channel.invokeMethod(
                "state",
                mapOf(
                    "id" to id,
                    "ready" to ready,
                    "buffering" to (exo.playbackState == Player.STATE_BUFFERING),
                    "playing" to exo.playWhenReady,
                    "failed" to failed,
                    "live" to exo.isCurrentMediaItemLive,
                    "seekable" to (!rangeless && exo.isCurrentMediaItemSeekable),
                    "rangeless" to rangeless,
                    "durationMs" to exo.duration.let { if (it == C.TIME_UNSET) -1L else it },
                    "width" to width.toDouble(),
                    "height" to size.height.toDouble(),
                    "audio" to tracks(exo.currentTracks, C.TRACK_TYPE_AUDIO),
                    "subtitles" to tracks(exo.currentTracks, C.TRACK_TYPE_TEXT),
                ),
            )
        }

        private fun tracks(current: Tracks, type: Int): List<Map<String, Any?>> {
            val out = ArrayList<Map<String, Any?>>()
            current.groups.forEachIndexed { groupIndex, group ->
                if (group.type != type) return@forEachIndexed
                for (index in 0 until group.length) {
                    val format = group.getTrackFormat(index)
                    if (!group.isTrackSupported(index) || isPicture(format)) continue
                    out.add(
                        mapOf(
                            "id" to "$groupIndex:$index",
                            "label" to label(format),
                            "detail" to detail(format),
                            "selected" to group.isTrackSelected(index),
                        ),
                    )
                }
            }
            return out
        }

        private fun isPicture(format: Format): Boolean {
            val mime = format.codecs ?: format.sampleMimeType
            return mime == MimeTypes.APPLICATION_PGS ||
                mime == MimeTypes.APPLICATION_VOBSUB ||
                mime == MimeTypes.APPLICATION_DVBSUBS
        }

        private fun label(format: Format): String? {
            val named = format.label?.takeIf { it.isNotBlank() }
            if (named != null) return named
            val language = format.language?.takeIf { it.isNotBlank() && it != C.LANGUAGE_UNDETERMINED } ?: return null
            return Locale.forLanguageTag(language).displayName.takeIf { it.isNotBlank() } ?: language
        }

        private fun detail(format: Format): String? = when {
            format.channelCount == 6 -> "5.1"
            format.channelCount == 8 -> "7.1"
            else -> null
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_READY) ready = true
            Log.i(TAG, "state $playbackState at ${exo.currentPosition} buffered ${exo.bufferedPosition}")
            send()
        }

        override fun onVideoInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: Format,
            decoderReuseEvaluation: DecoderReuseEvaluation?,
        ) {
            Log.i(TAG, "video ${format.codecs} ${format.width}x${format.height} ${format.bitrate}bps ${format.colorInfo?.toLogString()}")
        }

        override fun onRenderedFirstFrame(eventTime: AnalyticsListener.EventTime, output: Any, renderTimeMs: Long) {
            Log.i(TAG, "first frame shown")
        }

        override fun onDroppedVideoFrames(eventTime: AnalyticsListener.EventTime, droppedFrames: Int, elapsedMs: Long) {
            Log.i(TAG, "dropped $droppedFrames frames in ${elapsedMs}ms")
        }

        override fun onBandwidthEstimate(
            eventTime: AnalyticsListener.EventTime,
            totalLoadTimeMs: Int,
            totalBytesLoaded: Long,
            bitrateEstimate: Long,
        ) {
            Log.i(TAG, "loaded ${totalBytesLoaded / 1048576}MB in ${totalLoadTimeMs}ms, ${bitrateEstimate / 1000000}Mbps, buffered ${exo.bufferedPosition}")
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) = send()

        override fun onTimelineChanged(timeline: Timeline, reason: Int) = send()

        override fun onVideoSizeChanged(videoSize: VideoSize) = send()

        override fun onTracksChanged(tracks: Tracks) = send()

        override fun onPlayerError(error: PlaybackException) {
            Log.w(TAG, "playback error ${error.errorCodeName}")
            failed = true
            send()
        }

        override fun onCues(cueGroup: CueGroup) {
            channel.invokeMethod(
                "cues",
                mapOf("id" to id, "lines" to cueGroup.cues.mapNotNull { it.text?.toString() }),
            )
        }

        override fun onAudioInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: Format,
            decoderReuseEvaluation: DecoderReuseEvaluation?,
        ) {
            Log.i(TAG, "audio ${format.sampleMimeType} ${format.channelCount}ch")
        }

        override fun onAudioDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializedTimestampMs: Long,
            initializationDurationMs: Long,
        ) {
            Log.i(TAG, "audio decoder $decoderName")
        }

        override fun onVideoDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializedTimestampMs: Long,
            initializationDurationMs: Long,
        ) {
            Log.i(TAG, "video decoder $decoderName")
        }
    }

    companion object {
        const val CHANNEL = "our_space/watch_player"
        private const val TAG = "WatchPlayer"
        private const val MAX_HOPS = 5
        private const val PROBE_TIMEOUT_MS = 8000
        private const val USER_AGENT = "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36"
    }
}
