package com.lacaprichosa.app

import android.Manifest
import android.app.Application
import android.app.Notification
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
class DebtReminderTest {
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
        SystemClock.setCurrentTimeMillis(at(2026, 10, 2))
    }

    @After fun tearDown() { TimeZone.setDefault(originalZone) }

    private fun at(year: Int, month: Int, day: Int) = Calendar.getInstance().apply {
        clear()
        set(year, month - 1, day, 19, 0)
    }.timeInMillis

    private fun debt(id: String = "d", kind: String = "payable") = JSONObject()
        .put("id", id).put("kind", kind).put("title", "Prueba $id")
        .put("amount", 100).put("paidAmount", 0).put("dueDate", "02/10/2026")

    private fun save(vararg debts: JSONObject, daily: Boolean = false) {
        NativeJsonStore.writeState(context, JSONObject().put("dailyMovementReminderEnabled", daily)
            .put("debts", JSONArray(debts.toList())).toString())
        DailyReminderScheduler.schedule(context)
    }

    private fun deliver() = DailyReminderReceiver().onReceive(context, Intent())

    @Test fun paidDeletedAndDisabledNoticesAreRemovedAndNeverRedelivered() {
        for (kind in listOf("payable", "receivable")) {
            for (change in listOf("paid", "deleted", "disabled", "noDate")) {
                val d = debt(kind = kind)
                save(d)
                deliver()
                assertEquals(1, manager.activeNotifications.size)
                when (change) {
                    "paid" -> save(d.put("paidAmount", 100))
                    "deleted" -> save()
                    "disabled" -> save(d.put("notifyDueDate", false))
                    else -> save(d.put("hasDueDate", false))
                }
                assertTrue(manager.activeNotifications.isEmpty())
                deliver()
                assertTrue(manager.activeNotifications.isEmpty())
            }
        }
    }

    @Test fun roundingAndInvalidDebtsDoNotProduceFalsePendingPayments() {
        val paid = debt().put("amount", 100.000000001).put("paidAmount", 100)
        assertNull(DebtReminder.from(paid))
        for (invalid in listOf(debt().put("amount", 0), debt().put("amount", -1),
            debt().put("paidAmount", "NaN"), debt().put("dueDate", "31/02/2026"),
            debt().put("dueDate", "02/10/2026junk"))) assertNull(DebtReminder.from(invalid))
        save(paid, debt("zero").put("amount", 0))
        deliver()
        assertTrue(manager.activeNotifications.isEmpty())
    }

    @Test fun advancesToNextUnpaidInstallmentIncludingPartialPayments() {
        val d = debt().put("amount", 300).put("installments", 3).put("hasInstallments", true)
            .put("paymentFrequency", "Mensual").put("installmentMode", "auto")
        save(d)
        deliver()
        assertEquals(1, manager.activeNotifications.size)
        save(d.put("paidAmount", 50))
        assertEquals(1, manager.activeNotifications.size)
        save(d.put("paidAmount", 100))
        assertTrue(manager.activeNotifications.isEmpty())
        deliver()
        assertTrue(manager.activeNotifications.isEmpty())
        SystemClock.setCurrentTimeMillis(at(2026, 11, 2))
        deliver()
        assertEquals(1, manager.activeNotifications.size)
        save(d.put("paidAmount", 300))
        assertTrue(manager.activeNotifications.isEmpty())
    }

    @Test fun scheduleMatchesInitialManualCustomAndMonthEndInstallments() {
        val d = debt().put("amount", 100).put("initialAmount", 20).put("initialPaid", true)
            .put("installments", 3).put("paidAmount", 46.66).put("dueDate", "31/01/2026")
        assertEquals(28, DebtReminder.from(d)!!.due.get(Calendar.DAY_OF_MONTH))
        assertEquals(Calendar.FEBRUARY, DebtReminder.from(d)!!.due.get(Calendar.MONTH))
        d.put("installmentMode", "manual").put("installmentAmount", 30).put("paidAmount", 49.99)
        assertEquals(Calendar.JANUARY, DebtReminder.from(d)!!.due.get(Calendar.MONTH))
        d.put("paidAmount", 50).put("installmentDates", JSONArray(listOf("31/01/2026", "2026-03-05", "15/04/2026")))
        assertEquals(Calendar.MARCH, DebtReminder.from(d)!!.due.get(Calendar.MONTH))
        assertEquals(5, DebtReminder.from(d)!!.due.get(Calendar.DAY_OF_MONTH))
        d.remove("installmentDates")
        d.put("paymentFrequency", "Semanal")
        assertEquals(7, DebtReminder.from(d)!!.due.get(Calendar.DAY_OF_MONTH))
        d.put("paymentFrequency", "Quincenal")
        assertEquals(15, DebtReminder.from(d)!!.due.get(Calendar.DAY_OF_MONTH))
    }

    @Test fun reorderingAndRepeatedBroadcastsDoNotDuplicateNotices() {
        val a = debt("a")
        val b = debt("b")
        save(a, b, daily = true)
        deliver()
        assertEquals(3, manager.activeNotifications.size)
        manager.cancelAll() // Simulate the user dismissing the notices.
        save(b, a, daily = true)
        deliver()
        assertTrue(manager.activeNotifications.isEmpty())
        SystemClock.setCurrentTimeMillis(at(2026, 10, 3))
        deliver()
        assertEquals(3, manager.activeNotifications.size)
        save(b, daily = false)
        assertEquals(1, manager.activeNotifications.size)
        assertEquals(DebtReminder.TAG_PREFIX + "b", manager.activeNotifications.single().tag)
    }

    @Test fun paidThenUndoneDebtCanNotifyAgain() {
        val d = debt()
        save(d)
        deliver()
        save(d.put("paidAmount", 100))
        assertTrue(manager.activeNotifications.isEmpty())
        save(d.put("paidAmount", 0))
        deliver()
        assertEquals(1, manager.activeNotifications.size)
    }

    @Test fun cleanupHandlesLegacyNoticesWithoutRemovingUpdateNotifications() {
        fun notice(title: String) = Notification.Builder(context).setSmallIcon(R.mipmap.ic_launcher).setContentTitle(title).build()
        manager.notify(2204, notice("Sin Rial: pago pendiente"))
        manager.notify(2601, notice("Actualizacion disponible"))
        save()
        assertEquals(2601, manager.activeNotifications.single().id)
    }

    @Test fun permissionDenialDoesNotMarkDebtAsDeliveredAndStillCleansPaidNotice() {
        save(debt())
        shadowOf(manager).setNotificationsEnabled(false)
        deliver()
        assertTrue(manager.activeNotifications.isEmpty())
        shadowOf(manager).setNotificationsEnabled(true)
        deliver()
        assertEquals(1, manager.activeNotifications.size)
        shadowOf(manager).setNotificationsEnabled(false)
        save(debt().put("paidAmount", 100))
        assertTrue(manager.activeNotifications.isEmpty())
    }

    @Test fun dueWindowAndDstUseLocalCalendarDays() {
        val d = debt()
        for (day in 1..12) {
            d.put("dueDate", "${day.toString().padStart(2, '0')}/10/2026")
            assertEquals(day in setOf(1, 2, 3, 5, 7, 9), DebtReminder.from(d)!!.isDue(at(2026, 10, 2)))
        }
        TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
        d.put("dueDate", "09/03/2026")
        assertEquals(1L, DebtReminder.from(d)!!.daysLeft(at(2026, 3, 8)))
        assertEquals(3L, DebtReminder.from(d)!!.daysLeft(at(2026, 3, 6)))
    }
}
