package com.ourspace.our_space_mobile

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private var watchPlayers: WatchPlayerChannel? = null
    private var reminders: RemindersChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NotificationChannels.create(this)
        QuickUnlockChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        SystemSettingsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        AppUpdateChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        reminders = RemindersChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        watchPlayers = WatchPlayerChannel(this, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        reminders?.deliver(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        reminders = null
        watchPlayers?.dispose()
        watchPlayers = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
