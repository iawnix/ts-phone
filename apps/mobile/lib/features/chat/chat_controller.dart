import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/corhub_api.dart';
import '../../models/chat_message.dart';
import '../../models/workspace.dart';
import '../../models/phone_model.dart';
import 'chat_view_memory.dart';
import 'chat_outbox.dart';

enum EventConnectionState {
  connecting,
  connected,
  reconnecting,
  suspended,
  failed,
  closed,
}

class ChatController extends ChangeNotifier {
  ChatController({
    required this.api,
    required this.workspaceId,
    required this.sessionId,
    required String initialSessionRevision,
    required RuntimeState initialRuntimeState,
    required this.accessMode,
    String? initialSessionTitle,
    SessionRuntimeSnapshot? initialSessionRuntime,
    String? initialPromptProblem,
    String? initialActiveAgentRunId,
    bool initialHistoryAvailable = false,
    bool? initialCanPrompt,
    Set<String> initialCapabilities = const <String>{},
    this.recoveredSession = false,
    this.eventErrorDelay = const Duration(seconds: 5),
    this.snapshotTimeout = const Duration(seconds: 15),
    this.streamRenderInterval = const Duration(milliseconds: 100),
    this.streamPreviewCharacterLimit = 6000,
    this.clientMessageIdFactory = createCorHubClientMessageId,
    ChatHistoryPreview? initialPreview,
    SessionSummary? initialSession,
    ChatOutbox? outbox,
  }) : assert(streamPreviewCharacterLimit > 0),
       assert(!snapshotTimeout.isNegative && snapshotTimeout != Duration.zero),
       outbox = outbox ?? ChatOutbox(),
       _runtimeState = initialRuntimeState,
       _historyAvailable = initialHistoryAvailable,
       _canPrompt = initialCanPrompt ?? initialRuntimeState.isAvailable,
       _capabilities = Set<String>.unmodifiable(initialCapabilities),
       _sessionRevision = initialSessionRevision,
       _sessionTitle = initialSessionTitle,
       _sessionRuntime = initialSessionRuntime,
       _promptProblem = initialPromptProblem,
       _activeAgentRunId = initialActiveAgentRunId {
    if (initialSession != null) _applySessionSummary(initialSession);
    if (initialPreview != null && initialPreview.revision == _sessionRevision) {
      _setMessages(initialPreview.messages, initialPreview.messageIds);
    }
    this.outbox.addListener(_syncOutbox);
    _syncOutbox();
  }

  final CorHubGateway api;
  final ChatOutbox outbox;
  final String workspaceId;
  final String sessionId;
  SessionAccessMode accessMode;
  final bool recoveredSession;
  final Duration eventErrorDelay;
  final Duration snapshotTimeout;
  final Duration streamRenderInterval;
  final int streamPreviewCharacterLimit;
  final String Function() clientMessageIdFactory;
  final ValueNotifier<List<ChatMessage>> _messagesUpdates =
      ValueNotifier<List<ChatMessage>>(const <ChatMessage>[]);
  final ValueNotifier<String?> _streamingTextUpdates = ValueNotifier(null);
  String? _lastMessageSnapshot;
  List<ChatMessage> _messages = const <ChatMessage>[];
  List<String?> _messageIds = const <String?>[];
  Set<String> _capabilities;
  RuntimeState _runtimeState;
  EventConnectionState _eventConnectionState = EventConnectionState.connecting;
  List<String>? _streamingTextChunks;
  int _streamingTextLength = 0;
  CorHubProblem? _operationProblem;
  CorHubProblem? _eventProblem;
  String? _promptProblem;
  String? _lastEventId;
  String _sessionRevision;
  String? _sessionTitle;
  String? _sessionModel;
  SessionRuntimeSnapshot? _sessionRuntime;
  String? _activeAgentRunId;
  bool _historyAvailable;
  bool _canPrompt;
  bool _commandInFlight = false;
  bool _eventStreamEnabled = true;
  bool _snapshotReady = false;
  bool _disposed = false;
  bool _sendingRequest = false;
  StreamSubscription<CorHubEvent>? _eventSubscription;
  Future<void>? _eventCancellation;
  Future<void>? _snapshotSynchronization;
  bool _connectAfterCancellationScheduled = false;
  bool _snapshotSyncInProgress = false;
  Timer? _reconnectTimer;
  Timer? _eventErrorTimer;
  Timer? _streamRenderTimer;
  Timer? _snapshotTimeoutTimer;
  int _eventGeneration = 0;
  int _retrySeconds = 1;

