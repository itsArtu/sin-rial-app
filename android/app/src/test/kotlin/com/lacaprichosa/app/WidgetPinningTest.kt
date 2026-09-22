package com.lacaprichosa.app

import android.app.Application
import android.appwidget.AppWidgetManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class)
class WidgetPinningTest {
    @Test fun supportedLauncherAcceptsAllProviders() {
        val context = RuntimeEnvironment.getApplication()
        shadowOf(AppWidgetManager.getInstance(context)).setRequestPinAppWidgetSupported(true)
        for (type in listOf("movement", "USD", "EUR", "calculator")) {
            assertTrue(type, WidgetPinning.request(context, type))
        }
    }

    @Test fun unsupportedLauncherAndInvalidTypesAreRejected() {
        val context = RuntimeEnvironment.getApplication()
        val manager = shadowOf(AppWidgetManager.getInstance(context))
        manager.setRequestPinAppWidgetSupported(false)
        assertFalse(WidgetPinning.request(context, "USD"))
        manager.setRequestPinAppWidgetSupported(true)
        assertFalse(WidgetPinning.request(context, "invalid"))
        assertFalse(WidgetPinning.request(context, null))
    }

    @Test @Config(sdk = [24]) fun oldAndroidDoesNotCallPinApi() {
        assertFalse(WidgetPinning.request(RuntimeEnvironment.getApplication(), "movement"))
    }
}
