package com.ourspace.our_space_mobile

import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

object OurNotifications {
    const val GROUP = "com.ourspace.our_space_mobile.TOGETHER"
    const val EXTRA_ROUTE = "our_space_route"
    private const val SUMMARY_TAG = "our-space-summary"
    private const val MAX_LINES = 5

    fun canNotify(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
            if (granted != PackageManager.PERMISSION_GRANTED) return false
        }
        return true
    }

    fun appOnScreen(context: Context): Boolean {
        val state = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(state)
        return state.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    }

    private fun openIntent(context: Context, key: String, route: String): PendingIntent {
        val open = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("ourspace://open/${Uri.encode(key)}"))
            .putExtra(EXTRA_ROUTE, route)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            0,
            open,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    fun show(
        context: Context,
        tag: String,
        channel: String,
        title: String,
        body: String,
        route: String,
        category: String,
        at: Long = System.currentTimeMillis(),
    ) {
        if (!canNotify(context)) return
        NotificationChannels.create(context)
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_our_space)
            .setColor(ContextCompat.getColor(context, R.color.notification_accent))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().setBigContentTitle(title).bigText(body))
            .setWhen(at)
            .setShowWhen(true)
            .setCategory(category)
            .setGroup(GROUP)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion(context, channel))
            .setContentIntent(openIntent(context, tag, route))
        try {
            NotificationManagerCompat.from(context).notify(tag, 0, builder.build())
            summarize(context, channel)
        } catch (e: SecurityException) {
        }
    }

    private fun publicVersion(context: Context, channel: String): Notification =
        NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_our_space)
            .setColor(ContextCompat.getColor(context, R.color.notification_accent))
            .setContentTitle(context.getString(R.string.notification_public_title))
            .build()

    private fun summarize(context: Context, channel: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val ours = manager.activeNotifications.filter {
            it.notification.group == GROUP && it.tag != SUMMARY_TAG
        }
        if (ours.size < 2) {
            NotificationManagerCompat.from(context).cancel(SUMMARY_TAG, 0)
            return
        }
        val lines = NotificationCompat.InboxStyle()
            .setSummaryText(context.resources.getQuantityString(R.plurals.notification_summary, ours.size, ours.size))
        ours.sortedByDescending { it.postTime }.take(MAX_LINES).forEach { item ->
            val title = item.notification.extras.getCharSequence(Notification.EXTRA_TITLE)
            if (!title.isNullOrBlank()) lines.addLine(title)
        }
        val summary = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_our_space)
            .setColor(ContextCompat.getColor(context, R.color.notification_accent))
            .setContentTitle(context.getString(R.string.notification_summary_title))
            .setContentText(context.resources.getQuantityString(R.plurals.notification_summary, ours.size, ours.size))
            .setStyle(lines)
            .setGroup(GROUP)
            .setGroupSummary(true)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(openIntent(context, SUMMARY_TAG, "away"))
        try {
            NotificationManagerCompat.from(context).notify(SUMMARY_TAG, 0, summary.build())
        } catch (e: SecurityException) {
        }
    }
}
