package com.leocy.hitable

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

/**
 * 小组件数据的接收端。
 *
 * 沿用原始实现的做法：整体序列化后写 SharedPreferences，再触发刷新。
 * 新增 dateLabel / weekLabel / slotCount 三个标量（头部用），
 * 以及 palette.*（配色，由 Dart 下发以支持「跟随应用」与自定义）。
 *
 * ⚠️ `slots` 必须用 `JSONArray(...)` 序列化，**不能**直接 `List.toString()`：
 * Kotlin 的 List/Map toString 产出 `[{name=x}]` 这种非 JSON 文本，
 * 读回来 `JSONArray(raw)` 会抛异常、被兜底成空数组，
 * 表现为小组件「今天没有课」而实际有课。原版正是用 JSONArray 才一直正常。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "offline_course_schedule/widget",
        ).setMethodCallHandler { call, result ->
            if (call.method != "update") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val payload = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()

            val slots = (payload["slots"] as? List<*>) ?: emptyList<Any?>()
            val slotsJson = runCatching { JSONArray(slots).toString() }
                .getOrElse { "[]" }

            val editor = getSharedPreferences(NextCourseWidget.PREFS_NAME, MODE_PRIVATE)
                .edit()
                .putString(NextCourseWidget.SLOTS_KEY, slotsJson)
                .putString(
                    NextCourseWidget.DATE_LABEL_KEY,
                    payload["dateLabel"]?.toString() ?: "",
                )
                .putString(
                    NextCourseWidget.WEEK_LABEL_KEY,
                    payload["weekLabel"]?.toString() ?: "",
                )
                .putInt(
                    NextCourseWidget.COUNT_KEY,
                    (payload["slotCount"] as? Number)?.toInt() ?: 0,
                )
                // 自定义背景：路径非空即「自定义背景模式」，原生切另一套元素逻辑。
                .putString(
                    NextCourseWidget.BG_PATH_KEY,
                    payload["bgPath"]?.toString() ?: "",
                )
                .putFloat(
                    NextCourseWidget.BG_DIM_KEY,
                    (payload["bgDim"] as? Number)?.toFloat() ?: 0f,
                )
                .putFloat(
                    NextCourseWidget.CARD_ALPHA_KEY,
                    (payload["cardAlpha"] as? Number)?.toFloat() ?: 1f,
                )
                .putFloat(
                    NextCourseWidget.TEXT_ALPHA_KEY,
                    (payload["textAlpha"] as? Number)?.toFloat() ?: 1f,
                )

            (payload["palette"] as? Map<*, *>)?.let {
                writePalette(editor, NextCourseWidget.PALETTE_PREFIX, it)
            }
            (payload["paletteNight"] as? Map<*, *>)?.let {
                writePalette(editor, NextCourseWidget.PALETTE_NIGHT_PREFIX, it)
            }
            editor.apply()

            NextCourseWidget.updateAll(this)
            result.success(null)
        }
    }

    /** 把一组 `key -> ARGB` 写进 prefs，键名前加 [prefix]。 */
    private fun writePalette(
        editor: android.content.SharedPreferences.Editor,
        prefix: String,
        palette: Map<*, *>,
    ) {
        palette.forEach { (key, value) ->
            val argb = (value as? Number)?.toInt() ?: return@forEach
            editor.putInt(prefix + key.toString(), argb)
        }
    }
}
