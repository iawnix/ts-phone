import 'dart:math' as math;
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:corhub/theme/app_icons.dart';

import '../models/chat_message.dart';
import '../l10n/app_localizations_extensions.dart';
import '../theme/corhub_theme.dart';
import 'markdown_message.dart';
import 'presentation.dart';
import 'activity_label.dart';
import 'conversation_time.dart';
import 'corhub_brand_mark.dart';

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
          failure: message.failure,
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
        for (var index = 0; index < message.tools.length; index++)
          _ToolDetailView(
            detail: message.tools[index],
            timestamp: index == 0 ? message.timestamp : null,
          ),
        if (message.hasInterruptedOutput)
          _OutputNotice(state: message.outputState!, failure: message.failure),
      ],
    );
    final frame = GestureDetector(
      onLongPress: message.text.isEmpty
          ? null
          : () async {
              try {
                await Clipboard.setData(ClipboardData(text: message.text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.outputCopied)),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.outputCopyFailed)),
                  );
                }
              }
            },
      child: _MessageFrame(
        isUser: isUser,
        compactAssistant: !isUser && !hasNarrative && message.tools.isNotEmpty,
        origin: message.origin,
        timestamp: message.timestamp,
        deliveryState: message.deliveryState,
        showAssistantAttribution: false,
        showAssistantTimestamp: message.tools.isEmpty,
        child: content,
      ),
    );
    if (!animate) return frame;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: CorHubMotion.resolve(context, CorHubMotion.standard),
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
  const _OutputNotice({required this.state, this.failure});
  final AssistantOutputState state;
  final ChatFailure? failure;

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
    final detail = failure?.detail?.trim();
    final summary = failure?.summary?.trim();
    if (failure != null &&
        (summary?.isNotEmpty == true || detail?.isNotEmpty == true)) {
      final colors = Theme.of(context).colorScheme;
      final subtitle = <String>[
        if (summary?.isNotEmpty == true) summary!,
        if (failure?.statusCode case final status?) 'HTTP $status',
      ].join(' · ');
      final details = <String>[
        if (detail?.isNotEmpty == true) detail!,
        if (failure?.code case final code? when code.isNotEmpty) 'Code: $code',
        if (failure?.operationId case final operationId?
            when operationId.isNotEmpty)
          'Operation: $operationId',
      ].join('\n');
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey<String>(
              'message-failure-${failure?.operationId ?? failure?.code ?? label}',
            ),
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.fromLTRB(48, 0, 12, 10),
            leading: Icon(
              AppIcons.error_outline,
              size: 18,
              color: colors.error,
            ),
            title: Text(label, style: TextStyle(color: colors.error)),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            children: details.isEmpty
                ? const <Widget>[]
                : <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        details,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
          ),
        ),
      );
    }
    return Padding(
      key: const ValueKey('message-output-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            failed ? AppIcons.error_outline : AppIcons.info_outline,
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
      showAssistantAttribution: false,
      child: MarkdownMessage(
        key: const ValueKey('streaming-message-text'),
        data: value.isEmpty ? '…' : value,
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
    this.showAssistantTimestamp = true,
    this.compactAssistant = false,
  });

  final bool isUser;
  final Widget child;
  final bool isStreaming;
  final String? origin;
  final DateTime? timestamp;
  final ChatDeliveryState? deliveryState;
  final bool showAssistantAttribution;
  final bool showAssistantTimestamp;
  final bool compactAssistant;

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
        margin: EdgeInsets.symmetric(
          horizontal: CorHubSpacing.large,
          vertical: compactAssistant ? 0 : CorHubSpacing.xSmall,
        ),
        padding: isUser
            ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
            : compactAssistant
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(
                horizontal: CorHubSpacing.xSmall,
                vertical: CorHubSpacing.small,
              ),
        decoration: isUser
            ? BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(CorHubRadii.bubble),
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
              const SizedBox(height: CorHubSpacing.xSmall),
            ] else if (showAssistantAttribution) ...<Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (isStreaming) ...<Widget>[
                    TsStatusDot(
                      color: CorHubStatusTheme.resolve(context).connected,
                      pulsing: true,
                    ),
                    const SizedBox(width: CorHubSpacing.small),
                  ] else ...<Widget>[
                    CorHubBrandMark(size: 15, color: theme.colorScheme.primary),
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
              const SizedBox(height: CorHubSpacing.xSmall),
            ],
            child,
            if (!isUser && showAssistantTimestamp)
              _AssistantMessageTimestamp(timestamp: timestamp),
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
      'local' || 'cli' || 'interactive' => context.l10n.messageOriginCli,
      _ => null,
    };
    final deliveryLabel = switch (deliveryState) {
      ChatDeliveryState.sending => context.l10n.messageSending,
      ChatDeliveryState.synchronizing => context.l10n.messageSynchronizing,
      ChatDeliveryState.uncertain => context.l10n.messageDeliveryUncertain,
      null => null,
    };
    final timeLabel = conversationTimeLabel(timestamp);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (originLabel != null) Text(originLabel, style: labelStyle),
        if (deliveryLabel != null) ...<Widget>[
          if (deliveryState == ChatDeliveryState.sending)
            SizedBox.square(
              dimension: 11,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Icon(AppIcons.cloud_upload_outlined, size: 13, color: color),
          Text(deliveryLabel, style: labelStyle),
        ],
        if (timeLabel != null) Text(timeLabel, style: labelStyle),
      ],
    );
  }
}

class _AssistantMessageTimestamp extends StatelessWidget {
  const _AssistantMessageTimestamp({required this.timestamp});

  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final label = conversationTimeLabel(timestamp);
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: CorHubSpacing.xSmall),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ToolDetailView extends StatelessWidget {
  const _ToolDetailView({required this.detail, this.timestamp});

  final ToolDetail detail;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terminal = CorHubStatusTheme.resolve(context);
    final stateColor = detail.isError ? terminal.error : terminal.connected;
    final title = detail.title.isEmpty ? context.l10n.toolResult : detail.title;
    final stateLabel = detail.isError
        ? context.l10n.statusError
        : context.l10n.toolCompleted;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Material(
        key: const ValueKey<String>('tool-disclosure-row'),
        color: Colors.transparent,
        child: ExpansionTile(
          dense: true,
          minTileHeight: 48,
          visualDensity: VisualDensity.compact,
          shape: const Border(),
          collapsedShape: const Border(),
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: CorHubSpacing.medium,
          ),
          textColor: theme.colorScheme.onSurface,
          collapsedTextColor: theme.colorScheme.onSurface,
          iconColor: stateColor,
          collapsedIconColor: theme.colorScheme.onSurfaceVariant,
          leading: Icon(
            detail.isError
                ? AppIcons.error_outline_rounded
                : AppIcons.terminal_rounded,
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
              const SizedBox(width: CorHubSpacing.small),
              if (detail.isError)
                Text(
                  stateLabel,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: stateColor,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Tooltip(
                  message: stateLabel,
                  child: Icon(
                    AppIcons.check_circle_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (conversationTimeLabel(timestamp)
                  case final time?) ...<Widget>[
                const SizedBox(width: CorHubSpacing.small),
                Text(
                  time,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            CorHubSpacing.medium,
            0,
            CorHubSpacing.medium,
            4,
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
