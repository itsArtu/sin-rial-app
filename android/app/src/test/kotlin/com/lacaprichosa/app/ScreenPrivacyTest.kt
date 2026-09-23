package com.lacaprichosa.app

import android.app.Activity
import android.os.Build
import android.view.WindowManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 33])
class ScreenPrivacyTest {
    class TestActivity : Activity() {
        var recentsVisible: Boolean? = null
        override fun setRecentsScreenshotEnabled(enabled: Boolean) {
            recentsVisible = enabled
        }
    }

    private fun secure(activity: Activity) =
        activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0

    @Test fun startupAndLockedStateAlwaysRemainProtected() {
        val activity = Robolectric.buildActivity(TestActivity::class.java).setup().get()
        val privacy = ScreenPrivacyController(activity)
        privacy.onResume()
        assertTrue(secure(activity))
        privacy.update(locked = true, hideInBackground = false, suspended = false)
        privacy.onPause()
        assertTrue(secure(activity))
        if (Build.VERSION.SDK_INT >= 33) assertEquals(false, activity.recentsVisible)
    }

    @Test fun optingOutAllowsBothRecentsAndThePausedWindow() {
        val activity = Robolectric.buildActivity(TestActivity::class.java).setup().get()
        val privacy = ScreenPrivacyController(activity)
        privacy.update(locked = false, hideInBackground = false, suspended = true)
        privacy.onPause()
        assertFalse(secure(activity))
        if (Build.VERSION.SDK_INT >= 33) assertEquals(true, activity.recentsVisible)
        privacy.onResume()
        assertFalse(secure(activity))
    }

    @Test fun optingInProtectsRecentsAndSuspensionButAllowsForegroundScreenshots() {
        val activity = Robolectric.buildActivity(TestActivity::class.java).setup().get()
        val privacy = ScreenPrivacyController(activity)
        privacy.update(locked = false, hideInBackground = true, suspended = false)
        assertFalse(secure(activity))
        if (Build.VERSION.SDK_INT >= 33) assertEquals(false, activity.recentsVisible)
        privacy.update(locked = false, hideInBackground = true, suspended = true)
        assertTrue(secure(activity))
        privacy.onPause()
        privacy.update(locked = false, hideInBackground = true, suspended = false)
        assertTrue(secure(activity))
        privacy.onResume()
        assertFalse(secure(activity))
        privacy.onPause()
        privacy.update(locked = false, hideInBackground = false, suspended = true)
        assertFalse(secure(activity))
    }
}