  UnmodifiableListView<ChatMessage> get messages =>
      UnmodifiableListView(_messages);
  ValueListenable<List<ChatMessage>> get messagesUpdates => _messagesUpdates;
  RuntimeState get runtimeState => _runtimeState;
  EventConnectionState get eventConnectionState => _eventConnectionState;
  String? get streamingText => _streamingTextChunks?.join();
  bool get hasStreamingText => _streamingTextChunks != null;
  ValueListenable<String?> get streamingTextUpdates => _streamingTextUpdates;
  bool get hasFailedOutput => _messages.any(
    (message) => message.outputState == AssistantOutputState.failed,
  );
  CorHubProblem? get problem =>
      _operationProblem ??
      (_promptProblem == null
          ? null
          : describeCorHubProblem(
              CorHubApiException('Model not ready', code: _promptProblem),
            )) ??
      (outbox.messages.any(
            (value) => value.state == ChatDeliveryState.uncertain,
          )
          ? const CorHubProblem(
              CorHubProblemKind.request,
              CorHubProblemCode.deliveryUncertain,
            )
          : null) ??
      _eventProblem;
  bool get isSynchronizing => _snapshotSyncInProgress;

  /// A dropped event stream is retried in the background. Keep this separate
  /// from actionable request failures so the chat can stay readable while the
  /// connection indicator communicates the transient state in the app bar.
  bool get hasTransientEventProblem =>
      _eventConnectionState == EventConnectionState.reconnecting &&
      _eventProblem?.code == CorHubProblemCode.networkRetrying;
  String? get sessionTitle => _sessionTitle;
  SessionRuntimeSnapshot? get sessionRuntime => _sessionRuntime;
  String get sessionRevision => _sessionRevision;
  String? get activeAgentRunId => _activeAgentRunId;
  bool get commandInFlight => _commandInFlight || outbox.isSending;
  bool get historyAvailable => _historyAvailable;
  bool get historyOnly =>
      _runtimeState == RuntimeState.offline && _historyAvailable && !_canPrompt;
  bool get _promptStateReady =>
      _canPrompt &&
      _promptProblem == null &&
      _runtimeState.isAvailable &&
      _snapshotReady &&
      !_snapshotSyncInProgress;
  bool get canSend =>
      _promptStateReady &&
      _eventConnectionState == EventConnectionState.connected;

  CorHubModelGateway? get modelGateway =>
      api is CorHubModelGateway ? api as CorHubModelGateway : null;
  String? get selectedModelReference {
    final model = _sessionRuntime?.model;
    final current = model == null ? null : '${model.provider}/${model.id}';
    return current ?? _sessionModel;
  }

  bool get canSelectModel =>
      modelGateway != null &&
      !_snapshotSyncInProgress &&
      !commandInFlight &&
      outbox.messages.isEmpty &&
      _activeAgentRunId == null &&
      _runtimeState == RuntimeState.idle &&
      _capabilities.contains('command.model') &&
      _snapshotReady &&
      _eventConnectionState == EventConnectionState.connected;

  bool get canRefresh => _historyAvailable || _runtimeState.isAvailable;
  Future<void> selectModel(PhoneModel model) async {
    if (!canSelectModel) {
      throw const CorHubApiException(
        'Session is not ready for model selection',
        code: 'session_not_ready',
      );
    }
    final revision = _sessionRevision;
    _commandInFlight = true;
    _notify();
    try {
      final session = await modelGateway!.selectModel(
        workspaceId,
        sessionId,
        revision,
        model,
      );
      if (_disposed) return;
      if (_sessionRevision != revision ||
          session.sessionId != sessionId ||
          session.sessionRevision != revision) {
        throw const CorHubApiException(
          'Session changed',
          code: 'session_resync_required',
        );
      }
      _sessionRuntime = session.runtime;
      _promptProblem = session.promptProblem;
      _canPrompt = session.canPrompt;
      _capabilities = session.capabilities;
      _applySessionSummary(session);
      _operationProblem = null;
    } on Object {
      if (!_disposed) {
        _snapshotReady = false;
        _canPrompt = false;
        await _refreshMessages(allowUnavailable: true);
      }
      rethrow;
    } finally {
      _commandInFlight = false;
      _notify();
    }
  }

