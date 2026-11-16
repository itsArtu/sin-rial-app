package com.lacaprichosa.app

import android.app.Application
import android.content.Intent
import android.content.ContextWrapper
import android.content.ActivityNotFoundException
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 36], application = Application::class)
class BankAppShortcutsTest {
    private val app: Application get() = RuntimeEnvironment.getApplication()

    @Test fun missingAndInvalidPackagesDoNotLaunch() {
        assertFalse(BankAppShortcuts.open(app, ""))
        assertFalse(BankAppShortcuts.open(app, "https://example.com"))
        assertFalse(BankAppShortcuts.open(app, app.packageName))
        assertFalse(BankAppShortcuts.open(app, "com.missing.bank"))
        assertNull(shadowOf(app).nextStartedActivity)
    }

    @Test fun installedAppLaunchHasNoFinancialExtras() {
        val name = "com.example.bank"
        val info = ResolveInfo().apply {
            nonLocalizedLabel = "Banco de prueba"
            activityInfo = ActivityInfo().apply {
                packageName = name
                this.name = "$name.MainActivity"
                exported = true
                applicationInfo = ApplicationInfo().apply { packageName = name }
            }
        }
        val manager = shadowOf(app.packageManager)
        manager.addResolveInfoForIntent(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), info)
        manager.addResolveInfoForIntent(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(name), info)
        assertTrue(BankAppShortcuts.openOrStore(app, name, "Banco"))
        val launched = shadowOf(app).nextStartedActivity
        assertEquals(name, launched.component!!.packageName)
        assertNull(launched.data)
        assertTrue(launched.extras == null || launched.extras!!.isEmpty)
        assertNull(shadowOf(app).nextStartedActivity)
    }

    @Test fun missingAppOpensItsExactPlayListing() {
        assertTrue(BankAppShortcuts.openOrStore(app, "com.missing.bank", "Banco"))
        val intent = shadowOf(app).nextStartedActivity
        assertEquals("market://details?id=com.missing.bank", intent.data.toString())
        assertEquals("com.android.vending", intent.`package`)
        assertNull(intent.extras)
    }

    @Test fun missingPlayUsesBrowserAndUnknownBankUsesEncodedSearch() {
        val intents = mutableListOf<Intent>()
        val context = object : ContextWrapper(app) {
            override fun startActivity(intent: Intent) {
                intents.add(intent)
                if (intent.data?.scheme == "market") throw ActivityNotFoundException()
            }
        }
        assertTrue(BankAppShortcuts.openOrStore(context, null, "Banco & Billetera"))
        assertEquals(2, intents.size)
        assertEquals("https", intents.last().data!!.scheme)
        assertEquals("play.google.com", intents.last().data!!.host)
        assertEquals("Banco & Billetera", intents.last().data!!.getQueryParameter("q"))
        assertFalse(BankAppShortcuts.openOrStore(context, "https://bad", "Banco"))
        assertFalse(BankAppShortcuts.openOrStore(context, app.packageName, "Banco"))
        assertFalse(BankAppShortcuts.openOrStore(context, null, ""))
        assertEquals(2, intents.size)
    }

    @Test fun noStoreOrBrowserReturnsFalse() {
        val context = object : ContextWrapper(app) {
            override fun startActivity(intent: Intent) { throw ActivityNotFoundException() }
        }
        assertFalse(BankAppShortcuts.openOrStore(context, "com.missing.bank", "Banco"))
    }
}
