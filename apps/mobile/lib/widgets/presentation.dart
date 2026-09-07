import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/ts_phone_theme.dart';
import '../theme/ts_visual_accessibility.dart';

enum TsInfoTone { neutral, info, warning, error }

class TsPageBackdrop extends StatelessWidget {
  const TsPageBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: child,
      ),
    );
  }
}

/// A quiet, opaque surface for ordinary content.
///
/// Glass is reserved for navigation and transient controls. Lists, settings,
/// notices, and other readable content use this surface so their hierarchy
/// remains stable in both color schemes and at large text sizes.
class TsContentSurface extends StatelessWidget {
  const TsContentSurface({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(TsPhoneRadii.panel),
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surfaceContainerLowest,
        borderRadius: borderRadius,
        border: Border.all(
          color:
              borderColor ??
              (highContrast ? colors.outline : colors.outlineVariant),
          width: highContrast ? 1 : 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}

class TsGlassSurface extends StatelessWidget {
  const TsGlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(TsPhoneRadii.panel),
    ),
    this.elevated = false,
    this.blurSigma,
    this.tint,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final bool elevated;
  final double? blurSigma;
  final Color? tint;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = TsPhoneGlassTheme.resolve(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final reduceTransparency =
        highContrast || TsVisualAccessibility.reduceTransparencyOf(context);
    final requestedFill =
        tint ?? (elevated ? glass.elevatedSurface : glass.surface);
    final fill = reduceTransparency
        ? theme.colorScheme.surfaceContainerLowest
        : requestedFill;
    final effectiveBorder =
        borderColor ??
        (highContrast
            ? theme.colorScheme.outline
            : reduceTransparency
            ? theme.colorScheme.outlineVariant
            : elevated
            ? glass.strongBorder
            : glass.border);
    final effectiveBlur = reduceTransparency
        ? 0.0
        : blurSigma ?? glass.blurSigma;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: reduceTransparency ? fill : null,
        gradient: reduceTransparency
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color.alphaBlend(glass.highlight, fill),
                  fill,
                  fill,
                ],
                stops: const <double>[0, 0.28, 1],
              ),
        borderRadius: borderRadius,
        border: Border.all(
          color: effectiveBorder,
          width: highContrast ? 1 : 0.7,
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child: effectiveBlur <= 0
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: effectiveBlur,
                sigmaY: effectiveBlur,
              ),
              child: content,
            ),
    );
    if (!elevated || reduceTransparency) return clipped;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: glass.shadow,
              blurRadius: 24,
              spreadRadius: -3,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: clipped,
      ),
    );
  }
}

enum TsGlassBarEdge { top, bottom }

class TsGlassBar extends StatelessWidget {
  const TsGlassBar({super.key, required this.edge, this.child});

  final TsGlassBarEdge edge;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = TsPhoneGlassTheme.resolve(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final reduceTransparency =
        highContrast || TsVisualAccessibility.reduceTransparencyOf(context);
    final fill = reduceTransparency
        ? theme.colorScheme.surfaceContainerLowest
        : glass.surface;
    final borderSide = BorderSide(
      color: highContrast
          ? theme.colorScheme.outline
          : reduceTransparency
          ? theme.colorScheme.outlineVariant
          : glass.border,
      width: highContrast ? 1 : 0.6,
    );
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: reduceTransparency ? fill : null,
        gradient: reduceTransparency
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color.alphaBlend(glass.highlight, fill),
                  fill,
                  fill,
                ],
                stops: const <double>[0, 0.22, 1],
              ),
        border: switch (edge) {
          TsGlassBarEdge.top => Border(top: borderSide),
          TsGlassBarEdge.bottom => Border(bottom: borderSide),
        },
      ),
      child: child,
    );
    return RepaintBoundary(
      child: ClipRect(
        child: reduceTransparency
            ? content
            : BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: glass.blurSigma,
                  sigmaY: glass.blurSigma,
                ),
                child: content,
              ),
      ),
    );
  }
}

class TsGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TsGlassAppBar({
    super.key,
    this.leading,
    this.title,
    this.actions,
    this.toolbarHeight = 52,
    this.centerTitle,
    this.titleSpacing,
    this.titleTextStyle,
  });

  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final double toolbarHeight;
  final bool? centerTitle;
  final double? titleSpacing;
  final TextStyle? titleTextStyle;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = TsPhoneGlassTheme.resolve(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final reduceTransparency =
        highContrast || TsVisualAccessibility.reduceTransparencyOf(context);
    final scrolledUnderFill = reduceTransparency
        ? theme.colorScheme.surfaceContainerLowest
        : glass.elevatedSurface;
    return AppBar(
      leading: leading,
      leadingWidth: 52,
      title: title,
      actions: actions,
      actionsPadding: const EdgeInsetsDirectional.only(end: 4),
      toolbarHeight: toolbarHeight,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      titleTextStyle: titleTextStyle,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: WidgetStateColor.resolveWith((states) {
        return states.contains(WidgetState.scrolledUnder)
            ? scrolledUnderFill
            : Colors.transparent;
      }),
      surfaceTintColor: Colors.transparent,
      animateColor: !MediaQuery.disableAnimationsOf(context),
      flexibleSpace: const TsGlassBar(edge: TsGlassBarEdge.bottom),
    );
  }
}

