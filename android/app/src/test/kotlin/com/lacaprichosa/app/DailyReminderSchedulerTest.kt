package com.lacaprichosa.app

import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager
import java.util.Calendar
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, instrumentedPackages = ["com.lacaprichosa.app"])
class DailyReminderSchedulerTest {
    private lateinit var context: Application
    private lateinit var alarm: AlarmManager
    private val originalZone = TimeZone.getDefault()

    @Before fun setUp() {
        installTestCipher()
        TimeZone.setDefault(TimeZone.getTimeZone("America/Caracas"))
        context = RuntimeEnvironment.getApplication()
        alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        NativeJsonStore.prefs(context).edit().clear().commit()
        SystemClock.setCurrentTimeMillis(at(2026, 9, 17, 10, 0))
    }

    @After fun tearDown() {
        TimeZone.setDefault(originalZone)
    }

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int, zone: String = "America/Caracas") =
        Calendar.getInstance(TimeZone.getTimeZone(zone)).apply {
            clear()
            set(year, month - 1, day, hour, minute)
        }.timeInMillis

    @Test @Config(sdk = [33, 36]) fun exactAlarmUsesSelectedMinuteAndAllowsIdle() {
        DailyReminderScheduler.schedule(context, true, 19, 0)
        val scheduled = shadowOf(alarm).scheduledAlarms.single()
        assertEquals(at(2026, 9, 17, 19, 0), scheduled.triggerAtMs)
        assertEquals(AlarmManager.RTC_WAKEUP, scheduled.type)
        assertEquals(0L, scheduled.windowLengthMs)
        assertEquals(0L, scheduled.intervalMs)
        assertTrue(scheduled.allowWhileIdle)
        DailyReminderScheduler.schedule(context, true, 20, 37)
        assertEquals(at(2026, 9, 17, 20, 37), shadowOf(alarm).scheduledAlarms.single().triggerAtMs)
    }

    @Test fun missingPermissionUsesExplicitInexactFallback() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        DailyReminderScheduler.schedule(context, true, 19, 0)
        val scheduled = shadowOf(alarm).scheduledAlarms.single()
        assertNotEquals(0L, scheduled.windowLengthMs)
        assertTrue(scheduled.allowWhileIdle)
        assertEquals(false, DailyReminderScheduler.status(context)["exactAllowed"])
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        DailyReminderScheduler.schedule(context)
        assertEquals(0L, shadowOf(alarm).scheduledAlarms.single().windowLengthMs)
    }

    @Test fun unrelatedSavesDoNotPostponeAnAlarmAwaitingDelivery() {
        DailyReminderScheduler.schedule(context)
        val original = shadowOf(alarm).scheduledAlarms.single()
        SystemClock.setCurrentTimeMillis(at(2026, 9, 17, 19, 1))
        DailyReminderScheduler.schedule(context)
        assertSame(original, shadowOf(alarm).scheduledAlarms.single())
    }

    @Test fun disablingWithoutDebtNoticesCancelsTheAlarm() {
        DailyReminderScheduler.schedule(context)
        DailyReminderScheduler.schedule(context, false, 19, 0)
        assertTrue(shadowOf(alarm).scheduledAlarms.isEmpty())
        assertEquals(0L, DailyReminderScheduler.status(context)["nextReminderMillis"])
    }

    @Test fun debtNoticesRemainWhenMovementReminderIsOff() {
        NativeJsonStore.writeState(context, """{"dailyMovementReminderEnabled":false,"debts":[{"amount":50,"paidAmount":0,"dueDate":"20/09/2026"}]}""")
        DailyReminderScheduler.schedule(context)
        assertEquals(1, shadowOf(alarm).scheduledAlarms.size)
        NativeJsonStore.writeState(context, """{"dailyMovementReminderEnabled":false,"debts":[{"amount":50,"paidAmount":50,"dueDate":"20/09/2026"}]}""")
        DailyReminderScheduler.schedule(context)
        assertTrue(shadowOf(alarm).scheduledAlarms.isEmpty())
    }

    @Test fun receiverRearmsEvenWhenNotificationsAreBlocked() {
        DailyReminderScheduler.schedule(context)
        SystemClock.setCurrentTimeMillis(at(2026, 9, 17, 19, 0))
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        shadowOf(manager).setNotificationsEnabled(false)
        DailyReminderReceiver().deliver(context)
        assertEquals(at(2026, 9, 18, 19, 0), shadowOf(alarm).scheduledAlarms.single().triggerAtMs)
        assertTrue(shadowOf(manager).allNotifications.isEmpty())
        assertEquals(false, DailyReminderScheduler.status(context)["notificationsAllowed"])
    }

    @Test @Config(sdk = [24]) fun receiverDeliversAndRearmsOnOlderAndroid() {
        DailyReminderScheduler.schedule(context)
        SystemClock.setCurrentTimeMillis(at(2026, 9, 17, 19, 0))
        DailyReminderReceiver().deliver(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        assertEquals(1, shadowOf(manager).allNotifications.size)
        assertEquals(at(2026, 9, 18, 19, 0), shadowOf(alarm).scheduledAlarms.single().triggerAtMs)
    }

    @Test fun clockAndTimezoneChangesRearmFromLocalTime() {
        DailyReminderScheduler.schedule(context)
        SystemClock.setCurrentTimeMillis(at(2026, 9, 17, 21, 0))
        BootReceiver().reschedule(context, Intent(Intent.ACTION_TIME_CHANGED))
        assertEquals(at(2026, 9, 18, 19, 0), reminderAlarm().triggerAtMs)
        TimeZone.setDefault(TimeZone.getTimeZone("Europe/Madrid"))
        BootReceiver().reschedule(context, Intent(Intent.ACTION_TIMEZONE_CHANGED))
        assertEquals(at(2026, 9, 18, 19, 0, "Europe/Madrid"), reminderAlarm().triggerAtMs)
    }

    @Test fun bootAndPermissionBroadcastsRestoreAlarm() {
        for (action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) {
            DailyReminderScheduler.schedule(context)
            alarm.cancel(reminderAlarm().operation!!)
            BootReceiver().reschedule(context, Intent(action))
            assertEquals(0L, reminderAlarm().windowLengthMs)
        }
    }

    private fun reminderAlarm() = shadowOf(alarm).scheduledAlarms.single {
        shadowOf(it.operation!!).savedIntent.component?.className == DailyReminderReceiver::class.java.name
    }

    @Test fun staleAlarmIsRecoveredWithoutPostponingTodayUntilTomorrow() {
        DailyReminderScheduler.schedule(context)
        val old = reminderAlarm()
        alarm.cancel(old.operation!!)
        val now = at(2026, 9, 17, 19, 20)
        SystemClock.setCurrentTimeMillis(now)
        DailyReminderScheduler.schedule(context)
        assertEquals(now + 1000L, reminderAlarm().triggerAtMs)
        SystemClock.setCurrentTimeMillis(now + 1000L)
        DailyReminderReceiver().deliver(context)
        assertEquals(at(2026, 9, 18, 19, 0), reminderAlarm().triggerAtMs)
    }

    @Test fun staleAlarmBeforeTodaysSelectedTimeDoesNotSendAnEarlyNotice() {
        DailyReminderScheduler.schedule(context)
        SystemClock.setCurrentTimeMillis(at(2026, 9, 18, 10, 0))
        DailyReminderScheduler.schedule(context)
        assertEquals(at(2026, 9, 18, 19, 0), reminderAlarm().triggerAtMs)
    }

    @Test fun broadcastReturnsBeforeStorageWorkAndRearmsInBackground() {
        val entered = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        ReminderWork.executor.execute { entered.countDown(); release.await(5, java.util.concurrent.TimeUnit.SECONDS) }
        assertTrue(entered.await(5, java.util.concurrent.TimeUnit.SECONDS))
        try {
            DailyReminderReceiver().onReceive(context, Intent())
            assertTrue(shadowOf(alarm).scheduledAlarms.isEmpty())
        } finally {
            release.countDown()
            ReminderWork.executor.submit {}.get(10, java.util.concurrent.TimeUnit.SECONDS)
        }
        assertEquals(1, shadowOf(alarm).scheduledAlarms.size)
    }

    @Test fun nextLocalDayHandlesMidnightAndDaylightSaving() {
        assertEquals(at(2027, 1, 1, 19, 0), DailyReminderScheduler.nextReminderTime(19, 0, at(2026, 12, 31, 19, 0)))
        val zone = TimeZone.getTimeZone("America/New_York")
        val now = at(2026, 3, 7, 20, 0, zone.id)
        val next = DailyReminderScheduler.nextReminderTime(19, 0, now, zone)
        assertEquals(at(2026, 3, 8, 19, 0, zone.id), next)
        assertEquals(22L * 60 * 60 * 1000, next - now)
    }
}
