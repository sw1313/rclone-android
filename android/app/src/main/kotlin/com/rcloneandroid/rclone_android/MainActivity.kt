package com.rcloneandroid.rclone_android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var bridge: NativeBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = NativeBridge(this)
        bridge.attach(flutterEngine)
    }

    // 根页面返回时不要 finish 整个 Activity，只退到后台，避免小米上“返回即退出”。
    override fun finish() {
        moveTaskToBack(true)
    }
}
