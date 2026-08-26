import 'package:flutter/material.dart';

const _colorMarkAsset = 'assets/branding/ts-phone-mark.png';
const _monochromeMarkAsset = 'assets/branding/ts-phone-mark-monochrome.png';

class TsPhoneBrandMark extends StatelessWidget {
  const TsPhoneBrandMark({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Image.asset(
        color == null ? _colorMarkAsset : _monochromeMarkAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        color: color,
        colorBlendMode: color == null ? null : BlendMode.srcIn,
      ),
    );
  }
}

class TsPhoneBrandBadge extends StatelessWidget {
  const TsPhoneBrandBadge({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(size * 0.23),
          border: Border.all(
            color: const Color(0xFF0D1726).withValues(alpha: 0.10),
            width: 0.8,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF126CD6).withValues(alpha: 0.14),
              blurRadius: size * 0.24,
              offset: Offset(0, size * 0.06),
            ),
          ],
        ),
        child: Center(child: TsPhoneBrandMark(size: size * 0.94)),
      ),
    );
  }
}
