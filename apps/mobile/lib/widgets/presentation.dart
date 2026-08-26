import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/ts_phone_theme.dart';

enum TsInfoTone { neutral, info, warning, error }

class TsPageBackdrop extends StatelessWidget {
  const TsPageBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isLight
                ? const <Color>[Color(0xFFF2F2F7), Color(0xFFEDEDF2)]
                : const <Color>[Color(0xFF0B0F14), Color(0xFF090D12)],
          ),
        ),
        child: child,
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
    this.blurSigma = 0,
    this.tint,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final bool elevated;
  final double blurSigma;
  final Color? tint;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final glass = TsPhoneGlassTheme.resolve(context);
    final fill = tint ?? (elevated ? glass.elevatedSurface : glass.surface);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color.alphaBlend(glass.highlight, fill), fill],
        ),
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? glass.border, width: 0.6),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child: blurSigma <= 0
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: content,
            ),
    );
    if (!elevated) return clipped;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: glass.shadow,
              blurRadius: 16,
              offset: const Offset(0, 6),
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
    final borderSide = BorderSide(
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
      width: 0.5,
    );
    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glass.blurSigma,
            sigmaY: glass.blurSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color.alphaBlend(glass.highlight, glass.surface),
                  glass.surface,
                ],
              ),
              border: switch (edge) {
                TsGlassBarEdge.top => Border(top: borderSide),
                TsGlassBarEdge.bottom => Border(bottom: borderSide),
              },
            ),
            child: child,
          ),
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
    return AppBar(
      leading: leading,
      title: title,
      actions: actions,
      toolbarHeight: toolbarHeight,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      titleTextStyle: titleTextStyle,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        TsPhoneSpacing.large,
        TsPhoneSpacing.large,
        TsPhoneSpacing.small,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (caption case final value?)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: TsPhoneSpacing.medium),
                child: Text(
                  value,
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
    this.maxLines = 3,
  });

  final IconData icon;
  final String message;
  final TsInfoTone tone;
  final Widget? action;
  final int maxLines;

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
      child: TsGlassSurface(
        tint: background.withValues(alpha: 0.82),
        borderColor: rail.withValues(alpha: 0.24),
        padding: EdgeInsets.fromLTRB(
          TsPhoneSpacing.medium,
          TsPhoneSpacing.small,
          action == null ? TsPhoneSpacing.medium : TsPhoneSpacing.xSmall,
          TsPhoneSpacing.small,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 19, color: rail),
            const SizedBox(width: TsPhoneSpacing.small),
            Expanded(
              child: Text(
                message,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
            ?action,
          ],
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
  });

  final Color statusColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? iconColor;
  final bool showStatusIndicator;
  final Widget? details;
  final bool titleMonospace;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TsPhoneSpacing.medium,
        vertical: 3,
      ),
      child: TsGlassSurface(
        tint: TsPhoneGlassTheme.resolve(context).elevatedSurface,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(TsPhoneRadii.panel),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: TsPhoneSpacing.medium),
                  Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh.withValues(
                          alpha: 0.7,
                        ),
                        borderRadius: BorderRadius.circular(
                          TsPhoneRadii.medium,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          Icon(icon, size: 23, color: iconColor ?? statusColor),
                          if (showStatusIndicator)
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colors.surfaceContainerLowest,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: TsPhoneSpacing.medium),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (titleMonospace)
                            TsMonoText(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            )
                          else
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
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
                  ),
                  const SizedBox(width: TsPhoneSpacing.small),
                  Center(
                    child:
                        trailing ??
                        Icon(
                          Icons.chevron_right,
                          size: 22,
                          color: colors.outline,
                        ),
                  ),
                  const SizedBox(width: TsPhoneSpacing.medium),
                ],
              ),
            ),
          ),
        ),
      ),
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
          TsGlassSurface(
            elevated: true,
            child: Material(color: Colors.transparent, child: child),
          ),
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

class TsSettingsIcon extends StatelessWidget {
  const TsSettingsIcon({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(TsPhoneRadii.small),
      ),
      child: Icon(icon, size: 19, color: Colors.white),
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
        child: TsGlassSurface(
          elevated: true,
          padding: const EdgeInsets.all(TsPhoneSpacing.xLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(TsPhoneRadii.medium),
                ),
                child: Icon(icon, size: 28, color: theme.colorScheme.primary),
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
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.24), width: 0.6),
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

class TsMetadataItem extends StatelessWidget {
  const TsMetadataItem({
    super.key,
    required this.icon,
    required this.text,
    this.tooltip,
  });

  final IconData icon;
  final String text;
  final String? tooltip;

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
            maxLines: 1,
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
