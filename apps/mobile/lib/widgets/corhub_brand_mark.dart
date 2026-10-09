import 'package:flutter/material.dart';

const _colorMarkAsset = 'assets/branding/corhub-mark.png';
const _smallMarkAsset = 'assets/branding/corhub-mark-small.png';
const _monochromeMarkAsset = 'assets/branding/corhub-mark-monochrome.png';

class CorHubBrandMark extends StatelessWidget {
  const CorHubBrandMark({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return ExcludeSemantics(
      child: Image.asset(
        color != null
            ? _monochromeMarkAsset
            : size <= 32
            ? _smallMarkAsset
            : _colorMarkAsset,
        width: size,
        height: size,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        color: color,
        colorBlendMode: color == null ? null : BlendMode.srcIn,
      ),
    );
  }
}

class CorHubBrandBadge extends StatelessWidget {
  const CorHubBrandBadge({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (size < 24) {
      return CorHubBrandMark(size: size, color: theme.colorScheme.primary);
    }
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(size * 0.23),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 0.8,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: theme.colorScheme.primary.withValues(
                alpha: theme.brightness == Brightness.light ? 0.14 : 0.20,
              ),
              blurRadius: size * 0.24,
              offset: Offset(0, size * 0.06),
            ),
          ],
        ),
        child: Center(child: CorHubBrandMark(size: size * 0.94)),
      ),
    );
  }
}
