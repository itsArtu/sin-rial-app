package com.lacaprichosa.app

import android.content.Context
import android.content.Intent
import android.net.Uri

object BankAppShortcuts {
    fun open(context: Context, packageName: String): Boolean {
        if (packageName == context.packageName || !Regex("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+").matches(packageName)) return false
        val launch = context.packageManager.getLaunchIntentForPackage(packageName) ?: return false
        // Launch only the app's public entry point, without financial data or deep links.
        return runCatching { context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true }.getOrDefault(false)
    }

    fun openOrStore(context: Context, packageName: String?, query: String): Boolean {
        val valid = packageName?.takeIf {
            it != context.packageName && Regex("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+").matches(it)
        }
        if (packageName != null && valid == null) return false
        if (valid != null && open(context, valid)) return true
        if (valid == null && query.isBlank()) return false
        val suffix = if (valid != null) "details?id=${Uri.encode(valid)}"
            else "search?q=${Uri.encode(query.trim().take(120))}&c=apps"
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://$suffix"))
            .setPackage("com.android.vending").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (runCatching { context.startActivity(market); true }.getOrDefault(false)) return true
        val web = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/$suffix"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { context.startActivity(web); true }.getOrDefault(false)
    }
}
