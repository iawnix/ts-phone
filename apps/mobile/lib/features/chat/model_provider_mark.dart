import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small, local brand mark for the model picker and composer.
///
/// These are intentionally drawn as compact marks instead of loading remote
/// logos. The phone remains useful offline and a custom provider still gets a
/// neutral, honest fallback rather than an unrelated vendor logo.
class ModelProviderMark extends StatelessWidget {
  const ModelProviderMark({
    super.key,
    required this.provider,
    this.modelId,
    this.size = 22,
  });

  final String provider;
  final String? modelId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brand = _modelBrandKey(provider, modelId: modelId);
    return Semantics(
      label: modelId == null ? provider : '$provider $modelId',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: brand == _ModelBrand.unknown
            ? _FallbackMark(provider: provider, size: size, colors: colors)
            : CustomPaint(
                painter: _BrandMarkPainter(brand: brand, colors: colors),
              ),
      ),
    );
  }
}

class _FallbackMark extends StatelessWidget {
  const _FallbackMark({
    required this.provider,
    required this.size,
    required this.colors,
  });

  final String provider;
  final double size;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: colors.surfaceContainerHighest,
      shape: BoxShape.circle,
    ),
    child: Center(
      child: Text(
        _monogram(provider),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontSize: size * .36,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    ),
  );
}

enum _ModelBrand {
  openai,
  anthropic,
  google,
  deepseek,
  qwen,
  mistral,
  kimi,
  zhipu,
  xai,
  unknown,
}

