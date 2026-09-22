package com.lacaprichosa.app

import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

object BcvRatePolicy {
    val zone: TimeZone get() = TimeZone.getTimeZone("America/Caracas")

    fun dateKey(now: Long): String = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        .apply { timeZone = zone }.format(Date(now))

    fun merge(vararg sources: JSONArray): JSONArray {
        val byDate = sortedMapOf<String, JSONObject>()
        val parser = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            isLenient = false
            timeZone = zone
        }
        for (source in sources) for (i in 0 until source.length()) {
            val item = source.optJSONObject(i) ?: continue
            val date = item.optString("effective_date", item.optString("date"))
            val parsed = try { parser.parse(date) } catch (_: Exception) { null } ?: continue
            if (parser.format(parsed) != date) continue
            val usd = item.optDouble("USD", 0.0)
            val eur = item.optDouble("EUR", 0.0)
            if (!usd.isFinite() || usd <= 0 || !eur.isFinite() || eur <= 0) continue
            val stamp = item.optString("updated_at")
            if ((byDate[date]?.optString("updated_at") ?: "") > stamp) continue
            byDate[date] = JSONObject().put("USD", usd).put("EUR", eur)
                .put("effective_date", date).put("updated_at", stamp)
        }
        return JSONArray(byDate.values.toList().takeLast(40))
    }

    fun saved(state: JSONObject): JSONArray = merge(
        JSONArray().put(JSONObject().put("USD", state.optDouble("rate", 0.0))
            .put("EUR", state.optDouble("eurRate", 0.0))
            .put("effective_date", state.optString("rateEffectiveDate"))
            .put("updated_at", state.optString("rateUpdatedAt"))),
        state.optJSONArray("bcvRateSnapshots") ?: JSONArray()
    )

    fun active(snapshots: JSONArray, now: Long): JSONObject? {
        val today = dateKey(now)
        val sorted = merge(snapshots)
        var current: JSONObject? = null
        var next: JSONObject? = null
        for (i in 0 until sorted.length()) {
            val quote = sorted.getJSONObject(i)
            if (quote.getString("effective_date") <= today) current = quote
            else if (next == null) next = quote
        }
        val friday = Calendar.getInstance(zone).apply {
            timeInMillis = now
            add(Calendar.DATE, -((get(Calendar.DAY_OF_WEEK) - Calendar.FRIDAY + 7) % 7))
            set(Calendar.HOUR_OF_DAY, 18)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis > now) add(Calendar.DATE, -7)
        }
        return if (current != null && next != null &&
            current.getString("effective_date") <= dateKey(friday.timeInMillis)) next else current
    }

    fun apply(state: JSONObject, now: Long): Boolean {
        val quote = active(saved(state), now) ?: return false
        val changed = state.optDouble("rate") != quote.getDouble("USD") ||
            state.optDouble("eurRate") != quote.getDouble("EUR") ||
            state.optString("rateEffectiveDate") != quote.getString("effective_date")
        if (!changed) return false
        for (currency in listOf("USD", "EUR")) {
            val key = if (currency == "USD") "rate" else "eurRate"
            val old = state.optDouble(key, 0.0)
            val value = quote.getDouble(currency)
            if (old > 0 && old != value) state.put(if (currency == "USD") "previousRate" else "previousEurRate", old)
            state.put(key, value)
            state.put("${key}EffectiveDate", quote.getString("effective_date"))
            state.put("${key}UpdatedAt", quote.optString("updated_at"))
        }
        state.put("lastRateDate", quote.getString("effective_date"))
        state.put("rateLastAttemptMillis", now)
        return true
    }

    fun nextBoundary(now: Long): Long = nextAt(now, listOf(0), fridayAdvance = true)

    fun nextFetch(now: Long): Long = nextAt(now, listOf(0, 17, 18, 19), fridayAdvance = false)

    private fun nextAt(now: Long, hours: List<Int>, fridayAdvance: Boolean): Long {
        var result = Long.MAX_VALUE
        for (day in 0..1) {
            val base = Calendar.getInstance(zone).apply {
                timeInMillis = now
                add(Calendar.DATE, day)
            }
            val options = if (fridayAdvance && base.get(Calendar.DAY_OF_WEEK) == Calendar.FRIDAY) hours + 18 else hours
            for (hour in options) {
                val candidate = (base.clone() as Calendar).apply {
                    set(Calendar.HOUR_OF_DAY, hour)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }.timeInMillis
                if (candidate > now) result = minOf(result, candidate)
            }
        }
        return result
    }
}
