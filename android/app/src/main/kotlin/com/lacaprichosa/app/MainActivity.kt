package com.lacaprichosa.app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsetsController
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "rial/native_state"
    private val storeName = "la_caprichosa_native_010"
    private var screenReceiver: BroadcastReceiver? = null

    companion object {
        const val ACTION_WIDGET_MOVEMENT = "com.lacaprichosa.app.WIDGET_MOVEMENT"
        const val EXTRA_WIDGET_MOVEMENT_TYPE = "movement_type"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DailyReminderScheduler.schedule(this)
        storeLaunchAction(intent)
        registerScreenOffReceiver()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1907)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        storeLaunchAction(intent)
    }

    override fun onDestroy() {
        screenReceiver?.let { unregisterReceiver(it) }
        screenReceiver = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(storeName, Context.MODE_PRIVATE)
            when (call.method) {
                "readState" -> result.success(prefs.getString("state", null))
                "writeState" -> {
                    val state = call.argument<String>("state") ?: "{}"
                    prefs.edit().putString("state", state).apply()
                    MovementWidgetProvider.updateAll(this)
                    UsdRateWidgetProvider.updateAll(this)
                    EurRateWidgetProvider.updateAll(this)
                    result.success(true)
                }
                "scheduleDailyReminder" -> {
                    DailyReminderScheduler.schedule(this)
                    result.success(true)
                }
                "consumeScreenOff" -> {
                    val wasOff = prefs.getBoolean("screen_off_pending", false)
                    prefs.edit().putBoolean("screen_off_pending", false).apply()
                    result.success(wasOff)
                }
                "consumeLaunchAction" -> {
                    val action = prefs.getString("launch_action", null)
                    prefs.edit().remove("launch_action").apply()
                    result.success(action)
                }
                "setSystemBars" -> {
                    val dark = call.argument<Boolean>("dark") ?: true
                    val color = (call.argument<Number>("color")?.toLong() ?: Color.BLACK.toLong()).toInt()
                    applySystemBars(dark, color)
                    result.success(true)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")?.trim().orEmpty()
                    if (url.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val opened = runCatching {
                        startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        )
                        true
                    }.getOrDefault(false)
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun registerScreenOffReceiver() {
        if (screenReceiver != null) return
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == Intent.ACTION_SCREEN_OFF) {
                    getSharedPreferences(storeName, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean("screen_off_pending", true)
                        .apply()
                }
            }
        }
        registerReceiver(screenReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    private fun storeLaunchAction(intent: Intent?) {
        if (intent?.action != ACTION_WIDGET_MOVEMENT) return
        val type = intent.getStringExtra(EXTRA_WIDGET_MOVEMENT_TYPE) ?: return
        if (type != "expense" && type != "income" && type != "transfer" && type != "account") return
        getSharedPreferences(storeName, Context.MODE_PRIVATE)
            .edit()
            .putString("launch_action", type)
            .apply()
    }

    private fun applySystemBars(dark: Boolean, color: Int) {
        window.statusBarColor = color
        window.navigationBarColor = color
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val mask = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            val appearance = if (dark) 0 else mask
            window.insetsController?.setSystemBarsAppearance(appearance, mask)
            return
        }

        var flags = window.decorView.systemUiVisibility
        flags = if (dark) {
            flags and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv()
        } else {
            flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            flags = if (dark) {
                flags and View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv()
            } else {
                flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            }
        }
        window.decorView.systemUiVisibility = flags
    }
}
