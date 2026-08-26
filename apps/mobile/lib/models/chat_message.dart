import 'dart:convert';

enum ChatRole { user, assistant, tool, system }

enum ChatDeliveryState { sending, synchronizing }

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
    );
  }

  final ChatRole role;
  final String text;
  final List<ToolDetail> tools;
  final DateTime? timestamp;
  final String? clientMessageId;
  final String? origin;
  final ChatDeliveryState? deliveryState;

  ChatMessage copyWith({ChatDeliveryState? deliveryState}) {
    return ChatMessage(
      role: role,
      text: text,
      tools: tools,
      timestamp: timestamp,
      clientMessageId: clientMessageId,
      origin: origin,
      deliveryState: deliveryState ?? this.deliveryState,
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
