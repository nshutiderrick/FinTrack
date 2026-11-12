package dev.personal.expense_tracker

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "expense_tracker/alerts").setMethodCallHandler { call, result ->
            when (call.method) {
                "isListenerEnabled" -> result.success(Alerts.listenerEnabled(this))
                "openListenerSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "isCaptureOn" -> result.success(Alerts.captureOn(this))
                "setCapture" -> {
                    Alerts.setCapture(this, call.arguments as Boolean)
                    result.success(null)
                }
                "readCaptured" -> result.success(Alerts.readCaptured(this))
                "recentAlerts" -> result.success(Alerts.recent(this))
                "readLog" -> result.success(Alerts.readLog(this))
                "resetLocal" -> {
                    Alerts.resetLocal(this)
                    Popup.takeDecisions(this) // drops choices not yet saved
                    result.success(null)
                }
                // When this app was first installed on the phone (statements are read from that day on).
                "installedAt" -> result.success(packageManager.getPackageInfo(packageName, 0).firstInstallTime)
                "clearCaptured" -> {
                    Alerts.clearCaptured(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // The floating category pop-up: its switch, permissions, my settings for it, and the choices made in it.
        MethodChannel(messenger, "expense_tracker/popup_settings").setMethodCallHandler { call, result ->
            when (call.method) {
                "isOn" -> result.success(Popup.enabled(this))
                "setOn" -> {
                    Popup.setEnabled(this, call.arguments as Boolean)
                    result.success(null)
                }
                "canOverlay" -> result.success(Popup.canOverlay(this))
                "openOverlaySettings" -> {
                    startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:$packageName")))
                    result.success(null)
                }
                "requestNotifications" -> {
                    if (android.os.Build.VERSION.SDK_INT >= 33) {
                        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 7)
                    }
                    result.success(null)
                }
                "setConfig" -> {
                    Popup.setConfig(this, call.arguments as String)
                    result.success(null)
                }
                "takeDecisions" -> result.success(Popup.takeDecisions(this))
                else -> result.notImplemented()
            }
        }

        // Statement PDFs are read off the main thread; the text never leaves the phone.
        MethodChannel(messenger, "expense_tracker/pdf").setMethodCallHandler { call, result ->
            if (call.method != "text") return@setMethodCallHandler result.notImplemented()
            val path = call.arguments as String
            Thread {
                try {
                    val text = PdfText.read(this, path)
                    runOnUiThread { result.success(text) }
                } catch (e: com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException) {
                    runOnUiThread { result.error("password", "The PDF has a password", null) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("unreadable", e.message, null) }
                }
            }.start()
        }

        EventChannel(messenger, "expense_tracker/alerts/stream").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                Alerts.sink = events
            }

            override fun onCancel(arguments: Any?) {
                Alerts.sink = null
            }
        })
    }
}
