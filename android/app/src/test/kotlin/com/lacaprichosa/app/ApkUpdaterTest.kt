package com.lacaprichosa.app

import android.content.Context
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 33])
class ApkUpdaterTest {
    private val context get() = RuntimeEnvironment.getApplication() as Context

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
