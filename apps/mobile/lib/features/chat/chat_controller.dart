import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../data/ts_phone_api.dart';
import '../../models/chat_message.dart';
import '../../models/session_timeline.dart';
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
const int _timelinePageSize = 50;

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
    this.clientMessageIdFactory = createTsPhoneClientMessageId,
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
      _timelineHistory = initialPreview.history;
      _selectedBranchId =
          initialPreview.history?.selectedBranchIsActive == false
          ? initialPreview.history?.selectedBranchId
          : null;
      _hasMoreHistory = initialPreview.hasMore;
      _nextBefore = initialPreview.before;
      _viewingHistoryWindow = initialPreview.viewingHistoryWindow;
      _hasLaterHistory = initialPreview.hasLater;
      _nextAfter = initialPreview.after;
      _loadedEarlierHistory = true;
      if (initialPreview.history != null) {
        _setTimelineItems(initialPreview.items);
        _latestTimelineItemIds = initialPreview.items
            .map((item) => item.id)
            .where((id) => RegExp(r'^[0-9a-f]{8}$').hasMatch(id))
            .toList();
      } else {
        _setMessages(initialPreview.messages, initialPreview.messageIds);
        _latestSnapshotMessageIds = initialPreview.messageIds
            .whereType<String>()
            .toList();
      }
    }
    this.outbox.addListener(_syncOutbox);
    _syncOutbox();
  }

  final TsPhoneGateway api;
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
  final StreamController<ExtensionUiRequest> _uiRequests =
      StreamController<ExtensionUiRequest>.broadcast();
  final ValueNotifier<List<ChatMessage>> _messagesUpdates =
      ValueNotifier<List<ChatMessage>>(const <ChatMessage>[]);
  final ValueNotifier<List<SessionTimelineItem>> _timelineUpdates =
      ValueNotifier<List<SessionTimelineItem>>(const <SessionTimelineItem>[]);
  final ValueNotifier<String?> _streamingTextUpdates = ValueNotifier(null);
  final Set<String> _handledApprovalIdentities = <String>{};
  final Set<String> _receivedPhoneMessageIdentities = <String>{};
  final Set<String> _acceptedPhoneMessageIdentities = <String>{};
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
  String? _nextAfter;
  bool _hasLaterHistory = false;
  bool _viewingHistoryWindow = false;
  bool _historyNavigationInProgress = false;
  int _historyGeneration = 0;
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
  bool get hasFailedOutput => _messages.any(
    (message) => message.outputState == AssistantOutputState.failed,
  );
  TsPhoneProblem? get problem =>
      _operationProblem ??
      (_promptProblem == null
          ? null
          : describeTsPhoneProblem(
              TsPhoneApiException('Model not ready', code: _promptProblem),
            )) ??
      (outbox.messages.any(
            (value) => value.state == ChatDeliveryState.uncertain,
          )
          ? const TsPhoneProblem(
              TsPhoneProblemKind.request,
              TsPhoneProblemCode.deliveryUncertain,
            )
          : null) ??
      _eventProblem;
  bool get isSynchronizing => _snapshotSyncInProgress;

  /// A dropped event stream is retried in the background. Keep this separate
  /// from actionable request failures so the chat can stay readable while the
  /// connection indicator communicates the transient state in the app bar.
  bool get hasTransientEventProblem =>
      _eventConnectionState == EventConnectionState.reconnecting &&
      _eventProblem?.code == TsPhoneProblemCode.networkRetrying;
  String? get sessionTitle => _sessionTitle;
  SessionRuntimeSnapshot? get sessionRuntime => _sessionRuntime;
  String get sessionRevision => _sessionRevision;
  String? get activeAgentRunId => _activeAgentRunId;
  bool get commandInFlight => _commandInFlight || outbox.isSending;
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
  bool get viewingHistoryWindow => _viewingHistoryWindow;
  bool get historyNavigationInProgress => _historyNavigationInProgress;
  bool get canLoadLaterMessages =>
      _hasLaterHistory && _nextAfter != null && !_historyNavigationInProgress;
  bool get canLoadEarlierMessages =>
      _hasMoreHistory &&
      _nextBefore != null &&
      !_loadingEarlierMessages &&
      !_historyNavigationInProgress;
  bool get _promptStateReady =>
      _canPrompt &&
      _promptProblem == null &&
      _runtimeState.isAvailable &&
      _snapshotReady &&
      !_historyNavigationInProgress &&
      !viewingInactiveBranch &&
      !_snapshotSyncInProgress;
  bool get canSend =>
      _promptStateReady &&
      _eventConnectionState == EventConnectionState.connected;
  Stream<ExtensionUiRequest> get uiRequests => _uiRequests.stream;

  TsPhoneModelGateway? get modelGateway =>
      api is TsPhoneModelGateway ? api as TsPhoneModelGateway : null;
  String? get selectedModelReference {
    final model = _sessionRuntime?.model;
    final current = model == null ? null : '${model.provider}/${model.id}';
    return current ?? _sessionModel;
  }

  bool get canSelectModel =>
      modelGateway != null &&
      !_snapshotSyncInProgress &&
      !viewingInactiveBranch &&
      !_historyNavigationInProgress &&
      !commandInFlight &&
      outbox.messages.isEmpty &&
      _activeAgentRunId == null &&
      _runtimeState == RuntimeState.idle &&
      _capabilities.contains('command.model') &&
      _snapshotReady &&
      _eventConnectionState == EventConnectionState.connected;

  Future<void> selectModel(PhoneModel model) async {
    if (!canSelectModel) {
      throw const TsPhoneApiException(
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
        throw const TsPhoneApiException(
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

  String timelineKeyAt(int index) => _timelineItems[index].id;

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
    items: _timelineItems,
    history: _timelineHistory,
    hasMore: _hasMoreHistory,
    before: _nextBefore,
    hasLater: _hasLaterHistory,
    after: _nextAfter,
    viewingHistoryWindow: _viewingHistoryWindow,
  );

  Future<void> refreshMessages() => _refreshMessages();

  Future<SessionSummary> refreshSessionMetadata() async {
    final sessions = await api.listSessions(workspaceId);
    final session = sessions
        .where((value) => value.sessionId == sessionId)
        .firstOrNull;
    if (session == null) {
      throw const TsPhoneApiException(
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
        _messages.isNotEmpty ||
        _timelineItems.isNotEmpty ||
        outbox.messages.isNotEmpty;
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
      if (_capabilities.contains(timelineCapability)) {
        final snapshot = await _awaitSnapshot(
          api.getTimeline(
            workspaceId,
            sessionId,
            branch: _selectedBranchId,
            limit: _timelinePageSize,
          ),
        );
        if (_disposed) return;
        if (snapshot.sessionId != sessionId) {
          throw const FormatException('Timeline belongs to another session');
        }
        final revisionChanged = snapshot.sessionRevision != _sessionRevision;
        _applySnapshotAgentRun(snapshot.activeAgentRunId);
        if (resetView || revisionChanged || !_viewingHistoryWindow) {
          _applyTimelineSnapshot(snapshot, reset: revisionChanged || resetView);
          _viewingHistoryWindow = false;
        }
        _sessionRevision = snapshot.sessionRevision;
        _lastEventId = snapshot.lastEventId;
      } else {
        final snapshot = await _awaitSnapshot(
          api.getMessages(workspaceId, sessionId, limit: _timelinePageSize),
        );
        if (_disposed) return;
        if (snapshot.sessionId != sessionId) {
          throw const FormatException('Snapshot belongs to another session');
        }
        final revisionChanged = snapshot.sessionRevision != _sessionRevision;
        _applySnapshotAgentRun(snapshot.activeAgentRunId);
        if (resetView || revisionChanged || !_viewingHistoryWindow) {
          _applyMessageSnapshot(snapshot, reset: revisionChanged || resetView);
          _viewingHistoryWindow = false;
        }
        _sessionRevision = snapshot.sessionRevision;
        _lastEventId = snapshot.lastEventId;
      }
      _snapshotReady = true;
      _clearStreamingText();
      _activity = null;
      _operationProblem = null;
      _notify();
    } on Object catch (error) {
      if (!_disposed) {
        // A cached transcript remains useful while the relay is recovering.
        // Keep the failure in the status channel so the chat does not flash an
        // error page for a transient snapshot request failure.
        if (hadCachedSnapshot && _isTransientTransportError(error)) {
          _operationProblem = describeTsPhoneProblem(error);
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

  Future<bool> loadEarlierMessages() async {
    final before = _nextBefore;
    if (_disposed ||
        _loadingEarlierMessages ||
        _historyNavigationInProgress ||
        !_hasMoreHistory ||
        before == null) {
      return false;
    }
    _loadingEarlierMessages = true;
    final generation = _historyGeneration;
    _operationProblem = null;
    _notify();
    try {
      if (usesStructuredTimeline) {
        return await _loadEarlierTimelinePage(before);
      }
      return await _loadEarlierMessagePage(before);
    } on Object catch (error) {
      if (!_disposed && generation == _historyGeneration) _setError(error);
      return false;
    } finally {
      if (generation == _historyGeneration) {
        _loadingEarlierMessages = false;
        if (!_disposed) _notify();
      }
    }
  }

  Future<bool> jumpToStart() async {
    if (!_hasMoreHistory) return true;
    return _readForwardHistory(fromStart: true);
  }

  Future<bool> loadLaterMessages() => _readForwardHistory(fromStart: false);

  Future<bool> returnToLatest() async {
    if (_disposed) return false;
    // A direct tail request supersedes pagination, including replies in flight.
    final generation = ++_historyGeneration;
    _loadingEarlierMessages = false;
    _loadingAllHistory = false;
    _historyNavigationInProgress = true;
    _operationProblem = null;
    _notify();
    try {
      await _refreshMessages(allowUnavailable: true, resetView: true);
      return !_disposed && !_viewingHistoryWindow && _snapshotReady;
    } finally {
      if (generation == _historyGeneration) {
        _historyNavigationInProgress = false;
        if (!_disposed) _notify();
      }
    }
  }

  Future<bool> _readForwardHistory({required bool fromStart}) async {
    final gateway = api is TsPhoneHistoryGateway
        ? api as TsPhoneHistoryGateway
        : null;
    if (_disposed ||
        _historyNavigationInProgress ||
        _snapshotSyncInProgress ||
        _loadingEarlierMessages ||
        _loadingAllHistory ||
        (!fromStart && !canLoadLaterMessages)) {
      return false;
    }
    if (gateway == null || !_capabilities.contains('history.seek')) {
      _setError(
        const TsPhoneApiException(
          'History navigation is not exposed by the native App Server',
          code: 'management_unsupported',
        ),
      );
      return false;
    }
    final revision = _sessionRevision;
    final branch = _selectedBranchId;
    final after = fromStart ? null : _nextAfter;
    final generation = _historyGeneration;
    _historyNavigationInProgress = true;
    _operationProblem = null;
    _notify();
    try {
      if (usesStructuredTimeline) {
        final page = await gateway.getTimelineWindow(
          workspaceId,
          sessionId,
          fromStart: fromStart,
          after: after,
          branch: branch,
          limit: _timelinePageSize,
        );
        if (_disposed ||
            revision != _sessionRevision ||
            generation != _historyGeneration) {
          return false;
        }
        if (page.sessionId != sessionId ||
            page.sessionRevision != revision ||
            (branch == null
                ? !page.history.selectedBranchIsActive
                : page.history.selectedBranchId != branch)) {
          throw const FormatException(
            'History belongs to another session branch',
          );
        }
        if (fromStart && page.hasMore ||
            page.hasLater && page.nextAfter == after) {
          throw const FormatException(
            'History navigation did not reach the requested position',
          );
        }
        if (fromStart) {
          _applyTimelineSnapshot(page, reset: true);
        } else {
          _mergeTimelinePage(page.items);
          _timelineHistory = page.history;
        }
        _hasLaterHistory = page.hasLater;
        _nextAfter = page.nextAfter;
      } else {
        final page = await gateway.getMessageWindow(
          workspaceId,
          sessionId,
          fromStart: fromStart,
          after: after,
          limit: _historyPageSize,
        );
        if (_disposed ||
            revision != _sessionRevision ||
            generation != _historyGeneration) {
          return false;
        }
        if (page.sessionId != sessionId ||
            page.sessionRevision != revision ||
            page.messageIds == null ||
            fromStart && page.hasMore ||
            page.hasLater && page.nextAfter == after) {
          throw const FormatException(
            'History navigation returned an invalid page',
          );
        }
        if (fromStart) {
          _applyMessageSnapshot(page, reset: true);
        } else {
          _mergeMessagePage(_parseMessagePage(page.messages, page.messageIds));
        }
        _hasLaterHistory = page.hasLater;
        _nextAfter = page.nextAfter;
      }
      _viewingHistoryWindow = true;
      _loadedEarlierHistory = true;
      _clearStreamingText();
      return true;
    } on Object catch (error) {
      if (!_disposed && generation == _historyGeneration) _setError(error);
      return false;
    } finally {
      if (generation == _historyGeneration) {
        _historyNavigationInProgress = false;
        if (!_disposed) _notify();
      }
    }
  }

  Future<void> loadAllHistory() async {
    if (_disposed || _loadingAllHistory || !canLoadEarlierMessages) return;
    final generation = _historyGeneration;
    _loadingAllHistory = true;
    _operationProblem = null;
    _notify();
    try {
      while (!_disposed &&
          generation == _historyGeneration &&
          _hasMoreHistory &&
          _nextBefore != null) {
        final loaded = usesStructuredTimeline
            ? await _loadEarlierTimelinePage(_nextBefore!)
            : await _loadEarlierMessagePage(_nextBefore!);
        if (!loaded) break;
        _notify();
      }
    } on Object catch (error) {
      if (!_disposed && generation == _historyGeneration) _setError(error);
    } finally {
      if (generation == _historyGeneration) {
        _loadingAllHistory = false;
        if (!_disposed) _notify();
      }
    }
  }

  Future<void> selectTimelineBranch(String branchId) async {
    if (_disposed ||
        _snapshotSyncInProgress ||
        _historyNavigationInProgress ||
        _loadingEarlierMessages ||
        branchId == _timelineHistory?.selectedBranchId ||
        !timelineBranches.any((branch) => branch.id == branchId)) {
      return;
    }
    _selectedBranchId = branchId;
    _viewingHistoryWindow = false;
    _hasLaterHistory = false;
    _nextAfter = null;
    _loadedEarlierHistory = false;
    _hasMoreHistory = false;
    _nextBefore = null;
    _latestTimelineItemIds = const <String>[];
    await refreshMessages();
  }

  Future<bool> _loadEarlierTimelinePage(String before) async {
    final generation = _historyGeneration;
    final page = await api.getTimeline(
      workspaceId,
      sessionId,
      before: before,
      limit: _timelinePageSize,
      branch: _selectedBranchId,
    );
    if (_disposed || generation != _historyGeneration) return false;
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
    final generation = _historyGeneration;
    final page = await api.getMessages(
      workspaceId,
      sessionId,
      before: before,
      limit: _historyPageSize,
    );
    if (_disposed || generation != _historyGeneration) return false;
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
    if (message.isEmpty || commandInFlight || !canSend) return false;
    if (_viewingHistoryWindow && !await returnToLatest()) return false;
    if (!_promptStateReady) return false;
    final revision = _sessionRevision;
    final retry = outbox.uncertain(message);
    if (retry != null) {
      if (retry.revision != revision) {
        _setError(
          const TsPhoneApiException(
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
    final messageIdentity = '$revision\u0000$clientMessageId';
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
      if (!_receivedPhoneMessageIdentities.contains(messageIdentity)) {
        _updateOutgoingDelivery(
          clientMessageId,
          ChatDeliveryState.synchronizing,
        );
      }
      return true;
    } on Object catch (error) {
      if (outbox.accepted(outgoing) ||
          _acceptedPhoneMessageIdentities.contains(messageIdentity)) {
        outbox.finish(outgoing, sent: true);
        return true;
      }
      final definitive =
          error is TsPhoneApiException &&
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
    if (_snapshotSyncInProgress ||
        _historyNavigationInProgress ||
        _viewingHistoryWindow) {
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
      final problem = describeTsPhoneProblem(error);
      if (problem.code == TsPhoneProblemCode.agentRunChanged) {
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
    _hasMoreHistory = false;
    _nextBefore = null;
    _nextAfter = null;
    _hasLaterHistory = false;
    _viewingHistoryWindow = false;
    _loadedEarlierHistory = false;
    _timelineHistory = null;
    _selectedBranchId = null;
    _latestTimelineItemIds = const <String>[];
    _snapshotReady = false;
    _activeAgentRunId = null;
    _setRuntimeState(RuntimeState.connecting);
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

  static bool _isTransientTransportError(Object error) {
    final problem = describeTsPhoneProblem(error);
    return const {
      TsPhoneProblemCode.connectionFailed,
      TsPhoneProblemCode.requestTimeout,
      TsPhoneProblemCode.serviceUnavailable,
      TsPhoneProblemCode.sessionOffline,
      TsPhoneProblemCode.networkRetrying,
    }.contains(problem.code);
  }

  void _handleEvent(TsPhoneEvent event) {
    final payload = _asMap(event.payload);
    if (_isLiveContentEvent(event.type) &&
        (viewingInactiveBranch ||
            ((_viewingHistoryWindow || _historyNavigationInProgress) &&
                event.type != 'approval.request'))) {
      return;
    }
    var deferStreamRender = false;
    var flushStreamRender = false;
    var notifyController = true;
    switch (event.type) {
      case 'session_state':
        _promptProblem = payload?['promptProblem'] as String?;
        final previous = _runtimeState;
        late final RuntimeState nextState;
        try {
          nextState = RuntimeState.parse(payload?['state']);
        } on FormatException {
          nextState = RuntimeState.recoveryRequired;
        }
        _applyRunState(
          nextState,
          payload?['activeAgentRunId'],
          source: 'session_state',
        );
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
        _promptProblem = payload?['promptProblem'] as String?;
        final messages = payload?['messages'];
        if (messages is List &&
            !usesStructuredTimeline &&
            !_viewingHistoryWindow &&
            !_historyNavigationInProgress) {
          try {
            _applyMessageSnapshot(
              TsPhoneMessageSnapshot(
                sessionId: sessionId,
                sessionRevision: _sessionRevision,
                activeAgentRunId: payload?['activeAgentRunId'] as String?,
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
        _applyRunState(
          payload?['runtimeState'] is String
              ? RuntimeState.parse(payload?['runtimeState'])
              : payload?['isStreaming'] == true
              ? RuntimeState.running
              : RuntimeState.idle,
          payload?['activeAgentRunId'],
          source: 'session.snapshot',
        );
        if (payload?['isStreaming'] == true) {
          final streamingMessage = payload?['streamingMessage'];
          if (streamingMessage is Map) {
            final parsed = ChatMessage.fromJson(streamingMessage);
            if (parsed.role == ChatRole.assistant) {
              _replaceStreamingText(parsed.text);
            }
          }
        } else {
          _clearStreamingText();
        }
        if (payload?['historyAvailable'] is bool) {
          _historyAvailable = payload!['historyAvailable']! as bool;
        }
        _updateCapabilities(payload?['capabilities']);
        _operationProblem = null;
        _applyRuntimeError(payload?['runtimeError']);
        _updateSessionRuntime(payload?['runtime']);
        _updateAccessMode(payload?['accessMode']);
        _canPrompt = payload?['canPrompt'] is bool
            ? payload!['canPrompt']! as bool
            : true;
        _snapshotReady = true;
        if (usesStructuredTimeline &&
            !_viewingHistoryWindow &&
            !_historyNavigationInProgress) {
          unawaited(refreshMessages());
        }
      case 'input':
        final text = payload?['text'];
        if (text is String && text.isNotEmpty) {
          _applyInputEvent(event, payload!, text);
        }
      case 'runtime.error':
        _setError(
          TsPhoneApiException(
            'Pi runtime error',
            code: payload?['code'] as String?,
          ),
        );
      case 'agent_start':
        _applyRunState(
          RuntimeState.running,
          payload?['agentRunId'],
          source: 'agent_start',
        );
      case 'agent_settled':
        final settledRunId = _requireAgentRunId(
          payload?['agentRunId'],
          'agent_settled',
        );
        if (_activeAgentRunId != null && _activeAgentRunId != settledRunId) {
          throw const FormatException(
            'agent_settled belongs to another agent run',
          );
        }
        _activeAgentRunId = null;
        _setRuntimeState(RuntimeState.idle);
        _clearStreamingText();
        _activity = null;
        if (usesStructuredTimeline &&
            !_viewingHistoryWindow &&
            !_historyNavigationInProgress) {
          unawaited(refreshMessages());
        }
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
      outbox.receive(
        event.sessionRevision,
        clientMessageId!,
        preflightAccepted: payload['preflightAccepted'] == true,
      );
      if (payload['preflightAccepted'] == true) {
        _acceptedPhoneMessageIdentities.add(identity);
        while (_acceptedPhoneMessageIdentities.length > 200) {
          _acceptedPhoneMessageIdentities.remove(
            _acceptedPhoneMessageIdentities.first,
          );
        }
      }
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

  void _removePendingOutgoing(
    String clientMessageId, {
    bool includeReceived = false,
  }) {
    if (usesStructuredTimeline) {
      _setTimelineItems(
        _timelineItems
            .where(
              (item) =>
                  item is! TimelineMessageItem ||
                  item.message.clientMessageId != clientMessageId ||
                  (!includeReceived && item.message.deliveryState == null),
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
          (includeReceived || message.deliveryState != null)) {
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
    outbox.reconcile(
      snapshot.sessionRevision,
      snapshot.items.whereType<TimelineMessageItem>().map(
        (value) => value.message,
      ),
    );
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
    _hasLaterHistory = snapshot.hasLater;
    _nextAfter = snapshot.nextAfter;
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
    _syncOutbox();
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
      if (!item.message.hasVisibleContent) continue;
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
    outbox.reconcile(snapshot.sessionRevision, parsed.messages);
    _hasLaterHistory = snapshot.hasLater;
    _nextAfter = snapshot.nextAfter;
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
    _syncOutbox();
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
        if (message.hasVisibleContent) {
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
    _operationProblem = describeTsPhoneProblem(
      TsPhoneApiException(message, code: code, statusCode: statusCode),
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
