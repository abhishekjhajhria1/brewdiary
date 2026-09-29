package site.bwdy.brewdiary

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/**
 * Quick log: +1 water or +1 cigarette from the home screen. A tap opens the app on
 * brewdiary://quick/<what>, which writes a real entry for today (the same one the
 * day counter writes) and shows a toast. Today's counts are pushed here by Flutter.
 */
class QuickLogWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        private const val PREFS = "brewdiary_widgets"

        fun setCounts(context: Context, water: Int, cigarettes: Int) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putInt("water", water).putInt("cigarettes", cigarettes).apply()
            val manager = AppWidgetManager.getInstance(context)
            for (id in manager.getAppWidgetIds(ComponentName(context, QuickLogWidget::class.java))) {
                manager.updateAppWidget(id, views(context))
            }
        }

        private fun open(context: Context, what: String, code: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("brewdiary://quick/$what"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        private fun views(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val v = RemoteViews(context.packageName, R.layout.quick_log_widget)
            v.setTextViewText(R.id.quick_water_count, prefs.getInt("water", 0).toString())
            v.setTextViewText(R.id.quick_cig_count, prefs.getInt("cigarettes", 0).toString())
            v.setOnClickPendingIntent(R.id.quick_water, open(context, "water", 11))
            v.setOnClickPendingIntent(R.id.quick_cig, open(context, "cigarette", 12))
            return v
        }
    }
}
