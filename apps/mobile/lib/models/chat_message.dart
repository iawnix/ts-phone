import 'dart:convert';

enum ChatRole { user, assistant, tool, system }

enum ChatDeliveryState { sending, synchronizing, uncertain }

enum AssistantOutputState { empty, notDisplayed, failed, aborted }

class ToolDetail {
  const ToolDetail({
    required this.title,
    required this.body,
    this.isError = false,
  });

  final String title;
  final String body;
  final bool isError;
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.tools = const <ToolDetail>[],
    this.timestamp,
    this.clientMessageId,
    this.origin,
    this.deliveryState,
    this.outputState,
  });

  factory ChatMessage.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Message must be an object');
    final json = value.cast<String, Object?>();
    final roleValue = json['role'];
    final role = switch (roleValue) {
      'user' => ChatRole.user,
      'assistant' => ChatRole.assistant,
      'toolResult' => ChatRole.tool,
      _ => ChatRole.system,
    };
    final textParts = <String>[];
    final tools = <ToolDetail>[];
    final content = json['content'];
    if (content is String) {
      textParts.add(content);
    } else if (content is List) {
      for (final blockValue in content) {
        if (blockValue is! Map) continue;
        final block = blockValue.cast<String, Object?>();
        switch (block['type']) {
          case 'text':
            final text = block['text'];
            if (text is String && text.isNotEmpty) textParts.add(text);
          case 'toolCall':
            final name = block['name'] is String
                ? block['name']! as String
                : 'tool';
            final arguments = block['arguments'];
            tools.add(ToolDetail(title: name, body: _prettyJson(arguments)));
        }
      }
    }
    if (role == ChatRole.tool) {
      final name = json['toolName'] is String
          ? json['toolName']! as String
          : '';
      tools.add(
        ToolDetail(
          title: name,
          body: textParts.join('\n\n'),
          isError: json['isError'] == true,
        ),
      );
      textParts.clear();
    }
    final timestampValue = json['timestamp'];
    final clientMessageId = json['clientMessageId'];
    final origin = json['origin'];
    if ((clientMessageId != null && clientMessageId is! String) ||
        (origin != null && origin is! String)) {
      throw const FormatException('Message metadata is invalid');
    }
    return ChatMessage(
      role: role,
      text: textParts.join('\n\n'),
      tools: tools,
      timestamp: timestampValue is num
          ? DateTime.fromMillisecondsSinceEpoch(timestampValue.toInt())
          : null,
      clientMessageId: clientMessageId as String?,
      origin: origin as String?,
      outputState: switch (json['outputState']) {
        'empty' => AssistantOutputState.empty,
        'not_displayed' => AssistantOutputState.notDisplayed,
        'failed' => AssistantOutputState.failed,
        'aborted' => AssistantOutputState.aborted,
        _ => null,
      },
    );
  }

  final ChatRole role;
  final String text;
  final List<ToolDetail> tools;
  final DateTime? timestamp;
  final String? clientMessageId;
  final String? origin;
  final ChatDeliveryState? deliveryState;
  final AssistantOutputState? outputState;

  bool get hasVisibleContent =>
      text.isNotEmpty || tools.isNotEmpty || outputState != null;

  bool get hasInterruptedOutput =>
      outputState == AssistantOutputState.failed ||
      outputState == AssistantOutputState.aborted;
  bool get isActivityOnly => role != ChatRole.user && text.trim().isEmpty;

  ChatMessage copyWith({ChatDeliveryState? deliveryState}) {
    return ChatMessage(
      role: role,
      text: text,
      tools: tools,
      timestamp: timestamp,
      clientMessageId: clientMessageId,
      origin: origin,
      deliveryState: deliveryState ?? this.deliveryState,
      outputState: outputState,
    );
  }

  static String _prettyJson(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } on JsonUnsupportedObjectError {
      return value.toString();
    }
  }
}
