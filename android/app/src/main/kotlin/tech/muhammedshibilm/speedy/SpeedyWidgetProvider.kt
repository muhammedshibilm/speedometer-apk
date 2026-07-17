package tech.muhammedshibilm.speedy

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import android.graphics.Color

class SpeedyWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.speedy_widget).apply {
                val tripScore = widgetData.getString("trip_score", "--")
                val scoreLabel = widgetData.getString("score_label", "No Trip")
                val maxSpeed = widgetData.getString("max_speed", "--")
                val distance = widgetData.getString("distance", "--")

                setTextViewText(R.id.tv_trip_score, tripScore)
                setTextViewText(R.id.tv_score_label, scoreLabel)
                setTextViewText(R.id.tv_max_speed, "Max Speed: $maxSpeed")
                setTextViewText(R.id.tv_distance, "Distance: $distance")
                
                val colorHex = when(scoreLabel) {
                    "Excellent" -> "#00E576"
                    "Good" -> "#76D800"
                    "Fair" -> "#FFC107"
                    "Poor" -> "#FF7200"
                    "Dangerous" -> "#FF1A1A"
                    else -> "#FFFFFF"
                }
                setTextColor(R.id.tv_trip_score, Color.parseColor(colorHex))
                setTextColor(R.id.tv_score_label, Color.parseColor(colorHex))
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
