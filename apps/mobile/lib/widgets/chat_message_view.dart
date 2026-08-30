import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../l10n/app_localizations_extensions.dart';
import '../theme/ts_phone_theme.dart';
import 'markdown_message.dart';
import 'presentation.dart';
import 'ts_phone_brand_mark.dart';

class ChatMessageView extends StatelessWidget {
  const ChatMessageView({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: <Widget>[
        if (message.text.isNotEmpty) MarkdownMessage(data: message.text),
        for (final tool in message.tools) _ToolDetailView(detail: tool),
      ],
    );
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: TsPhoneMotion.standard,
      curve: Curves.easeOut,
      child: _MessageFrame(
        isUser: isUser,
        origin: message.origin,
        timestamp: message.timestamp,
        deliveryState: message.deliveryState,
        child: content,
      ),
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
  });

  final bool isUser;
  final Widget child;
  final bool isStreaming;
  final String? origin;
  final DateTime? timestamp;
  final ChatDeliveryState? deliveryState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = math.min(760.0, viewportWidth * (isUser ? 0.84 : 0.96));
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
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
                color: theme.colorScheme.surfaceContainerHigh.withValues(
                  alpha: 0.86,
                ),
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
            ] else ...<Widget>[
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
        : context.l10n.statusReady;
    return Padding(
      padding: const EdgeInsets.only(top: TsPhoneSpacing.small),
      child: TsGlassSurface(
        tint: terminal.terminalBackground,
        borderColor: detail.isError
            ? terminal.error.withValues(alpha: 0.52)
            : terminal.terminalMuted.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(TsPhoneRadii.medium),
        child: ExpansionTile(
          dense: true,
          shape: const Border(),
          collapsedShape: const Border(),
          textColor: terminal.terminalForeground,
          collapsedTextColor: terminal.terminalForeground,
          iconColor: stateColor,
          collapsedIconColor: terminal.terminalMuted,
          leading: Icon(
            detail.isError ? Icons.error_outline : Icons.terminal_rounded,
            size: 19,
            color: stateColor,
          ),
          title: TsMonoText(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: terminal.terminalForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            stateLabel,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(color: stateColor),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            TsPhoneSpacing.medium,
            0,
            TsPhoneSpacing.medium,
            TsPhoneSpacing.medium,
          ),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  detail.body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: terminal.terminalForeground,
                    fontFamily: 'monospace',
                    letterSpacing: 0,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
