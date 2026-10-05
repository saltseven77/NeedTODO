package com.needtodo.needtodo

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Build
import android.net.Uri
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
            view.setOnClickPendingIntent(R.id.agenda_add,WidgetTheme.launch(context,date,true,"agenda"))
            view.setOnClickPendingIntent(R.id.agenda_root,WidgetTheme.launch(context,date,view="agenda"))
            val tasks = AgendaRows.tasks(snapshot)
            if (Build.VERSION.SDK_INT >= 31) {
                val collection = RemoteViews.RemoteCollectionItems.Builder().setHasStableIds(false).setViewTypeCount(1)
                tasks.forEachIndexed { index, task -> collection.addItem(index.toLong(), AgendaRows.view(context,task,theme)) }
                view.setRemoteAdapter(R.id.agenda_rows,collection.build())
            } else {
                val adapter = Intent(context,AgendaWidgetService::class.java)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID,id).setData(Uri.parse("needtodo-widget://agenda/$id"))
                view.setRemoteAdapter(R.id.agenda_rows,adapter)
            }
            view.setPendingIntentTemplate(R.id.agenda_rows,WidgetTheme.collectionLaunch(context,id,date))
            view.setEmptyView(R.id.agenda_rows,R.id.agenda_empty)
            view.setTextColor(R.id.agenda_empty,ink)
            manager.updateAppWidget(id,view)
            if (Build.VERSION.SDK_INT < 31) manager.notifyAppWidgetViewDataChanged(id,R.id.agenda_rows)
        }
    }
}