class TsSectionHeader extends StatelessWidget {
  const TsSectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
  });

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleWidget = Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
    final captionValue = caption;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            captionValue != null &&
            (constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(13) > 17);
        final content = stack
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: titleWidget),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: TsPhoneSpacing.xSmall),
                  Text(
                    captionValue,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(child: titleWidget),
                  if (captionValue != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: TsPhoneSpacing.medium,
                        ),
                        child: Text(
                          captionValue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ?trailing,
                ],
              );
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            TsPhoneSpacing.large,
            TsPhoneSpacing.large,
            TsPhoneSpacing.large,
            TsPhoneSpacing.small,
          ),
          child: content,
        );
      },
    );
  }
}

/// The single segmented-control implementation used across TS Phone.
///
/// It intentionally omits Material's selected check mark and lets the shared
/// theme express selection through fill, foreground, and border contrast.
class TsSegmentedControl<T> extends StatelessWidget {
  const TsSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      segments: segments,
      selected: <T>{selected},
      onSelectionChanged: enabled ? (values) => onChanged(values.single) : null,
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
    );
  }
}

/// Compact success state for rows where text would duplicate the primary
/// label. The tooltip and semantic label keep the icon understandable.
class TsReadyStatusIcon extends StatelessWidget {
  const TsReadyStatusIcon({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = TsPhoneStatusTheme.resolve(context).connected;
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: ExcludeSemantics(
          child: Icon(Icons.check_circle_rounded, size: 19, color: color),
        ),
      ),
    );
  }
}

class TsInfoBand extends StatelessWidget {
  const TsInfoBand({
    super.key,
    required this.icon,
    required this.message,
    this.tone = TsInfoTone.neutral,
    this.action,
    this.maxLines,
  });

  final IconData icon;
  final String message;
  final TsInfoTone tone;
  final Widget? action;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, rail) = switch (tone) {
      TsInfoTone.neutral => (
        colors.surfaceContainerLow,
        colors.onSurface,
        colors.outline,
      ),
      TsInfoTone.info => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        colors.secondary,
      ),
      TsInfoTone.warning => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        colors.tertiary,
      ),
      TsInfoTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        colors.error,
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TsPhoneSpacing.medium,
        TsPhoneSpacing.small,
        TsPhoneSpacing.medium,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(TsPhoneRadii.small),
          border: Border(left: BorderSide(color: rail, width: 3)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(13);
            final stackAction =
                action != null &&
                (constraints.maxWidth < 340 || textScale > 17);
            final messageRow = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, size: 19, color: rail),
                ),
                const SizedBox(width: TsPhoneSpacing.small),
                Expanded(
                  child: Text(
                    message,
                    maxLines: maxLines,
                    overflow: maxLines == null ? null : TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: foreground),
                  ),
                ),
                if (action != null && !stackAction) action!,
              ],
            );
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TsPhoneSpacing.medium,
                vertical: TsPhoneSpacing.small,
              ),
              child: stackAction
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        messageRow,
                        const SizedBox(height: TsPhoneSpacing.xSmall),
                        Align(alignment: Alignment.centerRight, child: action),
                      ],
                    )
                  : messageRow,
            );
          },
        ),
      ),
    );
  }
}

class TsStatusListTile extends StatelessWidget {
  const TsStatusListTile({
    super.key,
    required this.statusColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.iconColor,
    this.showStatusIndicator = false,
    this.details,
    this.titleMonospace = false,
    this.titleTrailing,
  });

  final Color statusColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final bool showStatusIndicator;
  final Widget? details;
  final bool titleMonospace;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.outlineVariant, width: 0.5),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TsPhoneSpacing.large,
                vertical: TsPhoneSpacing.small,
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Icon(icon, size: 24, color: iconColor ?? statusColor),
                        if (showStatusIndicator)
                          Positioned(
                            right: 1,
                            bottom: 5,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.surface,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: TsPhoneSpacing.medium),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _StatusListTileTitle(
                          title: title,
                          monospace: titleMonospace,
                          trailing: titleTrailing,
                        ),
                        const SizedBox(height: TsPhoneSpacing.xSmall),
                        details ??
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(width: TsPhoneSpacing.small),
                  trailing ??
                      Icon(
                        Icons.chevron_right,
                        size: 22,
                        color: colors.outline,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusListTileTitle extends StatelessWidget {
  const _StatusListTileTitle({
    required this.title,
    required this.monospace,
    required this.trailing,
  });

  final String title;
  final bool monospace;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titleWidget = monospace
        ? TsMonoText(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          )
        : Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          );
    final trailingWidget = trailing;
    if (trailingWidget == null) return titleWidget;

    return Wrap(
      spacing: TsPhoneSpacing.small,
      runSpacing: TsPhoneSpacing.xSmall,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[titleWidget, trailingWidget],
    );
  }
}

