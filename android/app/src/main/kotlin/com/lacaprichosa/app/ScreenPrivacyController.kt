package com.lacaprichosa.app

import android.app.Activity
import android.os.Build
import android.view.WindowManager

internal class ScreenPrivacyController(private val activity: Activity) {
    private var locked = true
    private var hideInBackground = false
    private var suspended = false
    private var paused = false

    fun update(locked: Boolean, hideInBackground: Boolean, suspended: Boolean) {
        this.locked = locked
        this.hideInBackground = hideInBackground
        this.suspended = suspended
        apply()
    }

    fun onPause() {
        paused = true
        apply()
    }

    fun onResume() {
        paused = false
        apply()
    }

    private fun apply() {
        if (locked || (hideInBackground && (paused || suspended))) {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            activity.setRecentsScreenshotEnabled(!locked && !hideInBackground)
        }
    }
}
