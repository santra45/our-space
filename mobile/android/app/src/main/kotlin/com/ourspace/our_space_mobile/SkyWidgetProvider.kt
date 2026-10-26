package com.ourspace.our_space_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.min
import kotlin.math.roundToInt

class SkyWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val sky = image(widgetData, "sky_widget_sky")
        val stars = if (sky == null) null else image(widgetData, "sky_widget_stars")
        val night = sky == null || widgetData.getBoolean("sky_widget_night", true)
        val label = if (sky == null) null else widgetData.getString("sky_widget_label", null)
        val square = if (roundsItself) null else sky ?: BitmapFactory.decodeResource(context.resources, R.drawable.sky_widget_empty)
        val radius = context.resources.getDimension(R.dimen.sky_widget_radius) / context.resources.displayMetrics.density
        appWidgetIds.forEach { id ->
            val views = if (square == null) {
                views(context, sky, stars, night, label)
            } else {
                val options = appWidgetManager.getAppWidgetOptions(id)
                val portrait = rounded(square, radius, options, AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
                val landscape = rounded(square, radius, options, AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                RemoteViews(views(context, landscape, stars, night, label), views(context, portrait, stars, night, label))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        if (!roundsItself) onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    private val roundsItself: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

    private fun views(context: Context, sky: Bitmap?, stars: Bitmap?, night: Boolean, label: String?) =
        RemoteViews(context.packageName, R.layout.sky_widget).apply {
            if (sky != null) {
                setImageViewBitmap(R.id.sky_widget_sky, sky)
            } else {
                setImageViewResource(R.id.sky_widget_sky, R.drawable.sky_widget_empty)
            }
            if (stars != null) setImageViewBitmap(R.id.sky_widget_stars, stars)
            setViewVisibility(R.id.sky_widget_stars, if (stars != null) View.VISIBLE else View.GONE)
            setTextViewText(R.id.sky_widget_label, label ?: context.getString(R.string.sky_widget_empty))
            setTextColor(
                R.id.sky_widget_label,
                context.getColor(if (night) R.color.sky_widget_night_text else R.color.sky_widget_day_text),
            )
            setOnClickPendingIntent(R.id.sky_widget, open(context))
        }

    private fun rounded(source: Bitmap, radius: Float, options: Bundle, widthKey: String, heightKey: String): Bitmap {
        val width = options.getInt(widthKey).takeIf { it > 0 }?.toFloat() ?: FALLBACK_SIDE
        val height = options.getInt(heightKey).takeIf { it > 0 }?.toFloat() ?: FALLBACK_SIDE
        val scale = min(source.width / width, source.height / height)
        val out = Bitmap.createBitmap(
            (width * scale).roundToInt().coerceAtLeast(1),
            (height * scale).roundToInt().coerceAtLeast(1),
            Bitmap.Config.ARGB_8888,
        )
        val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
            setLocalMatrix(Matrix().apply { setTranslate((out.width - source.width) / 2f, (out.height - source.height) / 2f) })
        }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply { this.shader = shader }
        Canvas(out).drawRoundRect(RectF(0f, 0f, out.width.toFloat(), out.height.toFloat()), radius * scale, radius * scale, paint)
        return out
    }

    private fun image(data: SharedPreferences, key: String): Bitmap? =
        data.getString(key, null)?.let { runCatching { BitmapFactory.decodeFile(it) }.getOrNull() }

    private fun open(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private companion object {
        const val FALLBACK_SIDE = 110f
    }
}
