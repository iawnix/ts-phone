import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations_extensions.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/presentation.dart';
import 'chat_controller.dart';

/// A compact, persistent indication that the current turn is still running.
///
/// When a concrete tool activity is known it owns the single stop action.  If
/// the run has no tool activity, the composer remains the stop affordance.
/// Once the turn settles, the strip disappears and the persisted timeline
/// becomes the source of truth.
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

    return Semantics(
      liveRegion: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TsPhoneSpacing.medium,
          TsPhoneSpacing.small,
          TsPhoneSpacing.medium,
          0,
        ),
        child: TsGlassSurface(
          tint: colors.secondaryContainer.withValues(alpha: 0.72),
          borderColor: accent.withValues(alpha: 0.32),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: <Widget>[
              TsStatusDot(color: accent, size: 8, pulsing: !failed),
              const SizedBox(width: TsPhoneSpacing.small),
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.auto_awesome_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: TsPhoneSpacing.small),
              Expanded(
                child: AnimatedSwitcher(
                  duration: TsPhoneMotion.quick,
                  child: Text(
                    key: ValueKey<String>(label),
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (elapsedLabel != null) ...<Widget>[
                const SizedBox(width: TsPhoneSpacing.small),
                Text(
                  elapsedLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSecondaryContainer.withValues(alpha: 0.78),
                  ),
                ),
              ],
              if (activity?.kind == ChatActivityKind.runningTool) ...<Widget>[
                const SizedBox(width: TsPhoneSpacing.xSmall),
                IconButton(
                  onPressed: widget.canAbort && !widget.aborting
                      ? widget.onAbort
                      : null,
                  tooltip: widget.aborting
                      ? context.l10n.aborting
                      : context.l10n.abortGeneration,
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
