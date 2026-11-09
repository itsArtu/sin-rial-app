package com.lacaprichosa.app

import android.Manifest
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
class ProfileMaintenanceTest {
    private lateinit var context: Application
    private val originalZone = TimeZone.getDefault()
    private fun time(year: Int = 2026, month: Int = 11, day: Int = 1): Long = Calendar.getInstance().apply {
        clear(); set(year, month - 1, day, 19, 0)
    }.timeInMillis
    @Before fun setUp() {
        installTestCipher()
        TimeZone.setDefault(TimeZone.getTimeZone("America/Caracas"))
        context = RuntimeEnvironment.getApplication()
        NativeJsonStore.prefs(context).edit().clear().commit()
        shadowOf(context).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        SystemClock.setCurrentTimeMillis(time())
    }
    @After fun tearDown() { TimeZone.setDefault(originalZone) }
    private fun account() = JSONObject().put("id", "a").put("kind", "national").put("provider", "0134")
        .put("currency", "VES").put("balance", 1000).put("bankAccountType", "current")
        .put("maintenanceEnabled", true).put("maintenanceAmount", 684).put("maintenanceNextMonth", "2026-11")
        .put("maintenancePolicy", BankMaintenance.POLICY)
    private fun state(account: JSONObject = account()) = JSONObject().put("accounts", JSONArray().put(account))
        .put("movements", JSONArray()).put("dailyMovementReminderEnabled", false)

