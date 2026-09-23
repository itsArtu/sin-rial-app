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
import android.provider.Settings
import android.view.View
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

open class MainActivity : FlutterFragmentActivity() {
    protected open val quickAccess: Boolean = false
    private var loadedRevision: Long? = null
    private val channelName = "rial/native_state"
    private var screenReceiver: BroadcastReceiver? = null
    private var screenOffPending = false
    private val screenPrivacy by lazy { ScreenPrivacyController(this) }
    private var pdfResult: MethodChannel.Result? = null
    private var pdfBytes: ByteArray? = null
    private val createPdf = registerForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        val bytes = pdfBytes
        pdfBytes = null
        if (uri == null || bytes == null) {
            pdfResult?.success(false)
            pdfResult = null
        } else {
            val resolver = applicationContext.contentResolver
            Thread {
                val error = runCatching {
                    val stream = resolver.openOutputStream(uri, "wt") ?: error("No output stream")
                    stream.use { it.write(bytes) }
                }.exceptionOrNull()
                runOnUiThread {
                    if (error == null) pdfResult?.success(true)
                    else pdfResult?.error("PDF_SAVE_FAILED", "No se pudo guardar el PDF", null)
                    pdfResult = null
                }
            }.start()
        }
    }

    companion object {
        private val stateExecutor = Executors.newSingleThreadExecutor()
        const val ACTION_WIDGET_MOVEMENT = "com.lacaprichosa.app.WIDGET_MOVEMENT"
        const val EXTRA_WIDGET_MOVEMENT_TYPE = "movement_type"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        screenPrivacy.onResume()
        stateExecutor.execute {
            runCatching { DailyReminderScheduler.schedule(applicationContext) }
            runCatching { RateUpdateScheduler.schedule(applicationContext) }
        }
        storeLaunchAction(intent)
        registerScreenOffReceiver()
        if (!quickAccess && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1907)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        storeLaunchAction(intent)
    }

    override fun onResume() {
        super.onResume()
        screenPrivacy.onResume()
        stateExecutor.execute { runCatching { DailyReminderScheduler.schedule(applicationContext) } }
    }

    override fun onPause() {
        screenPrivacy.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        pdfResult?.error("PDF_INTERRUPTED", "La exportacion fue interrumpida", null)
        pdfResult = null
        pdfBytes = null
        screenReceiver?.let { unregisterReceiver(it) }
        screenReceiver = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method in setOf("readState", "readRateState", "stateChanged", "writeState", "writeSplitState", "configureSecurity", "verifyPin")) {
                stateExecutor.execute {
                    try {
                        val response: Any = when (call.method) {
                            "readState" -> NativeJsonStore.readUiState(this).let { (state, revision) ->
                                loadedRevision = revision
                                state
                            }
                            "stateChanged" -> loadedRevision != NativeJsonStore.uiRevision(this)
                            "readRateState" -> NativeJsonStore.readMain(this).toString()
                            "configureSecurity" -> PinSecurity.configure(this,
                                requireNotNull(call.argument<String>("pin")), call.argument<Boolean>("biometrics") == true)
                            "verifyPin" -> PinSecurity.verify(this, call.argument<String>("pin") ?: "")
                            else -> {
                                val state = requireNotNull(call.argument<String>("state"))
                                val revision = requireNotNull(loadedRevision) { "Read state before writing" }
                                loadedRevision = if (call.method == "writeState") NativeJsonStore.writeState(this, state, revision)
                                else NativeJsonStore.writeSplitState(this, state,
                                    call.argument<Map<String, String>>("parts") ?: emptyMap(), revision)
                                runCatching { DailyReminderScheduler.schedule(this) }
                                runCatching { RateUpdateScheduler.schedule(this) }
                                runCatching { MovementWidgetProvider.updateAll(this) }
                                runCatching { UsdRateWidgetProvider.updateAll(this) }
                                runCatching { EurRateWidgetProvider.updateAll(this) }
                                runCatching { CalculatorWidgetProvider.updateAll(this) }
                                true
                            }
                        }
                        runOnUiThread { result.success(response) }
                    } catch (_: NativeJsonStore.StaleStateException) {
                        runOnUiThread { result.error("STATE_CONFLICT", "Los datos cambiaron en otra ventana. Vuelve a cargar antes de guardar.", null) }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("SECURE_STORAGE_UNAVAILABLE", "No se pudo acceder al almacenamiento protegido. Tus datos no se han borrado.", null) }
                    }
                }
                return@setMethodCallHandler
            }
            val prefs = NativeJsonStore.prefs(this)
            when (call.method) {
                "quickAction" -> result.success(if (quickAccess) QuickAccessActivity.actionFrom(intent) else null)
                "closeQuickAccess" -> {
                    result.success(quickAccess)
                    if (quickAccess) finishAndRemoveTask()
                }
                "openFullApp" -> {
                    result.success(true)
                    startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    if (quickAccess) finishAndRemoveTask()
                }
                "setScreenPrivacy" -> {
                    screenPrivacy.update(
                        locked = call.argument<Boolean>("locked") != false,
                        hideInBackground = call.argument<Boolean>("hideInBackground") == true,
                        suspended = call.argument<Boolean>("suspended") == true
                    )
                    result.success(true)
                }
                "exportBudgetPdf" -> {
                    if (pdfResult != null) {
                        result.error("PDF_BUSY", "Ya hay una exportacion en curso", null)
                    } else {
                        try {
                            pdfBytes = requireNotNull(call.argument<ByteArray>("bytes"))
                            require(pdfBytes!!.size >= 5 && String(pdfBytes!!, 0, 5, Charsets.US_ASCII) == "%PDF-")
                            pdfResult = result
                            val name = call.argument<String>("name") ?: "Sin-Rial-presupuesto.pdf"
                            createPdf.launch(name.replace(Regex("[^a-zA-Z0-9.\\-]"), "_"))
                        } catch (_: Exception) {
                            pdfBytes = null
                            pdfResult = null
                            result.error("PDF_UNAVAILABLE", "No se pudo abrir el selector de archivos", null)
                        }
                    }
                }
                "scheduleDailyReminder" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val hour = (call.argument<Number>("hour")?.toInt() ?: 19).coerceIn(0, 23)
                    val minute = (call.argument<Number>("minute")?.toInt() ?: 0).coerceIn(0, 59)
                    DailyReminderScheduler.schedule(this, enabled, hour, minute)
                    result.success(true)
                }
                "scheduleRateUpdate" -> {
                    result.success(RateUpdateScheduler.schedule(this))
                }
                "dailyReminderStatus" -> result.success(DailyReminderScheduler.status(this))
                "openReminderSettings" -> {
                    val exact = call.argument<Boolean>("exact") == true
                    val settingsIntent = if (exact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        if (manager.areNotificationsEnabled()) {
                            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                .putExtra(Settings.EXTRA_CHANNEL_ID, DailyReminderScheduler.CHANNEL_ID)
                        } else {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                    }
                    result.success(runCatching { startActivity(settingsIntent); true }.getOrDefault(false))
                }
                "workManagerStatus" -> {
                    result.success(
                        mapOf(
                            "available" to prefs.getBoolean("work_manager_available", true),
                            "lastCheckMillis" to prefs.getLong("work_manager_last_check_millis", 0L),
                            "lastError" to prefs.getString("work_manager_last_error", "")
                        )
                    )
                }
                "consumeScreenOff" -> {
                    val wasOff = screenOffPending || prefs.getBoolean("screen_off_pending", false)
                    screenOffPending = false
                    prefs.edit().putBoolean("screen_off_pending", false).apply()
                    result.success(wasOff)
                }
                "consumeLaunchAction" -> {
                    if (quickAccess) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
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
                "pinHomeWidget" -> {
                    result.success(WidgetPinning.request(this, call.argument<String>("type")))
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")?.trim().orEmpty()
                    val uri = Uri.parse(url)
                    if (uri.scheme != "https" || uri.host.isNullOrBlank() || !uri.userInfo.isNullOrEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val opened = runCatching {
                        startActivity(
                            Intent(Intent.ACTION_VIEW, uri).apply {
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
                    screenOffPending = true
                    NativeJsonStore.prefs(context)
                        .edit()
                        .putBoolean("screen_off_pending", true)
                        .apply()
                }
            }
        }
        registerReceiver(screenReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    private fun storeLaunchAction(intent: Intent?) {
        if (quickAccess) return
        if (intent?.action != ACTION_WIDGET_MOVEMENT) return
        val type = intent.getStringExtra(EXTRA_WIDGET_MOVEMENT_TYPE) ?: return
        if (type != "expense" && type != "income" && type != "transfer" && type != "account") return
        NativeJsonStore.prefs(this)
            .edit()
            .putString("launch_action", type)
            .apply()
    }

    private fun applySystemBars(dark: Boolean, color: Int) {
        window.statusBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
        }
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
