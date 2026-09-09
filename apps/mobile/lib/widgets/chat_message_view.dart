import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../l10n/app_localizations_extensions.dart';
import '../theme/ts_phone_theme.dart';
import 'markdown_message.dart';
import 'presentation.dart';
import 'activity_label.dart';
import 'ts_phone_brand_mark.dart';

class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    this.animate = true,
  });

  final ChatMessage message;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final hasNarrative = message.text.trim().isNotEmpty;
    if (!isUser && !hasNarrative && message.tools.isEmpty) {
      return RepaintBoundary(
        child: _OutputNotice(
          state: message.outputState ?? AssistantOutputState.empty,
        ),
      );
    }
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: <Widget>[
        if (hasNarrative) MarkdownMessage(data: message.text),
        for (final tool in message.tools) _ToolDetailView(detail: tool),
        if (message.hasInterruptedOutput)
          _OutputNotice(state: message.outputState!),
      ],
    );
    final frame = RepaintBoundary(
      child: _MessageFrame(
        isUser: isUser,
        origin: message.origin,
        timestamp: message.timestamp,
        deliveryState: message.deliveryState,
        showAssistantAttribution: false,
        child: content,
      ),
    );
    if (!animate) return frame;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: TsPhoneMotion.resolve(context, TsPhoneMotion.standard),
      curve: Curves.easeOut,
      child: frame,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 2 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class _OutputNotice extends StatelessWidget {
  const _OutputNotice({required this.state});
  final AssistantOutputState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final failed = state == AssistantOutputState.failed;
    final label = switch (state) {
      AssistantOutputState.empty => l10n.messageNoText,
      AssistantOutputState.notDisplayed => l10n.messageNotDisplayed,
      AssistantOutputState.failed => l10n.messageGenerationFailed,
      AssistantOutputState.aborted => l10n.messageGenerationAborted,
    };
    return Padding(
      key: const ValueKey('message-output-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: failed ? colors.error : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: failed ? colors.error : colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StreamingChatMessageView extends StatefulWidget {
  const StreamingChatMessageView({
    super.key,
    required this.textListenable,
    required this.updatesEnabledListenable,
  });

  final ValueListenable<String?> textListenable;
  final ValueListenable<bool> updatesEnabledListenable;

  @override
  State<StreamingChatMessageView> createState() =>
      _StreamingChatMessageViewState();
}

class _StreamingChatMessageViewState extends State<StreamingChatMessageView> {
  String? _visibleText;

  @override
  void initState() {
    super.initState();
    _visibleText = widget.updatesEnabledListenable.value
        ? widget.textListenable.value
        : null;
    widget.textListenable.addListener(_onTextChanged);
    widget.updatesEnabledListenable.addListener(_onUpdatesEnabledChanged);
  }

  @override
  void didUpdateWidget(StreamingChatMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textListenable != widget.textListenable) {
      oldWidget.textListenable.removeListener(_onTextChanged);
      widget.textListenable.addListener(_onTextChanged);
      _visibleText = widget.updatesEnabledListenable.value
          ? widget.textListenable.value
          : null;
    }
    if (oldWidget.updatesEnabledListenable != widget.updatesEnabledListenable) {
      oldWidget.updatesEnabledListenable.removeListener(
        _onUpdatesEnabledChanged,
      );
      widget.updatesEnabledListenable.addListener(_onUpdatesEnabledChanged);
      if (widget.updatesEnabledListenable.value) {
        _visibleText = widget.textListenable.value;
      }
    }
  }

  void _onTextChanged() {
    final next = widget.textListenable.value;
    if (next != null && !widget.updatesEnabledListenable.value) return;
    _updateVisibleText(next);
  }

  void _onUpdatesEnabledChanged() {
    if (widget.updatesEnabledListenable.value) {
      _updateVisibleText(widget.textListenable.value);
    }
  }

  void _updateVisibleText(String? next) {
    if (!mounted || next == _visibleText) return;
    setState(() => _visibleText = next);
  }

  @override
  void dispose() {
    widget.textListenable.removeListener(_onTextChanged);
    widget.updatesEnabledListenable.removeListener(_onUpdatesEnabledChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _visibleText;
    if (value == null) return const SizedBox.shrink();
    return _MessageFrame(
      isUser: false,
      isStreaming: true,
      child: Text(
        key: const ValueKey<String>('streaming-message-text'),
        value.isEmpty ? '…' : value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
    );
  }
}

class _MessageFrame extends StatelessWidget {
  const _MessageFrame({
    required this.isUser,
    required this.child,
    this.isStreaming = false,
    this.origin,
    this.timestamp,
    this.deliveryState,
    this.showAssistantAttribution = true,
  });

  final bool isUser;
  final Widget child;
  final bool isStreaming;
  final String? origin;
  final DateTime? timestamp;
  final ChatDeliveryState? deliveryState;
  final bool showAssistantAttribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = math.min(760.0, viewportWidth * (isUser ? 0.84 : 0.96));
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: isUser ? null : double.infinity,
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.symmetric(
          horizontal: TsPhoneSpacing.large,
          vertical: TsPhoneSpacing.xSmall,
        ),
        padding: isUser
            ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
            : const EdgeInsets.symmetric(
                horizontal: TsPhoneSpacing.xSmall,
                vertical: TsPhoneSpacing.small,
              ),
        decoration: isUser
            ? BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(TsPhoneRadii.bubble),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.stretch,
          children: <Widget>[
            if (isUser) ...<Widget>[
              _UserMessageMetadata(
                origin: origin,
                timestamp: timestamp,
                deliveryState: deliveryState,
              ),
              const SizedBox(height: TsPhoneSpacing.xSmall),
            ] else if (showAssistantAttribution) ...<Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (isStreaming) ...<Widget>[
                    TsStatusDot(
                      color: theme.colorScheme.tertiary,
                      pulsing: true,
                    ),
                    const SizedBox(width: TsPhoneSpacing.small),
                  ] else ...<Widget>[
                    TsPhoneBrandMark(
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    isStreaming ? context.l10n.tspiGenerating : 'TSPi',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TsPhoneSpacing.xSmall),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _UserMessageMetadata extends StatelessWidget {
  const _UserMessageMetadata({
    required this.origin,
    required this.timestamp,
    required this.deliveryState,
  });

  final String? origin;
  final DateTime? timestamp;
  final ChatDeliveryState? deliveryState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final originLabel = switch (origin) {
      'phone' => context.l10n.messageOriginPhone,
      'local' || 'cli' || 'interactive' => context.l10n.messageOriginCli,
      _ => null,
    };
    final deliveryLabel = switch (deliveryState) {
      ChatDeliveryState.sending => context.l10n.messageSending,
      ChatDeliveryState.synchronizing => context.l10n.messageSynchronizing,
      ChatDeliveryState.uncertain => context.l10n.messageDeliveryUncertain,
      null => null,
    };
    final localTime = timestamp?.toLocal();
    final timeLabel = localTime == null
        ? null
        : '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(context.l10n.you, style: labelStyle),
        if (originLabel != null) Text('· $originLabel', style: labelStyle),
        if (deliveryLabel != null) ...<Widget>[
          if (deliveryState == ChatDeliveryState.sending)
            SizedBox.square(
              dimension: 11,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Icon(Icons.cloud_upload_outlined, size: 13, color: color),
          Text(deliveryLabel, style: labelStyle),
        ] else if (timeLabel != null)
          Text('· $timeLabel', style: labelStyle),
      ],
    );
  }
}

class _ToolDetailView extends StatelessWidget {
  const _ToolDetailView({required this.detail});

  final ToolDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terminal = TsPhoneStatusTheme.resolve(context);
    final stateColor = detail.isError ? terminal.error : terminal.connected;
    final title = detail.title.isEmpty ? context.l10n.toolResult : detail.title;
    final stateLabel = detail.isError
        ? context.l10n.statusError
        : context.l10n.timelineCompleted;
    return Padding(
      padding: const EdgeInsets.only(top: TsPhoneSpacing.xSmall),
      child: Material(
        key: const ValueKey<String>('tool-disclosure-row'),
        color: Colors.transparent,
        child: ExpansionTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: const Border(),
          collapsedShape: const Border(),
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: TsPhoneSpacing.medium,
          ),
          textColor: theme.colorScheme.onSurface,
          collapsedTextColor: theme.colorScheme.onSurface,
          iconColor: stateColor,
          collapsedIconColor: theme.colorScheme.onSurfaceVariant,
          leading: Icon(
            detail.isError
                ? Icons.error_outline_rounded
                : Icons.terminal_rounded,
            size: 18,
            color: detail.isError
                ? stateColor
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  activityLabel(title, context.l10n),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: TsPhoneSpacing.small),
              Text(
                stateLabel,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: detail.isError
                      ? stateColor
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            TsPhoneSpacing.small,
            TsPhoneSpacing.xSmall,
            TsPhoneSpacing.small,
            TsPhoneSpacing.small,
          ),
          children: <Widget>[
            TsTerminalBlock(
              key: const ValueKey<String>('tool-raw-output'),
              body: '${detail.title}\n${detail.body}',
              isError: detail.isError,
            ),
          ],
        ),
      ),
    );
  }
}
