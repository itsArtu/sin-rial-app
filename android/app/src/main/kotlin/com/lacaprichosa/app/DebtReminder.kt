package com.lacaprichosa.app

import org.json.JSONObject
import java.math.BigDecimal
import java.math.RoundingMode
import java.security.MessageDigest
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

internal data class DebtReminder(val tag: String, val title: String, val kind: String, val due: Calendar) {
    fun daysLeft(now: Long): Long = dayNumber(due) - dayNumber(Calendar.getInstance().apply { timeInMillis = now })

    fun isDue(now: Long): Boolean = daysLeft(now).let { it < 0 || it in setOf(0L, 1L, 3L, 5L, 7L) }

    fun text(now: Long): String {
        val days = daysLeft(now)
        val time = when {
            days > 1 -> "vence en $days d\u00edas"
            days == 1L -> "vence ma\u00f1ana"
            days == 0L -> "vence hoy"
            else -> "est\u00e1 atrasado ${-days} d\u00eda(s)"
        }
        return "$title $time."
    }

    fun signature(now: Long) = digest("$kind:${dayNumber(due)}:${text(now)}")

    companion object {
        const val TAG_PREFIX = "sin_rial_debt:"

        private fun digest(value: String) = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

        // Calendar dates, not elapsed 24-hour periods, keep reminders correct across DST.
        fun dayNumber(date: Calendar): Long = TimeUnit.MILLISECONDS.toDays(
            Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                clear()
                set(date.get(Calendar.YEAR), date.get(Calendar.MONTH), date.get(Calendar.DAY_OF_MONTH))
            }.timeInMillis
        )

        fun from(debt: JSONObject): DebtReminder? {
            if (!debt.optBoolean("hasDueDate", true) || !debt.optBoolean("notifyDueDate", true)) return null
            val amount = cents(debt, "amount") ?: return null
            val paid = cents(debt, "paidAmount") ?: return null
            if (amount <= 0 || paid >= amount || paid < 0) return null
            val hasInstallments = debt.optBoolean("hasInstallments") || debt.optDouble("installments", 0.0) > 1 ||
                debt.optDouble("installmentAmount", 0.0) > 0 || debt.optString("paymentFrequency").isNotBlank()
            val index = if (hasInstallments) installmentIndex(debt, amount, paid) ?: return null else 0
            val dates = debt.optJSONArray("installmentDates")
            val custom = if (hasInstallments && dates != null && index < dates.length()) dates.optString(index) else ""
            val due = if (custom.isNotBlank()) parseDate(custom) else parseDate(debt.optString("dueDate"))?.apply {
                if (hasInstallments) when (debt.optString("paymentFrequency")) {
                    "Semanal" -> add(Calendar.DAY_OF_YEAR, 7 * index)
                    "Quincenal" -> add(Calendar.DAY_OF_YEAR, 15 * index)
                    else -> add(Calendar.MONTH, index)
                }
            }
            if (due == null) return null
            val kind = if (debt.optString("kind") == "receivable") "cobro" else "pago"
            val title = debt.optString("title").ifBlank { if (kind == "cobro") "Por cobrar" else "Por pagar" }
            val id = debt.optString("id").ifBlank {
                // Older imports may lack an id; never use the mutable array position.
                digest("$kind:$title:${debt.optString("dueDate")}:$amount")
            }
            return DebtReminder(TAG_PREFIX + id, title, kind, due)
        }

        private fun installmentIndex(debt: JSONObject, amount: Long, paid: Long): Int? {
            val countValue = debt.optDouble("installments", 1.0)
            if (!countValue.isFinite()) return null
            val count = kotlin.math.floor(countValue + 0.5).toInt().coerceIn(1, 999)
            val initialValue = cents(debt, "initialAmount") ?: return null
            val initial = minOf(amount, if (initialValue > 0 || !debt.optBoolean("initialPaid")) initialValue else paid)
            if (initial < 0) return null
            val principal = amount - initial
            val paidInstallments = maxOf(0, paid - initial)
            val manual = cents(debt, "installmentAmount") ?: return null
            val automatic = debt.optString("installmentMode") == "auto" || manual <= 0
            var remaining = principal
            var boundary = 0L
            for (index in 0 until count) {
                val portion = if (index == count - 1) remaining else if (automatic) principal / count else minOf(manual, remaining)
                remaining -= portion
                boundary += portion
                if (paidInstallments < boundary) return index
            }
            return count - 1
        }

        private fun cents(debt: JSONObject, field: String): Long? = runCatching {
            BigDecimal(debt.optString(field, "0")).movePointRight(2).setScale(0, RoundingMode.HALF_UP).longValueExact()
        }.getOrNull()

        private fun parseDate(value: String): Calendar? {
            val text = value.trim()
            for (pattern in listOf("dd/MM/yyyy", "yyyy-MM-dd")) {
                val parser = SimpleDateFormat(pattern, Locale.US).apply { isLenient = false }
                val position = ParsePosition(0)
                val date = parser.parse(text, position) ?: continue
                if (position.index == text.length) return Calendar.getInstance().apply { time = date }
            }
            return null
        }
    }
}
