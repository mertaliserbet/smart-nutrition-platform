package com.example.smart_nutrition_mobile

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val reader = HealthRecordReader(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smart_nutrition/health_read")
            .setMethodCallHandler { call, result ->
                if (call.method == "read") reader.read(call, result)
                else result.notImplemented()
            }
    }
}
