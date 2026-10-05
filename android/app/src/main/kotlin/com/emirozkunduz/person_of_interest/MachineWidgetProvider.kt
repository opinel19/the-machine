package com.emirozkunduz.person_of_interest

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/** Home screen widget: the Machine's box; tapping it opens the feed. */
class MachineWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val views = RemoteViews(context.packageName, R.layout.machine_widget).apply {
            setOnClickPendingIntent(R.id.widget_root, open)
        }
        ids.forEach { manager.updateAppWidget(it, views) }
    }
}
