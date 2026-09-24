import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

/// 桌面小组件背景图预处理器。
///
/// ## 为什么模糊要在 Dart 侧算
///
/// 小组件由原生 RemoteViews 渲染，而原生侧**没有可用的高斯模糊方案**：
/// `RenderEffect` 要 API 31+（本项目 minSdk 是 26），`RenderScript` 早已废弃。
/// 所以「cover 缩放 + 高斯模糊」在 Dart 侧一次算完，输出一张 PNG，
/// 原生只需 `BitmapFactory.decodeFile` 贴上。
///
/// 参数语义与主页背景（`AppBackground`）一致，用户看到的滑块手感相同。
///
/// ## 为什么明暗蒙层**不**在这里叠
///
/// 明暗（黑/白蒙层）的选择依赖当前是否深色模式。若烘焙进 PNG，
/// 用户一切换深浅模式就得重算一遍模糊。
/// 放到原生合成时叠加（原生本来就要 decode + crop + 圆角，顺手画一层矩形），
/// 于是这张 PNG **只依赖模糊强度**：拖「明暗」滑块完全不用重算。
///
/// ## 为什么输出一张「大图」而不是精确尺寸
///
/// 小组件在桌面上的实际尺寸由用户拖拽决定，事先不可知。
/// 所以这里给一张够大的图，由原生按 `AppWidgetManager` 报回的真实尺寸
/// 做 center-crop + 缩放到精确像素，再贴图。
class WidgetBackgroundRenderer {
  const WidgetBackgroundRenderer();

  /// 输出画布尺寸。
  ///
  /// 取 1600×1000（16:10）：比大多数桌面上小组件的实际分辨率都大，
  /// 原生侧缩小时不会糊；模糊 sigma 在这个分辨率下的视觉强度
  /// 也正好与主页背景接近。
  static const int _outWidth = 1600;
  static const int _outHeight = 1000;

  /// 解码时限制的长边像素，避免超大原图撑爆内存。
  static const int _decodeWidth = 1600;

  /// 渲染（或复用缓存）小组件背景图，返回可交给原生 `decodeFile` 的路径。
  ///
  /// 失败时返回 null —— 调用方应退回「无背景」，不要让小组件整块挂掉。
  Future<String?> render({
    required String sourcePath,
    required double blur,
  }) async {
    final source = File(sourcePath);
    if (!source.existsSync()) return null;

    final dir = Directory('${await getDatabasesPath()}/widget_background');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final output = File('${dir.path}/widget_bg.png');
    final stamp = File('${dir.path}/widget_bg.key');

    // 输入签名：只要它没变就复用上次的 PNG。
    // 同步会在每次改设置 / 回前台 / 首次加载时触发，不缓存的话
    // 每启动一次就要重算一遍模糊。
    final key = '$sourcePath'
        '|${source.lastModifiedSync().millisecondsSinceEpoch}'
        '|${blur.toStringAsFixed(2)}';
    if (output.existsSync() &&
        stamp.existsSync() &&
        stamp.readAsStringSync() == key) {
      return output.path;
    }

    try {
      final decoded = await _decode(source);
      if (decoded == null) return null;

      final picture = _paint(decoded, blur: blur);
      final image = await picture.toImage(_outWidth, _outHeight);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      decoded.dispose();

      if (data == null) return null;
      await output.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await stamp.writeAsString(key, flush: true);
      return output.path;
    } catch (_) {
      // 图被删 / 格式不认 / 空间不足 —— 一律退回「无背景」，
      // 小组件本身仍要正常显示课程。
      return null;
    }
  }

  /// 解码原图，长边压到 [_decodeWidth] 以内。
  Future<ui.Image?> _decode(File source) async {
    final bytes = await source.readAsBytes();
    if (bytes.isEmpty) return null;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);

    // 按长边等比缩放，避免手机拍的 4000×3000 直接解码占掉几十 MB
    final longer = math.max(descriptor.width, descriptor.height);
    final codec = longer > _decodeWidth
        ? await descriptor.instantiateCodec(
            targetWidth:
                descriptor.width >= descriptor.height ? _decodeWidth : null,
            targetHeight:
                descriptor.height > descriptor.width ? _decodeWidth : null,
          )
        : await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// 把小图画到 [_outWidth]×[_outHeight] 画布上：cover 缩放 + 模糊。
  ui.Picture _paint(ui.Image image, {required double blur}) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // cover：短边铺满，长边溢出（原生侧还会再 center-crop 一次，不影响）
    final scale = math.max(_outWidth / src.width, _outHeight / src.height);
    // 模糊会让边缘变透明，所以稍微放大以免四周露出底色
    // ——与主页背景 `_CustomBackgroundImage` 的 over 系数一致。
    final over = blur > 0 ? 1 + blur / 100 : 1.0;
    final width = src.width * scale * over;
    final height = src.height * scale * over;
    final dst = Rect.fromLTWH(
      (_outWidth - width) / 2,
      (_outHeight - height) / 2,
      width,
      height,
    );

    final recorder = ui.PictureRecorder();
    final bounds = Rect.fromLTWH(
      0,
      0,
      _outWidth.toDouble(),
      _outHeight.toDouble(),
    );
    final canvas = Canvas(recorder, bounds);

    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (blur > 0) {
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: blur,
        sigmaY: blur,
        tileMode: TileMode.decal,
      );
    }
    canvas.drawImageRect(image, src, dst, paint);
    return recorder.endRecording();
  }
}
