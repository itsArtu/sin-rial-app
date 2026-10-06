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
        assertFalse(BankMaintenance.applyToState(state, time(month = 10, day = 31)))
        assertTrue(BankMaintenance.applyToState(state, time()))
        assertEquals(316.0, state.getJSONArray("accounts").getJSONObject(0).getDouble("balance"), .00001)
        assertEquals(1, state.getJSONArray("movements").length())
        assertEquals("2026-11-01T00:00:00", state.getJSONArray("movements").getJSONObject(0).getString("date"))
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
            account().put("bankAccountType", "savings"), account().put("bankAccountType", ""))) {
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
    private fun birthday() = JSONObject().put("onboardingComplete", true).put("userBirthDate", "1990-11-01")
        .put("birthdayReminderEnabled", true).put("dailyMovementReminderEnabled", false)
    @Test fun birthdayFiresOncePerYearWithoutAgeAndCancelsWhenDateRemoved() {
        NativeJsonStore.writeState(context, birthday().put("birthdayReminderEnabled", false).toString())
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        DailyReminderReceiver().onReceive(context, Intent())
        assertEquals(1, manager.activeNotifications.size)
        assertEquals(BirthdayReminder.ID, manager.activeNotifications.single().id)
        manager.cancelAll()
        DailyReminderReceiver().onReceive(context, Intent())
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
