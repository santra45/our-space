package com.ourspace.our_space_mobile

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

data class Reminder(
    val id: String,
    val at: Long,
    val title: String,
    val body: String,
    val route: String,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("at", at)
        .put("title", title)
        .put("body", body)
        .put("route", route)

    companion object {
        const val MAX_ID = 64
        const val MAX_TEXT = 160
        const val MAX_ROUTE = 200

        fun from(raw: Any?): Reminder? {
            val map = raw as? Map<*, *> ?: return null
            val id = map["id"] as? String ?: return null
            val at = (map["at"] as? Number)?.toLong() ?: return null
            val title = map["title"] as? String ?: return null
            val body = map["body"] as? String ?: ""
            val route = map["route"] as? String ?: ""
            if (id.isEmpty() || id.length > MAX_ID || title.isEmpty()) return null
            if (title.length > MAX_TEXT || body.length > MAX_TEXT || route.length > MAX_ROUTE) return null
            return Reminder(id, at, title, body, route)
        }

        fun fromJson(json: JSONObject): Reminder? =
            try {
                Reminder(
                    json.getString("id"),
                    json.getLong("at"),
                    json.getString("title"),
                    json.optString("body", ""),
                    json.optString("route", ""),
                )
            } catch (e: Exception) {
                null
            }
    }
}

object ReminderStore {
    private const val PREFS = "our_space_reminders"
    private const val KEY = "plan"

    fun load(context: Context): List<Reminder> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { Reminder.fromJson(array.getJSONObject(it)) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun save(context: Context, reminders: List<Reminder>) {
        val array = JSONArray()
        reminders.forEach { array.put(it.toJson()) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, array.toString()).apply()
    }
}

object ReminderAlarms {
    const val ACTION_FIRE = "com.ourspace.our_space_mobile.REMINDER"
    const val EXTRA_ID = "reminder_id"
    const val EXTRA_ROUTE = "our_space_route"
    const val MAX_PLANNED = 64

    private fun alarmIntent(context: Context, id: String, create: Boolean): PendingIntent? {
        val intent = Intent(context, ReminderReceiver::class.java)
            .setAction(ACTION_FIRE)
            .setData(Uri.parse("ourspace://reminder/${Uri.encode(id)}"))
            .putExtra(EXTRA_ID, id)
        var flags = PendingIntent.FLAG_IMMUTABLE
        flags = flags or if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    fun arm(context: Context, reminder: Reminder) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = alarmIntent(context, reminder.id, true) ?: return
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, reminder.at, pending)
    }

    fun disarm(context: Context, id: String) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = alarmIntent(context, id, false) ?: return
        manager.cancel(pending)
        pending.cancel()
    }

    fun replace(context: Context, wanted: List<Reminder>): Int {
        val now = System.currentTimeMillis()
        val next = wanted.filter { it.at > now }.sortedBy { it.at }.distinctBy { it.id }.take(MAX_PLANNED)
        ReminderStore.load(context).forEach { disarm(context, it.id) }
        next.forEach { arm(context, it) }
        ReminderStore.save(context, next)
        return next.size
    }

    fun rearm(context: Context) {
        val now = System.currentTimeMillis()
        val kept = ReminderStore.load(context).filter { it.at > now }
        kept.forEach { arm(context, it) }
        ReminderStore.save(context, kept)
    }

    fun canNotify(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
            if (granted != PackageManager.PERMISSION_GRANTED) return false
        }
        return true
    }

    fun show(context: Context, reminder: Reminder) {
        if (!canNotify(context)) return
        val open = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("ourspace://open/${Uri.encode(reminder.id)}"))
            .putExtra(EXTRA_ROUTE, reminder.route)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = PendingIntent.getActivity(
            context,
            0,
            open,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, context.getString(R.string.notification_channel_reminders))
            .setSmallIcon(R.drawable.ic_stat_our_space)
            .setColor(ContextCompat.getColor(context, R.color.notification_accent))
            .setContentTitle(reminder.title)
            .setContentText(reminder.body)
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        try {
            NotificationManagerCompat.from(context).notify("reminder:${reminder.id}", 0, notification)
        } catch (e: SecurityException) {
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ReminderAlarms.ACTION_FIRE) return
        val id = intent.getStringExtra(ReminderAlarms.EXTRA_ID) ?: return
        val plan = ReminderStore.load(context)
        val reminder = plan.firstOrNull { it.id == id } ?: return
        ReminderStore.save(context, plan.filter { it.id != id })
        NotificationChannels.create(context)
        ReminderAlarms.show(context, reminder)
    }
}

class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> ReminderAlarms.rearm(context)
        }
    }
}

class RemindersChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private var pendingRoute: String? = null

    init {
        channel.setMethodCallHandler(this)
        pendingRoute = routeOf(activity.intent)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "plan" -> {
                val list = (call.arguments as? List<*>)?.mapNotNull { Reminder.from(it) } ?: emptyList()
                result.success(ReminderAlarms.replace(activity, list))
            }
            "canNotify" -> result.success(ReminderAlarms.canNotify(activity))
            "askPermission" -> result.success(askPermission())
            "takeRoute" -> {
                val route = pendingRoute
                pendingRoute = null
                result.success(route)
            }
            else -> result.notImplemented()
        }
    }

    private fun askPermission(): Boolean {
        if (ReminderAlarms.canNotify(activity)) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS)
            if (granted != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
                return false
            }
        }
        val settings = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        try {
            activity.startActivity(settings)
        } catch (e: Exception) {
        }
        return false
    }

    fun deliver(intent: Intent?) {
        val route = routeOf(intent) ?: return
        intent?.removeExtra(ReminderAlarms.EXTRA_ROUTE)
        channel.invokeMethod("open", route)
    }

    private fun routeOf(intent: Intent?): String? {
        val route = intent?.getStringExtra(ReminderAlarms.EXTRA_ROUTE) ?: return null
        return route.ifEmpty { null }
    }

    companion object {
        const val CHANNEL = "our_space/reminders"
        const val PERMISSION_REQUEST = 7041
    }
}
