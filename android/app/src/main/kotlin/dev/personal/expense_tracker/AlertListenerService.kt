package dev.personal.expense_tracker

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import java.io.File

/**
 * Reads every notification the phone shows and keeps the money alerts:
 * SMS from M-Money / EQUITYBANK / AirtelMoney (shown by the messaging app)
 * and push notifications from the Equity app. Android keeps this service
 * bound once the user grants notification access.
 */
class AlertListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val alert = extract(sbn) ?: return
        if (!Alerts.isRelevant(alert)) return
        if (Alerts.captureOn(this)) Alerts.capture(this, alert)
        Alerts.log(this, alert)
        Alerts.remember(this, alert)
        Alerts.emit(alert)
        Popup.onAlert(this, alert)
    }

    private fun extract(sbn: StatusBarNotification): JSONObject? {
        val e = sbn.notification.extras
        val title = e.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        // Messaging apps put each SMS of a conversation in EXTRA_MESSAGES; the newest is last.
        @Suppress("DEPRECATION")
        val newest = e.getParcelableArray(Notification.EXTRA_MESSAGES)?.lastOrNull() as? Bundle
        val text = newest?.getCharSequence("text")?.toString()
            ?: e.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: e.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: return null
        return JSONObject()
            .put("package", sbn.packageName)
            .put("title", title)
            .put("text", text)
            .put("postedAt", sbn.postTime)
    }
}

object Alerts {
    private const val FILE = "captured_alerts.jsonl"
    private const val PREFS = "alerts"
    private val senders = setOf("M-Money", "EQUITYBANK", "AirtelMoney")
    private val mentionsRwf = Regex("""\b(RWF|Rwf|Frw)\b""")
    private val main = Handler(Looper.getMainLooper())

    /** Set while the Flutter app is listening; alerts are only captured otherwise. */
    @Volatile var sink: EventChannel.EventSink? = null

    fun isRelevant(a: JSONObject): Boolean =
        a.getString("title") in senders ||
            a.getString("package").contains("equity", ignoreCase = true) ||
            mentionsRwf.containsMatchIn(a.getString("text"))

    // On by default in the capture app, off in the daily app (see build.gradle.kts flavors).
    fun captureOn(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getBoolean("capture", c.resources.getBoolean(R.bool.capture_default))

    private const val RECENT_MAX = 50

    /**
     * The last [RECENT_MAX] alerts, kept in every build, so Home can show each
     * account's latest balance until the real database exists.
     */
    @Synchronized
    fun remember(c: Context, a: JSONObject) {
        val prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = org.json.JSONArray(prefs.getString("recent", "[]"))
        list.put(a)
        val trimmed = org.json.JSONArray()
        for (i in maxOf(0, list.length() - RECENT_MAX) until list.length()) trimmed.put(list.get(i))
        prefs.edit().putString("recent", trimmed.toString()).apply()
    }

    fun recent(c: Context): String =
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("recent", "[]") ?: "[]"

    fun setCapture(c: Context, on: Boolean) =
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("capture", on).apply()

    /** Private app storage only; never uploaded. */
    @Synchronized
    fun capture(c: Context, a: JSONObject) = File(c.filesDir, FILE).appendText(a.toString() + "\n")

    private const val LOG = "alerts_log.jsonl"

    /**
     * Every money alert, kept in every build, so the app can add the ones that
     * arrived while it was closed. Private app storage only; never uploaded.
     * Unlike the capture file, this one is not cleared from the app.
     */
    @Synchronized
    fun log(c: Context, a: JSONObject) = File(c.filesDir, LOG).appendText(a.toString() + "\n")

    /** "Erase all data": forget every alert seen so far (the capture file is left alone). */
    @Synchronized
    fun resetLocal(c: Context) {
        File(c.filesDir, LOG).delete()
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove("recent").apply()
    }

    @Synchronized
    fun readLog(c: Context): String = File(c.filesDir, LOG).let { if (it.exists()) it.readText() else "" }

    @Synchronized
    fun readCaptured(c: Context): String = File(c.filesDir, FILE).let { if (it.exists()) it.readText() else "" }

    @Synchronized
    fun clearCaptured(c: Context) {
        File(c.filesDir, FILE).delete()
    }

    fun emit(a: JSONObject) {
        main.post { sink?.success(a.toString()) }
    }

    fun listenerEnabled(c: Context): Boolean {
        val enabled = Settings.Secure.getString(c.contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.contains(ComponentName(c, AlertListenerService::class.java).flattenToString())
    }
}
