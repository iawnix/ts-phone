import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/models/chat_message.dart';

void main() {
  test(
    'output outcomes survive local display copies without exposing reasoning',
    () {
      final message = ChatMessage.fromJson({
        'role': 'assistant',
        'content': [],
        'outputState': 'failed',
      });
      expect(message.hasInterruptedOutput, isTrue);
      expect(message.copyWith().outputState, AssistantOutputState.failed);
      expect(message.isActivityOnly, isTrue);
    },
  );

  test('extracts Markdown and tool calls from assistant messages', () {
    final message = ChatMessage.fromJson(<String, Object?>{
      'role': 'assistant',
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': '**done**'},
        <String, Object?>{
          'type': 'toolCall',
          'name': 'ts_workspace',
          'arguments': <String, Object?>{'action': 'report'},
        },
        <String, Object?>{'type': 'thinking', 'thinking': 'private'},
      ],
      'timestamp': 1000,
    });

    expect(message.role, ChatRole.assistant);
    expect(message.text, '**done**');
    expect(message.text, isNot(contains('private')));
    expect(message.tools.single.title, 'ts_workspace');
    expect(message.tools.single.body, contains('report'));
  });

  test('keeps tool errors separate from chat Markdown', () {
    final message = ChatMessage.fromJson(<String, Object?>{
      'role': 'toolResult',
      'toolName': 'compute',
      'isError': true,
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': 'failed'},
      ],
    });

    expect(message.text, isEmpty);
    expect(message.tools.single.isError, isTrue);
    expect(message.tools.single.body, 'failed');
  });

  test('rejects malformed optional delivery metadata', () {
    expect(
      () => ChatMessage.fromJson(<String, Object?>{
        'role': 'user',
        'content': 'hello',
        'clientMessageId': 42,
      }),
      throwsFormatException,
    );
  });
}
