package com.needtodo.needtodo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.BitmapFactory
import android.util.Base64
import android.os.Bundle
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter

class CalendarWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { ids.forEach { render(context, manager, it) } }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) { render(context, manager, id) }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == NAVIGATE) {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
            if (id < 0) return
            val prefs = context.getSharedPreferences("needtodo_widget", Context.MODE_PRIVATE)
            val previous = shownMonth(context, id)
            val delta = intent.getIntExtra("delta", 0).coerceIn(-1, 1)
            val next = if (delta == 0) YearMonth.now() else previous.plusMonths(delta.toLong())
            prefs.edit().putString("month_$id", next.toString()).apply()
            render(context, AppWidgetManager.getInstance(context), id)
        } else if (intent.action in listOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) updateAll(context)
    }
    override fun onDeleted(context: Context, ids: IntArray) {
        val editor = context.getSharedPreferences("needtodo_widget", Context.MODE_PRIVATE).edit()
        ids.forEach { editor.remove("month_$it") }; editor.apply()
    }
    companion object {
        private const val NAVIGATE = "com.needtodo.WIDGET_MONTH"
        private fun shownMonth(context: Context, id: Int): YearMonth = try {
            val value = context.getSharedPreferences("needtodo_widget", Context.MODE_PRIVATE).getString("month_$id", null)
            if (value == null) YearMonth.now() else YearMonth.parse(value)
        } catch (_: Exception) { YearMonth.now() }
        private fun navigate(context: Context, id: Int, delta: Int): PendingIntent {
            val intent = Intent(context, CalendarWidget::class.java).setAction(NAVIGATE)
                .setData(Uri.parse("needtodo-widget://$id/$delta"))
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id).putExtra("delta", delta)
            return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        fun updateAll(context: Context) { val manager = AppWidgetManager.getInstance(context); manager.getAppWidgetIds(ComponentName(context, CalendarWidget::class.java)).forEach { render(context, manager, it) } }
        private fun launch(context: Context, date: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).putExtra("date", date).setAction("com.needtodo.OPEN.$date").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(context, date.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val snapshot = try { JSONObject(context.getSharedPreferences("needtodo_widget", Context.MODE_PRIVATE).getString("snapshot", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
            val theme = snapshot.optJSONObject("calendar") ?: JSONObject()
            val palettes = theme.optJSONArray("palettes")
            var palette = JSONObject()
            if (palettes != null) for (i in 0 until palettes.length()) { val p = palettes.optJSONObject(i); if (p?.optString("id") == theme.optString("paletteId")) palette = p }
            val text = palette.optLong("text", 0xff34475e).toInt()
            val accent = palette.optLong("accent", 0xff527ca7).toInt()
            val today = LocalDate.now(); val month = shownMonth(context, id).atDay(1); val start = month.minusDays((month.dayOfWeek.value - 1).toLong())
            val tasks = snapshot.optJSONArray("tasks")
            val counts = mutableMapOf<String, Int>(); val agenda = mutableListOf<String>()
            if (tasks != null) for (i in 0 until tasks.length()) { val task = tasks.optJSONObject(i) ?: continue; if (task.optBoolean("deleted") || task.optBoolean("done") || task.optString("scope") != "day") continue; val date = task.optString("date"); counts[date] = (counts[date] ?: 0) + 1; if (date == today.toString()) agenda.add(task.optString("title")) }
            val view = RemoteViews(context.packageName, R.layout.calendar_widget)
            val options = manager.getAppWidgetOptions(id)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 280).coerceIn(180, 600)
            val widgetHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 240).coerceIn(190, 600)
            val surface = Bitmap.createBitmap(width, widgetHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(surface)
            val radius = theme.optDouble("radius", 22.0).toFloat().coerceIn(0f,48f)
            val rect = RectF(0f,0f,width.toFloat(),widgetHeight.toFloat())
            val clip = Path().apply { addRoundRect(rect,radius,radius,Path.Direction.CW) }
            canvas.clipPath(clip)
            val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = palette.optLong("background",0xfff7f8fa).toInt(); alpha = (Color.alpha(color)*theme.optDouble("opacity",1.0)).toInt().coerceIn(0,255) }
            canvas.drawRect(rect,fill)
            try {
                val image = theme.optString("background")
                if(image.startsWith("data:image/")) {
                    val bytes = Base64.decode(image.substringAfter(','),Base64.DEFAULT)
                    val bitmap = BitmapFactory.decodeByteArray(bytes,0,bytes.size)
                    if(bitmap!=null) {
                        val scale = maxOf(width.toFloat()/bitmap.width,widgetHeight.toFloat()/bitmap.height)
                        val w=bitmap.width*scale;val h=bitmap.height*scale
                        val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply { alpha=(255*theme.optDouble("imageOpacity",.55)).toInt().coerceIn(0,255) }
                        canvas.drawBitmap(bitmap,null,RectF((width-w)/2,(widgetHeight-h)/2,(width+w)/2,(widgetHeight+h)/2),paint)
                        bitmap.recycle()
                    }
                }
            } catch (_:Exception) { /* Keep a readable background if an image is invalid. */ }
            view.setImageViewBitmap(R.id.widget_surface,surface)
            val weekdays=RemoteViews(context.packageName,R.layout.widget_week)
            val weekIds=intArrayOf(R.id.day0,R.id.day1,R.id.day2,R.id.day3,R.id.day4,R.id.day5,R.id.day6)
            arrayOf("一","二","三","四","五","六","日").forEachIndexed { i,label -> weekdays.setTextViewText(weekIds[i],label);weekdays.setTextColor(weekIds[i],text) }
            view.removeAllViews(R.id.widget_weekdays);view.addView(R.id.widget_weekdays,weekdays)
            view.setTextViewText(R.id.widget_title, "${month.year}年 ${month.monthValue}月")
            view.setTextColor(R.id.widget_title, text)
            view.setOnClickPendingIntent(R.id.widget_title, navigate(context, id, 0))
            view.setTextColor(R.id.widget_previous, text); view.setTextColor(R.id.widget_next, text)
            view.setOnClickPendingIntent(R.id.widget_previous, navigate(context, id, -1))
            view.setOnClickPendingIntent(R.id.widget_next, navigate(context, id, 1))
            view.setOnClickPendingIntent(R.id.widget_root, launch(context, today.toString()))
            view.removeAllViews(R.id.widget_grid)
            for (row in 0..5) {
                val line = RemoteViews(context.packageName, R.layout.widget_week)
                val ids = intArrayOf(R.id.day0,R.id.day1,R.id.day2,R.id.day3,R.id.day4,R.id.day5,R.id.day6)
                for (column in 0..6) {
                    val date = start.plusDays((row*7+column).toLong()); val key = date.format(DateTimeFormatter.ISO_LOCAL_DATE)
                    line.setTextViewText(ids[column], "${date.dayOfMonth}${if ((counts[key] ?: 0)>0) "·" else ""}")
                    line.setTextColor(ids[column], if (date == today) accent else if (YearMonth.from(date) == YearMonth.from(month)) text else Color.GRAY)
                    line.setInt(ids[column], "setPaintFlags", Paint.ANTI_ALIAS_FLAG or (if (date == today) Paint.FAKE_BOLD_TEXT_FLAG else 0))
                    line.setOnClickPendingIntent(ids[column], launch(context, key))
                }
                view.addView(R.id.widget_grid, line)
            }
            val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180)
            view.setViewVisibility(R.id.widget_agenda, if (height >= 260 && agenda.isNotEmpty()) View.VISIBLE else View.GONE)
            view.setTextViewText(R.id.widget_agenda, agenda.take(if (height >= 340) 3 else 2).joinToString("\n"))
            view.setTextColor(R.id.widget_agenda, text)
            manager.updateAppWidget(id, view)
        }
    }
}
