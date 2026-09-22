package com.lacaprichosa.app

import android.app.Application
import android.appwidget.AppWidgetManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, qualifiers = "mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WidgetDesignTest {
    @org.junit.Before fun secureStore() { installTestCipher() }
    private val context get() = RuntimeEnvironment.getApplication()
    private fun options(height: Int) = Bundle().apply {
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height)
    }
    private fun state(dark: Boolean) = JSONObject().put("darkMode", dark).put("themeColor", "teal")
        .put("rate", 852.42).put("eurRate", 978.17).put("previousRate", 849.56)
        .put("rateEffectiveDate", "2026-09-22").put("eurRateEffectiveDate", "2026-09-22")
        .put("lastRateMillis", 1790078400000L).put("eurLastRateMillis", 1790078400000L)
        .put("bcvRateSnapshots", JSONArray().put(quote("2026-09-20", 842.0))
            .put(quote("2026-09-21", 849.56)).put(quote("2026-09-22", 852.42))
            .put(quote("2026-09-23", 999.0)))
    private fun quote(date: String, value: Double) =
        JSONObject().put("effective_date", date).put("USD", value).put("EUR", value * 1.1)

    @Test fun rateWidgetsHandleThemeSizesAndRealHistory() {
        for (dark in listOf(true, false)) {
            val saved = state(dark)
            NativeJsonStore.writeState(context, saved.toString())
            assertEquals(listOf(842.0, 849.56, 852.42), RateWidgetRenderer.history(saved, "USD"))
            for (height in listOf(40, 54, 90, 116, 170)) {
                val view = RateWidgetRenderer.buildViews(context, "USD", options(height))
                    .apply(context, FrameLayout(context))
                measure(view, 180, height)
                assertEquals("Bs 852,42", view.findViewById<TextView>(R.id.rate_value).text.toString())
                assertEquals(if (height >= 160) View.VISIBLE else View.GONE,
                    view.findViewById<View>(R.id.rate_chart).visibility)
                assertEquals(WidgetAppearance(saved).ink,
                    view.findViewById<TextView>(R.id.rate_value).currentTextColor)
                bounds(view, view)
                screenshot(view, "rate-" + (if (dark) "dark" else "light") + "-$height")
            }
        }
    }

    @Test fun noRateOrNoPreviousDoesNotInventVariationOrChart() {
        NativeJsonStore.writeState(context, JSONObject().put("rate", 0).toString())
        val view = RateWidgetRenderer.buildViews(context, "USD", options(170))
            .apply(context, FrameLayout(context))
        assertEquals("Sin tasa", view.findViewById<TextView>(R.id.rate_value).text.toString())
        assertEquals(View.GONE, view.findViewById<View>(R.id.rate_chart).visibility)
        assertEquals(View.GONE, view.findViewById<View>(R.id.rate_change).visibility)
    }

    @Test fun quotePrecisionMatchesAppAndGroupsThousands() {
        NativeJsonStore.writeState(context, state(true).put("rate", 1852.42999).toString())
        val view = RateWidgetRenderer.buildViews(context, "USD", options(170))
            .apply(context, FrameLayout(context))
        assertEquals("Bs 1.852,42", view.findViewById<TextView>(R.id.rate_value).text.toString())
    }

    @Test fun movementActionsRenderBothSizesAndThemes() {
        for (dark in listOf(true, false)) for ((width, height) in listOf(110 to 40, 160 to 56, 180 to 136, 330 to 136)) {
            NativeJsonStore.writeState(context, state(dark).toString())
            val view = MovementWidgetProvider.buildViews(context, options(height))
                .apply(context, FrameLayout(context))
            measure(view, width, height)
            assertNotNull(view.findViewById<View>(R.id.widget_income))
            assertNotNull(view.findViewById<View>(R.id.widget_expense))
            if (height >= 124) assertNotNull(view.findViewById<View>(R.id.widget_transfer))
            bounds(view, view)
            screenshot(view, "movement-" + (if (dark) "dark" else "light") + "-$width")
        }
    }

    @Test fun providersDefaultToTwoColumnsAndOneRow() {
        val namespace = "http://schemas.android.com/apk/res/android"
        for (xml in listOf(R.xml.movement_widget_info, R.xml.usd_rate_widget_info,
            R.xml.eur_rate_widget_info, R.xml.calculator_widget_info)) {
            context.resources.getXml(xml).use { parser ->
                while (parser.next() != org.xmlpull.v1.XmlPullParser.START_TAG) {}
                assertEquals(2, parser.getAttributeIntValue(namespace, "targetCellWidth", 0))
                assertEquals(1, parser.getAttributeIntValue(namespace, "targetCellHeight", 0))
            }
        }
    }

    @Test fun calculatorFitsSmallWidgetAndThemes() {
        for (dark in listOf(true, false)) {
            NativeJsonStore.writeState(context, state(dark).toString())
            val view = CalculatorWidgetProvider.buildViews(context).apply(context, FrameLayout(context))
            measure(view, 160, 56)
            bounds(view, view)
            screenshot(view, "calculator-" + if (dark) "dark" else "light")
        }
    }

    private fun measure(view: View, width: Int, height: Int) {
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        view.layout(0, 0, width, height)
    }
    private fun bounds(root: View, parent: View) {
        if (parent !is ViewGroup) return
        for (i in 0 until parent.childCount) {
            val child = parent.getChildAt(i)
            if (child.visibility != View.VISIBLE) continue
            assertTrue("view " + child.id + " top " + child.top, child.top >= 0)
            assertTrue("view " + child.id + " bottom " + child.bottom + "/" + parent.height,
                child.bottom <= parent.height)
            assertTrue(child.right <= parent.width)
            bounds(root, child)
        }
    }
    private fun screenshot(view: View, name: String) {
        val bitmap = Bitmap.createBitmap(view.width * 3, view.height * 3, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap).apply { scale(3f, 3f) }
        view.draw(canvas)
        val dir = File(System.getProperty("user.dir"), "../build/widgets-pdf-qa").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
}
