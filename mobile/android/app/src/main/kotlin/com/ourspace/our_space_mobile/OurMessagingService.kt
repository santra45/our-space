package com.ourspace.our_space_mobile

import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class OurMessagingService : FlutterFirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        val data = remoteMessage.data
        if (data["style"] != RICH) return
        if (OurNotifications.appOnScreen(this)) return
        val title = data["title"]?.take(MAX_TEXT)
        if (title.isNullOrBlank()) return
        val body = data["body"]?.take(MAX_TEXT) ?: ""
        val ring = data["ring"] ?: ""
        val channel = when (data["channel"]) {
            getString(R.string.notification_channel_film_invites) -> getString(R.string.notification_channel_film_invites)
            else -> getString(R.string.notification_channel_little_things)
        }
        val tag = data["tag"]?.takeIf { TAG.matches(it) } ?: "our-space-new"
        OurNotifications.show(
            this,
            tag = tag,
            channel = channel,
            title = title,
            body = body,
            route = routeFor(ring),
            category = if (ring == "watch") NotificationCompat.CATEGORY_EVENT else NotificationCompat.CATEGORY_SOCIAL,
            at = remoteMessage.sentTime.takeIf { it > 0 } ?: System.currentTimeMillis(),
        )
    }

    private fun routeFor(ring: String): String = when (ring) {
        "answer" -> "daily"
        "watch" -> ""
        else -> "away"
    }

    companion object {
        const val RICH = "rich"
        const val MAX_TEXT = 160
        private val TAG = Regex("^our-space-[a-z]{1,16}$")
    }
}