    @Test fun maintenanceStartsNextMonthAndNeverDuplicatesDeletedOrEditedExpense() {
        val state = state()
        assertFalse(BankMaintenance.applyToState(state, time(month = 10, day = 30)))
        assertTrue(BankMaintenance.applyToState(state, time(month = 10, day = 31)))
        assertFalse(BankMaintenance.applyToState(state, time()))
        assertEquals(316.0, state.getJSONArray("accounts").getJSONObject(0).getDouble("balance"), .00001)
        assertEquals(1, state.getJSONArray("movements").length())
        assertEquals("2026-10-31T00:00:00", state.getJSONArray("movements").getJSONObject(0).getString("date"))
        assertEquals("Comisión mantenimiento mensual octubre", state.getJSONArray("movements").getJSONObject(0).getString("description"))
        state.put("movements", JSONArray())
        assertFalse(BankMaintenance.applyToState(state, time(day = 15)))
        assertTrue(BankMaintenance.applyToState(state, time(month = 12)))
        assertEquals(-368.0, state.getJSONArray("accounts").getJSONObject(0).getDouble("balance"), .00001)
    }
    @Test fun maintenanceDoesNotBackfillMissedMonthsAndPreservesCurrency() {
        val state = state()
        assertTrue(BankMaintenance.applyToState(state, time(month = 12)))
        val movements = state.getJSONArray("movements")
        assertEquals(1, movements.length())
        assertEquals("2026-12", movements.getJSONObject(0).getString("maintenanceMonth"))
        assertEquals("VES", movements.getJSONObject(0).getString("currency"))
    }
    @Test fun maintenanceRequiresExplicitValidBankConfiguration() {
        for (a in listOf(account().put("currency", "USD"), account().put("kind", "benefit"),
            account().put("provider", "UBII"), account().put("kind", "cash"),
            account().put("bankAccountType", ""))) {
            val state = state(a)
            assertFalse(BankMaintenance.applyToState(state, time()))
            assertEquals(0, state.getJSONArray("movements").length())
        }
    }
    @Test fun existingCurrentAccountsStartNextMonthWithoutRetroactiveCharges() {
        val a = account().put("maintenanceEnabled", false).put("maintenanceAmount", 10.25)
        a.remove("maintenancePolicy")
        val state = state(a)
        assertTrue(BankMaintenance.applyToState(state, time()))
        assertEquals(0, state.getJSONArray("movements").length())
        assertEquals("2026-12", a.getString("maintenanceNextMonth"))
        assertEquals(684.0, a.getDouble("maintenanceAmount"), .001)
        assertTrue(BankMaintenance.applyToState(state, time(month = 12)))
        assertEquals(1, state.getJSONArray("movements").length())
        assertEquals(316.0, a.getDouble("balance"), .001)
    }
    @Test fun nativeMaintenanceIsAtomicAndDoesNotOverwriteOtherCollections() {
        val state = state().put("debts", JSONArray().put(JSONObject().put("id", "d").put("amount", 20)))
        NativeJsonStore.writeState(context, state.toString())
        assertTrue(BankMaintenance.apply(context, time()))
        assertFalse(BankMaintenance.apply(context, time()))
        val saved = NativeJsonStore.readState(context)
        assertEquals(20, saved.getJSONArray("debts").getJSONObject(0).getInt("amount"))
        assertEquals(316.0, saved.getJSONArray("accounts").getJSONObject(0).getDouble("balance"), .00001)
        assertEquals(1, saved.getJSONArray("movements").length())
    }
    @Test fun savingsCloseThirtyDayAndFebruaryMonthsOnNextFirst() {
        for (year in listOf(2026, 2028)) {
            for (month in listOf(2, 4, 6, 9, 11)) {
                val cycle = "%04d-%02d".format(year, month + 1)
                val a = account().put("bankAccountType", "savings").put("maintenanceNextMonth", cycle)
                val s = state(a)
                val last = Calendar.getInstance().apply { timeInMillis = time(year, month); set(Calendar.DAY_OF_MONTH, getActualMaximum(Calendar.DAY_OF_MONTH)) }
                assertFalse(BankMaintenance.applyToState(s, last.timeInMillis))
                assertTrue(BankMaintenance.applyToState(s, time(year, month + 1)))
                val entry = s.getJSONArray("movements").getJSONObject(0)
                assertEquals("$cycle-01T00:00:00", entry.getString("date"))
                assertEquals("%04d-%02d".format(year, month), entry.getString("maintenancePeriod"))
                assertEquals(316.0, a.getDouble("balance"), .001)
                assertFalse(BankMaintenance.applyToState(s, time(year, month + 1, 2)))
                if (month == 2) assertEquals("Comisión mantenimiento mensual febrero", entry.getString("description"))
                if (month == 11) assertEquals("Comisión mantenimiento mensual noviembre", entry.getString("description"))
            }
        }
    }
    @Test fun decemberCloseKeepsYearBoundaryAndLegacyCursor() {
        val a = account().put("maintenancePolicy", "ves-current-2026-09").put("maintenanceNextMonth", "2027-01")
        val s = state(a)
        assertTrue(BankMaintenance.applyToState(s, time(month = 12, day = 30)))
        assertEquals(0, s.getJSONArray("movements").length())
        assertTrue(BankMaintenance.applyToState(s, time(month = 12, day = 31)))
        assertEquals("Comisión mantenimiento mensual diciembre", s.getJSONArray("movements").getJSONObject(0).getString("description"))
        assertEquals("2027-02", a.getString("maintenanceNextMonth"))
        assertFalse(BankMaintenance.applyToState(s, time(2027, 1)))
    }
    @Test fun legacyChargeAndCursorNeverDuplicateAfterUpgrade() {
        val a = account().put("maintenancePolicy", "ves-current-2026-09").put("maintenanceNextMonth", "2026-12")
        val s = state(a)
        assertTrue(BankMaintenance.applyToState(s, time()))
        assertEquals(0, s.getJSONArray("movements").length())
        assertEquals(1000.0, a.getDouble("balance"), .001)
        assertTrue(BankMaintenance.applyToState(s, time(month = 12)))
        assertEquals(1, s.getJSONArray("movements").length())
    }
    @Test fun newSavingsEnrolledOnThirtyFirstWaitsUntilNextClose() {
        val a = account().put("bankAccountType", "savings").put("maintenancePolicy", "")
        val s = state(a)
        assertTrue(BankMaintenance.applyToState(s, time(month = 10, day = 31)))
        assertEquals("2026-12", a.getString("maintenanceNextMonth"))
        assertEquals(0, s.getJSONArray("movements").length())
        assertFalse(BankMaintenance.applyToState(s, time()))
        assertTrue(BankMaintenance.applyToState(s, time(month = 12)))
    }
    private fun birthday() = JSONObject().put("onboardingComplete", true).put("userBirthDate", "1990-11-01")
        .put("birthdayReminderEnabled", true).put("dailyMovementReminderEnabled", false)
    @Test fun birthdayFiresOncePerYearWithoutAgeAndCancelsWhenDateRemoved() {
        NativeJsonStore.writeState(context, birthday().put("birthdayReminderEnabled", false).toString())
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        DailyReminderReceiver().deliver(context)
        assertEquals(1, manager.activeNotifications.size)
        assertEquals(BirthdayReminder.ID, manager.activeNotifications.single().id)
        manager.cancelAll()
        DailyReminderReceiver().deliver(context)
        assertTrue(manager.activeNotifications.isEmpty())
        NativeJsonStore.writeState(context, birthday().put("userBirthDate", "").toString())
        DailyReminderScheduler.schedule(context)
        assertTrue(manager.activeNotifications.isEmpty())
    }
    @Test fun birthdayHandlesLeapDayAndRejectsInvalidDates() {
        assertEquals(2027, BirthdayReminder.dueYear(birthday().put("userBirthDate", "2000-02-29"), time(2027, 2, 28)))
        assertNull(BirthdayReminder.dueYear(birthday().put("userBirthDate", "2000-02-29"), time(2028, 2, 28)))
        assertEquals(2028, BirthdayReminder.dueYear(birthday().put("userBirthDate", "2000-02-29"), time(2028, 2, 29)))
        for (date in listOf("", "2026-02-30", "tomorrow", "1899-11-01", "2100-11-01"))
            assertNull(BirthdayReminder.dueYear(birthday().put("userBirthDate", date), time()))
    }
    @Test fun optionalSecurityCannotRemoveExistingPinWithoutVerification() {
        assertEquals(false, PinSecurity.disable(context, "")["pinEnabled"])
        PinSecurity.configure(context, "123456", false)
        try { PinSecurity.disable(context, "000000"); fail("Wrong PIN accepted") } catch (_: IllegalArgumentException) { }
        assertTrue(NativeJsonStore.readMain(context).getBoolean("pinEnabled"))
        assertEquals(false, PinSecurity.disable(context, "123456")["pinEnabled"])
        assertTrue(NativeJsonStore.readMain(context).getBoolean("securitySetupComplete"))
    }
}
