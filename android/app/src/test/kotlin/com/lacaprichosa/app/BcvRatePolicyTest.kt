package com.lacaprichosa.app

import android.app.Application
import android.app.AlarmManager
import android.content.Context
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager
import org.robolectric.annotation.Config
import java.util.Calendar
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, instrumentedPackages = ["com.lacaprichosa.app"])
class BcvRatePolicyTest {
    @org.junit.Before fun secureStore() { installTestCipher() }
    private fun at(day: Int, hour: Int = 0, minute: Int = 0): Long = Calendar.getInstance(BcvRatePolicy.zone).apply {
        clear()
        set(2026, Calendar.SEPTEMBER, day, hour, minute)
    }.timeInMillis

    private fun quote(day: Int, rate: Double) = JSONObject().put("effective_date", "2026-09-$day")
        .put("USD", rate).put("EUR", rate * 1.2).put("updated_at", "2026-09-${day}T20:00:00Z")

    @Test fun midnightUsesCaracasRegardlessOfDeviceZone() {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Tokyo"))
            val rates = JSONArray().put(quote(21, 840.0)).put(quote(22, 850.0))
            assertEquals(840.0, BcvRatePolicy.active(rates, at(21, 23, 59))!!.getDouble("USD"), 0.0)
            assertEquals(850.0, BcvRatePolicy.active(rates, at(22))!!.getDouble("USD"), 0.0)
            assertEquals(at(22), BcvRatePolicy.nextBoundary(at(21, 23, 59)))
        } finally { TimeZone.setDefault(original) }
    }

    @Test fun fridayAdvancePersistsThroughHoliday() {
        val rates = JSONArray().put(quote(25, 840.0)).put(quote(29, 855.0))
        assertEquals(840.0, BcvRatePolicy.active(rates, at(25, 17, 59))!!.getDouble("USD"), 0.0)
        for (now in listOf(at(25, 18), at(26), at(28), at(29))) {
            assertEquals(855.0, BcvRatePolicy.active(rates, now)!!.getDouble("USD"), 0.0)
        }
        assertEquals(at(25, 18), BcvRatePolicy.nextBoundary(at(25, 17, 59)))
        assertEquals(at(26), BcvRatePolicy.nextBoundary(at(25, 18)))
    }

    @Test fun unavailableNextRateDoesNotInventValue() {
        val rates = JSONArray().put(quote(25, 840.0))
        assertEquals(840.0, BcvRatePolicy.active(rates, at(25, 18))!!.getDouble("USD"), 0.0)
        assertNull(BcvRatePolicy.active(JSONArray().put(quote(29, 850.0)), at(25, 10)))
    }

    @Test fun repeatedPromotionDoesNotChangePreviousRate() {
        val state = JSONObject().put("rate", 840.0).put("eurRate", 1008.0)
            .put("rateEffectiveDate", "2026-09-25")
            .put("bcvRateSnapshots", JSONArray().put(quote(25, 840.0)).put(quote(29, 855.0)))
        assertTrue(BcvRatePolicy.apply(state, at(25, 18)))
        assertFalse(BcvRatePolicy.apply(state, at(26)))
        assertEquals(840.0, state.getDouble("previousRate"), 0.0)
    }

    @Test fun snapshotsSurviveNativeStorageAndOlderFlutterSave() {
        val context = RuntimeEnvironment.getApplication()
        NativeJsonStore.prefs(context).edit().clear().commit()
        val state = JSONObject().put("rate", 840.0).put("eurRate", 1008.0)
            .put("rateEffectiveDate", "2026-09-25").put("rateLastAttemptMillis", at(25, 17))
            .put("bcvRateSnapshots", JSONArray().put(quote(25, 840.0)).put(quote(29, 855.0)))
        NativeJsonStore.writeState(context, state.toString())
        val newer = JSONObject(state.toString())
        BcvRatePolicy.apply(newer, at(25, 18))
        NativeJsonStore.updateRateFields(context, newer)
        NativeJsonStore.writeState(context, state.toString())
        val saved = NativeJsonStore.readState(context)
        assertEquals(855.0, saved.getDouble("rate"), 0.0)
        assertEquals(2, saved.getJSONArray("bcvRateSnapshots").length())
    }

    @Test fun refreshRunsAtMidnightAndPublicationHours() {
        assertEquals(at(22), BcvRatePolicy.nextFetch(at(21, 23, 59)))
        assertEquals(at(21, 17), BcvRatePolicy.nextFetch(at(21, 12)))
        assertEquals(at(21, 18), BcvRatePolicy.nextFetch(at(21, 17)))
        assertEquals(at(21, 19), BcvRatePolicy.nextFetch(at(21, 18)))
    }

    @Test fun boundaryAlarmUsesExactAccessOrInexactFallbackWithoutDuplicates() {
        val context = RuntimeEnvironment.getApplication()
        NativeJsonStore.prefs(context).edit().clear().commit()
        SystemClock.setCurrentTimeMillis(at(25, 17, 59))
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (exact in listOf(true, false)) {
            ShadowAlarmManager.setCanScheduleExactAlarms(exact)
            RateUpdateScheduler.schedule(context)
            RateUpdateScheduler.schedule(context)
            val boundary = shadowOf(alarm).scheduledAlarms.single {
                shadowOf(it.operation!!).savedIntent.component?.className == RateUpdateReceiver::class.java.name
            }
            assertEquals(at(25, 18), boundary.triggerAtMs)
            assertEquals(exact, boundary.windowLengthMs == 0L)
        }
    }
}
