import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations_extensions.dart';
import '../../theme/ts_phone_theme.dart';
import 'chat_controller.dart';
import '../../widgets/activity_label.dart';

/// A compact, persistent indication that the current turn is still running.
///
/// This row lives in the timeline; the composer owns the single stop action.
/// Once the turn settles, persisted activity becomes the source of truth.
class LiveRunStrip extends StatelessWidget {
  const LiveRunStrip({super.key, required this.activity});

  final ChatActivity? activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activity = this.activity;
    final failed = activity?.kind == ChatActivityKind.toolFailed;
    final name = activity?.toolName?.trim();
    final label = failed
        ? name == null || name.isEmpty
              ? context.l10n.toolFailed
              : '${context.l10n.toolFailed}: ${activityLabel(name, context.l10n)}'
        : name == null || name.isEmpty
        ? context.l10n.runtimeCompactRunning
        : activityLabel(name, context.l10n);
    final startedAt = failed ? null : activity?.startedAt;
    final accent = failed ? colors.error : colors.onSurfaceVariant;
    return Material(
      key: const ValueKey<String>('live-run-strip'),
      color: colors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            children: <Widget>[
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.hourglass_top_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: TsPhoneSpacing.medium),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: label,
                  child: ExcludeSemantics(
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (startedAt != null)
                            _ElapsedLabel(
                              key: ValueKey<DateTime>(startedAt),
                              startedAt: startedAt,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ElapsedLabel extends StatefulWidget {
  const _ElapsedLabel({super.key, required this.startedAt});

  final DateTime startedAt;

  @override
  State<_ElapsedLabel> createState() => _ElapsedLabelState();
}

class _ElapsedLabelState extends State<_ElapsedLabel> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    final safeElapsed = elapsed.isNegative ? Duration.zero : elapsed;
    return ExcludeSemantics(
      child: Text(
        context.l10n.timelineDuration(_formatElapsed(safeElapsed)),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _formatElapsed(Duration value) {
  final seconds = value.inSeconds;
  if (seconds < 60) return '$seconds';
  final minutes = seconds ~/ 60;
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}
