package com.ourspace.our_space_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

object NotificationChannels {
    private val HEARTBEAT = longArrayOf(0, 120, 120, 200)

    fun create(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        val littleThings = NotificationChannel(
            context.getString(R.string.notification_channel_little_things),
            context.getString(R.string.notification_little_things_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        )
        littleThings.description = context.getString(R.string.notification_little_things_description)

        val filmInvites = NotificationChannel(
            context.getString(R.string.notification_channel_film_invites),
            context.getString(R.string.notification_film_invites_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        filmInvites.description = context.getString(R.string.notification_film_invites_description)
        filmInvites.enableVibration(true)
        filmInvites.vibrationPattern = HEARTBEAT

        manager.createNotificationChannels(listOf(littleThings, filmInvites))
    }
}
