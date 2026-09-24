package com.leocy.hitable

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * 今日课程小组件。
 *
 * 改造自原「下一节课」小组件（已验证可用的实现），保留其全部成熟做法，
 * 只把「单个下一节课 + 倒计时」换成「当日课程列表」：
 *
 * - **4 个固定槽位**，不用的整体 GONE —— 不用 `View.addView`。
 *   运行时 addView 在部分 ROM 的 RemoteViews 白名单里支持不佳，
 *   会静默失败导致整块空白，这是上一版「显示不出来」的根因。
 * - 颜色直接写十六进制常量，与布局保持一致。
 * - 顶部给出日期、教学周、当日节数。
 * - 每行右侧状态：未开始显示开课时间、进行中「进行中」、已结束「已结束」。
 * - 已结束沉底（排序在 Dart 侧完成）。
 *
 * 数据由 Dart 侧按「大节」聚合后经 MethodChannel 写入 SharedPreferences。
 */
class NextCourseWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
        scheduleNextRefresh(context)
    }

    /**
     * 用户拖动改了小组件尺寸。
     *
     * 铺满已由 `centerCrop` 保证，这里重贴一次是为了：
     * 让 `clipToOutline` 的圆角在尺寸变化后重新生效，
     * 并顺手让「进行中/已结束」按当前时间重新判定。
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) updateAll(context)
    }

    companion object {
        const val PREFS_NAME = "next_course_widget"
        const val COURSES_KEY = "courses"

        /** 新版键名（当日大节列表），回退读 [COURSES_KEY] 兼容旧缓存。 */
        const val SLOTS_KEY = "slots"
        const val DATE_LABEL_KEY = "dateLabel"
        const val WEEK_LABEL_KEY = "weekLabel"
        const val COUNT_KEY = "slotCount"

        /**
         * 自定义背景图路径（Dart 侧已算好模糊、写成 PNG）。
         * **非空即代表「自定义背景模式」** —— 此时才启用半透明卡片
         * 与文字透明度这两个独立可调项。
         */
        const val BG_PATH_KEY = "bgPath"

        /** 背景明暗蒙层强度（0~0.8）：黑/白按深浅模式选择，合成时叠加。 */
        const val BG_DIM_KEY = "bgDim"

        /** 课程卡片不透明度（0.1~1.0），作用于卡片底色那一层。 */
        const val CARD_ALPHA_KEY = "cardAlpha"

        /** 文字内容不透明度（0.1~1.0），只作用于文字，不影响色条。 */
        const val TEXT_ALPHA_KEY = "textAlpha"

        /** 配色在 SharedPreferences 里的前缀（由 Dart 下发，浅色用）。 */
        const val PALETTE_PREFIX = "palette."

        /** 深色配色前缀（同样由 Dart 下发）。 */
        const val PALETTE_NIGHT_PREFIX = "palette.night."

        private const val ACTION_REFRESH = "com.leocy.hitable.REFRESH_WIDGET"

        /** 小组件高度有限，最多显示 4 行。 */
        private const val MAX_ROWS = 4

        // ---- 浅色回退值（Dart 未下发时使用，与布局默认一致）----
        private const val L_TEXT = 0xFF111111.toInt()
        private const val L_SUB = 0xFF8A8A8E.toInt()
        private const val L_ACTIVE = 0xFF0A84FF.toInt()
        private const val L_ACCENT = 0xFFFF9500.toInt()
        private const val L_DONE_TEXT = 0xFFA0A0A5.toInt()
        private const val L_CARD = 0xFFF2F2F7.toInt()
        private const val L_ACTIVE_BG = 0xFFE3F0FF.toInt()
        private const val L_DONE_BG = 0xFFEFFEF4.toInt()

        // ---- 深色回退值 ----
        private const val D_TEXT = 0xFFF5F5F7.toInt()
        private const val D_SUB = 0xFF9A9AA0.toInt()
        private const val D_ACTIVE = 0xFF0A84FF.toInt()
        private const val D_ACCENT = 0xFFFF9F0A.toInt()
        private const val D_DONE_TEXT = 0xFF7C7C82.toInt()
        private const val D_CARD = 0xFF232325.toInt()
        private const val D_ACTIVE_BG = 0xFF12325B.toInt()
        private const val D_DONE_BG = 0xFF232325.toInt()

        /**
         * 一组渲染配色。
         *
         * [night] 由调用方从当前 Configuration 读出 —— 小组件由原生渲染，
         * 拿不到 Flutter 的 Theme，系统深浅只能自己感知。
         * 按模式选用 Dart 下发的浅色 / 深色色板；某项缺省时回退到常量。
         */
        private class Palette(
            private val prefs: android.content.SharedPreferences,
            private val night: Boolean,
        ) {
            private fun get(key: String, light: Int, dark: Int): Int {
                val prefix = if (night) PALETTE_NIGHT_PREFIX else PALETTE_PREFIX
                val pushed = prefs.getInt(prefix + key, NO_COLOR)
                if (pushed != NO_COLOR) return pushed
                return if (night) dark else light
            }

            val text get() = get("text", L_TEXT, D_TEXT)
            val sub get() = get("sub", L_SUB, D_SUB)
            val active get() = get("active", L_ACTIVE, D_ACTIVE)
            val accent get() = get("accent", L_ACCENT, D_ACCENT)
            val doneText get() = get("doneText", L_DONE_TEXT, D_DONE_TEXT)
            val card get() = get("card", L_CARD, D_CARD)
            val activeBg get() = get("activeBg", L_ACTIVE_BG, D_ACTIVE_BG)
            val doneBg get() = get("doneBg", L_DONE_BG, D_DONE_BG)
        }

        /** 用来区分「没下发」与「下发了纯黑」的哨兵值。 */
        private const val NO_COLOR = Int.MIN_VALUE

        /** 当前系统是否深色。 */
        private fun isNight(context: Context): Boolean =
            (context.resources.configuration.uiMode and
                android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NextCourseWidget::class.java)
            val ids = manager.getAppWidgetIds(component)
            ids.forEach { updateWidget(context, manager, it) }
            scheduleNextRefresh(context)
        }

        /**
         * 槽位控件 id，索引 0..3 对应 slot1..slot4。
         *
         * 顺序：`[槽位容器, 色条, 课程名, 地点教师, 状态, 卡片底色层]`。
         */
        private val SLOT_IDS = arrayOf(
            intArrayOf(R.id.slot1, R.id.slot1_bar, R.id.slot1_name, R.id.slot1_meta, R.id.slot1_status, R.id.slot1_card),
            intArrayOf(R.id.slot2, R.id.slot2_bar, R.id.slot2_name, R.id.slot2_meta, R.id.slot2_status, R.id.slot2_card),
            intArrayOf(R.id.slot3, R.id.slot3_bar, R.id.slot3_name, R.id.slot3_meta, R.id.slot3_status, R.id.slot3_card),
            intArrayOf(R.id.slot4, R.id.slot4_bar, R.id.slot4_name, R.id.slot4_meta, R.id.slot4_status, R.id.slot4_card),
        )

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.next_course_widget)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            val dateLabel = prefs.getString(DATE_LABEL_KEY, "") ?: ""
            val weekLabel = prefs.getString(WEEK_LABEL_KEY, "") ?: ""
            val raw = prefs.getString(SLOTS_KEY, null)
                ?: prefs.getString(COURSES_KEY, "[]")
                ?: "[]"
            val slots = runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
            // 深浅在此刻从 Configuration 读，切系统深色后下次渲染即生效
            val night = isNight(context)
            val palette = Palette(prefs, night)

            // ---- 自定义背景模式 ----
            // 只有「路径非空 + 文件还在 + 贴图成功」才真正进入这套独立逻辑。
            // 图被用户清理掉或解码失败时静默退回普通模式，不能给一块白板。
            val bgPath = prefs.getString(BG_PATH_KEY, "") ?: ""
            val bgBitmap = if (bgPath.isEmpty()) {
                null
            } else {
                runCatching {
                    backgroundBitmap(
                        bgPath,
                        prefs.getFloat(BG_DIM_KEY, 0f).coerceIn(0f, 0.8f),
                        night,
                    )
                }.getOrNull()
            }
            val backgroundMode = bgBitmap != null
            if (backgroundMode) {
                views.setViewVisibility(R.id.widget_bg, View.VISIBLE)
                views.setImageViewBitmap(R.id.widget_bg, bgBitmap)
            } else {
                views.setViewVisibility(R.id.widget_bg, View.GONE)
            }
            // 两个透明度只在自定义背景模式下生效：没有背景时卡片就该是不透明的。
            val cardAlpha = if (backgroundMode) {
                prefs.getFloat(CARD_ALPHA_KEY, 1f).coerceIn(0.05f, 1f)
            } else {
                1f
            }
            val textAlpha = if (backgroundMode) {
                prefs.getFloat(TEXT_ALPHA_KEY, 1f).coerceIn(0.05f, 1f)
            } else {
                1f
            }

            // ---- 头部（与课程之间不用分割线）----
            if (dateLabel.isBlank()) {
                views.setViewVisibility(R.id.widget_header, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_header, View.VISIBLE)
                views.setTextViewText(R.id.widget_date_label, dateLabel)
                views.setTextViewText(R.id.widget_week_label, weekLabel)
                views.setTextViewText(R.id.widget_count_label, slots.length().toString())
                views.setTextColor(R.id.widget_date_label, fade(palette.text, textAlpha))
                views.setTextColor(R.id.widget_week_label, fade(palette.sub, textAlpha))
                views.setTextColor(R.id.widget_count_label, fade(palette.active, textAlpha))
                // 「节课」在布局里只有默认色，自定义背景模式下要跟着一起变淡，
                // 否则同一行里两个字的深浅会不一致。
                if (backgroundMode) {
                    views.setTextColor(
                        R.id.widget_count_unit,
                        fade(palette.sub, textAlpha),
                    )
                }
            }

            // ---- 课程槽位 ----
            val count = minOf(slots.length(), MAX_ROWS)
            for (index in SLOT_IDS.indices) {
                val ids = SLOT_IDS[index]
                val slot = if (index < count) slots.optJSONObject(index) else null
                if (slot == null) {
                    views.setViewVisibility(ids[0], View.GONE)
                    continue
                }
                views.setViewVisibility(ids[0], View.VISIBLE)
                paintSlot(
                    context,
                    views,
                    ids,
                    slot,
                    palette,
                    cardAlpha,
                    textAlpha,
                )
            }

            // ---- 空态 / 折叠提示 ----
            if (slots.length() == 0) {
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_empty,
                    when {
                        dateLabel.isBlank() -> "尚未同步，打开 App 即可"
                        weekLabel == "学期未开始" -> "学期还没开始"
                        else -> "今天没有课，好好休息"
                    },
                )
                views.setTextColor(R.id.widget_empty, fade(palette.sub, textAlpha))
            } else if (slots.length() > MAX_ROWS) {
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_empty,
                    "还有 ${slots.length() - MAX_ROWS} 节…",
                )
                views.setTextColor(R.id.widget_empty, fade(palette.sub, textAlpha))
            } else {
                views.setViewVisibility(R.id.widget_empty, View.GONE)
            }

            val openApp = PendingIntent.getActivity(
                context,
                2001,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, openApp)
            manager.updateAppWidget(widgetId, views)
        }

        /**
         * 按状态给一个槽位填内容与配色。
         *
         * [cardAlpha] / [textAlpha] 为 1 时（即非自定义背景模式）行为与旧版**完全一致**。
         */
        private fun paintSlot(
            context: Context,
            views: RemoteViews,
            ids: IntArray,
            slot: JSONObject,
            palette: Palette,
            cardAlpha: Float,
            textAlpha: Float,
        ) {
            val status = slot.optString("status", "upcoming")
            val isNow = status == "ongoing"
            val isDone = status == "finished"

            val barColor = when {
                isNow -> palette.active
                isDone -> palette.doneText
                else -> palette.accent
            }
            // 卡片底色用**圆角 drawable**（按状态 + 深浅选），
            // 不能用 setBackgroundColor —— 那会把 drawable 换成直角纯色，圆角丢失。
            // 因此卡片底色跟随系统深浅，配色预设驱动色条与文字。
            val cardDrawable = when {
                isNow -> R.drawable.widget_slot_now
                isDone -> R.drawable.widget_slot_done
                else -> R.drawable.widget_slot_next
            }
            val nameColor = if (isDone) palette.doneText else palette.text
            val metaColor = if (isDone) palette.doneText else palette.sub

            val statusText = when {
                isNow -> "进行中"
                isDone -> "已结束"
                // 未开始：显示开课时间
                else -> slot.optString("startTime")
            }

            // 卡片底色画在 slotN_card 这一层（一个空的 FrameLayout），
            // 而不是槽位容器本身 —— 这样「卡片透明度」用 setAlpha 只影响底色，
            // 里面的文字另由 textAlpha 独立控制，两者互不牵连。
            // 槽位容器自身在布局里没有背景，所以不需要清空它。
            views.setInt(ids[5], "setBackgroundResource", cardDrawable)
            views.setFloat(ids[5], "setAlpha", cardAlpha)

            // 色条用位图而非 setBackgroundColor —— 后者只能画直角，
            // 这里是代码画的圆角小图，既能圆角又能跟随配色变色。
            // 色条**不**乘 textAlpha：它是视觉强调，跟着文字变淡会丢掉状态区分。
            views.setImageViewBitmap(ids[1], barBitmap(context, barColor))

            val name = slot.optString("name")
            views.setTextViewText(ids[2], name)
            views.setTextColor(ids[2], fade(nameColor, textAlpha))
            // 课程名过长时缩字号，避免被截断
            views.setFloat(ids[2], "setTextSize", nameSize(name))

            views.setTextViewText(ids[3], slot.optString("meta"))
            views.setTextColor(ids[3], fade(metaColor, textAlpha))

            views.setTextViewText(ids[4], statusText)
            views.setTextColor(ids[4], fade(barColor, textAlpha))
        }

        /**
         * 把颜色的 alpha 通道乘上 [factor]。
         *
         * [factor] >= 1 时原样返回 —— 保证非自定义背景模式下的取色
         * 与旧版逐位一致，不会有任何观感漂移。
         */
        private fun fade(color: Int, factor: Float): Int {
            if (factor >= 1f) return color
            val base = (color ushr 24) and 0xFF
            val alpha = (base * factor.coerceIn(0f, 1f)).toInt().coerceIn(0, 255)
            return (alpha shl 24) or (color and 0x00FFFFFF)
        }

        /** 课程名越长字号越小；用码点计数，中文才准。基准与布局的 13sp 一致。 */
        private fun nameSize(name: String): Float = when (name.codePointCount(0, name.length)) {
            in 0..6 -> 13f
            in 7..8 -> 12f
            in 9..11 -> 11f
            else -> 10f
        }

        /** 色条宽度（dp），与布局里的 ImageView 一致。 */
        private const val BAR_WIDTH_DP = 3

        /**
         * 色条位图的画布高度（dp）。
         *
         * 比实际显示高度大一些 —— ImageView 是 `match_parent`（高度随文字），
         * 用 `fitXY` 缩下来时仍能保持正常的圆角比例；
         * 若按实际高度画，缩放比例不均会让圆角变形。
         */
        private const val BAR_BITMAP_HEIGHT_DP = 40

        /** 色条位图缓存：远端渲染很频繁，避免反复分配 Bitmap 造成 GC 抖动。 */
        private val barCache = HashMap<Long, Bitmap>()

        /**
         * 画一根圆角色条。
         *
         * 为什么不用 TextView 的背景色：`setBackgroundColor` 只能得到直角矩形，
         * 而 RemoteViews 里没法给背景 drawable 动态染色。
         * 用 `setImageViewBitmap` 把圆角矩形画进位图，圆角与配色就都能控。
         */
        private fun barBitmap(context: Context, color: Int): Bitmap {
            val density = context.resources.displayMetrics.density
            // 向上取整：位图绝不小于 ImageView 的实际像素，避免留出细缝
            val width = max(1, ceil(BAR_WIDTH_DP * density).toInt())
            val height = max(1, ceil(BAR_BITMAP_HEIGHT_DP * density).toInt())
            val key = (color.toLong() shl 32) or (width.toLong() shl 16) or height.toLong()

            barCache[key]?.let { return it }
            if (barCache.size > 32) barCache.clear()

            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
            // 半径取短边一半 → 胶囊形；在 3dp 宽下就是「微微圆角」
            val radius = min(width, height) / 2f
            Canvas(bitmap).drawRoundRect(
                RectF(0f, 0f, width.toFloat(), height.toFloat()),
                radius,
                radius,
                paint,
            )
            barCache[key] = bitmap
            return bitmap
        }

        /**
         * 背景位图缓存。
         *
         * 小组件渲染很频繁（每 30 分钟一次系统刷新、每次下课闹钟、
         * 每次改设置），同一份背景反复解码合成就没必要。
         * 键里含 PNG 的 `lastModified` —— Dart 侧换图后会重写这个文件，
         * 时间戳一变缓存自然失效。
         */
        private var bgCacheKey: String? = null
        private var bgCacheBitmap: Bitmap? = null

        /**
         * 生成自定义背景位图：只做「解码 + 叠明暗蒙层」。
         *
         * ## 为什么刻意不缩放、不裁切、不做圆角
         *
         * 这几件事原先都按小组件的**真实像素尺寸**在原生侧算，
         * 尺寸来自 `AppWidgetManager.getAppWidgetOptions` ——
         * 但那个值在部分 ROM 上**根本不可靠**：华为 launcher 实测上报
         * `min=(64001x35841)`，按它建 Bitmap 会直接 OutOfMemoryError。
         *
         * 后果不是「差一点点」，而是两种故障：
         * 1. 尺寸算得比实际小 → 位图盖不满 → **四边留白**；
         * 2. 尺寸算到天上去 → OOM 被 `runCatching` 吞掉 → **背景整个不显示**。
         *
         * 所以现在把职责全部下移给布局，原生**不依赖任何尺寸**：
         * - 铺满 → `widget_bg` 的 `scaleType="centerCrop"`：无论位图多大、
         *   什么比例，都缩放并居中裁切到盖满，结构上杜绝留白；
         * - 圆角 → 根的 `clipToOutline`，由 `widget_background` 的 shape
         *   outline 裁出，与卡片圆角天然一致。
         *
         * 蒙层仍在这里叠、而不烘焙进 PNG：黑/白的选择依赖系统深浅模式，
         * 烘焙进去的话用户一切换深浅就得让 Dart 重算一遍高斯模糊。
         */
        private fun backgroundBitmap(path: String, dim: Float, night: Boolean): Bitmap? {
            val file = File(path)
            if (!file.exists()) return null

            val key = "$path|${file.lastModified()}|$dim|$night"
            if (key == bgCacheKey) bgCacheBitmap?.let { return it }

            val source = BitmapFactory.decodeFile(path, decodeOptions(path)) ?: return null
            val output = if (dim <= 0f) {
                source
            } else {
                val shaded = Bitmap.createBitmap(
                    source.width,
                    source.height,
                    Bitmap.Config.ARGB_8888,
                )
                val canvas = Canvas(shaded)
                canvas.drawBitmap(source, 0f, 0f, null)
                // 深色用黑蒙层、浅色用白蒙层 —— 与主页背景的 _DimOverlay 同一套语义。
                // SRC_ATOP：只叠在已有像素上，位图若带透明边缘也不会被填成实心。
                val shade = if (night) 0 else 255
                canvas.drawColor(
                    Color.argb(
                        (dim.coerceIn(0f, 0.8f) * 255).toInt(),
                        shade,
                        shade,
                        shade,
                    ),
                    android.graphics.PorterDuff.Mode.SRC_ATOP,
                )
                shaded
            }

            bgCacheKey = key
            bgCacheBitmap = output
            return output
        }

        /** 背景图长边上限，纯粹是内存兜底（Dart 侧正常只输出 1600×1000）。 */
        private const val MAX_BG_EDGE = 2048

        /**
         * 给 `decodeFile` 算一个 2 的幂降采样比。
         *
         * 正常情况下 `sample` 恒为 1；这里只防「用户换了大图 / 旧版缓存残留」
         * 把内存顶爆。
         */
        private fun decodeOptions(path: String): BitmapFactory.Options {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            val longest = max(bounds.outWidth, bounds.outHeight)
            var sample = 1
            while (longest / (sample * 2) >= MAX_BG_EDGE) sample *= 2
            return BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
        }

        private fun nextEnd(context: Context): Long? {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(SLOTS_KEY, null)
                ?: prefs.getString(COURSES_KEY, "[]")
                ?: "[]"
            val slots = runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
            val now = System.currentTimeMillis()
            var earliest: Long? = null
            for (index in 0 until slots.length()) {
                val item = slots.optJSONObject(index) ?: continue
                for (key in listOf("startMillis", "endMillis")) {
                    val target = item.optLong(key, 0L) + 1_000L
                    if (target > now && (earliest == null || target < earliest!!)) {
                        earliest = target
                    }
                }
            }
            return earliest
        }

        private fun scheduleNextRefresh(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val operation = PendingIntent.getBroadcast(
                context,
                2002,
                Intent(context, NextCourseWidget::class.java).setAction(ACTION_REFRESH),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val triggerAt = nextEnd(context)
            if (triggerAt == null) {
                alarmManager.cancel(operation)
                return
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            }
        }
    }
}
