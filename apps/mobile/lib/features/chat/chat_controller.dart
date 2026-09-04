import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../data/ts_phone_api.dart';
import '../../models/chat_message.dart';
import '../../models/session_timeline.dart';
import '../../models/workspace.dart';

enum EventConnectionState {
  connecting,
  connected,
  reconnecting,
  suspended,
  failed,
  closed,
}

class ExtensionUiRequest {
  const ExtensionUiRequest({
    required this.id,
    required this.toolName,
    required this.preview,
    required this.expiresAt,
    required this.sessionRevision,
    this.turnId,
    this.toolCallId,
  });

  factory ExtensionUiRequest.fromJson(
    Map<String, Object?> json, {
    required String sessionRevision,
  }) {
    final id = json['id'];
    final method = json['method'];
    final preview = json['preview'] ?? json['message'];
    final toolName = json['toolName'];
    final expiresAt = json['expiresAt'];
    final turnId = json['turnId'];
    final toolCallId = json['toolCallId'];
    if (id is! String ||
        method != 'confirm' ||
        preview is! String ||
        toolName is! String ||
        expiresAt is! String ||
        (turnId != null && turnId is! String) ||
        (toolCallId != null && toolCallId is! String)) {
      throw const FormatException('Approval request is invalid');
    }
    return ExtensionUiRequest(
      id: id,
      toolName: toolName,
      preview: preview,
      expiresAt: DateTime.parse(expiresAt),
      sessionRevision: sessionRevision,
      turnId: turnId as String?,
      toolCallId: toolCallId as String?,
    );
  }

  final String id;
  final String toolName;
  final String preview;
  final DateTime expiresAt;
  final String sessionRevision;
  final String? turnId;
  final String? toolCallId;

  String get identity => '$sessionRevision\u0000$id';
}

enum ChatActivityKind { runningTool, toolFailed }

const int _historyPageSize = 200;
const int _timelinePageSize = 500;
const int _automaticTimelineItemLimit = 2000;

class ChatActivity {
  const ChatActivity(this.kind, {this.toolName, this.startedAt});

  final ChatActivityKind kind;
  final String? toolName;
  final DateTime? startedAt;