  String messageKeyAt(int index) =>
      _messageIds[index] ??
      '${_messages[index].role.name}-${_messages[index].timestamp?.microsecondsSinceEpoch ?? 0}-$index';

  Future<void> initialize() async {
    if (canRefresh) {
      await refreshMessages();
    } else {
      _connectEventStream();
    }
  }

  ChatHistoryPreview get historyPreview => ChatHistoryPreview(
    revision: _sessionRevision,
    messages: _messages,
    messageIds: _messageIds,
  );
  Future<void> refreshMessages() => _refreshMessages();
  Future<SessionSummary> refreshSessionMetadata() async {
    final sessions = await api.listSessions(workspaceId);
    final session = sessions
        .where((value) => value.sessionId == sessionId)
        .firstOrNull;
    if (session == null) {
      throw const CorHubApiException(
        'Conversation is no longer available',
        statusCode: 404,
        code: 'session_not_found',
      );
    }
    if (!_disposed) {
      _applySessionSummary(session);
      _notify();
    }
    return session;
  }

  void _applySessionSummary(SessionSummary session) {
    if (session.model != null) _sessionModel = session.model;
    if (session.sessionName?.isNotEmpty == true) {
      _sessionTitle = session.sessionName;
    }
    _capabilities = session.capabilities;
  }

  Future<void> _refreshMessages({
    bool allowUnavailable = false,
    bool resetView = false,
  }) {
    final existing = _snapshotSynchronization;
    if (existing != null) {
      return resetView
          ? existing.then(
              (_) => _refreshMessages(
                allowUnavailable: allowUnavailable,
                resetView: true,
              ),
            )
          : existing;
    }
    if ((!allowUnavailable && !canRefresh) || _disposed) {
      return Future<void>.value();
    }
    late final Future<void> tracked;
    tracked = _synchronizeMessages(resetView: resetView).whenComplete(() {
      if (identical(_snapshotSynchronization, tracked)) {
        _snapshotSynchronization = null;
      }
    });
    _snapshotSynchronization = tracked;
    return tracked;
  }

  Future<void> _synchronizeMessages({bool resetView = false}) async {
    final hadCachedSnapshot =
        _messages.isNotEmpty || outbox.messages.isNotEmpty;
    _cancelStreamRender();
    _snapshotSyncInProgress = true;
    _snapshotReady = false;
    _eventGeneration += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _eventErrorTimer?.cancel();
    _eventErrorTimer = null;
    _eventProblem = null;
    _eventConnectionState = _lastEventId == null
        ? EventConnectionState.connecting
        : EventConnectionState.reconnecting;
    _notify();
    try {
      // Event generations fence late data; reading history must not wait for
      // an idle network stream to close. Reconnection still waits for cleanup.
      _cancelEventSubscription();
      final snapshot = await _awaitSnapshot(
        api.getMessages(workspaceId, sessionId),
      );
      if (_disposed) return;
      if (snapshot.sessionId != sessionId) {
        throw const FormatException('Snapshot belongs to another session');
      }
      _applySnapshotAgentRun(snapshot.activeAgentRunId);
      _sessionRevision = snapshot.sessionRevision;
      _applyMessageSnapshot(snapshot);
      _lastEventId = snapshot.lastEventId;
      _snapshotReady = true;
      _clearStreamingText();
      _operationProblem = null;
      _notify();
    } on Object catch (error) {
      if (!_disposed) {
        // A cached transcript remains useful while the relay is recovering.
        // Keep the failure in the status channel so the chat does not flash an
        // error page for a transient snapshot request failure.
        if (hadCachedSnapshot && _isTransientTransportError(error)) {
          _operationProblem = describeCorHubProblem(error);
          _eventConnectionState = EventConnectionState.reconnecting;
          _armEventError(error);
        } else {
          _setError(error);
        }
      }
    } finally {
      _snapshotSyncInProgress = false;
      if (!_disposed) {
        _syncOutbox();
        if (_eventStreamEnabled) _connectEventStream();
      }
    }
  }

