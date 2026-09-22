package com.lacaprichosa.app

import android.graphics.Color
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Locale

class WidgetAppearance(state: JSONObject) {
    val dark = state.optBoolean("darkMode", true)
    val ink = Color.parseColor(if (dark) "#F5F5F7" else "#18181B")
    val muted = Color.parseColor(if (dark) "#A8ABB4" else "#60646D")
    val green = Color.parseColor(if (dark) "#58BE86" else "#247B55")
    val red = Color.parseColor(if (dark) "#EF6683" else "#B83452")
    val background = if (dark) R.drawable.widget_background else R.drawable.widget_background_light
    val button = if (dark) R.drawable.widget_button_neutral else R.drawable.widget_button_light
    val accent: Int = run {
        val pair = when (state.optString("themeColor", "emerald")) {
            "amber" -> "B98518" to "E0AE55"
            "indigo", "navy", "sky" -> "2463D4" to "5B9AFF"
            "cyan" -> "237C9A" to "62C4E2"
            "graphite" -> "4D5663" to "8D99A8"
            "lime" -> "708D2B" to "A7C957"
            "violet", "magenta" -> "853DC4" to "B676E8"
            "coral", "orange" -> "C35C3E" to "F28A68"
            "wine" -> "C41E1E" to "E05252"
            "rose" -> "B84E68" to "E9819A"
            "teal" -> "247B7B" to "55BDBD"
            else -> "03674A" to "55BD91"
        }
        Color.parseColor("#" + if (dark) pair.second else pair.first)
    }

    companion object {
        fun amount(value: Double): String = NumberFormat.getNumberInstance(Locale.forLanguageTag("es-VE"))
            .apply { minimumFractionDigits = 2; maximumFractionDigits = 2 }.format(value)
    }
}
