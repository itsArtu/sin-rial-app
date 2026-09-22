package com.lacaprichosa.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/** A private, separate task. It never places the main app behind the quick form. */
class QuickAccessActivity : MainActivity() {
    override val quickAccess = true
    override fun getDartEntrypointFunctionName() = "quickMain"
    override fun getBackgroundMode() = BackgroundMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.attributes = window.attributes.apply { dimAmount = 0.38f }
    }

    companion object {
        private const val EXTRA_ACTION = "quick_action"
        fun actionFrom(intent: Intent): String =
            intent.getStringExtra(EXTRA_ACTION)?.takeIf { it in setOf("income", "expense", "calculator") } ?: "calculator"

        fun pendingIntent(context: Context, action: String): PendingIntent {
            require(action in setOf("income", "expense", "calculator"))
            val intent = Intent(context, QuickAccessActivity::class.java).apply {
                this.action = "com.lacaprichosa.app.QUICK_$action"
                putExtra(EXTRA_ACTION, action)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(context, action.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}
