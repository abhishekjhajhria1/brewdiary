package site.bwdy.brewdiary

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import java.io.File

/**
 * The home-screen widget: this month's mosaic. Flutter draws the card
 * (lib/ui/home_widget.dart) into the app's files dir; this just shows that
 * picture and opens the app on tap. No network, no data of its own.
 */
class MosaicWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        private const val FILE = "mosaic_widget.png"

        /** Redraw every placed widget (called from Flutter after the card is saved). */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, MosaicWidget::class.java))
            for (id in ids) manager.updateAppWidget(id, views(context))
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
                v.setViewVisibility(R.id.mosaic_image, View.GONE)
                v.setViewVisibility(R.id.mosaic_empty, View.VISIBLE)
            }
            val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pending = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            v.setOnClickPendingIntent(R.id.mosaic_root, pending)
            return v
        }
    }
}
