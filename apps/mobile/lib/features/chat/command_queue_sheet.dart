import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/queued_command.dart';
import '../../theme/ts_phone_theme.dart';
import 'chat_controller.dart';

Future<void> showCommandQueue(
  BuildContext context,
  ChatController controller,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => _PendingCommandsSheet(controller: controller),
);

/// A compact conversation affordance for messages that are admitted but have
/// not started. The durable queue remains a Host concern; this strip only
/// appears when there is something the user can act on or needs to review.
class PendingCommandsStrip extends StatelessWidget {
  const PendingCommandsStrip({super.key, required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final waiting = controller.currentWaitingCommands;
      final otherWaiting = controller.otherWaitingCommands;
      final hasRecovery = controller.recoveryCommands.isNotEmpty;
      final queueProblem = controller.queueProblem;
      if (waiting.isEmpty &&
          otherWaiting.isEmpty &&
          !hasRecovery &&
          queueProblem == null) {
        return const SizedBox.shrink();
      }

      final l10n = context.l10n;
      final label = queueProblem == null
          ? hasRecovery
                ? l10n.commandNeedsReview
                : waiting.isNotEmpty
                ? waiting.length == 1
                      ? l10n.commandWaitingForCurrent
                      : l10n.commandQueueCount(waiting.length)
                : l10n.commandOtherConversationWaiting
          : describeTsPhoneProblem(
              TsPhoneApiException('Queue is paused', code: queueProblem),
            ).localizedMessage(l10n);
      final actionable =
          waiting.isNotEmpty || otherWaiting.isNotEmpty || hasRecovery;
      final colors = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(bottom: TsPhoneSpacing.small),
        child: Semantics(
          button: actionable,
          label: label,
          child: Material(
            color: queueProblem == null
                ? colors.surfaceContainerHighest
                : colors.errorContainer,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('pending-messages-strip'),
              onTap: actionable
                  ? () => showCommandQueue(context, controller)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TsPhoneSpacing.medium,
                  vertical: TsPhoneSpacing.small,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      queueProblem == null
                          ? Icons.schedule_rounded
                          : Icons.error_outline_rounded,
                      size: 18,
                      color: queueProblem == null
                          ? colors.primary
                          : colors.onErrorContainer,
                    ),
                    const SizedBox(width: TsPhoneSpacing.small),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: queueProblem == null
                              ? colors.onSurface
                              : colors.onErrorContainer,
                        ),
                      ),
                    ),
                    if (actionable) ...<Widget>[
                      const SizedBox(width: TsPhoneSpacing.small),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: queueProblem == null
                            ? colors.onSurfaceVariant
                            : colors.onErrorContainer,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PendingCommandsSheet extends StatefulWidget {
  const _PendingCommandsSheet({required this.controller});
  final ChatController controller;
  @override
  State<_PendingCommandsSheet> createState() => _PendingCommandsSheetState();
}

class _PendingCommandsSheetState extends State<_PendingCommandsSheet> {
  bool _busy = false;
  TsPhoneProblem? _problem;

  Future<void> _act(QueuedCommand command) async {
    if (_busy) return;
    if (command.status == CommandStatus.unknown) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.acknowledgeRequest),
          content: Text(context.l10n.acknowledgeRequestBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.acknowledgeRequest),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      if (command.status == CommandStatus.unknown) {
        await widget.controller.acknowledgeQueuedCommand(command);
      } else {
        await widget.controller.cancelQueuedCommand(command);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _problem = describeTsPhoneProblem(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final l10n = context.l10n;
      final colors = Theme.of(context).colorScheme;
      final problem =
          _problem ??
          (controller.queueProblem == null
              ? null
              : describeTsPhoneProblem(
                  TsPhoneApiException(
                    'Queue paused',
                    code: controller.queueProblem,
                  ),
                ));
      final pending = <QueuedCommand>[
        ...controller.waitingCommands,
        ...controller.recoveryCommands,
      ];
      return SizedBox(
        height: math.min(620, MediaQuery.sizeOf(context).height * .78),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                l10n.commandQueue,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  problem.localizedMessage(l10n),
                  style: TextStyle(color: colors.error),
                ),
              ),
            Expanded(
              child: pending.isEmpty
                  ? Center(child: Text(l10n.commandQueueEmpty))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: <Widget>[
                        if (pending.isNotEmpty) ...<Widget>[
                          _QueueSectionHeader(
                            icon: Icons.hourglass_top_rounded,
                            label: l10n.commandQueuePending,
                            count: pending.length,
                          ),
                          for (var index = 0; index < pending.length; index++)
                            _commandTile(
                              context,
                              pending[index],
                              controller,
                              colors,
                              index,
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );

  Widget _commandTile(
    BuildContext context,
    QueuedCommand command,
    ChatController controller,
    ColorScheme colors,
    int index,
  ) {
    final label = switch (command.status) {
      CommandStatus.queued => context.l10n.commandQueued(
        command.position ?? index + 1,
      ),
      CommandStatus.starting => context.l10n.commandStarting,
      CommandStatus.running => context.l10n.commandRunning,
      CommandStatus.completed => context.l10n.commandCompleted,
      CommandStatus.failed => context.l10n.commandFailed,
      CommandStatus.cancelled => context.l10n.commandCancelled,
      CommandStatus.unknown => context.l10n.commandUnknown,
      CommandStatus.acknowledged => context.l10n.commandAcknowledged,
    };
    final icon = switch (command.status) {
      CommandStatus.queued => Icons.schedule_outlined,
      CommandStatus.starting ||
      CommandStatus.running => Icons.play_arrow_outlined,
      CommandStatus.unknown ||
      CommandStatus.failed => Icons.error_outline_rounded,
      _ => Icons.check_rounded,
    };
    final details = <String>[
      label,
      if (command.model != null) command.model!,
      if (command.sessionId != null &&
          command.sessionId != controller.sessionId)
        context.l10n.commandOtherConversation,
      if (command.problem != null)
        describeTsPhoneProblem(
          TsPhoneApiException('Command failed', code: command.problem),
        ).localizedMessage(context.l10n),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          key: ValueKey('command-${command.sessionId}-${command.id}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 5,
          ),
          leading: Icon(
            icon,
            color: command.status == CommandStatus.failed
                ? colors.error
                : colors.onSurfaceVariant,
          ),
          title: Text(
            command.preview ?? label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            details.join('\n'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing:
              command.status == CommandStatus.queued ||
                  command.status == CommandStatus.unknown
              ? IconButton(
                  onPressed: _busy ? null : () => _act(command),
                  tooltip: command.status == CommandStatus.unknown
                      ? context.l10n.acknowledgeRequest
                      : context.l10n.cancelQueuedRequest,
                  icon: Icon(
                    command.status == CommandStatus.unknown
                        ? Icons.fact_check_outlined
                        : Icons.close_rounded,
                  ),
                )
              : null,
        ),
        const Divider(height: 1, indent: 20, endIndent: 20),
      ],
    );
  }
}

class _QueueSectionHeader extends StatelessWidget {
  const _QueueSectionHeader({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$count',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
