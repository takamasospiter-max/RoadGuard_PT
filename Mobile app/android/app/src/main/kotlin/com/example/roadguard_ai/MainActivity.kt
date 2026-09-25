package com.example.roadguard_ai

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "roadguard/device_sensors")
            .setMethodCallHandler { call, result ->
                if (call.method != "deviceCapabilities") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val manager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
                result.success(
                    mapOf(
                        "accelerometer" to (manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null),
                        "gyroscope" to (manager.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null),
                        "camera" to packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
                    ),
                )
            }
    }
}
