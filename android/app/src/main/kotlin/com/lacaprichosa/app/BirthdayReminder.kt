package com.lacaprichosa.app

import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

object BirthdayReminder {
    const val ID = 1903
    fun enabled(state: JSONObject): Boolean = state.optBoolean("onboardingComplete") &&
        date(state) != null

    private fun date(state: JSONObject): Calendar? {
        val raw = state.optString("userBirthDate")
        if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(raw)) return null
        return runCatching {
            val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }
            Calendar.getInstance().apply { time = format.parse(raw)!! }
                .takeIf { it.get(Calendar.YEAR) >= 1900 && it.timeInMillis <= System.currentTimeMillis() }
        }.getOrNull()
    }

    fun dueYear(state: JSONObject, now: Long = System.currentTimeMillis(), zone: TimeZone = TimeZone.getDefault()): Int? {
        if (!enabled(state)) return null
        val birth = date(state) ?: return null
        val today = Calendar.getInstance(zone).apply { timeInMillis = now }
        if (today.get(Calendar.YEAR) < birth.get(Calendar.YEAR)) return null
        val anniversary = Calendar.getInstance(zone).apply {
            clear(); set(today.get(Calendar.YEAR), birth.get(Calendar.MONTH), 1)
        }
        val day = birth.get(Calendar.DAY_OF_MONTH).coerceAtMost(anniversary.getActualMaximum(Calendar.DAY_OF_MONTH))
        return today.get(Calendar.YEAR).takeIf {
            today.get(Calendar.MONTH) == birth.get(Calendar.MONTH) && today.get(Calendar.DAY_OF_MONTH) == day
        }
    }
}
