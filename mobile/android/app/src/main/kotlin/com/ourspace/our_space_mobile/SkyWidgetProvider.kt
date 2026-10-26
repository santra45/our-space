package com.ourspace.our_space_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

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
        val views = RemoteViews(context.packageName, R.layout.sky_widget).apply {
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
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
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
}
