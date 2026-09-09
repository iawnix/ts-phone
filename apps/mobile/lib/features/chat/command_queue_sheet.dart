import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/queued_command.dart';
import 'chat_controller.dart';

Future<void> showCommandQueue(
  BuildContext context,
  ChatController controller,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => _CommandQueueSheet(controller: controller),
);

class _CommandQueueSheet extends StatefulWidget {
  const _CommandQueueSheet({required this.controller});
  final ChatController controller;
  @override
  State<_CommandQueueSheet> createState() => _CommandQueueSheetState();
}

class _CommandQueueSheetState extends State<_CommandQueueSheet> {
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
      final pending = controller.pendingCommands;
      final recent = controller.recentCommandResults;
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
              child: pending.isEmpty && recent.isEmpty
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
                        ] else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            child: Text(
                              l10n.commandQueueEmpty,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        if (recent.isNotEmpty) ...<Widget>[
                          _QueueSectionHeader(
                            icon: Icons.history_rounded,
                            label: l10n.commandQueueRecent,
                            count: recent.length,
                          ),
                          for (var index = 0; index < recent.length; index++)
                            _commandTile(
                              context,
                              recent[index],
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
        command.sessionId!,
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