class TsSettingsSection extends StatelessWidget {
  const TsSettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.footer,
  });

  final String title;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        TsPhoneSpacing.xLarge,
        TsPhoneSpacing.large,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TsPhoneSpacing.small,
              0,
              TsPhoneSpacing.small,
              TsPhoneSpacing.small,
            ),
            child: Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Material(color: Colors.transparent, child: child),
          if (footer case final value?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TsPhoneSpacing.small,
                TsPhoneSpacing.small,
                TsPhoneSpacing.small,
                0,
              ),
              child: Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TsEmptyState extends StatelessWidget {
  const TsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(TsPhoneSpacing.large),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(TsPhoneSpacing.xLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: 48,
                child: Icon(icon, size: 30, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: TsPhoneSpacing.large),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: TsPhoneSpacing.small),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action case final value?) ...<Widget>[
                const SizedBox(height: TsPhoneSpacing.large),
                value,
              ],
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return content;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

class TsStatusDot extends StatelessWidget {
  const TsStatusDot({
    super.key,
    required this.color,
    this.size = 8,
    this.pulsing = false,
  });

  final Color color;
  final double size;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    if (!pulsing || MediaQuery.disableAnimationsOf(context)) {
      return _buildDot(0);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: TsPhoneMotion.statusPulse,
      curve: Curves.easeOutCubic,
      builder: (context, pulse, _) => _buildDot(pulse),
    );
  }

  Widget _buildDot(double pulse) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: pulse > 0
          ? <BoxShadow>[
              BoxShadow(
                color: color.withValues(alpha: 0.18 * pulse),
                blurRadius: 5 * pulse,
                spreadRadius: 2 * pulse,
              ),
            ]
          : null,
    ),
  );
}

class TsMonoText extends StatelessWidget {
  const TsMonoText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: (style ?? Theme.of(context).textTheme.bodySmall)?.copyWith(
        fontFamily: 'monospace',
        letterSpacing: 0,
      ),
    );
  }
}

class TsStatusBadge extends StatelessWidget {
  const TsStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
    this.pulsing = false,
  });

  final String label;
  final Color color;
  final bool compact;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.1,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 22),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: highContrast ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: highContrast ? 0.72 : 0.24),
          width: highContrast ? 1 : 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (pulsing) ...<Widget>[
            TsStatusDot(color: color, size: 6, pulsing: true),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class TsInlineStatus extends StatelessWidget {
  const TsInlineStatus({
    super.key,
    required this.label,
    required this.color,
    this.pulsing = false,
  });

  final String label;
  final Color color;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.1,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: TsStatusDot(color: color, size: 6, pulsing: pulsing),
          ),
          const WidgetSpan(child: SizedBox(width: 5)),
          TextSpan(text: label),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class TsCenteredAction extends StatelessWidget {
  const TsCenteredAction({
    super.key,
    required this.child,
    this.minWidth = 160,
    this.maxWidth = 240,
  });

  final Widget child;
  final double minWidth;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final useAvailableWidth =
            MediaQuery.textScalerOf(context).scale(17) > 24 ||
            availableWidth < minWidth;
        final targetWidth = useAvailableWidth || availableWidth < maxWidth
            ? availableWidth
            : maxWidth;
        return Center(
          child: SizedBox(width: targetWidth, child: child),
        );
      },
    );
  }
}

class TsMetadataItem extends StatelessWidget {
  const TsMetadataItem({
    super.key,
    required this.icon,
    required this.text,
    this.tooltip,
    this.maxLines = 1,
  });

  final IconData icon;
  final String text;
  final String? tooltip;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: TsMonoText(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class TsTerminalBlock extends StatelessWidget {
  const TsTerminalBlock({
    super.key,
    required this.body,
    this.title,
    this.status,
    this.isError = false,
  });

  final String body;
  final String? title;
  final String? status;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final terminal = TsPhoneStatusTheme.resolve(context);
    final statusColor = isError ? terminal.error : terminal.connected;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: terminal.terminalBackground,
        borderRadius: BorderRadius.circular(TsPhoneRadii.small),
        border: Border.all(
          color: isError
              ? terminal.error.withValues(alpha: 0.48)
              : terminal.terminalMuted.withValues(alpha: 0.34),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null || status != null)
            Container(
              color: terminal.terminalSurface,
              padding: const EdgeInsets.symmetric(
                horizontal: TsPhoneSpacing.medium,
                vertical: TsPhoneSpacing.small,
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.terminal_rounded, size: 15, color: statusColor),
                  if (title case final value?) ...<Widget>[
                    const SizedBox(width: 6),
                    Expanded(
                      child: TsMonoText(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: terminal.terminalForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (status case final value?)
                    TsMonoText(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(TsPhoneSpacing.medium),
            child: SelectableText(
              body,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: terminal.terminalForeground,
                fontFamily: 'monospace',
                letterSpacing: 0,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
