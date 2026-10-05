package com.needtodo.needtodo

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.LocalDate

object AgendaRows {
    fun tasks(snapshot: JSONObject): List<JSONObject> {
        val today = LocalDate.now().toString()
        val source = snapshot.optJSONArray("tasks") ?: return emptyList()
        val tasks = mutableListOf<JSONObject>()
        for (i in 0 until source.length()) {
            val item = source.optJSONObject(i) ?: continue
            if (item.optString("date") == today && item.optString("scope") == "day" && !item.optBoolean("done") && !item.optBoolean("deleted")) tasks.add(item)
        }
        return tasks.sortedBy { if (it.isNull("startMinute")) 1441 else it.optInt("startMinute",1441) }
    }
    private fun time(minute: Int) = "%02d:%02d".format(minute/60,minute%60)
    fun view(context: Context, task: JSONObject, theme: JSONObject): RemoteViews {
        val row = RemoteViews(context.packageName,R.layout.agenda_widget_row)
        val start = if(task.isNull("startMinute")) "全天" else time(task.optInt("startMinute"))
        val end = if(task.isNull("endMinute")) "" else time(task.optInt("endMinute"))
        row.setTextViewText(R.id.agenda_time,start + if(end.isEmpty()) "" else "\n$end")
        row.setTextViewText(R.id.agenda_task,task.optString("title"))
        val ink = WidgetTheme.color(theme,"text",0xff292c32)
        row.setTextColor(R.id.agenda_time,ink);row.setTextColor(R.id.agenda_task,ink)
        row.setInt(R.id.agenda_bar,"setBackgroundColor",WidgetTheme.color(theme,"accent",0xff477cae))
        row.setOnClickFillInIntent(R.id.agenda_row,Intent().putExtra("date",task.optString("date")).putExtra("view","agenda"))
        return row
    }
}
