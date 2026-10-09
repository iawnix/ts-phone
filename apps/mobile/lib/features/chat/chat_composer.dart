import 'package:flutter/material.dart';
import 'package:ts_phone/theme/app_icons.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/workspace.dart';
import 'model_presentation.dart';
import '../../theme/ts_phone_theme.dart';
import 'model_provider_mark.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.canEdit,
    required this.canSend,
    required this.sending,
    required this.maxLines,
    required this.hint,
    required this.onSend,
    this.status,
    this.modelLabel,
    this.modelProvider,
    this.modelHint,
    this.onSelectModel,
    this.canSelectModel = true,
    this.contextUsage,
    this.onContextTap,
    this.onAbort,
    this.aborting = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canEdit;
  final bool canSend;
  final bool sending;
  final int maxLines;
  final String hint;
  final VoidCallback onSend;
  final String? status;
  final String? modelLabel;
  final String? modelProvider;
  final String? modelHint;
  final VoidCallback? onSelectModel;
  final bool canSelectModel;
  final SessionContextUsage? contextUsage;
  final VoidCallback? onContextTap;
  final VoidCallback? onAbort;
  final bool aborting;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: Material(
        key: const ValueKey('chat-composer'),
        color: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: MediaQuery.highContrastOf(context)
              ? BorderSide(color: colors.outline)
              : BorderSide.none,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  status!,
                  key: const ValueKey('composer-status'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                key: const ValueKey('chat-input'),
                controller: controller,
                focusNode: focusNode,
                enabled: canEdit,
                minLines: 1,
                maxLines: maxLines,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge!.copyWith(fontSize: 16, height: 1.45),
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                onTapOutside: (_) => focusNode.unfocus(),
                decoration: InputDecoration(
                  hintText: hint,
                  hintMaxLines: 2,
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: modelHint ?? context.l10n.chooseModel,
                        child: TextButton(
                          key: const ValueKey('composer-model'),
                          onPressed: onSelectModel,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.onSurfaceVariant,
                            minimumSize: const Size(44, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ModelProviderMark(
                                provider: modelProvider ?? '',
                                modelId: modelLabel,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  modelLabel == null
                                      ? context.l10n.chooseModel
                                      : modelDisplayName(modelLabel!),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ),
                              if (canSelectModel) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  AppIcons.keyboard_arrow_down_rounded,
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (contextUsage != null)
                    _ContextUsageIndicator(
                      usage: contextUsage!,
                      onTap: onContextTap,
                    ),
                  if (contextUsage != null) const SizedBox(width: 2),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final canStop = onAbort != null || aborting;
                      final stop = canStop && value.text.trim().isEmpty;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canStop && !stop)
                            IconButton(
                              key: const ValueKey('composer-stop'),
                              onPressed: aborting ? null : onAbort,
                              tooltip: context.l10n.abortGeneration,
                              icon: const Icon(AppIcons.stop_circle_outlined),
                            ),
                          SizedBox.square(
                            key: const ValueKey('composer-action-slot'),
                            dimension: 44,
                            child: IconButton.filled(
                              key: ValueKey(
                                stop ? 'composer-stop' : 'composer-send',
                              ),
                              onPressed: stop
                                  ? (aborting ? null : onAbort)
                                  : (canSend &&
                                            value.text.trim().isNotEmpty &&
                                            !sending
                                        ? onSend
                                        : null),
                              tooltip: stop
                                  ? context.l10n.abortGeneration
                                  : sending
                                  ? context.l10n.sending
                                  : context.l10n.send,
                              style: IconButton.styleFrom(
                                backgroundColor: colors.onSurface,
                                disabledBackgroundColor: colors.onSurface
                                    .withValues(alpha: .08),
                                foregroundColor: colors.surface,
                                shape: const CircleBorder(),
                                minimumSize: const Size.square(44),
                                padding: EdgeInsets.zero,
                              ),
                              icon: (stop ? aborting : sending)
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      stop
                                          ? AppIcons.stop_circle_outlined
                                          : AppIcons.send_rounded,
                                      size: 22,
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextUsageIndicator extends StatelessWidget {
  const _ContextUsageIndicator({required this.usage, this.onTap});

  final SessionContextUsage usage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = usage.percent;
    final normalized = ((percent ?? 0) / 100).clamp(0.0, 1.0);
    final color = percent == null
        ? theme.colorScheme.onSurfaceVariant
        : percent >= 85
        ? theme.colorScheme.error
        : percent >= 70
        ? TsPhoneStatusTheme.resolve(context).warning
        : theme.colorScheme.onSurfaceVariant;
    final used = usage.usedTokens;
    final label = used == null
        ? formatTokenCount(usage.limitTokens)
        : '${formatTokenCount(used)}/${formatTokenCount(usage.limitTokens)}';
    return Semantics(
      button: onTap != null,
      label: '${context.l10n.sessionContextWindow}: $label',
      child: Tooltip(
        message: '${context.l10n.sessionContextWindow}: $label',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    value: normalized,
                    strokeWidth: 2,
                    backgroundColor: color.withValues(alpha: .16),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
