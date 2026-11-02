package com.lacaprichosa.app

import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

internal class BackupDocuments(private val activity: ComponentActivity) {
    private var pending: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null
    private val create = activity.registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val bytes = exportBytes
        exportBytes = null
        if (uri == null || bytes == null) finish(false)
        else work {
            val stream = activity.contentResolver.openOutputStream(uri, "wt") ?: error("No output stream")
            stream.use { it.write(bytes) }
            true
        }
    }
    private val open = activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) finish(null)
        else work {
            val stream = activity.contentResolver.openInputStream(uri) ?: error("No input stream")
            stream.use {
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val read = it.read(buffer)
                    if (read < 0) break
                    require(out.size() + read <= MAX_BYTES) { "Backup too large" }
                    out.write(buffer, 0, read)
                }
                out.toByteArray()
            }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) { result.error("BACKUP_BUSY", "Ya hay una copia en curso", null); return }
        pending = result
        try {
            if (call.method == "pickBackupBytes") open.launch(arrayOf("application/json", "application/octet-stream", "*/*"))
            else {
                exportBytes = requireNotNull(call.argument<ByteArray>("bytes"))
                require(exportBytes!!.size in 1..MAX_BYTES)
                create.launch((call.argument<String>("name") ?: "Sin-Rial.sinrial.json")
                    .replace(Regex("[^a-zA-Z0-9.\\-]"), "_"))
            }
        } catch (_: Exception) { fail() }
    }

    private fun work(action: () -> Any) {
        Thread {
            val value = runCatching(action)
            activity.runOnUiThread { value.fold({ finish(it) }, { fail() }) }
        }.start()
    }
    private fun finish(value: Any?) { pending?.success(value); pending = null }
    private fun fail() {
        pending?.error("BACKUP_FILE", "No se pudo abrir o guardar la copia", null)
        pending = null
        exportBytes = null
    }
    fun close() {
        pending?.error("BACKUP_INTERRUPTED", "La copia fue interrumpida", null)
        pending = null
        exportBytes = null
    }
    companion object { const val MAX_BYTES = 32 * 1024 * 1024 }
}
