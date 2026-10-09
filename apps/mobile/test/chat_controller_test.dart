import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/features/chat/chat_view_memory.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/models/workspace.dart';

const revision = '11111111-1111-4111-8111-111111111111';
ChatController controllerFor(
  FakeGateway api, {
  ChatViewMemory? memory,
  Duration timeout = const Duration(seconds: 15),
}) => ChatController(
  api: api,
  workspaceId: 'ts_001',
  sessionId: 'session-test',
  initialSessionRevision: revision,
  initialRuntimeState: RuntimeState.idle,
  accessMode: SessionAccessMode.controller,
  outbox: memory?.outbox,
  initialPreview: memory?.preview,
  snapshotTimeout: timeout,
);
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('Host snapshots preserve errors and real tool output', () async {
    final api = FakeGateway()
      ..snapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: revision,
        messages: [
          {'role': 'assistant', 'content': [], 'outputState': 'failed'},
          {'role': 'assistant', 'content': [], 'outputState': 'aborted'},
          {
            'role': 'toolResult',
            'toolName': 'bash',
            'content': [
              {'type': 'text', 'text': 'result'},
            ],
          },
        ],
        lastEventId: '0',
      );
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    expect(chat.messages[0].outputState, AssistantOutputState.failed);
    expect(chat.messages[1].outputState, AssistantOutputState.aborted);
    expect(chat.messages[2].tools.single.body, 'result');
    await chat.refreshMessages();
    expect(chat.messages.length, 3);
  });
  test(
    'snapshot replaces transcript and deduplicates optimistic echo',
    () async {
      final api = FakeGateway();
      final chat = controllerFor(api);
      addTearDown(chat.dispose);
      await chat.initialize();
      expect(await chat.send('hello'), isTrue);
      final id = api.sentIds.single;
      api.publish(messages: [userMessage('hello', id: id)]);
      await flush();
      expect(chat.messages.where((m) => m.text == 'hello'), hasLength(1));
      expect(chat.messages.single.deliveryState, isNull);
      expect(chat.outbox.messages, isEmpty);
      api.publish(messages: [assistantMessage('new branch history')]);
      await flush();
      expect(chat.messages.single.text, 'new branch history');
    },
  );
  test('echo before a delayed response remains canonical', () async {
    final api = FakeGateway();
    final pending = Completer<void>();
    api.nextSend = pending.future;
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    final send = chat.send('hello');
    await flush();
    api.publish(messages: [userMessage('hello', id: api.sentIds.single)]);
    await flush();
    pending.complete();
    expect(await send, isTrue);
    expect(chat.messages.single.deliveryState, isNull);
    expect(chat.outbox.messages, isEmpty);
  });
  test('uncertain retry reuses the same submission ID', () async {
    final api = FakeGateway()..sendError = TimeoutException('lost response');
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    expect(await chat.send('hello'), isFalse);
    expect(chat.outbox.uncertain('hello'), isNotNull);
    api.sendError = null;
    expect(await chat.send('hello'), isTrue);
    expect(api.sentIds, hasLength(2));
    expect(api.sentIds.toSet(), hasLength(1));
  });
  test(
    'uncertain echo in refreshed history prevents a duplicate send',
    () async {
      final api = FakeGateway()..sendError = TimeoutException('lost response');
      final chat = controllerFor(api);
      addTearDown(chat.dispose);
      await chat.initialize();
      await chat.send('hello');
      api.snapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: revision,
        messages: [userMessage('hello', id: api.sentIds.single)],
        lastEventId: '1',
      );
      expect(await chat.send('hello'), isTrue);
      expect(api.sendCalls, 1);
    },
  );
  test('matching text never confirms uncertain delivery', () async {
    final api = FakeGateway()..sendError = TimeoutException('lost response');
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    await chat.send('same');
    api.publish(messages: [userMessage('same')]);
    await flush();
    expect(chat.outbox.uncertain('same'), isNotNull);
  });
  test('definitive rejection removes optimistic message', () async {
    final api = FakeGateway()
      ..sendError = const TsPhoneApiException(
        'rejected',
        code: 'prompt_rejected',
        statusCode: 409,
      );
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    expect(await chat.send('denied'), isFalse);
    expect(chat.messages.where((m) => m.text == 'denied'), isEmpty);
    expect(chat.problem?.code, TsPhoneProblemCode.promptRejected);
  });
  test('memory preserves uncertain send across page disposal', () async {
    final memory = ChatViewMemory();
    final api = FakeGateway()..sendError = TimeoutException('lost');
    final chat = controllerFor(api, memory: memory);
    await chat.initialize();
    await chat.send('hello');
    final id = api.sentIds.single;
    chat.dispose();
    final nextApi = FakeGateway();
    final next = controllerFor(nextApi, memory: memory);
    addTearDown(next.dispose);
    await next.initialize();
    await next.send('hello');
    expect(nextApi.sentIds.single, id);
  });
  test(
    'late send response survives disposal without notifying dead page',
    () async {
      final memory = ChatViewMemory();
      final api = FakeGateway();
      final pending = Completer<void>();
      api.nextSend = pending.future;
      final chat = controllerFor(api, memory: memory);
      await chat.initialize();
      final sending = chat.send('late');
      chat.dispose();
      pending.complete();
      expect(await sending, isTrue);
      expect(
        memory.outbox.messages.single.state,
        ChatDeliveryState.synchronizing,
      );
    },
  );
  test('disconnect keeps transcript and disables sending', () async {
    final api = FakeGateway();
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    api.failEventStream();
    await flush();
    expect(chat.messages.single.text, 'existing');
    expect(chat.canSend, isFalse);
    await chat.retryConnection();
    await flush();
    expect(chat.canSend, isTrue);
    expect(api.eventConnectionCount, 2);
  });
  test('suspend and resume fences old streams and refreshes history', () async {
    final api = FakeGateway();
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    chat.suspendEventStream();
    api.publish(messages: [userMessage('ignored')]);
    await flush();
    expect(chat.messages.single.text, 'existing');
    expect(chat.canSend, isFalse);
    chat.resumeEventStream();
    await flush();
    expect(api.messageSnapshotCalls, 2);
    expect(chat.canSend, isTrue);
  });
  test(
    'snapshot timeout unblocks retry and late completion is ignored',
    () async {
      final api = FakeGateway();
      final pending = Completer<TsPhoneMessageSnapshot>();
      api.nextSnapshot = pending.future;
      final chat = controllerFor(api, timeout: const Duration(milliseconds: 5));
      addTearDown(chat.dispose);
      await chat.initialize();
      expect(chat.isSynchronizing, isFalse);
      expect(chat.canSend, isFalse);
      await chat.refreshMessages();
      pending.complete(
        TsPhoneMessageSnapshot(
          sessionId: 'session-test',
          sessionRevision: revision,
          messages: [userMessage('stale')],
          lastEventId: 'old',
        ),
      );
      await flush();
      expect(chat.messages.single.text, 'existing');
      expect(chat.canSend, isTrue);
    },
  );
  test('abort targets only the current Host turn', () async {
    final api = FakeGateway();
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    api.publish(running: true, turn: 'turn-1');
    await flush();
    expect(
      await chat.abort(
        expectedSessionRevision: revision,
        expectedAgentRunId: 'old',
      ),
      isFalse,
    );
    expect(
      await chat.abort(
        expectedSessionRevision: revision,
        expectedAgentRunId: 'turn-1',
      ),
      isTrue,
    );
    expect(api.lastAbortAgentRunId, 'turn-1');
    api.publish();
    await flush();
    expect(
      await chat.abort(
        expectedSessionRevision: revision,
        expectedAgentRunId: 'turn-1',
      ),
      isFalse,
    );
    expect(api.abortCalls, 1);
  });
  test('read-only and offline Host snapshots disable commands', () async {
    final api = FakeGateway();
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    api.publish(online: false, canPrompt: false);
    await flush();
    expect(chat.canSend, isFalse);
    expect(await chat.send('no'), isFalse);
    api.publish(canPrompt: false);
    await flush();
    expect(chat.canSend, isFalse);
  });
  test('streaming Markdown preview is bounded and throttled', () async {
    final api = FakeGateway();
    final chat = controllerFor(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    var updates = 0;
    chat.streamingTextUpdates.addListener(() => updates++);
    for (var i = 0; i < 20; i++) {
      api.publish(
        running: true,
        turn: 'turn-1',
        stream: '**hello** ${'a' * 10000} $i',
      );
    }
    await flush();
    expect(updates, 0);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(updates, 1);
    expect(chat.streamingTextUpdates.value!.length, lessThanOrEqualTo(6005));
    expect(chat.streamingText!.length, greaterThan(10000));
    api.publish(messages: [assistantMessage('complete')]);
    await flush();
    expect(chat.streamingTextUpdates.value, isNull);
  });
  test('display memory isolates drafts and protects newer edits', () {
    final memory = ConversationMemory();
    final first = memory.view('a', 'one');
    first.draft = 'old';
    final revision = first.takeDraft();
    first.draft = 'new';
    first.restoreDraft('old', revision);
    expect(first.draft, 'new');
    expect(memory.view('b', 'one').draft, isEmpty);
  });
}

