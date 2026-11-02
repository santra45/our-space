package com.ourspace.our_space_mobile

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private var watchPlayers: WatchPlayerChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        QuickUnlockChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        SystemSettingsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        watchPlayers = WatchPlayerChannel(this, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        watchPlayers?.dispose()
        watchPlayers = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
