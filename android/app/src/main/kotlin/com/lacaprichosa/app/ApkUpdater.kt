package com.lacaprichosa.app

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest

/** Download metadata is separate from the financial database. No financial data is sent. */
class ApkUpdater(private val context: Context) {
    private val prefs = context.getSharedPreferences("apk_update", Context.MODE_PRIVATE)
    private val manager get() = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val apk get() = File(File(context.filesDir, "updates"), "verified.apk")
    private val download get() = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "sin-rial-update.apk")

    companion object {
        const val MAX_BYTES = 200L * 1024 * 1024
        fun validSource(url: String): Boolean = runCatching {
            val uri = java.net.URI(url)
            uri.scheme == "https" && uri.host == "github.com" && uri.userInfo == null &&
                uri.port == -1 && uri.fragment == null && uri.query == null &&
                Regex("^/itsArtu/sin-rial-app/releases/download/[^/]+/[^/]+\\.apk$").matches(uri.rawPath)
        }.getOrDefault(false)

        fun validDigest(value: String) = Regex("^[a-fA-F0-9]{64}$").matches(value)

        @Suppress("DEPRECATION")
        fun version(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

        fun sha256(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().buffered().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }
    }

    fun begin(url: String, digest: String, build: Long, size: Long, versionName: String): Map<String, Any> {
        require(validSource(url)) { "La descarga no pertenece al repositorio oficial" }
        require(validDigest(digest)) { "La actualizacion no incluye una huella SHA-256 valida" }
        require(build > version(context.packageManager.getPackageInfo(context.packageName, 0))) { "La version ya esta instalada" }
        require(size in 1..MAX_BYTES) { "Tamano de APK no valido" }
        if (prefs.getString("sha256", "") == digest.lowercase() && prefs.getLong("build", 0) == build) {
            val current = status()
            if (current["status"] in listOf("downloading", "paused", "ready")) return current
        }
        require(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) != null) { "Almacenamiento no disponible" }
        require(StatFs(context.filesDir.path).availableBytes > size * 2 + 20 * 1024 * 1024) { "No hay espacio para la actualizacion" }
        cancel()
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle("Sin Rial $versionName")
            .setDescription("Descargando actualizacion")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, "sin-rial-update.apk")
        val id = manager.enqueue(request)
        prefs.edit().putLong("downloadId", id).putString("sha256", digest.lowercase())
            .putLong("build", build).putLong("size", size).putString("version", versionName).commit()
        return status()
    }

    fun cancel() {
        val id = prefs.getLong("downloadId", -1)
        if (id >= 0) manager.remove(id)
        download.delete()
        apk.delete()
        prefs.edit().clear().commit()
    }

    fun status(): Map<String, Any> {
        val id = prefs.getLong("downloadId", -1)
        if (id < 0) return mapOf("status" to "idle")
        if (prefs.getLong("build", 0) <= version(context.packageManager.getPackageInfo(context.packageName, 0))) {
            cancel()
            return mapOf("status" to "installed")
        }
        val base = mapOf<String, Any>("build" to prefs.getLong("build", 0), "version" to (prefs.getString("version", "") ?: ""))
        if (prefs.getBoolean("verified", false) && apk.isFile) return base + ("status" to "ready")
        manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
            if (cursor == null || !cursor.moveToFirst()) return base + mapOf("status" to "failed", "message" to "La descarga no esta disponible. Puedes reintentar.")
            val received = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = prefs.getLong("size", 0)
            if (received > MAX_BYTES || received > total) {
                cancel()
                return base + mapOf("status" to "failed", "message" to "El tamano descargado no coincide con la APK publicada")
            }
            val progress = base + mapOf("received" to received, "total" to total)
            return when (cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                DownloadManager.STATUS_SUCCESSFUL -> {
                    try {
                        require(download.length() == total) { "La descarga esta incompleta" }
                        apk.parentFile!!.mkdirs()
                        download.copyTo(apk, overwrite = true)
                        verify()
                        prefs.edit().putBoolean("verified", true).commit()
                        download.delete()
                        progress + ("status" to "ready")
                    } catch (error: Exception) {
                        apk.delete()
                        manager.remove(id)
                        progress + mapOf("status" to "failed", "message" to (error.message ?: "No se pudo verificar la APK"))
                    }
                }
                DownloadManager.STATUS_FAILED -> progress + mapOf("status" to "failed", "message" to "No se pudo descargar. Revisa tu conexion y el espacio disponible.")
                DownloadManager.STATUS_PAUSED -> progress + mapOf("status" to "paused", "message" to "Esperando conexion o disponibilidad de la descarga")
                else -> progress + ("status" to "downloading")
            }
        }
    }

    @Suppress("DEPRECATION")
    fun verify() {
        require(apk.isFile && apk.length() == prefs.getLong("size", 0) && apk.length() <= MAX_BYTES) { "APK incompleta" }
        require(sha256(apk) == prefs.getString("sha256", "")) { "La huella de la APK no coincide. No se instalara." }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val installed = context.packageManager.getPackageInfo(context.packageName, flags)
        val candidate = context.packageManager.getPackageArchiveInfo(apk.path, flags)
            ?: error("El archivo no es una APK valida")
        require(candidate.packageName == context.packageName) { "La APK no corresponde a Sin Rial" }
        require(version(candidate) == prefs.getLong("build", 0) && version(candidate) > version(installed)) { "Version de APK incorrecta" }
        require(candidate.versionName == prefs.getString("version", "")) { "Nombre de version incorrecto" }
        fun signatures(info: PackageInfo): Set<String> =
            (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)
                ?.map { it.toCharsString() }?.toSet() ?: emptySet()
        val expected = signatures(installed)
        require(expected.isNotEmpty() && signatures(candidate) == expected) { "La firma no coincide con la app instalada" }
    }

    fun canInstall(): Boolean = Build.VERSION.SDK_INT < 26 || context.packageManager.canRequestPackageInstalls()

    fun requestPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= 26) activity.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
        )
    }

    // Called on the UI thread only after verify() has completed on a worker thread.
    fun openInstaller(activity: Activity) {
        require(canInstall()) { "Autoriza a Sin Rial para instalar actualizaciones" }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
        activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }
}
