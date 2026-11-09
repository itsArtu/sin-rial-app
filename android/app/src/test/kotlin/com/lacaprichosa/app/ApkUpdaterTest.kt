package com.lacaprichosa.app

import android.content.Context
import android.content.ContextWrapper
import android.content.ContentProvider
import android.content.ContentValues
import android.app.DownloadManager
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowStatFs
import org.robolectric.shadows.ShadowContentResolver
import java.io.File
import java.io.ByteArrayInputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 33])
class ApkUpdaterTest {
    private val context get() = RuntimeEnvironment.getApplication() as Context

    @Test @Config(sdk = [24, 28, 33, 36]) fun downloadDoesNotRequireAnExternalAppDirectoryAndResumes() {
        val blocked = object : ContextWrapper(context) {
            override fun getExternalFilesDir(type: String?): File? =
                throw IllegalStateException("Unable to create directory: /storage/emulated/0/Android/data/")
        }
        ShadowStatFs.registerStats(context.filesDir, 1_000_000, 1_000_000, 1_000_000)
        val updater = ApkUpdater(blocked)
        val build = ApkUpdater.version(context.packageManager.getPackageInfo(context.packageName, 0)) + 1
        val url = "https://github.com/itsArtu/sin-rial-app/releases/download/v3.5.2%2B101/app.apk"
        assertEquals("downloading", updater.begin(url, "a".repeat(64), build, 1024, "3.5.2")["status"])
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val shadow = shadowOf(manager)
        val id = context.getSharedPreferences("apk_update", Context.MODE_PRIVATE).getLong("downloadId", -1)
        val request = shadowOf(shadow.getRequest(id))
        assertNull(request.destination)
        assertEquals(url, request.uri.toString())
        updater.begin(url, "a".repeat(64), build, 1024, "3.5.2")
        assertEquals(1, shadow.requestCount)
        request.setBytesSoFar(1025)
        assertEquals("failed", updater.status()["status"])
        assertEquals(0, shadow.requestCount)
        updater.cancel()
        assertEquals("idle", updater.status()["status"])
    }

    @Test fun providerStreamMustHaveTheExactPublishedLength() {
        val destination = File(context.filesDir, "updates/copied.apk")
        for (length in listOf(8, 10, 12)) {
            val source = ByteArray(length) { it.toByte() }
            val result = runCatching {
                ByteArrayInputStream(source).use { ApkUpdater.copyDownload(it, destination, 10) }
            }
            if (length == 10) {
                assertTrue(result.isSuccess)
                assertArrayEquals(source, destination.readBytes())
            } else {
                assertTrue(result.isFailure)
                assertFalse(destination.exists())
            }
        }
    }

    @Test fun storageFailureDoesNotExposeADevicePath() {
        val message = ApkUpdater.errorMessage(java.io.IOException("/storage/emulated/0/private"))
        assertFalse(message.contains("/storage"))
        assertTrue(message.contains("espacio"))
    }

    @Test fun completedDownloadIsReadThroughProviderAndStillRequiresAValidDigest() {
        val providerFile = File(context.cacheDir, "provider-download.apk").apply { writeText("untrusted apk") }
        var opened = false
        val provider = object : ContentProvider() {
            override fun onCreate() = true
            override fun getType(uri: Uri) = "application/vnd.android.package-archive"
            override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, sort: String?): Cursor? = null
            override fun insert(uri: Uri, values: ContentValues?): Uri? = null
            override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = 0
            override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = 0
            override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
                opened = true
                assertEquals("r", mode)
                return ParcelFileDescriptor.open(providerFile, ParcelFileDescriptor.MODE_READ_ONLY)
            }
        }
        provider.attachInfo(context, android.content.pm.ProviderInfo().apply { authority = "downloads" })
        ShadowContentResolver.registerProviderInternal("downloads", provider)
        ShadowStatFs.registerStats(context.filesDir, 1_000_000, 1_000_000, 1_000_000)
        val updater = ApkUpdater(context)
        val build = ApkUpdater.version(context.packageManager.getPackageInfo(context.packageName, 0)) + 1
        updater.begin("https://github.com/itsArtu/sin-rial-app/releases/download/v3.5.2%2B101/app.apk",
            "0".repeat(64), build, providerFile.length(), "3.5.2")
        val id = context.getSharedPreferences("apk_update", Context.MODE_PRIVATE).getLong("downloadId", -1)
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        shadowOf(shadowOf(manager).getRequest(id)).setStatus(DownloadManager.STATUS_SUCCESSFUL)
        val result = updater.status()
        assertTrue(result.toString(), opened)
        assertEquals("failed", result["status"])
        assertTrue(result["message"].toString().contains("huella"))
        assertFalse(File(context.filesDir, "updates/verified.apk").exists())
        assertEquals(0, shadowOf(manager).requestCount)
    }

    @Test fun onlyOfficialHttpsReleaseApksAreAccepted() {
        assertTrue(ApkUpdater.validSource("https://github.com/itsArtu/sin-rial-app/releases/download/v3.1.1%2B75/sin-rial.apk"))
        for (url in listOf(
            "http://github.com/itsArtu/sin-rial-app/releases/download/v3/app.apk",
            "https://github.com.evil.test/itsArtu/sin-rial-app/releases/download/v3/app.apk",
            "https://github.com/another/app/releases/download/v3/app.apk",
            "https://user@github.com/itsArtu/sin-rial-app/releases/download/v3/app.apk",
            "file:///data/app.apk", "https://github.com/itsArtu/sin-rial-app/releases/download/v3/app.apk?redirect=1")) {
            assertFalse(url, ApkUpdater.validSource(url))
        }
        assertFalse(ApkUpdater.validDigest(""))
        assertFalse(ApkUpdater.validDigest("g".repeat(64)))
        assertTrue(ApkUpdater.validDigest("a".repeat(64)))
    }

    @Test fun corruptApkCannotPassVerification() {
        val apk = File(File(context.filesDir, "updates"), "verified.apk")
        apk.parentFile!!.mkdirs()
        apk.writeText("not an apk")
        context.getSharedPreferences("apk_update", Context.MODE_PRIVATE).edit()
            .putLong("size", apk.length()).putString("sha256", "0".repeat(64)).commit()
        val error = runCatching { ApkUpdater(context).verify() }.exceptionOrNull()
        assertTrue(error is IllegalArgumentException)
        assertTrue(error!!.message!!.contains("huella"))
        ApkUpdater(context).cancel()
        assertFalse(apk.exists())
    }

    @Test fun matchingDigestDoesNotMakeAnArbitraryFileInstallable() {
        val apk = File(File(context.filesDir, "updates"), "verified.apk")
        apk.parentFile!!.mkdirs()
        apk.writeText("fake apk with matching digest")
        context.getSharedPreferences("apk_update", Context.MODE_PRIVATE).edit()
            .putLong("size", apk.length()).putString("sha256", ApkUpdater.sha256(apk)).commit()
        assertNotNull(runCatching { ApkUpdater(context).verify() }.exceptionOrNull())
        ApkUpdater(context).cancel()
        assertEquals("idle", ApkUpdater(context).status()["status"])
    }
}
