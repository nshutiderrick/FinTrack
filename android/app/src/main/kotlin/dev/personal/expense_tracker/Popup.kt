package dev.personal.expense_tracker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * The floating category pop-up (spec: Category Confirmation Popup).
 *
 * When a money alert arrives, this waits a few seconds (so the other half of a
 * transfer between my accounts can arrive too), then starts a small Flutter
 * engine running `popupMain` to decide, with the app's own parser, whether the
 * alert is an expense or income that needs a category. If it is:
 *  - with "Display over other apps" allowed, the card floats at the top of the screen;
 *  - otherwise a notification offers the 2 likely categories and More.
 * My choice is stored on the phone and the app saves it when it next opens.
 */
object Popup {
    private const val TAG = "Popup"
    private const val PREFS = "popup"
    private const val CHANNEL_ID = "categories"
    private const val SETTLE_MS = 20_000L
    private val main = Handler(Looper.getMainLooper())

    private val queue = ArrayDeque<JSONObject>()
    private var engine: FlutterEngine? = null
    private var view: FlutterView? = null
    private var busy = false

    // On by default in the daily app; off in the capture app so the two do not both pop up.
    fun enabled(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getBoolean("enabled", c.resources.getBoolean(R.bool.popup_default))

    fun setEnabled(c: Context, on: Boolean) =
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("enabled", on).apply()

    fun canOverlay(c: Context) = Settings.canDrawOverlays(c)

    /** Names, numbers and categories, written by the app (never uploaded from here). */
    fun setConfig(c: Context, json: String) =
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("config", json).apply()

    private fun config(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("config", "{}") ?: "{}"

    // ------------------------------------------------------------- decisions

    @Synchronized
    fun saveDecision(c: Context, d: JSONObject) {
        val prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = JSONArray(prefs.getString("decisions", "[]"))
        list.put(d)
        prefs.edit().putString("decisions", list.toString()).apply()
    }

    /** The choices made in pop-ups since the app last asked; they are removed here. */
    @Synchronized
    fun takeDecisions(c: Context): String {
        val prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = prefs.getString("decisions", "[]") ?: "[]"
        prefs.edit().remove("decisions").apply()
        return list
    }

    // ----------------------------------------------------------------- flow

    fun onAlert(c: Context, alert: JSONObject) {
        if (!enabled(c)) return
        val app = c.applicationContext
        main.postDelayed({
            queue.addLast(alert)
            next(app)
        }, SETTLE_MS)
    }

    private fun next(c: Context) {
        if (busy) return
        val alert = queue.removeFirstOrNull() ?: return
        busy = true
        try {
            evaluate(c, alert)
        } catch (e: Exception) {
            Log.w(TAG, "Pop-up failed", e)
            close(c)
        }
    }

    private fun evaluate(c: Context, alert: JSONObject) {
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(c)
            loader.ensureInitializationComplete(c, null)
        }
        val e = FlutterEngine(c)
        engine = e
        val channel = MethodChannel(e.dartExecutor.binaryMessenger, "expense_tracker/popup")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    result.success(null)
                    val args = mapOf(
                        "alert" to toMap(alert),
                        "recent" to toList(JSONArray(Alerts.recent(c))),
                        "config" to toMap(JSONObject(config(c))),
                    )
                    channel.invokeMethod("evaluate", args, object : MethodChannel.Result {
                        override fun success(item: Any?) {
                            @Suppress("UNCHECKED_CAST")
                            val m = item as? Map<String, Any?>
                            when {
                                m == null -> close(c)
                                canOverlay(c) -> show(c, e)
                                else -> {
                                    notify(c, m)
                                    close(c)
                                }
                            }
                        }

                        override fun error(code: String, msg: String?, details: Any?) = close(c)
                        override fun notImplemented() = close(c)
                    })
                }
                "resize" -> {
                    val h = (call.arguments as Number).toInt()
                    view?.let { v ->
                        val lp = v.layoutParams as WindowManager.LayoutParams
                        if (lp.height != h) {
                            lp.height = h
                            windowManager(c).updateViewLayout(v, lp)
                        }
                    }
                    result.success(null)
                }
                "decide" -> {
                    @Suppress("UNCHECKED_CAST")
                    saveDecision(c, JSONObject(call.arguments as Map<String, Any?>))
                    result.success(null)
                    close(c)
                }
                "dismiss" -> {
                    result.success(null)
                    close(c)
                }
                else -> result.notImplemented()
            }
        }
        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "popupMain"))
    }

    private fun windowManager(c: Context) = c.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    /** Floats the card at the top of the screen; touches elsewhere go to the app underneath. */
    private fun show(c: Context, e: FlutterEngine) {
        val texture = FlutterTextureView(c).apply { isOpaque = false }
        val v = FlutterView(c, texture)
        v.attachToFlutterEngine(e)
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            (360 * c.resources.displayMetrics.density).toInt(),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP
            y = statusBarHeight(c)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
        }
        windowManager(c).addView(v, lp)
        view = v
        e.lifecycleChannel.appIsResumed()
    }

    private fun statusBarHeight(c: Context): Int {
        val id = c.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) c.resources.getDimensionPixelSize(id) else 0
    }

    private fun close(c: Context) {
        view?.let { v ->
            try {
                v.detachFromFlutterEngine()
                windowManager(c).removeView(v)
            } catch (e: Exception) {
                Log.w(TAG, "Removing pop-up", e)
            }
        }
        view = null
        engine?.destroy()
        engine = null
        busy = false
        main.post { next(c) }
    }

    // --------------------------------------------------------- notification

    /** Fallback without the overlay permission: 2 likely categories and More (Android allows 3 buttons). */
    private fun notify(c: Context, item: Map<String, Any?>) {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Pick a category", NotificationManager.IMPORTANCE_HIGH))
        }
        val id = (item["alertId"] as String).hashCode()
        val amount = (item["amount"] as Number).toLong()
        val currency = item["currency"] as String
        val shown = if (currency == "RWF") "RWF %,d".format(amount / 100) else "%s %.2f".format(currency, amount / 100.0)
        val open = PendingIntent.getActivity(
            c, id, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = android.app.Notification.Builder(c, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("$shown · ${item["title"]}")
            .setContentText("${item["providerLabel"]} · Pick a category")
            .setContentIntent(open)
            .setAutoCancel(true)
        @Suppress("UNCHECKED_CAST")
        for ((i, cat) in (item["suggested"] as? List<String> ?: emptyList()).take(2).withIndex()) {
            val intent = Intent(c, PopupActionReceiver::class.java)
                .putExtra("notificationId", id)
                .putExtra("decision", JSONObject(mapOf(
                    "alertId" to item["alertId"], "category" to cat, "lent" to false,
                    "title" to item["title"], "amount" to item["amount"], "time" to item["time"],
                )).toString())
            val pi = PendingIntent.getBroadcast(c, id * 4 + i, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            b.addAction(android.app.Notification.Action.Builder(null as android.graphics.drawable.Icon?, cat, pi).build())
        }
        b.addAction(android.app.Notification.Action.Builder(null as android.graphics.drawable.Icon?, "More", open).build())
        try {
            nm.notify(id, b.build())
        } catch (e: SecurityException) {
            Log.w(TAG, "Notifications not allowed", e)
        }
    }

    private fun toMap(o: JSONObject): Map<String, Any?> = o.keys().asSequence().associateWith { k -> unwrap(o.get(k)) }
    private fun toList(a: JSONArray): List<Any?> = (0 until a.length()).map { unwrap(a.get(it)) }
    private fun unwrap(v: Any?): Any? = when (v) {
        is JSONObject -> toMap(v)
        is JSONArray -> toList(v)
        JSONObject.NULL -> null
        else -> v
    }
}

/** A category button on the fallback notification. */
class PopupActionReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        val d = intent.getStringExtra("decision") ?: return
        Popup.saveDecision(c, JSONObject(d))
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(intent.getIntExtra("notificationId", 0))
    }
}
