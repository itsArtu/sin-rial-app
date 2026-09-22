package com.lacaprichosa.app

import android.app.Application
import android.content.ComponentName
import android.content.Intent
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class)
class QuickAccessTest {
    private val context get() = RuntimeEnvironment.getApplication()
    @Before fun setup() { installTestCipher() }

    @Test fun quickIntentsAreExplicitImmutableAndDoNotOpenMainActivity() {
        for (action in listOf("income", "expense", "calculator")) {
            val pending = QuickAccessActivity.pendingIntent(context, action)
            val intent = shadowOf(pending).savedIntent
            assertEquals(QuickAccessActivity::class.java.name, intent.component!!.className)
            assertEquals(action, QuickAccessActivity.actionFrom(intent))
            assertTrue(pending.isImmutable)
            assertTrue(intent.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        }
        val info = context.packageManager.getActivityInfo(ComponentName(context, QuickAccessActivity::class.java), 0)
        assertFalse(info.exported)
        assertEquals("com.lacaprichosa.app.quick", info.taskAffinity)
    }

    @Test fun staleWindowCannotOverwriteAnotherWindowCommit() {
        NativeJsonStore.writeState(context, """{"accounts":[{"id":"cash","balance":100}],"movements":[]}""")
        val (state, revision) = NativeJsonStore.readUiState(context)
        val first = JSONObject(state).put("movements", org.json.JSONArray().put(JSONObject().put("id", "one")))
        first.getJSONArray("accounts").getJSONObject(0).put("balance", 90)
        val committed = NativeJsonStore.writeState(context, first.toString(), revision)
        assertTrue(committed > revision)
        assertThrows(NativeJsonStore.StaleStateException::class.java) {
            NativeJsonStore.writeState(context, state, revision)
        }
        val actual = NativeJsonStore.readState(context)
        assertEquals(90, actual.getJSONArray("accounts").getJSONObject(0).getInt("balance"))
        assertEquals(1, actual.getJSONArray("movements").length())
        assertFalse(actual.has("uiRevision"))
    }

    @Test fun rateRefreshDoesNotInvalidateUiSessionAndNewerRateIsRetained() {
        NativeJsonStore.writeState(context, """{"accounts":[],"rate":800,"rateLastAttemptMillis":1}""")
        val (state, revision) = NativeJsonStore.readUiState(context)
        NativeJsonStore.updateRateFields(context, JSONObject().put("rate", 852.42).put("rateLastAttemptMillis", 2))
        assertEquals(revision, NativeJsonStore.uiRevision(context))
        NativeJsonStore.writeState(context, state, revision)
        assertEquals(852.42, NativeJsonStore.readMain(context).getDouble("rate"), 0.001)
    }
}