_ModelBrand _modelBrandKey(String provider, {String? modelId}) {
  final providerKey = _normalize(provider);
  final modelKey = _normalize(modelId ?? '');
  final key = providerKey == 'cpa' ? modelKey : providerKey;
  if (key == 'openai' ||
      key == 'chatgpt' ||
      _startsWithAny(modelKey, ['gpt', 'o1', 'o3', 'o4'])) {
    return _ModelBrand.openai;
  }
  if (key == 'anthropic' || key == 'claude' || modelKey.startsWith('claude')) {
    return _ModelBrand.anthropic;
  }
  if (key == 'google' || key == 'gemini' || modelKey.startsWith('gemini')) {
    return _ModelBrand.google;
  }
  if (key == 'deepseek' || modelKey.startsWith('deepseek')) {
    return _ModelBrand.deepseek;
  }
  if (key == 'qwen' || key == 'tongyi' || modelKey.startsWith('qwen')) {
    return _ModelBrand.qwen;
  }
  if (key == 'mistral' || modelKey.startsWith('mistral')) {
    return _ModelBrand.mistral;
  }
  if (key == 'moonshot' || key == 'kimi' || modelKey.startsWith('kimi')) {
    return _ModelBrand.kimi;
  }
  if (key == 'zhipu' ||
      key == 'glm' ||
      key == 'bigmodel' ||
      modelKey.startsWith('glm')) {
    return _ModelBrand.zhipu;
  }
  if (key == 'xai' || key == 'grok' || modelKey.startsWith('grok')) {
    return _ModelBrand.xai;
  }
  return _ModelBrand.unknown;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

bool _startsWithAny(String value, List<String> prefixes) =>
    prefixes.any(value.startsWith);

String _monogram(String provider) {
  final value = provider.trim();
  if (value.isEmpty) return 'AI';
  final words = value.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
  final initials = words.map((word) => word[0]).take(2).join();
  return (initials.isEmpty ? value.substring(0, 1) : initials).toUpperCase();
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter({required this.brand, required this.colors});

  final _ModelBrand brand;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final foreground = switch (brand) {
      _ModelBrand.openai ||
      _ModelBrand.zhipu ||
      _ModelBrand.xai => colors.onSurface,
      _ModelBrand.anthropic => const Color(0xffd97757),
      _ModelBrand.google => const Color(0xff5965f2),
      _ModelBrand.deepseek => const Color(0xff4b83ff),
      _ModelBrand.qwen => const Color(0xff1677ff),
      _ModelBrand.mistral => const Color(0xfff97316),
      _ModelBrand.kimi => colors.onSurface,
      _ModelBrand.unknown => colors.onSurfaceVariant,
    };
    final fill = Paint()
      ..color = foreground
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = foreground
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = unit * .105
      ..isAntiAlias = true;

    switch (brand) {
      case _ModelBrand.openai:
        _paintOpenAi(canvas, center, unit, stroke);
      case _ModelBrand.anthropic:
        _paintStar(canvas, center, unit, fill);
      case _ModelBrand.google:
        _paintGemini(canvas, center, unit, fill);
      case _ModelBrand.deepseek:
        _paintDeepSeek(canvas, center, unit, fill, stroke);
      case _ModelBrand.qwen:
        _paintQwen(canvas, center, unit, fill, stroke);
      case _ModelBrand.mistral:
        _paintMistral(canvas, center, unit, fill);
      case _ModelBrand.kimi:
        _paintKimi(canvas, center, unit, fill, stroke);
      case _ModelBrand.zhipu:
        _paintZhipu(canvas, center, unit, stroke);
      case _ModelBrand.xai:
        _paintXai(canvas, center, unit, stroke);
      case _ModelBrand.unknown:
        break;
    }
  }

  void _paintOpenAi(Canvas canvas, Offset center, double unit, Paint paint) {
    final radius = unit * .29;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var index = 0; index < 6; index++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(index * math.pi / 3);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawArc(
        rect.shift(Offset(0, -unit * .035)),
        -math.pi * .12,
        math.pi * .74,
        false,
        paint,
      );
      canvas.restore();
    }
    canvas.drawCircle(center, unit * .105, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
  }

  void _paintStar(Canvas canvas, Offset center, double unit, Paint paint) {
    final path = Path();
    for (var index = 0; index < 16; index++) {
      final radius = index.isEven ? unit * .42 : unit * .13;
      final angle = -math.pi / 2 + index * math.pi / 8;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _paintGemini(Canvas canvas, Offset center, double unit, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - unit * .46)
      ..cubicTo(
        center.dx + unit * .05,
        center.dy - unit * .18,
        center.dx + unit * .2,
        center.dy - unit * .05,
        center.dx + unit * .46,
        center.dy,
      )
      ..cubicTo(
        center.dx + unit * .2,
        center.dy + unit * .05,
        center.dx + unit * .05,
        center.dy + unit * .18,
        center.dx,
        center.dy + unit * .46,
      )
      ..cubicTo(
        center.dx - unit * .05,
        center.dy + unit * .18,
        center.dx - unit * .2,
        center.dy + unit * .05,
        center.dx - unit * .46,
        center.dy,
      )
      ..cubicTo(
        center.dx - unit * .2,
        center.dy - unit * .05,
        center.dx - unit * .05,
        center.dy - unit * .18,
        center.dx,
        center.dy - unit * .46,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  void _paintDeepSeek(
    Canvas canvas,
    Offset center,
    double unit,
    Paint fill,
    Paint stroke,
  ) {
    final body = Path()
      ..moveTo(center.dx - unit * .42, center.dy + unit * .08)
      ..cubicTo(
        center.dx - unit * .25,
        center.dy - unit * .2,
        center.dx + unit * .23,
        center.dy - unit * .2,
        center.dx + unit * .4,
        center.dy + unit * .02,
      )
      ..cubicTo(
        center.dx + unit * .27,
        center.dy + unit * .34,
        center.dx - unit * .15,
        center.dy + unit * .38,
        center.dx - unit * .42,
        center.dy + unit * .08,
      )
      ..close();
    canvas.drawPath(body, fill);
    final tail = Path()
      ..moveTo(center.dx + unit * .25, center.dy - unit * .06)
      ..lineTo(center.dx + unit * .49, center.dy - unit * .25)
      ..lineTo(center.dx + unit * .4, center.dy + unit * .03)
      ..close();
    canvas.drawPath(tail, fill);
    canvas.drawCircle(
      center + Offset(unit * .19, -unit * .05),
      unit * .035,
      Paint()..color = Colors.white,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: center + Offset(unit * .02, unit * .05),
        width: unit * .36,
        height: unit * .2,
      ),
      .1,
      2.3,
      false,
      stroke..color = Colors.white,
    );
  }

  void _paintQwen(
    Canvas canvas,
    Offset center,
    double unit,
    Paint fill,
    Paint stroke,
  ) {
    final bubble = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center + Offset(0, -unit * .03),
        width: unit * .74,
        height: unit * .55,
      ),
      Radius.circular(unit * .18),
    );
    canvas.drawRRect(bubble, stroke);
    final tail = Path()
      ..moveTo(center.dx - unit * .16, center.dy + unit * .24)
      ..lineTo(center.dx - unit * .28, center.dy + unit * .43)
      ..lineTo(center.dx + unit * .02, center.dy + unit * .28)
      ..close();
    canvas.drawPath(tail, fill);
    canvas.drawCircle(center + Offset(-unit * .15, 0), unit * .035, fill);
    canvas.drawCircle(center, unit * .035, fill);
    canvas.drawCircle(center + Offset(unit * .15, 0), unit * .035, fill);
  }

  void _paintMistral(Canvas canvas, Offset center, double unit, Paint paint) {
    for (var index = -2; index <= 2; index++) {
      final height = unit * (.2 + (2 - index.abs()) * .11);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + Offset(index * unit * .11, unit * .04),
          width: unit * .07,
          height: height,
        ),
        Radius.circular(unit * .035),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  void _paintKimi(
    Canvas canvas,
    Offset center,
    double unit,
    Paint fill,
    Paint stroke,
  ) {
    canvas.drawCircle(center, unit * .4, stroke);
    final path = Path()
      ..moveTo(center.dx - unit * .14, center.dy - unit * .2)
      ..lineTo(center.dx - unit * .14, center.dy + unit * .2)
      ..moveTo(center.dx - unit * .12, center.dy)
      ..lineTo(center.dx + unit * .18, center.dy - unit * .2)
      ..moveTo(center.dx - unit * .1, center.dy)
      ..lineTo(center.dx + unit * .22, center.dy + unit * .2);
    canvas.drawPath(path, stroke);
    canvas.drawCircle(
      center + Offset(unit * .25, -unit * .27),
      unit * .045,
      Paint()..color = const Color(0xff1677ff),
    );
  }

  void _paintZhipu(Canvas canvas, Offset center, double unit, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - unit * .37, center.dy - unit * .3)
      ..lineTo(center.dx + unit * .37, center.dy - unit * .3)
      ..lineTo(center.dx - unit * .3, center.dy + unit * .3)
      ..lineTo(center.dx + unit * .37, center.dy + unit * .3);
    canvas.drawPath(path, paint);
  }

  void _paintXai(Canvas canvas, Offset center, double unit, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - unit * .3, center.dy - unit * .3)
      ..lineTo(center.dx + unit * .3, center.dy + unit * .3)
      ..moveTo(center.dx + unit * .3, center.dy - unit * .3)
      ..lineTo(center.dx - unit * .3, center.dy + unit * .3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) =>
      oldDelegate.brand != brand || oldDelegate.colors != colors;
}
