package com.ourspace.our_space_mobile

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        QuickUnlockChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        SystemSettingsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
