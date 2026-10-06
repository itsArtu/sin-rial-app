package com.lacaprichosa.app

import android.Manifest
import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.Calendar
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 36], application = Application::class, instrumentedPackages = ["com.lacaprichosa.app"])
class RecurringReminderTest {
    private lateinit var context: Application
    private lateinit var manager: NotificationManager
    private val originalZone = TimeZone.getDefault()
    @Before fun setUp() {
        installTestCipher()
        TimeZone.setDefault(TimeZone.getTimeZone("America/Caracas"))
        context = RuntimeEnvironment.getApplication()
        manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        shadowOf(context).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        NativeJsonStore.prefs(context).edit().clear().commit()
        SystemClock.setCurrentTimeMillis(Calendar.getInstance().apply { clear(); set(2026, 9, 6, 19, 0) }.timeInMillis)
    }
    @After fun tearDown() { TimeZone.setDefault(originalZone) }
    private fun rule() = JSONObject().put("id", "r").put("name", "Internet").put("type", "expense")
        .put("amount", 20).put("accountId", "a").put("currency", "USD").put("frequency", "monthly").put("startDate", "2026-10-06")
    private fun save(r: JSONObject = rule(), confirmed: Boolean = false, account: Boolean = true) {
        NativeJsonStore.writeState(context, JSONObject().put("dailyMovementReminderEnabled", false)
            .put("recurringMovements", JSONArray().put(r))
            .put("accounts", if (account) JSONArray().put(JSONObject().put("id", "a").put("currency", "USD").put("balance", 100)) else JSONArray())
            .put("movements", if (confirmed) JSONArray().put(JSONObject().put("id", "m").put("recurringId", "r").put("recurringDate", "2026-10-06")) else JSONArray()).toString())
        DailyReminderScheduler.schedule(context)
    }
    private fun deliver() = DailyReminderReceiver().onReceive(context, Intent())

    @Test fun noticeDoesNotWriteMoneyAndDoesNotDuplicateSameDay() {
        save()
        val before = NativeJsonStore.readState(context).toString()
        deliver()
        assertEquals(1, manager.activeNotifications.size)
        assertEquals(before, NativeJsonStore.readState(context).toString())
        manager.cancelAll()
        deliver()
        assertTrue(manager.activeNotifications.isEmpty())
    }
    @Test fun confirmSkipPauseArchiveDisableAndDeletedAccountCancelNotices() {
        for (change in listOf("confirm", "skip", "pause", "archive", "disable", "account")) {
            save(); deliver()
            assertEquals(1, manager.activeNotifications.size)
            when (change) {
                "confirm" -> save(confirmed = true)
                "skip" -> save(rule().put("skippedDates", JSONArray().put("2026-10-06")))
                "pause" -> save(rule().put("paused", true))
                "archive" -> save(rule().put("archived", true))
                "disable" -> save(rule().put("notify", false))
                else -> save(account = false)
            }
            assertTrue(manager.activeNotifications.isEmpty())
            deliver()
            assertTrue(manager.activeNotifications.isEmpty())
            NativeJsonStore.prefs(context).edit().remove(ReminderNotifications.RECURRING_SENT_KEY).commit()
        }
    }
    @Test fun scheduleRunsWithDailyReminderOffAndStopsWhenPaused() {
        save()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        assertEquals(1, shadowOf(alarm).scheduledAlarms.size)
        save(rule().put("paused", true))
        assertTrue(shadowOf(alarm).scheduledAlarms.isEmpty())
    }
    @Test fun futureAndInvalidRulesDoNotNotify() {
        for (r in listOf(rule().put("startDate", "2026-11-06"), rule().put("startDate", "2026-02-31"),
            rule().put("amount", 0), rule().put("frequency", "bad"))) {
            save(r); deliver(); assertTrue(manager.activeNotifications.isEmpty())
        }
    }
    @Test fun anchorAndLeapYearMatchFlutter() {
        for (year in listOf(2024, 2026)) {
            val r = rule().put("startDate", "$year-01-31")
            val feb = RecurringReminder.nextDate(r, setOf("$year-01-31"))!!
            assertEquals(if (year == 2024) 29 else 28, feb.get(Calendar.DAY_OF_MONTH))
            val march = RecurringReminder.nextDate(r, setOf("$year-01-31", RecurringReminder.key(feb)))!!
            assertEquals("$year-03-31", RecurringReminder.key(march))
        }
        assertEquals("2026-10-13", RecurringReminder.key(RecurringReminder.nextDate(rule().put("frequency", "weekly"), setOf("2026-10-06"))!!))
        assertEquals("2026-10-21", RecurringReminder.key(RecurringReminder.nextDate(rule().put("frequency", "fortnightly"), setOf("2026-10-06"))!!))
    }
    @Test fun pendingRulesSurviveEncryptedStorageAndRestart() {
        save()
        val restored = NativeJsonStore.readState(context)
        assertEquals("r", restored.getJSONArray("recurringMovements").getJSONObject(0).getString("id"))
        assertTrue(sqlitePayloads(context).values.flatten().none { it.contains("Internet") })
        assertEquals(1, RecurringReminder.fromState(restored).size)
    }
}
