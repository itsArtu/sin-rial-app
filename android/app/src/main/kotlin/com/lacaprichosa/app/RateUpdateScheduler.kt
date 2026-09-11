package com.lacaprichosa.app

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.concurrent.TimeUnit
import kotlin.math.abs

object SafeWorkManager {
    private const val TAG = "SinRialWorkManager"
    private const val PREF_AVAILABLE = "work_manager_available"
    private const val PREF_LAST_CHECK = "work_manager_last_check_millis"
    private const val PREF_LAST_ERROR = "work_manager_last_error"

    fun get(context: Context): WorkManager? {
        val appContext = context.applicationContext
        return try {
            val manager = WorkManager.getInstance(appContext)
            NativeJsonStore.prefs(appContext)
                .edit()
                .putBoolean(PREF_AVAILABLE, true)
                .putLong(PREF_LAST_CHECK, System.currentTimeMillis())
                .remove(PREF_LAST_ERROR)
                .apply()
            manager
        } catch (error: Throwable) {
            markUnavailable(appContext, error)
            null
        }
    }

    fun markUnavailable(context: Context, error: Throwable) {
        val message = "${error.javaClass.simpleName}: ${error.message.orEmpty()}".take(240)
        Log.w(TAG, "WorkManager unavailable", error)
        NativeJsonStore.prefs(context.applicationContext)
            .edit()
            .putBoolean(PREF_AVAILABLE, false)
            .putLong(PREF_LAST_CHECK, System.currentTimeMillis())
            .putString(PREF_LAST_ERROR, message)
            .apply()
    }
}

object RateUpdateScheduler {
    private const val WORK_NAME = "sin_rial_daily_rate_update"

    fun schedule(context: Context): Boolean {
        return enqueue(context, ExistingWorkPolicy.KEEP)
    }

    fun scheduleNext(context: Context): Boolean {
        return enqueue(context, ExistingWorkPolicy.APPEND_OR_REPLACE)
    }

    private fun enqueue(context: Context, policy: ExistingWorkPolicy): Boolean {
        val appContext = context.applicationContext
        val manager = SafeWorkManager.get(appContext) ?: return false
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val request = OneTimeWorkRequestBuilder<RateUpdateWorker>()
            .setInitialDelay(delayUntilNextSixAm(), TimeUnit.MILLISECONDS)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.HOURS)
            .build()
        return try {
            manager.enqueueUniqueWork(
                WORK_NAME,
                policy,
                request
            )
            true
        } catch (error: Throwable) {
            SafeWorkManager.markUnavailable(appContext, error)
            false
        }
    }

    private fun delayUntilNextSixAm(): Long {
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 6)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (calendar.timeInMillis <= System.currentTimeMillis()) {
            calendar.add(Calendar.DAY_OF_YEAR, 1)
        }
        return (calendar.timeInMillis - System.currentTimeMillis()).coerceAtLeast(0L)
    }
}

class RateUpdateWorker(
    context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {
    override fun doWork(): Result {
        val updated = RateUpdateService.update(applicationContext)
        if (!updated) return Result.retry()
        RateUpdateScheduler.scheduleNext(applicationContext)
        return Result.success()
    }
}

class RateUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        RateUpdateScheduler.schedule(context.applicationContext)
    }
}

object RateUpdateService {
    private const val ENDPOINT = "https://bcv.today/api/v1/rate.json"
    private const val UPDATE_ENDPOINT = "https://api.github.com/repos/itsArtu/sin-rial-app/releases/latest"
    private const val UPDATE_NOTIFICATION_ID = 2601

    fun update(context: Context): Boolean {
        val data = fetchRateJson() ?: return false
        val usd = extractUsdRate(data)
        if (usd <= 0.0) return false
        val eur = extractNamedRate(data, "EUR")
        val effectiveDate = data.optString("effective_date").ifBlank {
            data.optString("date").ifBlank { currentIsoDate() }
        }
        val updatedAt = data.optString("updated_at")
        val state = NativeJsonStore.readState(context)

        val oldUsd = state.optDouble("rate", 0.0)
        if (oldUsd > 0.0 && abs(oldUsd - usd) > 0.0001) {
            state.put("previousRate", oldUsd)
        }
        val oldEur = state.optDouble("eurRate", 0.0)
        if (eur > 0.0 && oldEur > 0.0 && abs(oldEur - eur) > 0.0001) {
            state.put("previousEurRate", oldEur)
        }

        state.put("rate", usd)
        state.put("lastRateDate", effectiveDate)
        state.put("rateEffectiveDate", effectiveDate)
        state.put("rateUpdatedAt", updatedAt)
        if (eur > 0.0) {
            state.put("eurRate", eur)
            state.put("eurRateEffectiveDate", effectiveDate)
            state.put("eurRateUpdatedAt", updatedAt)
        }
        state.put("lastRateMillis", System.currentTimeMillis())

        NativeJsonStore.writeState(context, state.toString())
        UsdRateWidgetProvider.updateAll(context)
        EurRateWidgetProvider.updateAll(context)
        checkReleaseUpdate(context)
        return true
    }

