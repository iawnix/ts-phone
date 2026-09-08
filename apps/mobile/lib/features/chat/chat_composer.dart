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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canEdit;
  final bool canSend;
  final bool sending;
  final int maxLines;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.bodyLarge!.copyWith(fontSize: 16, height: 1.45);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => LayoutBuilder(
        builder: (context, constraints) {
          final measure =
              TextPainter(
                text: TextSpan(text: value.text, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout(
                maxWidth: (constraints.maxWidth - 76).clamp(1, double.infinity),
              );
          final multiline =
              measure.didExceedMaxLines || value.text.contains('\n');
          measure.dispose();
          return TextFieldTapRegion(
            child: Material(
              key: const ValueKey('chat-composer'),
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        6,
                        multiline ? 16 : 58,
                        multiline ? 52 : 6,
                      ),
                      child: TextField(
                        key: const ValueKey('chat-input'),
                        controller: controller,
                        focusNode: focusNode,
                        enabled: canEdit,
                        minLines: 1,
                        maxLines: maxLines,
                        style: style,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                        onTapOutside: (_) => focusNode.unfocus(),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintMaxLines: 2,
                          isDense: true,
                          filled: false,
                          hintStyle: style.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: SizedBox.square(
                        key: const ValueKey('composer-action-slot'),
                        dimension: 44,
                        child: IconButton.filled(
                          key: const ValueKey('composer-send'),
                          onPressed:
                              canSend &&
                                  value.text.trim().isNotEmpty &&
                                  !sending
                              ? onSend
                              : null,
                          tooltip: sending
                              ? context.l10n.sending
                              : context.l10n.send,
                          style: IconButton.styleFrom(
                            shape: const CircleBorder(),
                            backgroundColor: colors.onSurface,
                            foregroundColor: colors.surface,
                            disabledBackgroundColor: colors.onSurface
                                .withValues(alpha: 0.08),
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
                              : const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
