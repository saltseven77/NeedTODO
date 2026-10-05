package com.needtodo.needtodo

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.time.LocalDate
import org.json.JSONObject

class AgendaWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { ids.forEach { render(context, manager, it) } }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) { render(context, manager, id) }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context,intent)
        if (intent.action in listOf(Intent.ACTION_DATE_CHANGED,Intent.ACTION_TIMEZONE_CHANGED,Intent.ACTION_TIME_CHANGED,Intent.ACTION_BOOT_COMPLETED,Intent.ACTION_MY_PACKAGE_REPLACED)) updateAll(context)
    }
    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context,AgendaWidget::class.java)).forEach { render(context,manager,it) }
        }
        private fun time(value: Int) = "%02d:%02d".format(value/60,value%60)
        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val snapshot = WidgetTheme.snapshot(context); val theme = WidgetTheme.appearance(snapshot)
            val today = LocalDate.now(); val date = today.toString()
            val options = manager.getAppWidgetOptions(id)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,280).coerceIn(180,600)
            val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,150).coerceIn(110,600)
            val view = RemoteViews(context.packageName,R.layout.agenda_widget)
            WidgetTheme.background(view,R.id.agenda_surface,theme,width,height)
            val ink = WidgetTheme.color(theme,"text",0xff292c32); val accent = WidgetTheme.color(theme,"accent",0xff477cae)
            view.setTextViewText(R.id.agenda_title,"${today.monthValue}月${today.dayOfMonth}日  星期${arrayOf("一","二","三","四","五","六","日")[today.dayOfWeek.value-1]}")
            view.setTextColor(R.id.agenda_title,ink); view.setTextColor(R.id.agenda_add,ink)
            view.setOnClickPendingIntent(R.id.agenda_add,WidgetTheme.launch(context,date,true))
            view.setOnClickPendingIntent(R.id.agenda_root,WidgetTheme.launch(context,date))
            view.removeAllViews(R.id.agenda_rows)
            val items = snapshot.optJSONArray("tasks")
            val tasks = mutableListOf<JSONObject>()
            if(items != null) for(i in 0 until items.length()) {
                val task = items.optJSONObject(i) ?: continue
                if(task.optString("date") == date && task.optString("scope") == "day" && !task.optBoolean("done") && !task.optBoolean("deleted")) tasks.add(task)
            }
            tasks.sortBy { if(it.isNull("startMinute")) 1441 else it.optInt("startMinute",1441) }
            val count = ((height-54)/42).coerceIn(1,8)
            for(task in tasks.take(count)) {
                val row = RemoteViews(context.packageName,R.layout.agenda_widget_row)
                val timed = !task.isNull("startMinute")
                val start = if(timed) time(task.optInt("startMinute")) else "全天"
                val end = if(!task.isNull("endMinute")) time(task.optInt("endMinute")) else ""
                row.setTextViewText(R.id.agenda_time,start+if(end.isNotEmpty()) "\n$end" else "")
                row.setTextViewText(R.id.agenda_task,task.optString("title"))
                row.setTextColor(R.id.agenda_time,ink);row.setTextColor(R.id.agenda_task,ink)
                row.setInt(R.id.agenda_bar,"setBackgroundColor",accent)
                row.setOnClickPendingIntent(R.id.agenda_row,WidgetTheme.launch(context,date))
                view.addView(R.id.agenda_rows,row)
            }
            view.setViewVisibility(R.id.agenda_empty,if(tasks.isEmpty()) View.VISIBLE else View.GONE)
            view.setTextColor(R.id.agenda_empty,ink)
            manager.updateAppWidget(id,view)
        }
    }
}