    private fun fetchRateJson(): JSONObject? {
        val connection = (URL(ENDPOINT).openConnection() as? HttpURLConnection) ?: return null
        return try {
            connection.connectTimeout = 8000
            connection.readTimeout = 10000
            connection.requestMethod = "GET"
            connection.setRequestProperty("Accept", "application/json")
            if (connection.responseCode !in 200..299) return null
            val body = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            JSONObject(body)
        } catch (_: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    private fun extractUsdRate(data: JSONObject): Double {
        val named = extractNamedRate(data, "USD")
        if (named > 0.0) return named
        val dollar = data.optJSONObject("dollar") ?: return 0.0
        for (key in listOf("rate", "value", "price")) {
            val value = numberValue(dollar.opt(key))
            if (value > 0.0) return value
        }
        return 0.0
    }

    private fun extractNamedRate(data: JSONObject, code: String): Double {
        for (key in listOf(code, code.lowercase())) {
            val direct = numberValue(data.opt(key))
            if (direct > 0.0) return direct
        }
        for (groupKey in listOf("rates", "currencies")) {
            val group = data.optJSONObject(groupKey) ?: continue
            val item = group.opt(code) ?: group.opt(code.lowercase())
            val direct = numberValue(item)
            if (direct > 0.0) return direct
            if (item is JSONObject) {
                for (key in listOf("rate", "value", "price")) {
                    val nested = numberValue(item.opt(key))
                    if (nested > 0.0) return nested
                }
            }
        }
        return 0.0
    }

    private fun numberValue(value: Any?): Double {
        return when (value) {
            is Number -> value.toDouble()
            is String -> {
                val normalized = value.trim()
                    .replace(Regex("[^0-9,.-]"), "")
                    .let {
                        if (it.contains(",") && it.contains(".")) {
                            it.replace(".", "").replace(",", ".")
                        } else {
                            it.replace(",", ".")
                        }
                    }
                normalized.toDoubleOrNull() ?: 0.0
            }
            else -> 0.0
        }
    }

    private fun currentIsoDate(): String {
        val calendar = Calendar.getInstance()
        val year = calendar.get(Calendar.YEAR)
        val month = calendar.get(Calendar.MONTH) + 1
        val day = calendar.get(Calendar.DAY_OF_MONTH)
        return "%04d-%02d-%02d".format(year, month, day)
    }

    private fun checkReleaseUpdate(context: Context) {
        val data = fetchJson(UPDATE_ENDPOINT) ?: return
        val tag = data.optString("tag_name", "").trim()
        val (version, build) = parseReleaseTag(tag)
        if (version.isEmpty() && build <= 0) return
        val installedBuild = appVersionCode(context)
        val installedVersion = appVersionName(context)
        val isNewer = if (build > 0 && build.toLong() != installedBuild) {
            build.toLong() > installedBuild
        } else {
            compareVersions(version, installedVersion) > 0
        }
        if (!isNewer) return
        val downloadUrl = apkDownloadUrl(data).ifBlank {
            data.optString("html_url", "").trim()
        }
        if (downloadUrl.isEmpty()) return
        val identity = if (build > 0) build.toString() else version
        val prefs = NativeJsonStore.prefs(context)
        if (prefs.getString("native_notified_update_identity", "") == identity) return
        prefs.edit().putString("native_notified_update_identity", identity).apply()
        val versionText = if (build > 0 && version.isNotEmpty()) "$version+$build" else tag.ifBlank { version }
        notifyReleaseUpdate(context, versionText, downloadUrl)
    }

    private fun fetchJson(endpoint: String): JSONObject? {
        val connection = (URL(endpoint).openConnection() as? HttpURLConnection) ?: return null
        return try {
            connection.connectTimeout = 8000
            connection.readTimeout = 10000
            connection.requestMethod = "GET"
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("User-Agent", "Sin Rial")
            if (connection.responseCode !in 200..299) return null
            val body = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            JSONObject(body)
        } catch (_: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    private fun parseReleaseTag(tag: String): Pair<String, Int> {
        val clean = tag.trim().removePrefix("v").removePrefix("V")
        if (clean.isEmpty()) return "" to 0
        val pieces = clean.split("+", limit = 2)
        val version = pieces.firstOrNull()?.trim().orEmpty()
        val build = pieces.getOrNull(1)
            ?.filter { it.isDigit() }
            ?.toIntOrNull()
            ?: 0
        return version to build
    }

    private fun apkDownloadUrl(data: JSONObject): String {
        val assets = data.optJSONArray("assets") ?: return ""
        var fallback = ""
        for (index in 0 until assets.length()) {
            val asset = assets.optJSONObject(index) ?: continue
            val name = asset.optString("name", "").lowercase()
            if (!name.endsWith(".apk")) continue
            val url = asset.optString("browser_download_url", "").trim()
            if (url.isEmpty()) continue
            if (!name.contains("debug")) return url
            if (fallback.isEmpty()) fallback = url
        }
        return fallback
    }

    private fun compareVersions(left: String, right: String): Int {
        val leftParts = Regex("\\d+").findAll(left).map { it.value.toIntOrNull() ?: 0 }.toList()
        val rightParts = Regex("\\d+").findAll(right).map { it.value.toIntOrNull() ?: 0 }.toList()
        val size = maxOf(leftParts.size, rightParts.size)
        for (index in 0 until size) {
            val a = leftParts.getOrElse(index) { 0 }
            val b = rightParts.getOrElse(index) { 0 }
            if (a != b) return a.compareTo(b)
        }
        return 0
    }

    private fun appVersionCode(context: Context): Long {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    private fun appVersionName(context: Context): String {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return info.versionName ?: ""
    }

    private fun notifyReleaseUpdate(context: Context, versionText: String, downloadUrl: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        DailyReminderScheduler.createChannel(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val contentIntent = PendingIntent.getActivity(
            context,
            UPDATE_NOTIFICATION_ID,
            Intent(Intent.ACTION_VIEW, Uri.parse(downloadUrl)).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, DailyReminderScheduler.CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        manager.notify(
            UPDATE_NOTIFICATION_ID,
            builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Actualizacion disponible")
                .setContentText("Sin Rial $versionText esta lista para descargar.")
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .build()
        )
    }
}
