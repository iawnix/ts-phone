import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations_extensions.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/presentation.dart';
import 'chat_controller.dart';

/// A compact, persistent indication that the current turn is still running.
///
/// This bar owns the single stop action for every abortable run, including the
/// interval before a concrete tool is known. Once the turn settles, the strip
/// disappears and the persisted timeline becomes the source of truth.
class LiveRunStrip extends StatefulWidget {
  const LiveRunStrip({
    super.key,
    required this.activity,
    required this.onAbort,
    this.canAbort = false,
    this.aborting = false,
  });

  final ChatActivity? activity;
  final VoidCallback onAbort;
  final bool canAbort;
  final bool aborting;

  @override
  State<LiveRunStrip> createState() => _LiveRunStripState();
}

class _LiveRunStripState extends State<LiveRunStrip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(LiveRunStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity?.startedAt != widget.activity?.startedAt) {
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    if (widget.activity?.startedAt == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = TsPhoneStatusTheme.resolve(context);
    final activity = widget.activity;
    final failed = activity?.kind == ChatActivityKind.toolFailed;
    final name = activity?.toolName?.trim();
    final label = failed
        ? name == null || name.isEmpty
              ? context.l10n.toolFailed
              : '${context.l10n.toolFailed}: ${_humanize(name)}'
        : name == null || name.isEmpty
        ? context.l10n.tspiGenerating
        : context.l10n.toolRunning(_humanize(name));
    final elapsed = failed ? null : activity?.elapsed;
    final elapsedLabel = elapsed == null
        ? null
        : context.l10n.timelineDuration(_formatElapsed(elapsed));
    final accent = failed ? colors.error : status.connected;
    final glass = TsPhoneGlassTheme.resolve(context);
    final tint = Color.alphaBlend(
      accent.withValues(alpha: failed ? 0.12 : 0.07),
      glass.elevatedSurface,
    );

    return Semantics(
      liveRegion: true,
      label: label,
      child: TsGlassSurface(
        key: const ValueKey<String>('live-run-strip'),
        elevated: true,
        blurSigma: glass.floatingBlurSigma,
        tint: tint,
        borderColor: failed
            ? colors.error.withValues(alpha: 0.48)
            : glass.strongBorder,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Icon(
                        failed
                            ? Icons.error_outline_rounded
                            : Icons.hourglass_top_rounded,
                        size: 18,
                        color: accent,
                      ),
                      if (!failed)
                        Positioned(
                          right: 3,
                          bottom: 3,
                          child: TsStatusDot(
                            color: accent,
                            size: 6,
                            pulsing: true,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: TsPhoneSpacing.medium),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: TsPhoneMotion.resolve(
                      context,
                      TsPhoneMotion.quick,
                    ),
                    child: Column(
                      key: ValueKey<String>(label),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (elapsedLabel != null)
                          Text(
                            elapsedLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!failed &&
                    (widget.canAbort || widget.aborting)) ...<Widget>[
                  const SizedBox(width: TsPhoneSpacing.xSmall),
                  IconButton(
                    key: const ValueKey<String>('live-run-stop'),
                    onPressed: widget.canAbort && !widget.aborting
                        ? widget.onAbort
                        : null,
                    tooltip: widget.aborting
                        ? context.l10n.aborting
                        : context.l10n.abortGeneration,
                    color: colors.error,
                    icon: widget.aborting
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.stop_circle_outlined, size: 21),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _humanize(String value) {
  final normalized = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (normalized.isEmpty) return value;
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

String _formatElapsed(Duration value) {
  final seconds = value.inSeconds;
  if (seconds < 60) return '$seconds';
  final minutes = seconds ~/ 60;
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}
