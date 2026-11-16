package com.lacaprichosa.app

import android.app.Application
import android.app.NotificationManager
import android.content.Context
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
class CardReminderTest {
    private val originalZone = TimeZone.getDefault()
    private lateinit var context: Application
    private fun at(year: Int, month: Int, day: Int) = Calendar.getInstance().apply {
        clear(); set(year, month - 1, day, 19, 0)
    }.timeInMillis
    private fun card(id: String = "card") = JSONObject().put("id", id).put("kind", "credit")
        .put("label", "Visa").put("balance", -100).put("dueDay", 31).put("cutDay", 15)
    private fun state(vararg cards: JSONObject) = JSONObject().put("accounts", JSONArray(cards.toList()))
        .put("dailyMovementReminderEnabled", false)
    @Before fun setup() {
        installTestCipher()
        TimeZone.setDefault(TimeZone.getTimeZone("America/Caracas"))
        context = RuntimeEnvironment.getApplication()
        shadowOf(context).grantPermissions(android.Manifest.permission.POST_NOTIFICATIONS)
        NativeJsonStore.prefs(context).edit().clear().commit()
    }
    @After fun cleanup() { TimeZone.setDefault(originalZone) }
    @Test fun clampsFebruaryIncludingLeapYearsAndMonthBoundaries() {
        assertTrue(CardReminder.notice(state(card()), at(2026, 2, 28))!!.text.contains("pago hoy"))
        assertTrue(CardReminder.notice(state(card()), at(2028, 2, 29))!!.text.contains("pago hoy"))
        assertTrue(CardReminder.notice(state(card().put("dueDay", 1)), at(2026, 12, 30))!!.text.contains("en 2"))
        assertNull(CardReminder.notice(state(card()), at(2026, 2, 23)))
    }
    @Test fun settledDeletedOrDisabledCardsDoNotNotify() {
        assertNull(CardReminder.notice(state(card().put("balance", 0)), at(2026, 10, 31)))
        assertNull(CardReminder.notice(state(), at(2026, 10, 31)))
        assertNull(CardReminder.notice(state(card()).put("creditRemindersEnabled", false), at(2026, 10, 31)))
    }
    @Test fun groupsCardsWithStableSignatureAndShortCopy() {
        val now = at(2026, 10, 31)
        val a = CardReminder.notice(state(card("a"), card("b"), card("c"), card("d")), now)!!
        val b = CardReminder.notice(state(card("d"), card("b"), card("c"), card("a")), now)!!
        assertEquals(a.signature, b.signature)
        assertTrue(a.text.contains("Y 1"))
        assertTrue(a.text.length < 200)
    }
    @Test fun receiverDeduplicatesAndCancelsAfterSettlement() {
        SystemClock.setCurrentTimeMillis(at(2026, 10, 31))
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        NativeJsonStore.writeState(context, state(card()).toString())
        DailyReminderReceiver().deliver(context)
        assertEquals(1, manager.activeNotifications.count { it.id == CardReminder.ID })
        manager.cancel(CardReminder.ID)
        DailyReminderReceiver().deliver(context)
        assertTrue(manager.activeNotifications.isEmpty())
        NativeJsonStore.writeState(context, state(card().put("balance", 0)).toString())
        DailyReminderScheduler.schedule(context)
        assertTrue(manager.activeNotifications.isEmpty())
    }
}
