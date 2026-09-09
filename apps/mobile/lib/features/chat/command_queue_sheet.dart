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
      final commands = controller.queuedCommands;
      return SizedBox(
        height: math.min(560, MediaQuery.sizeOf(context).height * .7),
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
              child: commands.isEmpty
                  ? Center(child: Text(l10n.commandQueueEmpty))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: commands.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 20, endIndent: 20),
                      itemBuilder: (context, index) {
                        final command = commands[index];
                        final label = switch (command.status) {
                          CommandStatus.queued => l10n.commandQueued(
                            command.position ?? index + 1,
                          ),
                          CommandStatus.starting => l10n.commandStarting,
                          CommandStatus.running => l10n.commandRunning,
                          CommandStatus.completed => l10n.commandCompleted,
                          CommandStatus.failed => l10n.commandFailed,
                          CommandStatus.cancelled => l10n.commandCancelled,
                          CommandStatus.unknown => l10n.commandUnknown,
                          CommandStatus.acknowledged =>
                            l10n.commandAcknowledged,
                        };
                        final icon = switch (command.status) {
                          CommandStatus.queued => Icons.schedule_outlined,
                          CommandStatus.starting ||
                          CommandStatus.running => Icons.play_arrow_outlined,
                          CommandStatus.unknown ||
                          CommandStatus.failed => Icons.error_outline_rounded,
                          _ => Icons.check_rounded,
                        };
                        return ListTile(
                          key: ValueKey(
                            'command-${command.sessionId}-${command.id}',
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          leading: Icon(icon, color: colors.onSurfaceVariant),
                          title: Text(
                            command.preview ?? label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              label,
                              if (command.model != null) command.model!,
                              if (command.sessionId != null &&
                                  command.sessionId != controller.sessionId)
                                command.sessionId!,
                              if (command.problem != null)
                                describeTsPhoneProblem(
                                  TsPhoneApiException(
                                    'Command failed',
                                    code: command.problem,
                                  ),
                                ).localizedMessage(l10n),
                            ].join('\n'),
                          ),
                          trailing:
                              command.status == CommandStatus.queued ||
                                  command.status == CommandStatus.unknown
                              ? IconButton(
                                  onPressed: _busy ? null : () => _act(command),
                                  tooltip:
                                      command.status == CommandStatus.unknown
                                      ? l10n.acknowledgeRequest
                                      : l10n.cancelQueuedRequest,
                                  icon: Icon(
                                    command.status == CommandStatus.unknown
                                        ? Icons.fact_check_outlined
                                        : Icons.close_rounded,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
