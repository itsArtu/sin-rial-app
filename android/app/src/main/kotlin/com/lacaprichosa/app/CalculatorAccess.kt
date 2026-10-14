package com.lacaprichosa.app

import org.json.JSONObject

/** The calculator engine receives rates and appearance, never the ledger or credentials. */
internal object CalculatorAccess {
    val allowedMethods = setOf("quickAction", "readAppearance", "readCalculatorState",
        "closeQuickAccess", "openFullApp", "setScreenPrivacy", "setSystemBars", "scheduleRateUpdate")

    fun project(source: JSONObject): JSONObject = JSONObject().apply {
        for (key in NativeJsonStore.rateKeys + listOf("darkMode", "themeColor")) {
            if (source.has(key)) put(key, source.get(key))
        }
    }
}
