import 'package:flutter/material.dart';
import '../../l10n/app_localizations_extensions.dart';

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
    this.modelLabel,
    this.modelHint,
    this.onSelectModel,
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
  final String? modelLabel;
  final String? modelHint;
  final VoidCallback? onSelectModel;
  final VoidCallback? onAbort;
  final bool aborting;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: Material(
        key: const ValueKey('chat-composer'),
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                              const Icon(Icons.tune_rounded, size: 18),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  modelLabel ?? context.l10n.chooseModel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (onAbort != null || aborting)
                    SizedBox.square(
                      dimension: 44,
                      child: IconButton(
                        key: const ValueKey('composer-stop'),
                        onPressed: aborting ? null : onAbort,
                        tooltip: context.l10n.abortGeneration,
                        icon: aborting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.stop_circle_outlined, size: 24),
                      ),
                    ),
                  SizedBox.square(
                    key: const ValueKey('composer-action-slot'),
                    dimension: 44,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => IconButton.filled(
                        key: const ValueKey('composer-send'),
                        onPressed:
                            canSend && value.text.trim().isNotEmpty && !sending
                            ? onSend
                            : null,
                        tooltip: sending
                            ? context.l10n.sending
                            : context.l10n.send,
                        style: IconButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: colors.onSurface,
                          foregroundColor: colors.surface,
                          disabledBackgroundColor: colors.onSurface.withValues(
                            alpha: .08,
                          ),
                          minimumSize: const Size.square(44),
                          padding: EdgeInsets.zero,
                        ),
                        icon: sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded, size: 22),
                      ),
                    ),
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