  Duration? get elapsed {
    final started = startedAt;
    if (started == null) return null;
    final value = DateTime.now().difference(started);
    return value.isNegative ? Duration.zero : value;
  }
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
    bool initialHistoryAvailable = false,
    bool? initialCanPrompt,
    Set<String> initialCapabilities = const <String>{},
    this.recoveredSession = false,
    this.eventErrorDelay = const Duration(seconds: 5),
    this.snapshotTimeout = const Duration(seconds: 15),
    this.streamRenderInterval = const Duration(milliseconds: 100),
    this.streamPreviewCharacterLimit = 6000,
    this.clientMessageIdFactory = createTsPhoneClientMessageId,
  }) : assert(streamPreviewCharacterLimit > 0),
       assert(!snapshotTimeout.isNegative && snapshotTimeout != Duration.zero),
       _runtimeState = initialRuntimeState,
       _historyAvailable = initialHistoryAvailable,
       _canPrompt = initialCanPrompt ?? initialRuntimeState.isAvailable,
       _capabilities = Set<String>.unmodifiable(initialCapabilities),
       _sessionRevision = initialSessionRevision,
       _sessionTitle = initialSessionTitle,
       _sessionRuntime = initialSessionRuntime;

  final TsPhoneGateway api;
  final String workspaceId;
  final String sessionId;
  SessionAccessMode accessMode;
  final bool recoveredSession;
  final Duration eventErrorDelay;
  final Duration snapshotTimeout;
  final Duration streamRenderInterval;
  final int streamPreviewCharacterLimit;
  final String Function() clientMessageIdFactory;
  final StreamController<ExtensionUiRequest> _uiRequests =
      StreamController<ExtensionUiRequest>.broadcast();
  final ValueNotifier<List<ChatMessage>> _messagesUpdates =
      ValueNotifier<List<ChatMessage>>(const <ChatMessage>[]);
  final ValueNotifier<List<SessionTimelineItem>> _timelineUpdates =
      ValueNotifier<List<SessionTimelineItem>>(const <SessionTimelineItem>[]);
  final ValueNotifier<String?> _streamingTextUpdates = ValueNotifier(null);
  final Set<String> _handledApprovalIdentities = <String>{};
  final Set<String> _receivedPhoneMessageIdentities = <String>{};
  List<ChatMessage> _messages = const <ChatMessage>[];
  List<String?> _messageIds = const <String?>[];
  List<SessionTimelineItem> _timelineItems = const <SessionTimelineItem>[];
  TimelineHistorySummary? _timelineHistory;
  Set<String> _capabilities;
  RuntimeState _runtimeState;
  EventConnectionState _eventConnectionState = EventConnectionState.connecting;
  List<String>? _streamingTextChunks;
  int _streamingTextLength = 0;
  ChatActivity? _activity;
  TsPhoneProblem? _operationProblem;
  TsPhoneProblem? _eventProblem;
  String? _lastEventId;
  String _sessionRevision;
  String? _sessionTitle;
  SessionRuntimeSnapshot? _sessionRuntime;
  bool _historyAvailable;
  bool _canPrompt;
  bool _commandInFlight = false;
  bool _eventStreamEnabled = true;
  bool _snapshotReady = false;
  bool _disposed = false;
  StreamSubscription<TsPhoneEvent>? _eventSubscription;
  Future<void>? _eventCancellation;
  Future<void>? _snapshotSynchronization;
  bool _connectAfterCancellationScheduled = false;
  bool _snapshotSyncInProgress = false;
  bool _loadingEarlierMessages = false;
  bool _loadingAllHistory = false;
  bool _hasMoreHistory = false;
  bool _loadedEarlierHistory = false;
  String? _nextBefore;
  List<String> _latestSnapshotMessageIds = const <String>[];
  List<String> _latestTimelineItemIds = const <String>[];
  String? _selectedBranchId;
  String? _currentTurnId;
  Timer? _reconnectTimer;
  Timer? _eventErrorTimer;
  Timer? _streamRenderTimer;
  Timer? _snapshotTimeoutTimer;
  int _eventGeneration = 0;
  int _retrySeconds = 1;

  UnmodifiableListView<ChatMessage> get messages =>
      UnmodifiableListView(_messages);
  ValueListenable<List<ChatMessage>> get messagesUpdates => _messagesUpdates;
  UnmodifiableListView<SessionTimelineItem> get timelineItems =>
      UnmodifiableListView(_timelineItems);
  ValueListenable<List<SessionTimelineItem>> get timelineUpdates =>
      _timelineUpdates;
  RuntimeState get runtimeState => _runtimeState;
  EventConnectionState get eventConnectionState => _eventConnectionState;
  String? get streamingText => _streamingTextChunks?.join();
  bool get hasStreamingText => _streamingTextChunks != null;
  ValueListenable<String?> get streamingTextUpdates => _streamingTextUpdates;
  ChatActivity? get activity => _activity;
  TsPhoneProblem? get problem => _operationProblem ?? _eventProblem;
  bool get isSynchronizing => _snapshotSyncInProgress;
  String? get sessionTitle => _sessionTitle;
  SessionRuntimeSnapshot? get sessionRuntime => _sessionRuntime;
  String get sessionRevision => _sessionRevision;
  bool get commandInFlight => _commandInFlight;
  bool get historyAvailable => _historyAvailable;
  bool get historyOnly =>
      _runtimeState == RuntimeState.offline && _historyAvailable && !_canPrompt;
  bool get usesStructuredTimeline =>
      _capabilities.contains(timelineCapability) || _timelineHistory != null;
  TimelineHistorySummary? get timelineHistory => _timelineHistory;
  bool get viewingInactiveBranch =>
      _timelineHistory?.selectedBranchIsActive == false;
  int get loadedTimelineItemCount => _timelineItems
      .where((item) => RegExp(r'^[0-9a-f]{8}$').hasMatch(item.id))
      .length;
  int get totalTimelineItemCount =>
      _timelineHistory?.totalItems ?? _messages.length;
  int get timelineTurnCount => _timelineHistory?.turnCount ?? 0;
  int get timelineActivityCount => _timelineHistory?.activityCount ?? 0;
  List<TimelineBranchSummary> get timelineBranches =>
      _timelineHistory?.branches ?? const <TimelineBranchSummary>[];
  bool get canRefresh => _historyAvailable || _runtimeState.isAvailable;
  bool get loadingEarlierMessages => _loadingEarlierMessages;
  bool get loadingAllHistory => _loadingAllHistory;
  bool get canLoadEarlierMessages =>
      _hasMoreHistory && _nextBefore != null && !_loadingEarlierMessages;
  bool get canSend =>
      _canPrompt &&
      !viewingInactiveBranch &&
      _runtimeState.isAvailable &&
      _snapshotReady &&
      !_snapshotSyncInProgress &&
      _eventConnectionState == EventConnectionState.connected;
  Stream<ExtensionUiRequest> get uiRequests => _uiRequests.stream;

  String messageKeyAt(int index) =>
      _messageIds[index] ??
      '${_messages[index].role.name}-${_messages[index].timestamp?.microsecondsSinceEpoch ?? 0}-$index';

  String timelineKeyAt(int index) => _timelineItems[index].id;

  Future<void> initialize() async {
    if (canRefresh) {
      await refreshMessages();
    } else {
      _connectEventStream();
    }
  }

  Future<void> refreshMessages() => _refreshMessages();

  Future<void> _refreshMessages({bool allowUnavailable = false}) {
    final existing = _snapshotSynchronization;
    if (existing != null) return existing;
    if ((!allowUnavailable && !canRefresh) || _disposed) {
      return Future<void>.value();
    }
    late final Future<void> tracked;
    tracked = _synchronizeMessages().whenComplete(() {
      if (identical(_snapshotSynchronization, tracked)) {
        _snapshotSynchronization = null;
      }
    });
    _snapshotSynchronization = tracked;
    return tracked;
  }

  Future<void> _synchronizeMessages() async {
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
      await _cancelEventSubscriptionAndWait();
      if (_capabilities.contains(timelineCapability)) {
        final snapshot = await _awaitSnapshot(
          api.getTimeline(workspaceId, sessionId, branch: _selectedBranchId),
        );
        if (_disposed) return;
        if (snapshot.sessionId != sessionId) {
          throw const FormatException('Timeline belongs to another session');
        }
        final revisionChanged = snapshot.sessionRevision != _sessionRevision;
        _applyTimelineSnapshot(snapshot, reset: revisionChanged);
        _sessionRevision = snapshot.sessionRevision;
        _lastEventId = snapshot.lastEventId;
        await _loadAutomaticTimelineHistory();
      } else {
        final snapshot = await _awaitSnapshot(
          api.getMessages(workspaceId, sessionId),
        );
        if (_disposed) return;
        if (snapshot.sessionId != sessionId) {
          throw const FormatException('Snapshot belongs to another session');
        }
        final revisionChanged = snapshot.sessionRevision != _sessionRevision;
        _applyMessageSnapshot(snapshot, reset: revisionChanged);
        _sessionRevision = snapshot.sessionRevision;
        _lastEventId = snapshot.lastEventId;
      }
      _snapshotReady = true;
      _clearStreamingText();
      _activity = null;
      _operationProblem = null;
      _notify();
    } on Object catch (error) {
      if (!_disposed) _setError(error);
    } finally {
      _snapshotSyncInProgress = false;
      if (!_disposed) {
        _notify();
        if (_eventStreamEnabled) _connectEventStream();
      }
    }
  }

  Future<bool> loadEarlierMessages() async {
    final before = _nextBefore;
    if (_disposed ||
        _loadingEarlierMessages ||
        !_hasMoreHistory ||
        before == null) {
      return false;
    }
    _loadingEarlierMessages = true;
    _operationProblem = null;
    _notify();
    try {
      if (usesStructuredTimeline) {
        return await _loadEarlierTimelinePage(before);
      }
      return await _loadEarlierMessagePage(before);
    } on Object catch (error) {
      if (!_disposed) _setError(error);
      return false;
    } finally {
      _loadingEarlierMessages = false;
      if (!_disposed) _notify();
    }
  }

  Future<void> loadAllHistory() async {
    if (_disposed || _loadingAllHistory || !canLoadEarlierMessages) return;
    _loadingAllHistory = true;
    _operationProblem = null;
    _notify();
    try {
      while (!_disposed && _hasMoreHistory && _nextBefore != null) {
        final loaded = usesStructuredTimeline
            ? await _loadEarlierTimelinePage(_nextBefore!)
            : await _loadEarlierMessagePage(_nextBefore!);
        if (!loaded) break;
        _notify();
      }
    } on Object catch (error) {
      if (!_disposed) _setError(error);
    } finally {
      _loadingAllHistory = false;
      if (!_disposed) _notify();
    }
  }

  Future<void> selectTimelineBranch(String branchId) async {
    if (_disposed ||
        _snapshotSyncInProgress ||
        _loadingEarlierMessages ||
        branchId == _timelineHistory?.selectedBranchId ||
        !timelineBranches.any((branch) => branch.id == branchId)) {
      return;
    }
    _selectedBranchId = branchId;
    _loadedEarlierHistory = false;
    _hasMoreHistory = false;
    _nextBefore = null;
    _latestTimelineItemIds = const <String>[];
    await refreshMessages();
  }

  Future<void> _loadAutomaticTimelineHistory() async {
    final history = _timelineHistory;
    if (history == null || history.totalItems > _automaticTimelineItemLimit) {
      return;
    }
    while (!_disposed && _hasMoreHistory && _nextBefore != null) {
      if (!await _loadEarlierTimelinePage(_nextBefore!)) break;
    }
  }

  Future<bool> _loadEarlierTimelinePage(String before) async {
    final page = await api.getTimeline(
      workspaceId,
      sessionId,
      before: before,
      limit: _timelinePageSize,
      branch: _selectedBranchId,
    );
    if (_disposed) return false;
    if (page.sessionId != sessionId ||
        page.sessionRevision != _sessionRevision ||
        page.history.selectedBranchId != _timelineHistory?.selectedBranchId) {
      throw const FormatException(
        'Earlier timeline belongs to another session branch',
      );
    }
    _validateEarlierPageCursor(
      requestedBefore: before,
      hasMore: page.hasMore,
      nextBefore: page.nextBefore,
      resource: 'Timeline',
    );
    _loadedEarlierHistory = true;
    _hasMoreHistory = page.hasMore;
    _nextBefore = page.nextBefore;
    _prependTimelinePage(page.items);
    return true;
  }

  Future<bool> _loadEarlierMessagePage(String before) async {
    final page = await api.getMessages(
      workspaceId,
      sessionId,
      before: before,
      limit: _historyPageSize,
    );
    if (_disposed) return false;
    if (page.sessionId != sessionId ||
        page.sessionRevision != _sessionRevision ||
        page.messageIds == null) {
      throw const FormatException(
        'Earlier messages belong to another session revision',
      );
    }
    _validateEarlierPageCursor(
      requestedBefore: before,
      hasMore: page.hasMore,
      nextBefore: page.nextBefore,
      resource: 'Message',
    );
    final parsed = _parseMessagePage(page.messages, page.messageIds);
    _loadedEarlierHistory = true;
    _hasMoreHistory = page.hasMore;
    _nextBefore = page.nextBefore;
    _prependMessagePage(parsed);
    return true;
  }

  static void _validateEarlierPageCursor({
    required String requestedBefore,
    required bool hasMore,
    required String? nextBefore,
    required String resource,
  }) {
    if ((hasMore && (nextBefore == null || nextBefore == requestedBefore)) ||
        (!hasMore && nextBefore != null)) {
      throw FormatException('$resource pagination did not advance');
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
    if (message.isEmpty || _commandInFlight || !canSend) return false;
    final revision = _sessionRevision;
    final clientMessageId = clientMessageIdFactory();
    final messageIdentity = '$revision\u0000$clientMessageId';
    _appendLiveMessage(
      ChatMessage(
        role: ChatRole.user,
        text: message,
        timestamp: DateTime.now(),
        clientMessageId: clientMessageId,
        origin: 'phone',
        deliveryState: ChatDeliveryState.sending,
      ),
      localId: 'phone-$clientMessageId',
    );
    _commandInFlight = true;
    _operationProblem = null;
    _notify();
    try {
      await api.sendMessage(
        workspaceId,
        sessionId,
        revision,
        message,
        clientMessageId: clientMessageId,
      );
      if (!_receivedPhoneMessageIdentities.contains(messageIdentity)) {
        _updateOutgoingDelivery(
          clientMessageId,
          ChatDeliveryState.synchronizing,
        );
      }
      return true;
    } on Object catch (error) {
      if (_receivedPhoneMessageIdentities.contains(messageIdentity)) {
        return true;
      }
      _removePendingOutgoing(clientMessageId);
      _setError(error);
      return false;
    } finally {
      _commandInFlight = false;
      _notify();
    }
  }

  Future<void> abort() =>
      _runCommand(() => api.abort(workspaceId, sessionId, _sessionRevision));

  Future<TsPhoneProblem?> respondToUi(
    ExtensionUiRequest request, {
    required bool approved,
  }) async {
    if (request.sessionRevision != _sessionRevision) {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.approvalStale,
      );
    }
    if (!request.expiresAt.isAfter(DateTime.now())) {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.approvalExpired,
      );
    }
    try {
      await api.respondToApproval(
        workspaceId,
        sessionId,
        request.id,
        sessionRevision: request.sessionRevision,
        approved: approved,
      );
      return null;
    } on Object catch (error) {
      return describeTsPhoneProblem(error);
    }
  }

  Future<void> _runCommand(Future<void> Function() command) async {
    if (_commandInFlight || !canSend) return;
    _commandInFlight = true;
    _operationProblem = null;
    _notify();
    try {
      await command();
    } on Object catch (error) {
      _setError(error);
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

  void _receiveEvent(int generation, TsPhoneEvent event) {
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
    _handleEvent(event);
  }

  void _resynchronizeChangedSession(int generation, String revision) {
    if (!_isCurrentEventStream(generation)) return;
    _sessionRevision = revision;
    _lastEventId = null;
    _hasMoreHistory = false;
    _nextBefore = null;
    _loadedEarlierHistory = false;
    _timelineHistory = null;
    _selectedBranchId = null;
    _latestTimelineItemIds = const <String>[];
    _snapshotReady = false;
    _runtimeState = RuntimeState.connecting;
    _canPrompt = false;
    _clearStreamingText();
    _activity = null;
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
      _eventProblem = describeTsPhoneProblem(error);
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
      _eventProblem = const TsPhoneProblem(
        TsPhoneProblemKind.unavailable,
        TsPhoneProblemCode.networkRetrying,
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
            context: ErrorDescription(
              'while closing the TS Phone event stream',
            ),
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
    if (error is! TsPhoneApiException) return false;
    return switch (error.statusCode) {
      400 || 401 || 403 || 404 => true,
      _ => false,
    };
  }

  void _handleEvent(TsPhoneEvent event) {
    final payload = _asMap(event.payload);
    if (viewingInactiveBranch && _isLiveContentEvent(event.type)) return;
    var deferStreamRender = false;
    var flushStreamRender = false;
    var notifyController = true;
    switch (event.type) {
      case 'session_state':
        final previous = _runtimeState;
        try {
          _runtimeState = RuntimeState.parse(payload?['state']);
        } on FormatException {
          _runtimeState = RuntimeState.recoveryRequired;
        }
        if (payload?['sessionName'] is String) {
          _sessionTitle = payload!['sessionName']! as String;
        }
        _updateSessionRuntime(payload?['runtime']);
        if (payload?['historyAvailable'] is bool) {
          _historyAvailable = payload!['historyAvailable']! as bool;
        }
        _updateCapabilities(payload?['capabilities']);
        _updateAccessMode(payload?['accessMode']);
        _canPrompt = payload?['canPrompt'] is bool
            ? payload!['canPrompt']! as bool
            : _runtimeState.isAvailable;
        if (_runtimeState == RuntimeState.offline ||
            _runtimeState == RuntimeState.recoveryRequired) {
          _snapshotReady = false;
          _clearStreamingText();
          _activity = null;
        } else if ((previous == RuntimeState.offline ||
                previous == RuntimeState.connecting) &&
            _runtimeState.isAvailable) {
          unawaited(refreshMessages());
        }
      case 'session.snapshot':
        final messages = payload?['messages'];
        if (messages is List && !usesStructuredTimeline) {
          try {
            _applyMessageSnapshot(
              TsPhoneMessageSnapshot(
                sessionId: sessionId,
                sessionRevision: _sessionRevision,
                messages: messages.cast<Object?>(),
                messageIds: _optionalMessageIds(
                  payload?['messageIds'],
                  messages.length,
                ),
                hasMore: payload?['hasMore'] == true,
                nextBefore: payload?['nextBefore'] as String?,
                lastEventId: event.id,
              ),
              reset: false,
            );
          } on Object {
            _operationProblem = const TsPhoneProblem(
              TsPhoneProblemKind.incompatible,
              TsPhoneProblemCode.invalidHistoryMessage,
            );
          }
        }
        if (payload?['sessionName'] is String) {
          _sessionTitle = payload!['sessionName']! as String;
        }
        _runtimeState = payload?['isStreaming'] == true
            ? RuntimeState.running
            : RuntimeState.idle;
        if (payload?['historyAvailable'] is bool) {
          _historyAvailable = payload!['historyAvailable']! as bool;
        }
        _updateCapabilities(payload?['capabilities']);
        _operationProblem = null;
        _updateSessionRuntime(payload?['runtime']);
        _updateAccessMode(payload?['accessMode']);
        _canPrompt = payload?['canPrompt'] is bool
            ? payload!['canPrompt']! as bool
            : true;
        _snapshotReady = true;
        if (usesStructuredTimeline) unawaited(refreshMessages());
      case 'input':
        final text = payload?['text'];
        if (text is String && text.isNotEmpty) {
          _applyInputEvent(event, payload!, text);
        }
      case 'agent_start':
        _runtimeState = RuntimeState.running;
      case 'agent_settled':
        _runtimeState = RuntimeState.idle;
        _clearStreamingText();
        _activity = null;
        if (usesStructuredTimeline) unawaited(refreshMessages());
      case 'message_start':
        final message = _asMap(payload?['message']);
        if (message?['role'] == 'assistant') _startStreamingText();
      case 'message_update':
        notifyController = false;
        final update = _asMap(payload?['assistantMessageEvent']);
        if (update?['type'] == 'text_delta' && update?['delta'] is String) {
          final started = _appendStreamingText(update!['delta'] as String);
          if (started) _notify();
          deferStreamRender = true;
        } else if (update?['type'] == 'text_end') {
          if ((_streamingTextChunks == null || _streamingTextLength == 0) &&
              update?['content'] is String) {
            final started = _replaceStreamingText(update!['content'] as String);
            if (started) _notify();
          }
          flushStreamRender = true;
        }
      case 'message_end':
        final message = payload?['message'];
        if (message != null) {
          try {
            final parsed = ChatMessage.fromJson(message);
            if (parsed.role == ChatRole.assistant ||
                parsed.role == ChatRole.tool) {
              _appendLiveMessage(parsed);
            }
          } on FormatException {
            _operationProblem = const TsPhoneProblem(
              TsPhoneProblemKind.incompatible,
              TsPhoneProblemCode.invalidMessage,
            );
          }
        }
        _clearStreamingText();
      case 'tool_execution_start':
        _activity = ChatActivity(
          ChatActivityKind.runningTool,
          toolName: payload?['toolName'] as String?,
          startedAt: event.at,
        );
      case 'tool_execution_end':
        if (payload?['isError'] == true) {
          final previous = _activity;
          _activity = ChatActivity(
            ChatActivityKind.toolFailed,
            toolName: previous?.toolName,
            startedAt: previous?.startedAt,
          );
        } else {
          _activity = null;
        }
      case 'approval.request':
        if (payload != null) _handleApproval(payload, event.sessionRevision);
    }
    if (deferStreamRender) {
      _scheduleStreamRender();
    } else if (flushStreamRender) {
      _cancelStreamRender();
      _publishStreamingText();
    } else if (notifyController) {
      _cancelStreamRender();
      _notify();
    }
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
      _operationProblem = const TsPhoneProblem(
        TsPhoneProblemKind.incompatible,
        TsPhoneProblemCode.invalidHistoryMessage,
      );
    }
  }

  static bool _isLiveContentEvent(String type) => switch (type) {
    'input' ||
    'message_start' ||
    'message_update' ||
    'message_end' ||
    'tool_execution_start' ||
    'tool_execution_end' ||
    'approval.request' => true,
    _ => false,
  };

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
      _operationProblem = const TsPhoneProblem(
        TsPhoneProblemKind.incompatible,
        TsPhoneProblemCode.incompatible,
      );
    }
  }

  void _updateCapabilities(Object? value) {
    if (value == null) return;
    if (value is! List || value.any((item) => item is! String)) {
      _operationProblem = const TsPhoneProblem(
        TsPhoneProblemKind.incompatible,
        TsPhoneProblemCode.incompatible,
      );
      return;
    }
    _capabilities = Set<String>.unmodifiable(value.cast<String>());
  }

  void _startStreamingText() {
    _cancelStreamRender();
    _streamingTextChunks = <String>[];
    _streamingTextLength = 0;
    _streamingTextUpdates.value = '';
  }

  bool _appendStreamingText(String delta) {
    final started = _streamingTextChunks == null;
    _streamingTextChunks ??= <String>[];
    _streamingTextChunks!.add(delta);
    _streamingTextLength += delta.length;
    return started;
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

  void _handleApproval(Map<String, Object?> payload, String sessionRevision) {
    final id = payload['id'];
    if (id is! String) return;
    final identity = '$sessionRevision\u0000$id';
    if (_handledApprovalIdentities.contains(identity)) return;
    try {
      final request = ExtensionUiRequest.fromJson(
        payload,
        sessionRevision: sessionRevision,
      );
      _handledApprovalIdentities.add(identity);
      while (_handledApprovalIdentities.length > 200) {
        _handledApprovalIdentities.remove(_handledApprovalIdentities.first);
      }
      _uiRequests.add(request);
    } on FormatException {
      _operationProblem = const TsPhoneProblem(
        TsPhoneProblemKind.incompatible,
        TsPhoneProblemCode.invalidApproval,
      );
    }
  }

  void _applyInputEvent(
    TsPhoneEvent event,
    Map<String, Object?> payload,
    String text,
  ) {
    final rawClientMessageId = payload['clientMessageId'];
    final rawOrigin = payload['origin'];
    final clientMessageId = rawClientMessageId is String
        ? rawClientMessageId
        : null;
    final origin = rawOrigin is String ? rawOrigin : null;
    final identity = clientMessageId == null
        ? null
        : '${event.sessionRevision}\u0000$clientMessageId';
    if (identity != null &&
        _receivedPhoneMessageIdentities.contains(identity)) {
      return;
    }
    if (identity != null) {
      _receivedPhoneMessageIdentities.add(identity);
      while (_receivedPhoneMessageIdentities.length > 200) {
        _receivedPhoneMessageIdentities.remove(
          _receivedPhoneMessageIdentities.first,
        );
      }
    }

    final incoming = ChatMessage(
      role: ChatRole.user,
      text: text,
      timestamp: event.at,
      clientMessageId: clientMessageId,
      origin: origin,
    );
    if (usesStructuredTimeline) {
      final pendingIndex = clientMessageId == null
          ? -1
          : _timelineItems.indexWhere(
              (item) =>
                  item is TimelineMessageItem &&
                  item.message.clientMessageId == clientMessageId &&
                  item.message.deliveryState != null,
            );
      if (pendingIndex < 0) {
        _appendLiveMessage(
          incoming,
          localId: clientMessageId == null
              ? 'live-${event.id}'
              : 'phone-$clientMessageId',
        );
      } else {
        final updated = <SessionTimelineItem>[..._timelineItems];
        final pending = updated[pendingIndex] as TimelineMessageItem;
        updated[pendingIndex] = pending.copyWith(message: incoming);
        _setTimelineItems(updated);
      }
      return;
    }
    final pendingIndex = clientMessageId == null
        ? -1
        : _messages.indexWhere(
            (message) =>
                message.clientMessageId == clientMessageId &&
                message.deliveryState != null,
          );
    if (pendingIndex < 0) {
      _setMessages(
        <ChatMessage>[..._messages, incoming],
        <String?>[..._messageIds, null],
      );
      return;
    }
    final updated = <ChatMessage>[..._messages];
    updated[pendingIndex] = incoming;
    _setMessages(updated, _messageIds);
  }

  void _updateOutgoingDelivery(
    String clientMessageId,
    ChatDeliveryState deliveryState,
  ) {
    if (usesStructuredTimeline) {
      final index = _timelineItems.indexWhere(
        (item) =>
            item is TimelineMessageItem &&
            item.message.clientMessageId == clientMessageId &&
            item.message.deliveryState != null,
      );
      if (index < 0) return;
      final updated = <SessionTimelineItem>[..._timelineItems];
      final item = updated[index] as TimelineMessageItem;
      updated[index] = item.copyWith(
        message: item.message.copyWith(deliveryState: deliveryState),
      );
      _setTimelineItems(updated);
      return;
    }
    final index = _messages.indexWhere(
      (message) =>
          message.clientMessageId == clientMessageId &&
          message.deliveryState != null,
    );
    if (index < 0) return;
    final updated = <ChatMessage>[..._messages];
    updated[index] = updated[index].copyWith(deliveryState: deliveryState);
    _setMessages(updated, _messageIds);
  }

  void _removePendingOutgoing(String clientMessageId) {
    if (usesStructuredTimeline) {
      _setTimelineItems(
        _timelineItems
            .where(
              (item) =>
                  item is! TimelineMessageItem ||
                  item.message.clientMessageId != clientMessageId ||
                  item.message.deliveryState == null,
            )
            .toList(growable: false),
      );
      return;
    }
    final messages = <ChatMessage>[];
    final messageIds = <String?>[];
    for (var index = 0; index < _messages.length; index += 1) {
      final message = _messages[index];
      if (message.clientMessageId == clientMessageId &&
          message.deliveryState != null) {
        continue;
      }
      messages.add(message);
      messageIds.add(_messageIds[index]);
    }
    _setMessages(messages, messageIds);
  }

  void _appendLiveMessage(ChatMessage message, {String? localId}) {
    if (!usesStructuredTimeline) {
      _setMessages(
        <ChatMessage>[..._messages, message],
        <String?>[..._messageIds, null],
      );
      return;
    }
    final id =
        localId ??
        'live-${_lastEventId ?? DateTime.now().microsecondsSinceEpoch}';
    if (message.role == ChatRole.user) _currentTurnId = id;
    _setTimelineItems(<SessionTimelineItem>[
      ..._timelineItems,
      TimelineMessageItem(id: id, turnId: _currentTurnId, message: message),
    ]);
  }

  void _applyTimelineSnapshot(
    TsPhoneTimelineSnapshot snapshot, {
    required bool reset,
  }) {
    final previousBranch = _timelineHistory?.selectedBranchId;
    final incomingIds = snapshot.items.map((item) => item.id).toList();
    final branchChanged =
        previousBranch != null &&
        previousBranch != snapshot.history.selectedBranchId;
    final windowChanged =
        _latestTimelineItemIds.isNotEmpty &&
        !_continuesMessageWindow(_latestTimelineItemIds, incomingIds);
    final replaceHistory =
        reset || _timelineHistory == null || branchChanged || windowChanged;

    _timelineHistory = snapshot.history;
    _selectedBranchId = snapshot.history.selectedBranchIsActive
        ? null
        : snapshot.history.selectedBranchId;
    _capabilities = snapshot.capabilities;
    _canPrompt = snapshot.capabilities.contains(promptCapability);
    if (replaceHistory) _loadedEarlierHistory = false;
    if (replaceHistory || !_loadedEarlierHistory) {
      _hasMoreHistory = snapshot.hasMore;
      _nextBefore = snapshot.nextBefore;
    }
    if (replaceHistory) {
      _setTimelineItems(snapshot.items);
    } else {
      _mergeTimelinePage(snapshot.items);
    }
    _latestTimelineItemIds = incomingIds;
  }

  void _prependTimelinePage(List<SessionTimelineItem> incoming) {
    final existing = _timelineItems.map((item) => item.id).toSet();
    _setTimelineItems(<SessionTimelineItem>[
      ...incoming.where((item) => !existing.contains(item.id)),
      ..._timelineItems,
    ]);
  }

  void _mergeTimelinePage(List<SessionTimelineItem> incoming) {
    final incomingById = <String, SessionTimelineItem>{
      for (final item in incoming) item.id: item,
    };
    final incomingMessages = incoming.whereType<TimelineMessageItem>().toList(
      growable: false,
    );
    final incomingClientIds = incoming
        .whereType<TimelineMessageItem>()
        .map((item) => item.message.clientMessageId)
        .whereType<String>()
        .toSet();
    final reconciledIncomingMessages = <int>{};
    final included = <String>{};
    final merged = <SessionTimelineItem>[];
    for (final item in _timelineItems) {
      final stable = RegExp(r'^[0-9a-f]{8}$').hasMatch(item.id);
      if (!stable) {
        if (item is TimelineMessageItem) {
          if (item.message.clientMessageId != null &&
              incomingClientIds.contains(item.message.clientMessageId)) {
            continue;
          }
          if (item.message.deliveryState == null) {
            final match = _matchingPersistedMessage(
              item.message,
              incomingMessages,
              reconciledIncomingMessages,
            );
            if (match >= 0) {
              reconciledIncomingMessages.add(match);
              continue;
            }
          }
        }
        merged.add(item);
        continue;
      }
      merged.add(incomingById[item.id] ?? item);
      included.add(item.id);
    }
    for (final item in incoming) {
      if (included.add(item.id)) merged.add(item);
    }
    _setTimelineItems(merged);
  }

  static int _matchingPersistedMessage(
    ChatMessage transient,
    List<TimelineMessageItem> incoming,
    Set<int> consumed,
  ) {
    for (var index = 0; index < incoming.length; index += 1) {
      if (!consumed.contains(index) &&
          _sameTimelineMessage(transient, incoming[index].message)) {
        return index;
      }
    }
    return -1;
  }

  static bool _sameTimelineMessage(ChatMessage left, ChatMessage right) {
    if (left.role != right.role ||
        left.text != right.text ||
        left.tools.length != right.tools.length) {
      return false;
    }
    final leftClientId = left.clientMessageId;
    final rightClientId = right.clientMessageId;
    if (leftClientId != null || rightClientId != null) {
      return leftClientId != null && leftClientId == rightClientId;
    }
    final leftAt = left.timestamp;
    final rightAt = right.timestamp;
    if (leftAt == null || rightAt == null) return false;
    if ((leftAt.difference(rightAt).inMilliseconds).abs() > 120000) {
      return false;
    }
    for (var index = 0; index < left.tools.length; index += 1) {
      final leftTool = left.tools[index];
      final rightTool = right.tools[index];
      if (leftTool.title != rightTool.title ||
          leftTool.body != rightTool.body ||
          leftTool.isError != rightTool.isError) {
        return false;
      }
    }
    return true;
  }

  void _setTimelineItems(List<SessionTimelineItem> items) {
    _timelineItems = List<SessionTimelineItem>.unmodifiable(items);
    _timelineUpdates.value = _timelineItems;
    _currentTurnId = null;
    for (final item in _timelineItems) {
      if (item.turnId != null) _currentTurnId = item.turnId;
    }
    final messages = <ChatMessage>[];
    final messageIds = <String?>[];
    for (final item in _timelineItems.whereType<TimelineMessageItem>()) {
      if (item.message.text.isEmpty && item.message.tools.isEmpty) continue;
      messages.add(item.message);
      messageIds.add(
        RegExp(r'^[0-9a-f]{8}$').hasMatch(item.id) ? item.id : null,
      );
    }
    _setMessages(messages, messageIds);
  }

  void _applyMessageSnapshot(
    TsPhoneMessageSnapshot snapshot, {
    required bool reset,
  }) {
    final rawIds = snapshot.messageIds;
    if ((snapshot.hasMore &&
            (rawIds == null ||
                rawIds.isEmpty ||
                snapshot.nextBefore != rawIds.first)) ||
        (!snapshot.hasMore && snapshot.nextBefore != null)) {
      throw const FormatException('Message pagination cursor is invalid');
    }
    final parsed = _parseMessagePage(snapshot.messages, rawIds);
    final branchChanged =
        !reset &&
        rawIds != null &&
        !_continuesMessageWindow(_latestSnapshotMessageIds, rawIds);
    final replaceHistory = reset || rawIds == null || branchChanged;
    if (replaceHistory) _loadedEarlierHistory = false;
    if (replaceHistory || !_loadedEarlierHistory) {
      _hasMoreHistory = snapshot.hasMore;
      _nextBefore = snapshot.nextBefore;
    }
    if (replaceHistory) {
      _setMessages(parsed.messages, parsed.messageIds);
    } else {
      _mergeMessagePage(parsed);
    }
    _latestSnapshotMessageIds = rawIds ?? const <String>[];
  }

  void _prependMessagePage(_ParsedMessagePage parsed) {
    final existing = _messageIds.whereType<String>().toSet();
    final messages = <ChatMessage>[];
    final messageIds = <String?>[];
    for (var index = 0; index < parsed.messages.length; index += 1) {
      final id = parsed.messageIds[index];
      if (id == null || existing.contains(id)) continue;
      messages.add(parsed.messages[index]);
      messageIds.add(id);
    }
    _setMessages(
      <ChatMessage>[...messages, ..._messages],
      <String?>[...messageIds, ..._messageIds],
    );
  }

  void _mergeMessagePage(_ParsedMessagePage incoming) {
    final incomingById = <String, ChatMessage>{};
    for (var index = 0; index < incoming.messages.length; index += 1) {
      final id = incoming.messageIds[index];
      if (id != null) incomingById[id] = incoming.messages[index];
    }
    final existingIds = _messageIds.whereType<String>().toSet();
    final overlap = existingIds.intersection(incomingById.keys.toSet());
    final replaceStableHistory =
        existingIds.isNotEmpty && overlap.isEmpty && !_loadedEarlierHistory;
    final messages = <ChatMessage>[];
    final messageIds = <String?>[];
    final included = <String>{};
    final pending = <ChatMessage>[];

    for (var index = 0; index < _messages.length; index += 1) {
      final id = _messageIds[index];
      final message = _messages[index];
      if (id == null) {
        if (message.deliveryState != null) pending.add(message);
        continue;
      }
      if (replaceStableHistory) continue;
      messages.add(incomingById[id] ?? message);
      messageIds.add(id);
      included.add(id);
    }
    for (var index = 0; index < incoming.messages.length; index += 1) {
      final id = incoming.messageIds[index];
      if (id == null || included.contains(id)) continue;
      messages.add(incoming.messages[index]);
      messageIds.add(id);
      included.add(id);
    }
    messages.addAll(pending);
    messageIds.addAll(List<String?>.filled(pending.length, null));
    _setMessages(messages, messageIds);
  }

  _ParsedMessagePage _parseMessagePage(
    List<Object?> raw,
    List<String>? rawIds,
  ) {
    if (rawIds != null && rawIds.length != raw.length) {
      throw const FormatException('Message ids do not align with messages');
    }
    final messages = <ChatMessage>[];
    final messageIds = <String?>[];
    for (var index = 0; index < raw.length; index += 1) {
      try {
        final message = ChatMessage.fromJson(raw[index]);
        if (message.text.isNotEmpty || message.tools.isNotEmpty) {
          messages.add(message);
          messageIds.add(rawIds?[index]);
        }
      } on FormatException {
        _operationProblem = const TsPhoneProblem(
          TsPhoneProblemKind.incompatible,
          TsPhoneProblemCode.invalidHistoryMessage,
        );
      }
    }
    return _ParsedMessagePage(messages, messageIds);
  }

  static List<String>? _optionalMessageIds(Object? value, int messageCount) {
    if (value == null) return null;
    if (value is! List ||
        value.length != messageCount ||
        value.any((id) => id is! String)) {
      throw const FormatException('Message ids are invalid');
    }
    final ids = value.cast<String>();
    if (ids.toSet().length != ids.length ||
        ids.any((id) => !RegExp(r'^[0-9a-f]{8}$').hasMatch(id))) {
      throw const FormatException('Message ids are invalid or not unique');
    }
    return ids;
  }

  static bool _continuesMessageWindow(
    List<String> previous,
    List<String> incoming,
  ) {
    if (previous.isEmpty) return true;
    if (incoming.isEmpty) return false;
    final incomingIds = incoming.toSet();
    var overlapStart = 0;
    while (overlapStart < previous.length &&
        !incomingIds.contains(previous[overlapStart])) {
      overlapStart += 1;
    }
    final overlapLength = previous.length - overlapStart;
    if (overlapLength == 0 || overlapLength > incoming.length) return false;
    for (var index = 0; index < overlapLength; index += 1) {
      if (previous[overlapStart + index] != incoming[index]) return false;
    }
    return true;
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
    _operationProblem = describeTsPhoneProblem(error);
    _notify();
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
    api.close();
    unawaited(_uiRequests.close());
    _messagesUpdates.dispose();
    _timelineUpdates.dispose();
    _streamingTextUpdates.dispose();
    super.dispose();
  }
}

class _ParsedMessagePage {
  const _ParsedMessagePage(this.messages, this.messageIds);

  final List<ChatMessage> messages;
  final List<String?> messageIds;
}
