package com.needtodo.needtodo

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.util.Base64
import android.widget.RemoteViews
import org.json.JSONObject

object WidgetTheme {
    fun snapshot(context: Context): JSONObject = try {
        JSONObject(context.getSharedPreferences("needtodo_widget", Context.MODE_PRIVATE).getString("snapshot", "{}") ?: "{}")
    } catch (_: Exception) { JSONObject() }
    fun appearance(snapshot: JSONObject) = snapshot.optJSONObject("widgetAppearance") ?: JSONObject()
    fun palette(theme: JSONObject): JSONObject {
        val entries = theme.optJSONArray("palettes") ?: return JSONObject()
        for (i in 0 until entries.length()) {
            val entry = entries.optJSONObject(i) ?: continue
            if (entry.optString("id") == theme.optString("paletteId")) return entry
        }
        return JSONObject()
    }
    fun color(theme: JSONObject, field: String, fallback: Long) = palette(theme).optLong(field, fallback).toInt()
    fun launch(context: Context, date: String, add: Boolean = false, view: String = "calendar"): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).putExtra("date", date).putExtra("add", add).putExtra("view", view)
            .setAction("com.needtodo.OPEN.$date.$add.$view").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, (date + add + view).hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    fun collectionLaunch(context: Context, id: Int, date: String): PendingIntent {
        val intent = Intent(context,MainActivity::class.java).putExtra("date",date).putExtra("view","agenda")
            .setAction("com.needtodo.AGENDA.$id").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val mutable = if (android.os.Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getActivity(context,id,intent,PendingIntent.FLAG_UPDATE_CURRENT or mutable)
    }
    fun background(view: RemoteViews, imageId: Int, theme: JSONObject, width: Int, height: Int) {
        val surface = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(surface)
        val radius = theme.optDouble("radius", 12.0).toFloat().coerceIn(0f, 48f)
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        canvas.clipPath(Path().apply { addRoundRect(rect, radius, radius, Path.Direction.CW) })
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = WidgetTheme.color(theme, "background", 0xffffffff)
            alpha = (Color.alpha(color) * theme.optDouble("opacity", 1.0)).toInt().coerceIn(0,255)
        }
        canvas.drawRect(rect, paint)
        try {
            val data = theme.optString("background")
            if (data.startsWith("data:image/")) {
                val bytes = Base64.decode(data.substringAfter(','), Base64.DEFAULT)
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap != null) {
                    val scale = maxOf(width.toFloat()/bitmap.width, height.toFloat()/bitmap.height)
                    val w = bitmap.width*scale; val h = bitmap.height*scale
                    paint.alpha = (255*theme.optDouble("imageOpacity", .55)).toInt().coerceIn(0,255)
                    canvas.drawBitmap(bitmap, null, RectF((width-w)/2, (height-h)/2, (width+w)/2, (height+h)/2), paint)
                    bitmap.recycle()
                }
            }
        } catch (_: Exception) { }
        view.setImageViewBitmap(imageId, surface)
    }
}