class FakeGateway implements TsPhoneGateway {
  final eventsController = StreamController<TsPhoneEvent>.broadcast();
  int sequence = 0,
      eventConnectionCount = 0,
      messageSnapshotCalls = 0,
      sendCalls = 0,
      abortCalls = 0;
  String? lastAbortAgentRunId;
  final sentIds = <String>[];
  Object? sendError;
  Future<void>? nextSend;
  Future<TsPhoneMessageSnapshot>? nextSnapshot;
  TsPhoneMessageSnapshot snapshot = TsPhoneMessageSnapshot(
    sessionId: 'session-test',
    sessionRevision: revision,
    messages: [userMessage('existing')],
    lastEventId: 'epoch:0',
  );
  void publish({
    List<Object?>? messages,
    bool running = false,
    String? turn,
    String? stream,
    bool online = true,
    bool canPrompt = true,
  }) => eventsController.add(
    TsPhoneEvent(
      id: 'epoch:${++sequence}',
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      sessionRevision: revision,
      instanceEpoch: 'host',
      sessionGeneration: 1,
      type: 'session.snapshot',
      at: DateTime.now(),
      payload: {
        'messages': messages ?? snapshot.messages,
        'runtimeState': online ? (running ? 'running' : 'idle') : 'offline',
        'activeAgentRunId': turn,
        'isStreaming': running,
        'streamingMessage': stream == null ? null : assistantMessage(stream),
        'historyAvailable': true,
        'canPrompt': canPrompt,
        'capabilities': ['command.model'],
        'accessMode': canPrompt ? 'controller' : 'observer',
      },
    ),
  );
  void failEventStream() =>
      eventsController.addError(StateError('network suspended'));
  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId,
  ) {
    messageSnapshotCalls++;
    final pending = nextSnapshot;
    nextSnapshot = null;
    return pending ?? Future.value(snapshot);
  }

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) {
    eventConnectionCount++;
    onConnected?.call();
    return eventsController.stream;
  }

  @override
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    String message, {
    required String clientMessageId,
  }) async {
    sendCalls++;
    sentIds.add(clientMessageId);
    final pending = nextSend;
    nextSend = null;
    if (pending != null) await pending;
    if (sendError case final error?) throw error;
  }

  @override
  Future<void> abort(
    String workspaceId,
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  }) async {
    abortCalls++;
    lastAbortAgentRunId = agentRunId;
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => [];
  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async => [];
  @override
  Future<Map<String, Object?>> version() async => {'apiVersion': 'research-agent-host/2'};
  @override
  void close() {
    unawaited(eventsController.close());
  }
}

Map<String, Object?> userMessage(String text, {String? id}) => {
  'role': 'user',
  'content': [
    {'type': 'text', 'text': text},
  ],
  'timestamp': DateTime.now().millisecondsSinceEpoch,
  'clientMessageId': ?id,
};
Map<String, Object?> assistantMessage(String text) => {
  'role': 'assistant',
  'content': [
    {'type': 'text', 'text': text},
  ],
};
Map<String, Object?> sessionRuntimeJson({
  required String modelId,
  required int? usedTokens,
}) => <String, Object?>{
  'schemaVersion': 'ts-phone-session-runtime/1',
  'model': <String, Object?>{'provider': 'cpa', 'id': modelId},
  'context': <String, Object?>{
    'usedTokens': usedTokens,
    'limitTokens': 128000,
    'measurement': 'pi_estimate',
  },
  'updatedAt': '2026-08-31T06:32:18.000Z',
};