  Future<T> _awaitSnapshot<T>(Future<T> operation) {
    final result = Completer<T>();
    final timer = Timer(snapshotTimeout, () {
      if (!result.isCompleted) {
        result.completeError(
          TimeoutException('Session synchronization timed out'),
        );
      }
    });
    _snapshotTimeoutTimer = timer;
    operation.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!result.isCompleted) result.completeError(error, stackTrace);
      },
    );
    return result.future.whenComplete(() {
      timer.cancel();
      if (identical(_snapshotTimeoutTimer, timer)) {
        _snapshotTimeoutTimer = null;
      }
    });
  }

  Future<bool> send(String value) async {
    final message = value.trim();
    if (message.isEmpty || commandInFlight || !canSend) return false;
    if (!_promptStateReady) return false;
    final revision = _sessionRevision;
    final retry = outbox.uncertain(message);
    if (retry != null) {
      if (retry.revision != revision) {
        _setError(
          const CorHubApiException(
            'Session changed',
            code: 'session_changed',
            statusCode: 409,
          ),
        );
        return false;
      }
      await refreshMessages();
      // Reconcile against Host history before retrying the same outbox ID.
      if (_disposed || !_promptStateReady) return false;
      if (outbox.accepted(retry)) return true;
      if (_sessionRevision != revision) return false;
    }
    final outgoing =
        retry ??
        OutgoingChatMessage(
          revision: revision,
          id: clientMessageIdFactory(),
          text: message,
        );
    final clientMessageId = outgoing.id;
    _commandInFlight = true;
    _sendingRequest = true;
    _operationProblem = null;
    outbox.begin(outgoing);
    _notify();
    try {
      await api.sendMessage(
        workspaceId,
        sessionId,
        revision,
        message,
        clientMessageId: clientMessageId,
      );
      outbox.finish(outgoing, sent: true);
      if (_disposed) return true;
      if (!outbox.accepted(outgoing)) {
        _updateOutgoingDelivery(
          clientMessageId,
          ChatDeliveryState.synchronizing,
        );
      }
      return true;
    } on Object catch (error) {
      if (outbox.accepted(outgoing)) {
        outbox.finish(outgoing, sent: true);
        return true;
      }
      final definitive =
          error is CorHubApiException &&
          !const {
            'command_ambiguous',
            'connection_closed',
          }.contains(error.code) &&
          (const {
                'model_unavailable',
                'model_auth_missing',
                'model_storage_unavailable',
                'model_check_failed',
                'prompt_rejected',
              }.contains(error.code) ||
              error.statusCode != null &&
                  error.statusCode! >= 400 &&
                  error.statusCode! < 500);
      outbox.finish(outgoing, sent: false, uncertain: !definitive);
      if (_disposed) return false;
      if (!definitive) {
        _updateOutgoingDelivery(clientMessageId, ChatDeliveryState.uncertain);
        return false;
      }
      _removePendingOutgoing(clientMessageId, includeReceived: true);
      _setError(error);
      return false;
    } finally {
      _sendingRequest = false;
      _commandInFlight = false;
      if (_disposed) api.close();
      _notify();
    }
  }

  void _syncOutbox() {
    if (_disposed) return;
    if (_snapshotSyncInProgress) {
      _notify();
      return;
    }
    final pending = outbox.messages
        .where((value) => value.revision == _sessionRevision)
        .toList();
    final ids = pending.map((value) => value.id).toSet();
    for (final message in _messages.toList()) {
      final id = message.clientMessageId;
      if (id != null && message.deliveryState != null && !ids.contains(id)) {
        _removePendingOutgoing(id);
      }
    }
    for (final message in pending) {
      if (_messages.any((value) => value.clientMessageId == message.id)) {
        _updateOutgoingDelivery(message.id, message.state);
      } else {
        _appendLiveMessage(
          ChatMessage(
            role: ChatRole.user,
            text: message.text,
            timestamp: message.at,
            clientMessageId: message.id,
            origin: 'phone',
            deliveryState: message.state,
          ),
          localId: 'phone-${message.id}',
        );
      }
    }
    _notify();
  }

  Future<bool> abort({
    required String expectedSessionRevision,
    required String expectedAgentRunId,
  }) async {
    if (_commandInFlight ||
        !canSend ||
        _runtimeState != RuntimeState.running ||
        _sessionRevision != expectedSessionRevision ||
        _activeAgentRunId != expectedAgentRunId) {
      return false;
    }
    _commandInFlight = true;
    _operationProblem = null;
    _notify();
    try {
      await api.abort(
        workspaceId,
        sessionId,
        sessionRevision: expectedSessionRevision,
        agentRunId: expectedAgentRunId,
      );
      return true;
    } on Object catch (error) {
      final problem = describeCorHubProblem(error);
      if (problem.code == CorHubProblemCode.agentRunChanged) {
        // The App Server has authoritative evidence that this run is no longer
        // active. Retire the stale local identity before reconciling the
        // replacement (or idle state) from a fresh transcript snapshot.
        _activeAgentRunId = null;
        if (_runtimeState.isAvailable) _runtimeState = RuntimeState.idle;
        _operationProblem = null;
        await _refreshMessages(allowUnavailable: true);
      } else {
        _operationProblem = problem;
        _notify();
      }
      return false;
    } finally {
      _commandInFlight = false;
      _notify();
    }
  }

  void suspendEventStream() {
    if (_disposed || !_eventStreamEnabled) return;
    _eventStreamEnabled = false;
    _eventGeneration += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _eventErrorTimer?.cancel();
    _eventErrorTimer = null;
    _cancelStreamRender();
    _eventProblem = null;
    _cancelEventSubscription();
    _eventConnectionState = EventConnectionState.suspended;
    _notify();
  }

  void resumeEventStream() {
    if (_disposed || _eventStreamEnabled) return;
    _eventStreamEnabled = true;
    _retrySeconds = 1;
    _eventProblem = null;
    if (canRefresh) {
      unawaited(refreshMessages());
    } else {
      _connectEventStream();
    }
  }

  Future<void> retryConnection() async {
    if (_disposed || _snapshotSyncInProgress) return;
    _eventStreamEnabled = true;
    _retrySeconds = 1;
    _eventGeneration += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _eventErrorTimer?.cancel();
    _eventErrorTimer = null;
    _cancelStreamRender();
    _operationProblem = null;
    _eventProblem = null;
    _eventConnectionState = EventConnectionState.connecting;
    _notify();
    await _cancelEventSubscriptionAndWait();
    if (!_disposed) _connectEventStream();
  }

  void _connectEventStream() {
    if (_disposed ||
        !_eventStreamEnabled ||
        _snapshotSyncInProgress ||
        _eventSubscription != null) {
      return;
    }
    final cancellation = _eventCancellation;
    if (cancellation != null) {
      if (_connectAfterCancellationScheduled) return;
      _connectAfterCancellationScheduled = true;
      unawaited(
        cancellation.whenComplete(() {
          if (_eventCancellation == cancellation) _eventCancellation = null;
          _connectAfterCancellationScheduled = false;
          _connectEventStream();
        }),
      );
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final generation = ++_eventGeneration;
    _eventConnectionState = _lastEventId == null
        ? EventConnectionState.connecting
        : EventConnectionState.reconnecting;
    _notify();

    try {
      _eventSubscription = api
          .events(
            workspaceId,
            sessionId,
            lastEventId: _lastEventId,
            onConnected: () => _eventStreamOpened(generation),
          )
          .listen(
            (event) => _receiveEvent(generation, event),
            onError: (Object error, StackTrace stackTrace) {
              _finishEventStream(generation, error);
            },
            onDone: () {
              _finishEventStream(generation, StateError('Event stream closed'));
            },
            cancelOnError: true,
          );
    } on Object catch (error) {
      _finishEventStream(generation, error);
    }
  }

  void _eventStreamOpened(int generation) {
    if (!_isCurrentEventStream(generation)) return;
    _retrySeconds = 1;
    _eventErrorTimer?.cancel();
    _eventErrorTimer = null;
    _eventProblem = null;
    _eventConnectionState = EventConnectionState.connected;
    _notify();
  }

  void _receiveEvent(int generation, CorHubEvent event) {
    if (!_isCurrentEventStream(generation)) return;
    if (event.workspaceId != workspaceId || event.sessionId != sessionId) {
      _finishEventStream(
        generation,
        const FormatException('Event belongs to another session'),
      );
      return;
    }
    if (event.sessionRevision != _sessionRevision) {
      _resynchronizeChangedSession(generation, event.sessionRevision);
      return;
    }
    _lastEventId = event.id;
    _eventConnectionState = EventConnectionState.connected;
    _eventProblem = null;
    try {
      _handleEvent(event);
    } on Object catch (error) {
      _finishEventStream(generation, error);
    }
  }

  void _resynchronizeChangedSession(int generation, String revision) {
    if (!_isCurrentEventStream(generation)) return;
    _sessionRevision = revision;
    _lastEventId = null;
    _snapshotReady = false;
    _activeAgentRunId = null;
    _setRuntimeState(RuntimeState.connecting);
    _canPrompt = false;
    _clearStreamingText();
    _eventGeneration += 1;
    _cancelEventSubscription();
    _eventConnectionState = EventConnectionState.reconnecting;
    _notify();
    unawaited(_refreshMessages(allowUnavailable: true));
  }

  void _finishEventStream(int generation, Object error) {
    if (_disposed || generation != _eventGeneration) return;
    _cancelStreamRender();
    _eventGeneration += 1;
    _cancelEventSubscription();

    if (!_eventStreamEnabled) {
      _eventConnectionState = EventConnectionState.suspended;
      _notify();
      return;
    }
    if (_isFatalEventError(error)) {
      _eventErrorTimer?.cancel();
      _eventErrorTimer = null;
      _eventProblem = describeCorHubProblem(error);
      _eventConnectionState = EventConnectionState.failed;
      _notify();
      return;
    }

    _eventConnectionState = EventConnectionState.reconnecting;
    _armEventError(error);
    _notify();
    final delay = Duration(seconds: _retrySeconds);
    _retrySeconds = (_retrySeconds * 2).clamp(1, 15);
    _reconnectTimer = Timer(delay, _connectEventStream);
  }

  void _armEventError(Object error) {
    if (_eventErrorTimer != null) return;
    _eventErrorTimer = Timer(eventErrorDelay, () {
      _eventErrorTimer = null;
      if (_disposed ||
          !_eventStreamEnabled ||
          _eventConnectionState != EventConnectionState.reconnecting) {
        return;
      }
      _eventProblem = const CorHubProblem(
        CorHubProblemKind.unavailable,
        CorHubProblemCode.networkRetrying,
      );
      _notify();
    });
  }

  bool _isCurrentEventStream(int generation) =>
      !_disposed && _eventStreamEnabled && generation == _eventGeneration;

  void _cancelEventSubscription() {
    final subscription = _eventSubscription;
    _eventSubscription = null;
    if (subscription == null) return;
    _eventCancellation = subscription.cancel().then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            context: ErrorDescription('while closing the CoRHub event stream'),
          ),
        );
      },
    );
  }

  Future<void> _cancelEventSubscriptionAndWait() async {
    _cancelEventSubscription();
    final cancellation = _eventCancellation;
    if (cancellation == null) return;
    await cancellation;
    if (identical(_eventCancellation, cancellation)) {
      _eventCancellation = null;
    }
  }

  bool _isFatalEventError(Object error) {
    if (error is FormatException) return true;
    if (error is! CorHubApiException) return false;
    return switch (error.statusCode) {
      400 || 401 || 403 || 404 => true,
      _ => false,
    };
  }

  static bool _isTransientTransportError(Object error) {
    final problem = describeCorHubProblem(error);
    return const {
      CorHubProblemCode.connectionFailed,
      CorHubProblemCode.requestTimeout,
      CorHubProblemCode.serviceUnavailable,
      CorHubProblemCode.sessionOffline,
      CorHubProblemCode.networkRetrying,
    }.contains(problem.code);
  }

  void _handleEvent(CorHubEvent event) {
    if (event.type != 'session.snapshot') return;
    final payload = _asMap(event.payload);
    if (payload == null || payload['messages'] is! List) {
      throw const FormatException('Invalid Host snapshot');
    }
    _operationProblem = null;
    _promptProblem = payload['promptProblem'] as String?;
    _applyMessageSnapshot(
      CorHubMessageSnapshot(
        sessionId: sessionId,
        sessionRevision: _sessionRevision,
        messages: (payload['messages'] as List).cast<Object?>(),
        lastEventId: event.id,
      ),
    );
    if (payload['sessionName'] is String) {
      _sessionTitle = payload['sessionName'] as String;
    }
    if (payload['model'] is String) _sessionModel = payload['model'] as String;
    _applyRunState(
      RuntimeState.parse(payload['runtimeState']),
      payload['activeAgentRunId'],
      source: 'session.snapshot',
    );
    if (payload['isStreaming'] == true && payload['streamingMessage'] is Map) {
      final message = ChatMessage.fromJson(payload['streamingMessage']);
      _replaceStreamingText(message.text);
      _scheduleStreamRender();
    } else {
      _clearStreamingText();
    }
    _historyAvailable = payload['historyAvailable'] == true;
    _updateCapabilities(payload['capabilities']);
    _updateAccessMode(payload['accessMode']);
    _updateSessionRuntime(payload['runtime']);
    _canPrompt = payload['canPrompt'] == true;
    _applyRuntimeError(payload['runtimeError']);
    _snapshotReady = true;
    _notify();
  }

  void _applyMessageSnapshot(CorHubMessageSnapshot snapshot) {
    final identity = jsonEncode([
      snapshot.sessionRevision,
      snapshot.messages,
      snapshot.messageIds,
    ]);
    if (_lastMessageSnapshot == identity) return;
    final messages = snapshot.messages.map(ChatMessage.fromJson).toList();
    _lastMessageSnapshot = identity;
    outbox.reconcile(snapshot.sessionRevision, messages);
    _setMessages(
      messages,
      List.generate(
        messages.length,
        (i) => snapshot.messageIds != null && i < snapshot.messageIds!.length
            ? snapshot.messageIds![i]
            : null,
      ),
    );
    _syncOutbox();
  }

  void _appendLiveMessage(ChatMessage message, {String? localId}) {
    _setMessages([..._messages, message], [..._messageIds, localId]);
  }

  void _updateOutgoingDelivery(String id, ChatDeliveryState state) {
    _setMessages(
      _messages
          .map(
            (m) =>
                m.clientMessageId == id ? m.copyWith(deliveryState: state) : m,
          )
          .toList(),
      _messageIds,
    );
  }

  void _removePendingOutgoing(String id, {bool includeReceived = false}) {
    final indices = [
      for (var i = 0; i < _messages.length; i++)
        if (!(_messages[i].clientMessageId == id &&
            (includeReceived || _messages[i].deliveryState != null)))
          i,
    ];
    _setMessages(
      [for (final i in indices) _messages[i]],
      [for (final i in indices) _messageIds[i]],
    );
  }

  void _updateSessionRuntime(Object? value) {
    if (value == null) return;
    try {
      if (value is! Map) {
        throw const FormatException('Session runtime event is invalid');
      }
      _sessionRuntime = SessionRuntimeSnapshot.fromJson(
        Map<String, Object?>.from(value),
      );
    } on FormatException {
      _operationProblem = const CorHubProblem(
        CorHubProblemKind.incompatible,
        CorHubProblemCode.invalidHistoryMessage,
      );
    }
  }

  void _setRuntimeState(RuntimeState nextState) {
    _runtimeState = nextState;
    if (nextState != RuntimeState.running) _activeAgentRunId = null;
  }

  void _applySnapshotAgentRun(String? agentRunId) {
    _activeAgentRunId = agentRunId;
    if (agentRunId != null) {
      _runtimeState = RuntimeState.running;
    } else if (_runtimeState.isAvailable) {
      _runtimeState = RuntimeState.idle;
    }
  }

  void _applyRunState(
    RuntimeState nextState,
    Object? rawAgentRunId, {
    required String source,
  }) {
    if (nextState == RuntimeState.running) {
      _activeAgentRunId = _requireAgentRunId(rawAgentRunId, source);
    } else {
      if (rawAgentRunId != null) {
        throw FormatException('$source exposed an agent run while idle');
      }
      _activeAgentRunId = null;
    }
    _runtimeState = nextState;
  }

  static String _requireAgentRunId(Object? value, String source) {
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(value)) {
      throw FormatException('$source did not include a valid agentRunId');
    }
    return value;
  }

  void _scheduleStreamRender() {
    if (_streamRenderTimer != null || _disposed) return;
    _streamRenderTimer = Timer(streamRenderInterval, () {
      _streamRenderTimer = null;
      _publishStreamingText();
    });
  }

  void _updateAccessMode(Object? value) {
    if (value == null) return;
    try {
      accessMode = SessionAccessMode.parse(value);
    } on FormatException {
      _operationProblem = const CorHubProblem(
        CorHubProblemKind.incompatible,
        CorHubProblemCode.incompatible,
      );
    }
  }

  void _updateCapabilities(Object? value) {
    if (value == null) return;
    if (value is! List || value.any((item) => item is! String)) {
      _operationProblem = const CorHubProblem(
        CorHubProblemKind.incompatible,
        CorHubProblemCode.incompatible,
      );
      return;
    }
    _capabilities = Set<String>.unmodifiable(value.cast<String>());
  }

  bool _replaceStreamingText(String text) {
    final started = _streamingTextChunks == null;
    _streamingTextChunks = <String>[text];
    _streamingTextLength = text.length;
    return started;
  }

  void _publishStreamingText() {
    if (_disposed || _streamingTextChunks == null) return;
    _streamingTextUpdates.value = _buildStreamingPreview();
  }

  String _buildStreamingPreview() {
    final chunks = _streamingTextChunks!;
    if (_streamingTextLength <= streamPreviewCharacterLimit) {
      return chunks.join();
    }

    var remaining = streamPreviewCharacterLimit;
    final tailChunks = <String>[];
    for (var index = chunks.length - 1; index >= 0 && remaining > 0; index--) {
      final chunk = chunks[index];
      if (chunk.length <= remaining) {
        tailChunks.add(chunk);
        remaining -= chunk.length;
        continue;
      }

      var start = chunk.length - remaining;
      if (start > 0 &&
          start < chunk.length &&
          _isLowSurrogate(chunk.codeUnitAt(start)) &&
          _isHighSurrogate(chunk.codeUnitAt(start - 1))) {
        start += 1;
      }
      tailChunks.add(chunk.substring(start));
      remaining = 0;
    }
    return '...\n\n${tailChunks.reversed.join()}';
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  void _clearStreamingText() {
    _cancelStreamRender();
    _streamingTextChunks = null;
    _streamingTextLength = 0;
    _streamingTextUpdates.value = null;
  }

  void _cancelStreamRender() {
    _streamRenderTimer?.cancel();
    _streamRenderTimer = null;
  }

  void _setMessages(List<ChatMessage> messages, List<String?> messageIds) {
    if (messages.length != messageIds.length) {
      throw StateError('Message ids must align with messages');
    }
    _messages = List<ChatMessage>.unmodifiable(messages);
    _messageIds = List<String?>.unmodifiable(messageIds);
    _messagesUpdates.value = _messages;
  }

  void _setError(Object error) {
    _operationProblem = describeCorHubProblem(error);
    _notify();
  }

  void _applyRuntimeError(Object? value) {
    final error = _asMap(value);
    if (error == null) return;
    final code = error['code'] is String ? error['code']! as String : null;
    final statusCode = error['statusCode'] is int
        ? error['statusCode']! as int
        : null;
    final message = error['message'] is String
        ? error['message']! as String
        : error['summary'] is String
        ? error['summary']! as String
        : 'Pi runtime error';
    _operationProblem = describeCorHubProblem(
      CorHubApiException(message, code: code, statusCode: statusCode),
    );
  }

  static Map<String, Object?>? _asMap(Object? value) {
    if (value is! Map) return null;
    return value.cast<String, Object?>();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    outbox.removeListener(_syncOutbox);
    _disposed = true;
    _eventStreamEnabled = false;
    _eventGeneration += 1;
    _eventConnectionState = EventConnectionState.closed;
    _reconnectTimer?.cancel();
    _eventErrorTimer?.cancel();
    _snapshotTimeoutTimer?.cancel();
    _snapshotTimeoutTimer = null;
    _cancelStreamRender();
    _cancelEventSubscription();
    if (!_sendingRequest) api.close();
    _messagesUpdates.dispose();
    _streamingTextUpdates.dispose();
    super.dispose();
  }
}
