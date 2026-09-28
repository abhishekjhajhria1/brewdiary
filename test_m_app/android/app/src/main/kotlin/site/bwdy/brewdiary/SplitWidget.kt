package site.bwdy.brewdiary

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import java.io.File

/**
 * Split at a glance: what you're owed and what you owe. Flutter draws the card
 * (lib/ui/home_widget.dart) whenever the Split page loads; tapping opens Split.
 */
class SplitWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        private const val FILE = "split_widget.png"

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (id in manager.getAppWidgetIds(ComponentName(context, SplitWidget::class.java))) {
                manager.updateAppWidget(id, views(context))
            }
        }

        private fun views(context: Context): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.mosaic_widget)
            val file = File(context.filesDir, FILE)
            val bitmap = if (file.exists()) BitmapFactory.decodeFile(file.absolutePath) else null
            if (bitmap != null) {
                v.setImageViewBitmap(R.id.mosaic_image, bitmap)
                v.setViewVisibility(R.id.mosaic_image, View.VISIBLE)
                v.setViewVisibility(R.id.mosaic_empty, View.GONE)
            } else {
                v.setTextViewText(R.id.mosaic_empty, context.getString(R.string.split_widget_empty))
                v.setViewVisibility(R.id.mosaic_image, View.GONE)
                v.setViewVisibility(R.id.mosaic_empty, View.VISIBLE)
            }
            val open = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("brewdiary://split"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            v.setOnClickPendingIntent(R.id.mosaic_root, PendingIntent.getActivity(context, 13, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            return v
        }
    }
}
