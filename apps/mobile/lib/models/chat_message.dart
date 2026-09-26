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

class ChatFailure {
  const ChatFailure({
    this.code,
    this.summary,
    this.detail,
    this.statusCode,
    this.retryable,
    this.operationId,
  });

  factory ChatFailure.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Failure detail must be an object');
    }
    final json = value.cast<String, Object?>();
    final statusCode = json['statusCode'];
    final strings = <(String?, String?)>[
      (json['code'] as String?, 'failure code'),
      (json['summary'] as String?, 'failure summary'),
      (json['detail'] as String?, 'failure detail'),
      (json['operationId'] as String?, 'failure operation id'),
    ];
    for (final (value, label) in strings) {
      if (value != null && value.isEmpty) {
        throw FormatException('$label cannot be empty');
      }
    }
    if (statusCode != null && statusCode is! int) {
      throw const FormatException('Failure status code is invalid');
    }
    final retryable = json['retryable'];
    if (retryable != null && retryable is! bool) {
      throw const FormatException('Failure retryable flag is invalid');
    }
    return ChatFailure(
      code: json['code'] as String?,
      summary: json['summary'] as String?,
      detail: json['detail'] as String?,
      statusCode: statusCode as int?,
      retryable: retryable as bool?,
      operationId: json['operationId'] as String?,
    );
  }

  final String? code;
  final String? summary;
  final String? detail;
  final int? statusCode;
  final bool? retryable;
  final String? operationId;

  bool get hasDetail => detail?.trim().isNotEmpty == true;
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
    this.failure,
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
      failure: json['failure'] == null
          ? null
          : ChatFailure.fromJson(json['failure']),
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
  final ChatFailure? failure;

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
      failure: failure,
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
