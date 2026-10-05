package com.needtodo.needtodo

import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONObject

class AgendaWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = object : RemoteViewsFactory {
        private var tasks = emptyList<JSONObject>()
        private var theme = JSONObject()
        override fun onCreate() { onDataSetChanged() }
        override fun onDataSetChanged() {
            val snapshot = WidgetTheme.snapshot(applicationContext)
            tasks = AgendaRows.tasks(snapshot);theme = WidgetTheme.appearance(snapshot)
        }
        override fun onDestroy() {tasks = emptyList()}
        override fun getCount() = tasks.size
        override fun getViewAt(position: Int): RemoteViews? = tasks.getOrNull(position)?.let { AgendaRows.view(applicationContext,it,theme) }
        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount() = 1
        override fun getItemId(position: Int) = position.toLong()
        override fun hasStableIds() = false
    }
}
