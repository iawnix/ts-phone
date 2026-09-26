import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ts_phone/theme/app_icons.dart';
import 'package:flutter/rendering.dart'
    show RenderBox, ScrollCacheExtent, ScrollDirection;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/host_gateway.dart';
import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/chat_message.dart';
import '../../models/connection_settings.dart';
import '../../models/session_timeline.dart';
import '../../models/workspace.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/chat_message_view.dart';
import '../../widgets/presentation.dart';
import 'approval_panel.dart';
import 'chat_controller.dart';
import 'chat_composer.dart';
import 'chat_view_memory.dart';
import 'live_run_strip.dart';
import 'session_notice.dart';
import 'session_view_state.dart';
import 'timeline_widgets.dart';
import 'model_picker.dart';

enum _ChatScrollMode { following, reading }

const double _jumpToStartThreshold = 160;
const double _chatToolbarHeight = 62;

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.settings,
    required this.workspace,
    required this.session,
    this.recoveredSession = false,
    this.gateway,
    this.gatewayFactory,
    this.memory,
    this.onOpenContext,
    this.onOpenNavigation,
    this.onOpenSession,
    this.embedded = false,
  });

  final ConnectionSettings settings;
  final WorkspaceSummary workspace;
  final SessionSummary session;
  final bool recoveredSession;
  final TsPhoneGateway? gateway;
  final TsPhoneGateway Function()? gatewayFactory;
  final ChatViewMemory? memory;

  /// Opens the compact project/session context switcher on narrow layouts.
  ///
  /// [onOpenNavigation] remains available for callers that still expose the
  /// session drawer. When both callbacks are supplied, this one takes
  /// precedence so the chat page does not need to know which navigation
  /// surface the host uses.
  final VoidCallback? onOpenContext;
  final VoidCallback? onOpenNavigation;
  final ValueChanged<SessionSummary>? onOpenSession;
  final bool embedded;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  late final ChatViewMemory _memory;
  late final ChatController _controller;
  late final StreamSubscription<ExtensionUiRequest> _uiSubscription;
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _timelineKey = GlobalKey(debugLabel: 'chat-timeline');
  final GlobalKey _bottomDockKey = GlobalKey(debugLabel: 'chat-bottom-dock');
  final Queue<ExtensionUiRequest> _pendingUiRequests =
      Queue<ExtensionUiRequest>();
  final ValueNotifier<bool> _streamUpdatesEnabled = ValueNotifier<bool>(true);
  _ChatScrollMode _scrollMode = _ChatScrollMode.following;
  bool _scrollUpdateScheduled = false;
  bool _scrollingToStart = false;
  bool _scrollingToLatest = false;
  bool _preservingReadingPosition = false;
  int _navigationGeneration = 0;
  bool _showJumpToStart = false;
  bool _showJumpToLatest = false;
  bool _drainingUiRequests = false;
  bool _approvalDeferred = false;
  bool _syncing = false;
  bool _sending = false;
  bool _aborting = false;
  bool _abortConfirmationOpen = false;
  bool _hasDraft = false;
  TimelineViewFilter _timelineFilter = TimelineViewFilter.all;
  bool _initialTimelinePositioned = false;
  bool _bottomDockMeasureScheduled = false;
  double _bottomDockHeight = 72;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _memory = widget.memory ?? ChatViewMemory();
    _controller = ChatController(
      api:
          widget.gateway ??
          widget.gatewayFactory?.call() ??
          HostGateway(widget.settings),
      workspaceId: widget.workspace.id,
      sessionId: widget.session.sessionId,
      initialSession: widget.session,
      initialSessionRevision: widget.session.sessionRevision,
      initialSessionTitle: widget.session.sessionName,
      initialSessionRuntime: widget.session.runtime,
      initialPromptProblem: widget.session.promptProblem,
      initialActiveAgentRunId: widget.session.activeAgentRunId,
      initialRuntimeState: widget.session.runtimeState,
      accessMode: widget.session.accessMode,
      initialHistoryAvailable: widget.session.historyAvailable,
      initialCanPrompt: widget.session.canPrompt,
      initialCapabilities: widget.session.capabilities,
      recoveredSession: widget.recoveredSession,
      initialPreview: widget.memory?.preview,
      outbox: _memory.outbox,
    )..addListener(_onControllerUpdate);
    _controller.streamingTextUpdates.addListener(_onStreamingTextUpdate);
    _uiSubscription = _controller.uiRequests.listen(_queueUiRequest);
    _composer.text = _memory.draft;
    _hasDraft = _composer.text.trim().isNotEmpty;
    if (widget.memory?.preview?.revision == widget.session.sessionRevision &&
        widget.memory?.following == false) {
      _scrollMode = _ChatScrollMode.reading;
      _streamUpdatesEnabled.value = false;
    }
    _composer.addListener(_onComposerChanged);
    _memory.addListener(_onDraftChanged);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _memory.removeListener(_onDraftChanged);
    final memory = widget.memory;
    if (memory != null) {
      memory.draft = _composer.text;
      final preview = _controller.historyPreview;
      memory.preview = preview.isBounded ? preview : null;
      memory.following =
          memory.preview == null || _scrollMode == _ChatScrollMode.following;
      memory.scrollOffset = _scroll.hasClients ? _scroll.offset : 0;
    }
    WidgetsBinding.instance.removeObserver(this);
    _controller.streamingTextUpdates.removeListener(_onStreamingTextUpdate);
    _controller
      ..removeListener(_onControllerUpdate)
      ..dispose();
    unawaited(_uiSubscription.cancel());
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    _streamUpdatesEnabled.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _controller.resumeEventStream();
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _controller.suspendEventStream();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onControllerUpdate() {
    _scheduleScrollUpdate();
  }

  void _onStreamingTextUpdate() {
    if (_scrollMode == _ChatScrollMode.following) {
      _scheduleScrollUpdate();
    }
  }

  void _setScrollMode(_ChatScrollMode mode) {
    _scrollMode = mode;
    final updatesEnabled = mode == _ChatScrollMode.following;
    if (_streamUpdatesEnabled.value != updatesEnabled) {
      _streamUpdatesEnabled.value = updatesEnabled;
    }
  }

  void _scheduleScrollUpdate() {
    if (_scrollUpdateScheduled) return;
    _scrollUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollUpdateScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (!_initialTimelinePositioned &&
          _scrollMode == _ChatScrollMode.reading &&
          widget.memory?.preview != null) {
        _scroll.jumpTo(
          widget.memory!.scrollOffset.clamp(0, position.maxScrollExtent),
        );
      }
      if (_scrollMode == _ChatScrollMode.following &&
          !_scrollingToLatest &&
          !position.isScrollingNotifier.value) {
        final target = position.maxScrollExtent;
        if ((target - position.pixels).abs() > 0.5) {
          _scroll.jumpTo(target);
        }
      }
      if (!_initialTimelinePositioned &&
          (_controller.messages.isNotEmpty ||
              _controller.timelineItems.isNotEmpty ||
              _controller.hasStreamingText)) {
        // A structured timeline can change its extent once the grouped
        // activity rows finish laying out. Re-check on the next frame so a
        // first-frame jump cannot leave the controller beyond the new tail.
        Future<void>.microtask(() {
          if (!mounted || !_scroll.hasClients || _initialTimelinePositioned) {
            return;
          }
          final current = _scroll.position;
          if (_scrollMode == _ChatScrollMode.following &&
              !_scrollingToLatest &&
              !current.isScrollingNotifier.value) {
            final target = current.maxScrollExtent;
            if ((target - current.pixels).abs() > 0.5) {
              current.jumpTo(target);
            }
          }
          if (!_initialTimelinePositioned &&
              (_controller.messages.isNotEmpty ||
                  _controller.timelineItems.isNotEmpty ||
                  _controller.hasStreamingText)) {
            setState(() => _initialTimelinePositioned = true);
          }
        });
      }
      _updateTimelineNavigationVisibility(position);
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final userStarted =
        notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final userScrolling =
        notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    if (userStarted ||
        (userScrolling && !_scrollingToStart && !_scrollingToLatest)) {
      _setScrollMode(_ChatScrollMode.reading);
    }

    final userStopped =
        notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle);
    if (userStopped &&
        _isAtTail(notification.metrics) &&
        !_controller.viewingHistoryWindow &&
        !_scrollingToStart) {
      _setScrollMode(_ChatScrollMode.following);
    }
    if ((userScrolling || userStopped) &&
        !_scrollingToStart &&
        !_scrollingToLatest &&
        !_preservingReadingPosition &&
        notification.metrics.extentBefore <= 48 &&
        _controller.canLoadEarlierMessages) {
      unawaited(_loadEarlierMessages());
    }
    _updateTimelineNavigationVisibility(notification.metrics);
    return false;
  }

  bool _handleScrollMetricsNotification(
    ScrollMetricsNotification notification,
  ) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        _scrollMode != _ChatScrollMode.following ||
        _scrollingToLatest ||
        !_scroll.hasClients) {
      return false;
    }
    final position = _scroll.position;
    if ((position.pixels - position.maxScrollExtent).abs() <= 0.5) {
      return false;
    }
    Future<void>.microtask(() {
      if (!mounted ||
          !_scroll.hasClients ||
          _scrollMode != _ChatScrollMode.following ||
          _scrollingToLatest) {
        return;
      }
      final current = _scroll.position;
      if ((current.pixels - current.maxScrollExtent).abs() > 0.5) {
        current.jumpTo(current.maxScrollExtent);
      }
    });
    return false;
  }

  bool _isAtTail(ScrollMetrics metrics) => metrics.extentAfter <= 24;

  void _updateTimelineNavigationVisibility(ScrollMetrics metrics) {
    final showStart =
        metrics.extentBefore > _jumpToStartThreshold ||
        _controller.canLoadEarlierMessages;
    final showLatest =
        _controller.viewingHistoryWindow ||
        (_scrollMode == _ChatScrollMode.reading && !_isAtTail(metrics));
    if (!mounted ||
        (showStart == _showJumpToStart && showLatest == _showJumpToLatest)) {
      return;
    }
    setState(() {
      _showJumpToStart = showStart;
      _showJumpToLatest = showLatest;
    });
  }

  void _resumeTailFollow() {
    _setScrollMode(_ChatScrollMode.following);
    if (_showJumpToLatest && mounted) {
      setState(() => _showJumpToLatest = false);
    }
    _scheduleScrollUpdate();
  }

  Future<void> _jumpToLatest() async {
    if (_scrollingToLatest) return;
    final needsTailRead =
        _controller.viewingHistoryWindow ||
        _controller.historyNavigationInProgress ||
        _controller.loadingEarlierMessages;
    final generation = ++_navigationGeneration;
    ActionFeedback.selection();
    setState(() {
      _showJumpToLatest = true;
      _scrollingToLatest = true;
      _scrollingToStart = false;
      _preservingReadingPosition = false;
    });
    try {
      final loaded = !needsTailRead || await _controller.returnToLatest();
      if (!mounted || generation != _navigationGeneration) return;
      if (!loaded) {
        _showActionMessage(
          _controller.problem?.localizedMessage(context.l10n) ??
              context.l10n.problemRequestFailed,
        );
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _navigationGeneration) return;
      _setScrollMode(_ChatScrollMode.following);
      if (_scroll.hasClients) {
        final target = _scroll.position.maxScrollExtent;
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(target);
        } else {
          await _scroll.animateTo(
            target,
            duration: TsPhoneMotion.standard,
            curve: Curves.easeOut,
          );
        }
      }
    } finally {
      if (mounted && generation == _navigationGeneration) {
        setState(() => _scrollingToLatest = false);
        if (_scroll.hasClients) {
          _updateTimelineNavigationVisibility(_scroll.position);
        }
        if (_scrollMode == _ChatScrollMode.following) {
          _scheduleScrollUpdate();
        }
      }
    }
  }

  Future<void> _jumpToStart() async {
    if (_scrollingToStart || _scrollingToLatest || _preservingReadingPosition) {
      return;
    }
    ActionFeedback.selection();
    final generation = ++_navigationGeneration;
    _setScrollMode(_ChatScrollMode.reading);
    setState(() {
      _showJumpToStart = false;
      _scrollingToStart = true;
    });
    try {
      if (!await _controller.jumpToStart() ||
          !mounted ||
          generation != _navigationGeneration) {
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _navigationGeneration) return;
      if (_scroll.hasClients) {
        final target = _scroll.position.minScrollExtent;
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(target);
        } else {
          await _scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      }
    } finally {
      if (mounted && generation == _navigationGeneration) {
        setState(() => _scrollingToStart = false);
        if (_scroll.hasClients) {
          _updateTimelineNavigationVisibility(_scroll.position);
        }
      }
    }
  }

  Future<void> _loadEarlierMessages() async {
    if (!_controller.canLoadEarlierMessages) return;
    await _preserveReadingPosition(_controller.loadEarlierMessages);
  }

  Future<void> _loadAllHistory() async {
    if (!_controller.canLoadEarlierMessages || _controller.loadingAllHistory) {
      return;
    }
    await _preserveReadingPosition(_controller.loadAllHistory);
  }

  Iterable<({Key key, Rect rect})> _laidOutHistoryRows() sync* {
    final root = _timelineKey.currentContext;
    if (root is! Element) return;
    final rows = <({Key key, Rect rect})>[];
    void visit(Element element) {
      final key = element.widget.key;
      if (key != null &&
          (element.widget is ChatMessageView ||
              element.widget is TimelineActivityView)) {
        final box = element.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          rows.add((key: key, rect: box.localToGlobal(Offset.zero) & box.size));
        }
        return;
      }
      element.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    yield* rows;
  }

  Future<void> _preserveReadingPosition(Future<void> Function() load) async {
    if (_preservingReadingPosition) return;
    final generation = _navigationGeneration;
    setState(() => _preservingReadingPosition = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _navigationGeneration) return;
      await _prependAtReadingPosition(load, generation);
    } finally {
      if (mounted && generation == _navigationGeneration) {
        setState(() => _preservingReadingPosition = false);
      }
    }
  }

  Future<void> _prependAtReadingPosition(
    Future<void> Function() load,
    int generation,
  ) async {
    _setScrollMode(_ChatScrollMode.reading);
    final oldPixels = _scroll.hasClients ? _scroll.position.pixels : null;
    final oldMaxExtent = _scroll.hasClients
        ? _scroll.position.maxScrollExtent
        : null;
    final viewport = _timelineKey.currentContext?.findRenderObject();
    final bounds = viewport is RenderBox && viewport.hasSize
        ? viewport.localToGlobal(Offset.zero) & viewport.size
        : Rect.zero;
    final anchor = _laidOutHistoryRows()
        .where((row) => row.rect.overlaps(bounds))
        .firstOrNull;
    await load();
    if (!mounted ||
        generation != _navigationGeneration ||
        !_scroll.hasClients ||
        _scroll.position.pixels != oldPixels) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        generation != _navigationGeneration ||
        !_scroll.hasClients ||
        oldPixels == null ||
        oldMaxExtent == null) {
      return;
    }
    final addedExtent = _scroll.position.maxScrollExtent - oldMaxExtent;
    _scroll.jumpTo(
      (oldPixels + addedExtent).clamp(
        _scroll.position.minScrollExtent,
        _scroll.position.maxScrollExtent,
      ),
    );
    // Lazy lists estimate their total extent. Correct against the same visible
    // message after the coarse jump has laid out its new position.
    if (anchor != null) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !_scroll.hasClients ||
          generation != _navigationGeneration) {
        return;
      }
      final current = _laidOutHistoryRows()
          .where((row) => row.key == anchor.key)
          .firstOrNull;
      if (current != null) {
        _scroll.jumpTo(
          (_scroll.offset + current.rect.top - anchor.rect.top).clamp(
            _scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    }
    _updateTimelineNavigationVisibility(_scroll.position);
  }

  Future<void> _selectTimelineBranch(String branchId) async {
    ActionFeedback.selection();
    await _controller.selectTimelineBranch(branchId);
    if (!mounted) return;
    _resumeTailFollow();
  }

  void _onComposerChanged() {
    _memory.draft = _composer.text;
    final hasDraft = _composer.text.trim().isNotEmpty;
    if (hasDraft != _hasDraft && mounted) {
      setState(() => _hasDraft = hasDraft);
    }
  }

  void _onDraftChanged() {
    if (_composer.text == _memory.draft) return;
    _composer.value = TextEditingValue(
      text: _memory.draft,
      selection: TextSelection.collapsed(offset: _memory.draft.length),
    );
  }

  Future<void> _send({String? retryText}) async {
    if (_sending) return;
    final text = retryText ?? _composer.text;
    final clearedRevision = retryText == null || _memory.draft.isEmpty
        ? _memory.takeDraft()
        : null;
    ActionFeedback.tap();
    setState(() => _sending = true);
    try {
      final sent = await _controller.send(text);
      if (!sent &&
          clearedRevision != null &&
          _memory.outbox.uncertain(text.trim()) == null) {
        _memory.restoreDraft(text, clearedRevision);
      }
      if (!mounted) return;
      if (sent) {
        _resumeTailFollow();
      } else {
        ActionFeedback.error();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sync() async {
    if (_syncing) return;
    ActionFeedback.tap();
    setState(() => _syncing = true);
    try {
      await _controller.refreshMessages();
      if (!mounted || _controller.problem != null) return;
      _showActionMessage(context.l10n.messagesSynced);
    } on Object catch (error) {
      if (mounted) {
        _showActionMessage(
          describeTsPhoneProblem(error).localizedMessage(context.l10n),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _abort({
    required String expectedSessionRevision,
    required String expectedAgentRunId,
  }) async {
    if (_aborting) return;
    ActionFeedback.warning();
    setState(() => _aborting = true);
    try {
      final requested = await _controller.abort(
        expectedSessionRevision: expectedSessionRevision,
        expectedAgentRunId: expectedAgentRunId,
      );
      if (!mounted) return;
      if (!requested) {
        if (_controller.problem == null) {
          _showActionMessage(context.l10n.abortTargetChanged);
        }
        return;
      }
      if (_controller.problem != null) return;
      _showActionMessage(context.l10n.abortRequested);
    } finally {
      if (mounted) setState(() => _aborting = false);
    }
  }

  Future<void> _confirmAbort() async {
    if (_aborting || _abortConfirmationOpen) return;
    final agentRunId = _controller.activeAgentRunId;
    if (agentRunId == null) return;
    _abortConfirmationOpen = true;
    final sessionRevision = _controller.sessionRevision;
    final colors = Theme.of(context).colorScheme;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        animationStyle: TsPhoneMotion.resolveAnimationStyle(context),
        builder: (dialogContext) => AlertDialog(
          icon: Icon(AppIcons.stop_circle_outlined, color: colors.error),
          title: Text(context.l10n.abortGeneration),
          content: Text(context.l10n.abortGenerationConfirmation),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.keepGenerating),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: Text(context.l10n.abortGeneration),
            ),
          ],
        ),
      );
      if (confirmed == true &&
          mounted &&
          _controller.sessionRevision == sessionRevision &&
          _controller.activeAgentRunId == agentRunId &&
          SessionViewState.fromController(_controller).canAbort) {
        await _abort(
          expectedSessionRevision: sessionRevision,
          expectedAgentRunId: agentRunId,
        );
      } else if (confirmed == true && mounted) {
        _showActionMessage(context.l10n.abortTargetChanged);
      }
    } finally {
      _abortConfirmationOpen = false;
    }
  }

  Future<void> _retryConnection() async {
    ActionFeedback.tap();
    await _controller.retryConnection();
  }

  void _showSessionStatus() {
    ActionFeedback.selection();
    final state = SessionViewState.fromController(_controller);
    final hasCachedContent =
        _controller.messages.isNotEmpty ||
        _controller.timelineItems.isNotEmpty ||
        _controller.hasStreamingText;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: TsPhoneMotion.resolveAnimationStyle(context),
      builder: (context) => _SessionStatusSheet(
        state: state,
        runtimeState: _controller.runtimeState,
        problem: _controller.problem,
        hasCachedContent: hasCachedContent,
        onRetry: () => unawaited(_retryConnection()),
      ),
    );
  }

  void _goBack() {
    ActionFeedback.selection();
    Navigator.of(context).maybePop();
  }

  void _openContextOrDetails() {
    final callback = widget.onOpenContext ?? widget.onOpenNavigation;
    if (callback != null) {
      ActionFeedback.selection();
      callback();
      return;
    }
    _showSessionDetails();
  }

  String get _navigationTitle {
    final sessionTitle = _controller.sessionTitle?.trim();
    if (sessionTitle?.isNotEmpty == true) return sessionTitle!;
    return widget.session.localizedDisplayName(context.l10n);
  }

  void _showActionMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            TsPhoneSpacing.medium,
            0,
            TsPhoneSpacing.medium,
            _bottomDockHeight + TsPhoneSpacing.small,
          ),
        ),
      );
  }

  void _showSessionDetails() {
    ActionFeedback.selection();
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      sheetAnimationStyle: TsPhoneMotion.resolveAnimationStyle(context),
      builder: (context) => _SessionDetailsSheet(
        title: _navigationTitle,
        runtime: _controller.sessionRuntime,
        configuredModel: _controller.selectedModelReference,
        workspaceName: widget.workspace.name,
        runtimeState: _controller.runtimeState,
        sessionId: widget.session.sessionId,
      ),
    );
  }

  Future<void> _chooseModel() async {
    final gateway = _controller.modelGateway;
    if (gateway == null || !_controller.canSelectModel) {
      _showActionMessage(_modelSelectionHint);
      return;
    }
    final hadFocus = _composerFocus.hasFocus;
    final selection = _composer.selection;
    _composerFocus.unfocus();
    await showModelPicker(
      context,
      gateway: gateway,
      selected: _controller.selectedModelReference,
      onSelect: _controller.selectModel,
      canSelect: () => _controller.canSelectModel,
      state: _controller,
    );
    if (!mounted) return;
    _composer.selection = selection;
    if (hadFocus) _composerFocus.requestFocus();
  }

  String get _modelSelectionHint => _controller.canSelectModel
      ? context.l10n.chooseModel
      : _controller.runtimeState == RuntimeState.running ||
            _controller.commandInFlight
      ? context.l10n.modelSelectionBusy
      : context.l10n.modelSelectionUnavailable;

  void _queueUiRequest(ExtensionUiRequest request) {
    _pendingUiRequests.add(request);
    if (_approvalDeferred) {
      setState(() {});
    } else {
      unawaited(_drainUiRequests());
    }
  }

  Future<void> _drainUiRequests() async {
    if (_drainingUiRequests) return;
    setState(() => _approvalDeferred = false);
    _drainingUiRequests = true;
    try {
      while (mounted && _pendingUiRequests.isNotEmpty) {
        final request = _pendingUiRequests.removeFirst();
        if (!request.expiresAt.isAfter(DateTime.now())) {
          _showActionMessage(context.l10n.approvalExpired);
          continue;
        }
        if (request.sessionRevision != _controller.sessionRevision) {
          _showActionMessage(context.l10n.approvalStale);
          continue;
        }
        if (!mounted) return;
        final outcome = await showApprovalPanel(
          context: context,
          request: request,
          controller: _controller,
          workspaceName: widget.workspace.name,
          sessionName:
              _controller.sessionTitle ??
              widget.session.localizedDisplayName(context.l10n),
          accessMode: _controller.accessMode,
          queuedAfter: _pendingUiRequests.length,
        );
        if (!mounted) return;
        switch (outcome) {
          case ApprovalPanelOutcome.deferred:
            _pendingUiRequests.addFirst(request);
            setState(() => _approvalDeferred = true);
            return;
          case ApprovalPanelOutcome.expired:
            _showActionMessage(context.l10n.approvalExpired);
          case ApprovalPanelOutcome.stale:
            _showActionMessage(context.l10n.approvalStale);
          case ApprovalPanelOutcome.missing:
            _showActionMessage(context.l10n.approvalMissing);
          case ApprovalPanelOutcome.approved ||
              ApprovalPanelOutcome.rejected ||
              null:
            break;
        }
      }
    } finally {
      _drainingUiRequests = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedBuilder(
      animation: _controller,
      child: _buildMessages(),
      builder: (context, child) {
        final viewState = SessionViewState.fromController(_controller);
        return Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: TsGlassAppBar(
            toolbarHeight: _chatToolbarHeight,
            centerTitle: false,
            titleSpacing: 0,
            automaticallyImplyLeading: false,
            leading: BackButton(
              key: const ValueKey<String>('chat-back'),
              onPressed: _goBack,
            ),
            title: Row(
              children: <Widget>[
                Expanded(
                  child: TsPressable(
                    key: const ValueKey('chat-session-details'),
                    onTap: _openContextOrDetails,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _ChatNavigationTitle(
                            title: _navigationTitle,
                            workspace: widget.workspace.name,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsetsDirectional.only(start: 4, end: 8),
                          child: Icon(
                            widget.onOpenContext != null ||
                                    widget.onOpenNavigation != null
                                ? AppIcons.unfold_more_rounded
                                : AppIcons.info_outline_rounded,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _SessionStatusButton(
                  state: viewState,
                  runtimeState: _controller.runtimeState,
                  onPressed: _showSessionStatus,
                ),
                const SizedBox(width: 2),
              ],
            ),
            actions: <Widget>[
              PopupMenuButton<String>(
                key: const ValueKey('chat-menu'),
                tooltip: l10n.moreActions,
                icon: const Icon(AppIcons.more_horiz_rounded),
                onSelected: (action) {
                  if (action == 'start') {
                    unawaited(_jumpToStart());
                  } else if (action == 'sync') {
                    unawaited(_sync());
                  } else if (action == 'sidebar') {
                    _openContextOrDetails();
                  } else {
                    _showSessionDetails();
                  }
                },
                itemBuilder: (_) => [
                  if (widget.onOpenContext != null ||
                      widget.onOpenNavigation != null)
                    PopupMenuItem(
                      key: const ValueKey('chat-open-sidebar'),
                      value: 'sidebar',
                      child: Row(
                        children: [
                          const Icon(AppIcons.view_sidebar_outlined, size: 20),
                          const SizedBox(width: 12),
                          Flexible(child: Text(l10n.openSidebar)),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    key: const ValueKey('chat-sync'),
                    value: 'sync',
                    enabled:
                        viewState.canRefresh &&
                        !_syncing &&
                        !_controller.commandInFlight,
                    child: Row(
                      children: [
                        const Icon(AppIcons.sync, size: 20),
                        const SizedBox(width: 12),
                        Flexible(child: Text(l10n.syncMessages)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'start',
                    enabled:
                        (_showJumpToStart ||
                            _controller.canLoadEarlierMessages) &&
                        !_controller.historyNavigationInProgress &&
                        !_preservingReadingPosition,
                    child: Row(
                      children: [
                        const Icon(AppIcons.vertical_align_top, size: 20),
                        const SizedBox(width: 12),
                        Flexible(child: Text(l10n.jumpToStart)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: TsPageBackdrop(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  child!,
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomDock(
                      context,
                      viewState,
                      availableHeight: constraints.maxHeight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessages() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final showNotice =
            _controller.messages.isNotEmpty ||
            _controller.timelineItems.isNotEmpty ||
            _controller.hasStreamingText;
        return _buildMessagesForState(
          _MessageTimeline(
            key: _timelineKey,
            controller: _controller,
            messagesListenable: _controller.messagesUpdates,
            streamingTextListenable: _controller.streamingTextUpdates,
            streamUpdatesEnabledListenable: _streamUpdatesEnabled,
            scrollController: _scroll,
            onScrollNotification: _handleScrollNotification,
            onScrollMetricsNotification: _handleScrollMetricsNotification,
            onLoadEarlier: _loadEarlierMessages,
            onLoadAll: _loadAllHistory,
            onSelectBranch: _selectTimelineBranch,
            filter: _timelineFilter,
            onFilterChanged: (value) {
              if (_timelineFilter == value) return;
              setState(() => _timelineFilter = value);
            },
            header: showNotice ? _priorityBanner() : null,
            bottomContentInset: _bottomDockHeight,
          ),
        );
      },
    );
  }

  Widget _buildBottomDock(
    BuildContext context,
    SessionViewState viewState, {
    required double availableHeight,
  }) {
    _scheduleBottomDockMeasurement();
    final retry = _controller.outbox.messages
        .where((value) => value.state == ChatDeliveryState.uncertain)
        .firstOrNull;
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleBottomDockMeasurement();
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: Material(
          key: _bottomDockKey,
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_initialTimelinePositioned &&
                    _showJumpToLatest) ...<Widget>[
                  Align(
                    alignment: Alignment.centerRight,
                    child: _buildTimelineNavigation(),
                  ),
                  const SizedBox(height: TsPhoneSpacing.small),
                ],
                if (retry != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('retry-message'),
                      onPressed:
                          !_sending &&
                              _controller.canSend &&
                              !_controller.commandInFlight
                          ? () => _send(retryText: retry.text)
                          : null,
                      icon: const Icon(AppIcons.refresh_rounded, size: 20),
                      label: Text(context.l10n.retry),
                    ),
                  ),
                if (_approvalDeferred)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('pending-approvals'),
                      onPressed: _drainUiRequests,
                      icon: const Icon(
                        AppIcons.pending_actions_outlined,
                        size: 20,
                      ),
                      label: Text(context.l10n.pendingApprovals),
                    ),
                  ),
                if (!viewState.isHistorical)
                  _buildComposer(
                    context,
                    maxLines: _composerMaxLines(
                      context,
                      availableHeight: availableHeight,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _composerMaxLines(
    BuildContext context, {
    required double availableHeight,
  }) {
    if (!availableHeight.isFinite) return 5;
    final scaler = MediaQuery.textScalerOf(context);
    final scaledLineHeight = scaler.scale(16) * 1.45;
    final navigationReserve = _showJumpToLatest ? 52.0 : 0;
    // A multiline composer reserves its own action row below the text.
    final dockChrome =
        78.0 +
        MediaQuery.paddingOf(context).bottom.clamp(8, double.infinity) +
        (navigationReserve > 0 ? TsPhoneSpacing.small : 0);
    final lineBudget =
        availableHeight -
        navigationReserve -
        (_approvalDeferred ? 48 : 0) -
        (_controller.outbox.messages.any(
              (value) => value.state == ChatDeliveryState.uncertain,
            )
            ? 48
            : 0) -
        dockChrome;
    return (lineBudget / scaledLineHeight).floor().clamp(1, 5);
  }

  void _scheduleBottomDockMeasurement() {
    if (_bottomDockMeasureScheduled) return;
    _bottomDockMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomDockMeasureScheduled = false;
      if (!mounted) return;
      final renderObject = _bottomDockKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final height = renderObject.size.height;
      if ((height - _bottomDockHeight).abs() <= 0.5) return;
      setState(() => _bottomDockHeight = height);
    });
  }

  Widget _buildMessagesForState(Widget timeline) {
    final viewState = SessionViewState.fromController(_controller);
    final messages = _controller.messages;
    final hasTimelineItems =
        _controller.usesStructuredTimeline &&
        _controller.timelineItems.isNotEmpty;
    final hasStreaming = _controller.hasStreamingText;
    if (messages.isEmpty && !hasTimelineItems && !hasStreaming) {
      // Connection state belongs to the app-bar status control. Keeping the
      // conversation surface readable here means a reconnect never replaces
      // the user's cached transcript with a large error page.
      if (viewState.phase != SessionUiPhase.ready) {
        return const SizedBox.expand();
      }
      return const _EmptyConversationView();
    }
    final positioningInitialTimeline = !_initialTimelinePositioned;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        IgnorePointer(
          ignoring: positioningInitialTimeline,
          child: Opacity(
            key: const ValueKey<String>('initial-timeline-positioning'),
            opacity: positioningInitialTimeline ? 0 : 1,
            child: timeline,
          ),
        ),
        // The timeline can need one frame to settle after a cached snapshot.
        // Keep that layout pass invisible instead of showing a second sync
        // screen underneath the app-bar status control.
        if (positioningInitialTimeline) const SizedBox.expand(),
      ],
    );
  }

  Widget _buildTimelineNavigation() {
    final color = Theme.of(context).colorScheme.primary;
    final navigationBusy = _scrollingToLatest;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_showJumpToLatest || _scrollingToLatest)
            IconButton(
              key: const ValueKey<String>('jump-to-latest'),
              onPressed: navigationBusy ? null : _jumpToLatest,
              tooltip: context.l10n.jumpToLatest,
              color: color,
              icon: _scrollingToLatest
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.arrow_downward_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, {required int maxLines}) {
    final viewState = SessionViewState.fromController(_controller);
    final canDraft = !viewState.isHistorical;
    return ChatComposer(
      controller: _composer,
      focusNode: _composerFocus,
      canEdit: viewState.canCompose || canDraft,
      canSend: viewState.canCompose && !_sending && _hasDraft,
      sending: _sending,
      maxLines: maxLines,
      onSend: _send,
      hint: canDraft ? context.l10n.composerMessage : _composerHint(),
      modelLabel: _controller.selectedModelReference
          ?.split('/')
          .skip(1)
          .join('/'),
      modelHint: _modelSelectionHint,
      canSelectModel: _controller.canSelectModel,
      onSelectModel: _chooseModel,
      onAbort: viewState.canAbort ? _confirmAbort : null,
      aborting: _aborting,
    );
  }

  Widget? _priorityBanner() {
    if (_controller.messages.isEmpty &&
        _controller.timelineItems.isEmpty &&
        !_controller.hasStreamingText) {
      return null;
    }
    final state = SessionViewState.fromController(_controller);
    if (state.notice == SessionNoticeKind.offline ||
        _isTransportProblem(_controller.problem) ||
        _controller.hasFailedOutput) {
      return null;
    }
    return SessionNoticeView(
      state: state,
      problem: _controller.problem,
      onRetry: _retryConnection,
    );
  }

  String _composerHint() {
    final l10n = context.l10n;
    return switch (SessionViewState.fromController(_controller).phase) {
      SessionUiPhase.failed => l10n.composerReconnecting,
      SessionUiPhase.recovery => l10n.composerRecovery,
      SessionUiPhase.offline =>
        _controller.historyOnly ? l10n.composerHistory : l10n.composerOffline,
      SessionUiPhase.history => l10n.composerHistoricalBranch,
      SessionUiPhase.synchronizing => l10n.composerSynchronizing,
      SessionUiPhase.running => l10n.composerMessage,
      SessionUiPhase.reconnecting => l10n.composerReconnecting,
      SessionUiPhase.ready => l10n.composerMessage,
    };
  }
}

class _ChatNavigationTitle extends StatelessWidget {
  const _ChatNavigationTitle({required this.title, required this.workspace});

  final String title;
  final String workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                workspace,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ],
    );
  }
}

class _SessionStatusButton extends StatelessWidget {
  const _SessionStatusButton({
    required this.state,
    required this.runtimeState,
    required this.onPressed,
  });

  final SessionViewState state;
  final RuntimeState runtimeState;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final visual = _sessionStatusVisual(context, state);
    final label = _sessionStatusAccessibleLabel(context, state, runtimeState);
    return Semantics(
      key: const ValueKey('chat-session-status'),
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: IconButton(
          key: const ValueKey('chat-session-status-button'),
          onPressed: onPressed,
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: AnimatedSwitcher(
            duration: TsPhoneMotion.resolveFade(context, TsPhoneMotion.quick),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            child: _SessionStatusGlyph(
              key: ValueKey<SessionUiPhase>(state.phase),
              visual: visual,
              runtimeRunning: runtimeState == RuntimeState.running,
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionStatusGlyph extends StatelessWidget {
  const _SessionStatusGlyph({
    super.key,
    required this.visual,
    this.runtimeRunning = false,
  });

  final _SessionStatusVisual visual;
  final bool runtimeRunning;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 20,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          Icon(visual.icon, color: visual.color, size: 18),
          if (visual.pulsing)
            Positioned(
              right: -2,
              bottom: -1,
              child: TsStatusDot(color: visual.color, size: 6, pulsing: true),
            ),
          if (runtimeRunning &&
              visual.icon != AppIcons.motion_photos_on_outlined)
            Positioned(
              left: -2,
              top: -1,
              child: TsStatusDot(
                color: Theme.of(context).colorScheme.primary,
                size: 5,
                pulsing: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionStatusSheet extends StatelessWidget {
  const _SessionStatusSheet({
    required this.state,
    required this.runtimeState,
    required this.problem,
    required this.hasCachedContent,
    required this.onRetry,
  });

  final SessionViewState state;
  final RuntimeState runtimeState;
  final TsPhoneProblem? problem;
  final bool hasCachedContent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = _sessionStatusVisual(context, state);
    final l10n = context.l10n;
    final canRetry =
        state.phase != SessionUiPhase.ready &&
        state.phase != SessionUiPhase.running &&
        state.phase != SessionUiPhase.history;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        0,
        TsPhoneSpacing.large,
        TsPhoneSpacing.large + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _SessionStatusGlyph(
                visual: visual,
                runtimeRunning: runtimeState == RuntimeState.running,
              ),
              const SizedBox(width: TsPhoneSpacing.medium),
              Expanded(
                child: Text(
                  _sessionStatusLabel(context, state),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: TsPhoneSpacing.small),
          Text(
            runtimeState.localizedCompactLabel(l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (hasCachedContent) ...<Widget>[
            const SizedBox(height: TsPhoneSpacing.xSmall),
            Text(
              l10n.sessionRuntimeLastKnown,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (problem != null && !_isTransportProblem(problem)) ...<Widget>[
            const SizedBox(height: TsPhoneSpacing.small),
            Text(
              problem!.localizedMessage(l10n),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (canRetry) ...<Widget>[
            const SizedBox(height: TsPhoneSpacing.medium),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(AppIcons.refresh_rounded),
                label: Text(l10n.reconnect),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyConversationView extends StatelessWidget {
  const _EmptyConversationView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TsPhoneSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              AppIcons.chat_bubble_outline_rounded,
              size: 28,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: TsPhoneSpacing.small),
            Text(
              context.l10n.noMessages,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionStatusVisual {
  const _SessionStatusVisual({
    required this.icon,
    required this.color,
    this.pulsing = false,
  });

  final IconData icon;
  final Color color;
  final bool pulsing;
}

_SessionStatusVisual _sessionStatusVisual(
  BuildContext context,
  SessionViewState state,
) {
  final theme = Theme.of(context);
  final status = TsPhoneStatusTheme.resolve(context);
  return switch (state.phase) {
    SessionUiPhase.failed => _SessionStatusVisual(
      icon: AppIcons.error_outline_rounded,
      color: status.error,
    ),
    SessionUiPhase.recovery => _SessionStatusVisual(
      icon: AppIcons.restore_rounded,
      color: status.error,
    ),
    SessionUiPhase.history => _SessionStatusVisual(
      icon: AppIcons.history_rounded,
      color: theme.colorScheme.onSurfaceVariant,
    ),
    SessionUiPhase.offline => _SessionStatusVisual(
      icon: AppIcons.cloud_off_outlined,
      color: status.error,
    ),
    SessionUiPhase.synchronizing => _SessionStatusVisual(
      icon: AppIcons.cloud_sync_outlined,
      color: status.warning,
      pulsing: true,
    ),
    SessionUiPhase.reconnecting => _SessionStatusVisual(
      icon: AppIcons.refresh_rounded,
      color: status.warning,
      pulsing: true,
    ),
    SessionUiPhase.running => _SessionStatusVisual(
      icon: AppIcons.motion_photos_on_outlined,
      color: theme.colorScheme.primary,
      pulsing: true,
    ),
    SessionUiPhase.ready => _SessionStatusVisual(
      icon: AppIcons.check_circle_outline_rounded,
      color: status.connected,
    ),
  };
}

String _sessionStatusLabel(BuildContext context, SessionViewState state) {
  final l10n = context.l10n;
  return switch (state.phase) {
    SessionUiPhase.failed => l10n.chatFailed,
    SessionUiPhase.recovery => l10n.chatRecovery,
    SessionUiPhase.history => l10n.chatHistory,
    SessionUiPhase.offline => l10n.chatOffline,
    SessionUiPhase.synchronizing => l10n.chatConnecting,
    SessionUiPhase.reconnecting => l10n.chatReconnecting,
    SessionUiPhase.running => l10n.chatRunning,
    SessionUiPhase.ready => l10n.chatReady,
  };
}

String _sessionStatusAccessibleLabel(
  BuildContext context,
  SessionViewState state,
  RuntimeState runtimeState,
) =>
    '${_sessionStatusLabel(context, state)} · ${runtimeState.localizedCompactLabel(context.l10n)}';

bool _isTransportProblem(TsPhoneProblem? problem) =>
    problem?.code == TsPhoneProblemCode.serviceUnavailable ||
    problem?.code == TsPhoneProblemCode.connectionFailed ||
    problem?.code == TsPhoneProblemCode.requestTimeout ||
    problem?.code == TsPhoneProblemCode.networkRetrying ||
    problem?.code == TsPhoneProblemCode.sessionOffline;

class _SessionDetailsSheet extends StatelessWidget {
  const _SessionDetailsSheet({
    required this.title,
    required this.runtime,
    required this.workspaceName,
    required this.runtimeState,
    required this.sessionId,
    this.configuredModel,
  });

  final String title;
  final SessionRuntimeSnapshot? runtime;
  final String? configuredModel;
  final String workspaceName;
  final RuntimeState runtimeState;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final usage = runtime?.context;
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final used = usage?.usedTokens;
    final contextValue = usage == null
        ? null
        : '${used == null ? '—' : number.format(used)} / ${number.format(usage.limitTokens)}';
    final remaining = usage?.remainingTokens;
    final remainingPercent = usage?.percent == null
        ? null
        : (100 - usage!.percent!).clamp(0, 100).round();
    final remainingValue = usage == null
        ? null
        : remaining == null || remainingPercent == null
        ? l10n.sessionContextUnavailable
        : '${number.format(remaining)} · $remainingPercent%';
    final updated = runtime?.updatedAt.toLocal();
    final updatedValue = updated == null
        ? l10n.sessionContextUnavailable
        : [
            MaterialLocalizations.of(context).formatMediumDate(updated),
            MaterialLocalizations.of(
              context,
            ).formatTimeOfDay(TimeOfDay.fromDateTime(updated)),
          ].join(' · ');
    final lastKnown =
        runtime != null &&
        (runtimeState == RuntimeState.offline ||
            runtimeState == RuntimeState.recoveryRequired);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        0,
        TsPhoneSpacing.large,
        TsPhoneSpacing.large + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (lastKnown) ...<Widget>[
            const SizedBox(height: TsPhoneSpacing.small),
            Text(
              l10n.sessionRuntimeLastKnown,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: TsPhoneSpacing.medium),
          if (runtime == null && configuredModel != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TsPhoneSpacing.medium,
              ),
              child: _RuntimeDetailRow(
                icon: AppIcons.tune_rounded,
                label: l10n.sessionConfiguredModel,
                value: configuredModel!,
              ),
            ),
          Padding(
            key: const ValueKey<String>('session-identity-group'),
            padding: const EdgeInsets.symmetric(
              horizontal: TsPhoneSpacing.medium,
            ),
            child: Column(
              children: <Widget>[
                _RuntimeDetailRow(
                  icon: AppIcons.folder_outlined,
                  label: l10n.approvalWorkspace,
                  value: workspaceName,
                ),
              ],
            ),
          ),
          const SizedBox(height: TsPhoneSpacing.medium),
          if (runtime == null)
            Padding(
              key: const ValueKey<String>('session-runtime-unavailable'),
              padding: const EdgeInsets.all(TsPhoneSpacing.medium),
              child: _RuntimeUnavailableNote(
                message: l10n.sessionRuntimeUnavailable,
              ),
            )
          else
            Padding(
              key: const ValueKey<String>('session-runtime-group'),
              padding: const EdgeInsets.symmetric(
                horizontal: TsPhoneSpacing.medium,
              ),
              child: Column(
                children: <Widget>[
                  _RuntimeDetailRow(
                    icon: AppIcons.smart_toy_outlined,
                    label: lastKnown
                        ? l10n.sessionLastModel
                        : l10n.sessionModel,
                    value: runtime!.model.knownId ?? l10n.dataNotProvided,
                  ),
                  const _RuntimeDetailDivider(),
                  _RuntimeDetailRow(
                    icon: AppIcons.route_outlined,
                    label: l10n.sessionProvider,
                    value: runtime!.model.knownProvider ?? l10n.dataNotProvided,
                  ),
                  if (usage != null) ...<Widget>[
                    const _RuntimeDetailDivider(),
                    _RuntimeDetailRow(
                      icon: AppIcons.data_usage_rounded,
                      label: l10n.sessionContextWindow,
                      value: contextValue!,
                    ),
                    const _RuntimeDetailDivider(),
                    _RuntimeDetailRow(
                      icon: AppIcons.battery_5_bar_rounded,
                      label: l10n.sessionContextRemaining,
                      value: remainingValue!,
                    ),
                    const _RuntimeDetailDivider(),
                    _RuntimeDetailRow(
                      icon: AppIcons.calculate_outlined,
                      label: l10n.sessionContextSource,
                      value: l10n.sessionContextEstimate,
                    ),
                  ],
                  const _RuntimeDetailDivider(),
                  _RuntimeDetailRow(
                    icon: AppIcons.schedule_rounded,
                    label: l10n.sessionRuntimeUpdated,
                    value: updatedValue,
                  ),
                ],
              ),
            ),
          ExpansionTile(
            key: const ValueKey('session-technical-details'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: const Border(),
            collapsedShape: const Border(),
            expansionAnimationStyle: AnimationStyle(
              duration: TsPhoneMotion.resolve(context, TsPhoneMotion.standard),
              reverseDuration: TsPhoneMotion.resolve(
                context,
                TsPhoneMotion.quick,
              ),
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeOutCubic,
            ),
            title: Text(
              l10n.technicalDetails,
              style: theme.textTheme.bodyMedium,
            ),
            children: [
              _RuntimeDetailRow(
                icon: AppIcons.tag,
                label: l10n.approvalSession,
                value: sessionId,
                forceStacked: true,
                trailing: _CopySessionIdButton(sessionId: sessionId),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CopySessionIdButton extends StatefulWidget {
  const _CopySessionIdButton({required this.sessionId});

  final String sessionId;

  @override
  State<_CopySessionIdButton> createState() => _CopySessionIdButtonState();
}

class _CopySessionIdButtonState extends State<_CopySessionIdButton> {
  bool _copied = false;

  Future<void> _copy() async {
    ActionFeedback.tap();
    try {
      await Clipboard.setData(ClipboardData(text: widget.sessionId));
      if (mounted) setState(() => _copied = true);
    } on Object {
      if (!mounted) return;
      ActionFeedback.error();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.copySessionIdFailed),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey<String>('copy-session-id'),
      onPressed: _copy,
      tooltip: _copied
          ? context.l10n.sessionIdCopied
          : context.l10n.copySessionId,
      color: _copied ? Theme.of(context).colorScheme.primary : null,
      icon: AnimatedSwitcher(
        duration: TsPhoneMotion.resolveFade(context, TsPhoneMotion.quick),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: Icon(
          _copied ? AppIcons.check_rounded : AppIcons.copy_rounded,
          key: ValueKey<bool>(_copied),
          size: 18,
        ),
      ),
    );
  }
}

class _RuntimeUnavailableNote extends StatelessWidget {
  const _RuntimeUnavailableNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TsPhoneSpacing.small),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            AppIcons.history_toggle_off_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: TsPhoneSpacing.medium),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeDetailRow extends StatelessWidget {
  const _RuntimeDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.forceStacked = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final bool forceStacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stacked =
        forceStacked || MediaQuery.textScalerOf(context).scale(14) > 19;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TsPhoneSpacing.xSmall),
      child: Row(
        crossAxisAlignment: stacked
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: stacked ? 2 : 0),
            child: Icon(
              icon,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: TsPhoneSpacing.small),
          Expanded(
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(label, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: TsPhoneSpacing.xSmall),
                      TsMonoText(value, style: theme.textTheme.bodySmall),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(label, style: theme.textTheme.bodyMedium),
                      ),
                      const SizedBox(width: TsPhoneSpacing.medium),
                      Flexible(
                        child: TsMonoText(
                          value,
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
          ),
          if (trailing case final action?) ...<Widget>[
            const SizedBox(width: TsPhoneSpacing.xSmall),
            action,
          ],
        ],
      ),
    );
  }
}

class _RuntimeDetailDivider extends StatelessWidget {
  const _RuntimeDetailDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(indent: 25);
  }
}

class _MessageTimeline extends StatelessWidget {
  const _MessageTimeline({
    super.key,
    required this.controller,
    required this.messagesListenable,
    required this.streamingTextListenable,
    required this.streamUpdatesEnabledListenable,
    required this.scrollController,
    required this.onScrollNotification,
    required this.onScrollMetricsNotification,
    required this.onLoadEarlier,
    required this.onLoadAll,
    required this.onSelectBranch,
    required this.filter,
    required this.onFilterChanged,
    required this.bottomContentInset,
    this.header,
  });

  final ChatController controller;
  final ValueListenable<List<ChatMessage>> messagesListenable;
  final ValueListenable<String?> streamingTextListenable;
  final ValueListenable<bool> streamUpdatesEnabledListenable;
  final ScrollController scrollController;
  final NotificationListenerCallback<ScrollNotification> onScrollNotification;
  final NotificationListenerCallback<ScrollMetricsNotification>
  onScrollMetricsNotification;
  final Future<void> Function() onLoadEarlier;
  final Future<void> Function() onLoadAll;
  final Future<void> Function(String branchId) onSelectBranch;
  final TimelineViewFilter filter;
  final ValueChanged<TimelineViewFilter> onFilterChanged;
  final double bottomContentInset;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => controller.usesStructuredTimeline
          ? _buildStructuredTimeline(context)
          : _buildMessageTimeline(context),
    );
  }

  Widget _buildMessageTimeline(BuildContext context) {
    return ValueListenableBuilder<List<ChatMessage>>(
      valueListenable: messagesListenable,
      builder: (context, messages, _) {
        final showEarlier =
            controller.canLoadEarlierMessages ||
            controller.loadingEarlierMessages;
        final historyOffset = showEarlier ? 1 : 0;
        return _list(
          context: context,
          itemCount: messages.length + 1 + historyOffset,
          itemBuilder: (context, index) {
            if (showEarlier && index == 0) {
              return _EarlierMessagesControl(
                visible:
                    controller.canLoadEarlierMessages ||
                    controller.loadingEarlierMessages,
                loading: controller.loadingEarlierMessages,
                onPressed: onLoadEarlier,
              );
            }
            final messageIndex = index - historyOffset;
            if (messageIndex == messages.length) return _streamingMessage();
            return ChatMessageView(
              key: ValueKey<String>(
                'chat-message-${controller.messageKeyAt(messageIndex)}',
              ),
              message: messages[messageIndex],
              animate: false,
            );
          },
        );
      },
    );
  }

  Widget _buildStructuredTimeline(BuildContext context) {
    return ValueListenableBuilder<List<SessionTimelineItem>>(
      valueListenable: controller.timelineUpdates,
      builder: (context, items, _) {
        final allGroups = groupTimelineItems(
          items,
          totalTurnCount: controller.timelineTurnCount,
        );
        final groups = filterTimelineGroups(allGroups, filter);
        final includeStreaming = filter != TimelineViewFilter.activities;
        final showFilter = items.isNotEmpty;
        return _list(
          context: context,
          itemCount: groups.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TimelineHistoryControl(
                    controller: controller,
                    onLoadEarlier: onLoadEarlier,
                    onLoadAll: onLoadAll,
                    onSelectBranch: onSelectBranch,
                  ),
                  if (showFilter)
                    TimelineFilterControl(
                      selected: filter,
                      onChanged: onFilterChanged,
                    ),
                ],
              );
            }
            final groupIndex = index - 1;
            if (groupIndex == groups.length) {
              return _StructuredTimelineTail(
                hasVisibleGroups: groups.isNotEmpty,
                includeStreaming: includeStreaming,
                streamingTextListenable: streamingTextListenable,
                streamUpdatesEnabledListenable: streamUpdatesEnabledListenable,
              );
            }
            final group = groups[groupIndex];
            return TimelineTurnGroupView(
              key: ValueKey<String>('timeline-group-${group.identity}'),
              group: group,
            );
          },
        );
      },
    );
  }

  Widget _list({
    required BuildContext context,
    required int itemCount,
    required NullableIndexedWidgetBuilder itemBuilder,
  }) {
    final headerOffset = header == null ? 0 : 1;
    final showLater =
        controller.canLoadLaterMessages ||
        controller.historyNavigationInProgress;
    final showActivity =
        !showLater &&
        !controller.viewingInactiveBranch &&
        (SessionViewState.fromController(controller).hasLiveRun ||
            controller.activity?.kind == ChatActivityKind.toolFailed);
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: onScrollMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: onScrollNotification,
        child: ListView.builder(
          key: const ValueKey<String>('chat-message-list'),
          controller: scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          // Keep a small off-screen working set. Older pages remain available
          // through the cursor controls without forcing Flutter to retain and
          // repaint a large speculative cache during long conversations.
          scrollCacheExtent: ScrollCacheExtent.pixels(180),
          addAutomaticKeepAlives: false,
          padding: EdgeInsets.fromLTRB(0, 8, 0, bottomContentInset + 8),
          itemCount:
              itemCount +
              headerOffset +
              (showLater ? 1 : 0) +
              (showActivity ? 1 : 0),
          itemBuilder: (context, index) {
            if (header != null && index == 0) return header!;
            if (showActivity && index == itemCount + headerOffset) {
              return ValueListenableBuilder<String?>(
                valueListenable: streamingTextListenable,
                builder: (context, text, _) =>
                    text?.isNotEmpty == true && controller.activity == null
                    ? const SizedBox.shrink()
                    : LiveRunStrip(activity: controller.activity),
              );
            }
            if (index == itemCount + headerOffset && showLater) {
              return Center(
                child: TextButton.icon(
                  key: const ValueKey<String>('load-later-messages'),
                  onPressed: controller.canLoadLaterMessages
                      ? controller.loadLaterMessages
                      : null,
                  icon: const Icon(AppIcons.arrow_downward_rounded, size: 18),
                  label: Text(context.l10n.loadLaterMessages),
                ),
              );
            }
            return itemBuilder(context, index - headerOffset);
          },
        ),
      ),
    );
  }

  Widget _streamingMessage() => StreamingChatMessageView(
    key: const ValueKey<String>('streaming-message'),
    textListenable: streamingTextListenable,
    updatesEnabledListenable: streamUpdatesEnabledListenable,
  );
}

class _StructuredTimelineTail extends StatelessWidget {
  const _StructuredTimelineTail({
    required this.hasVisibleGroups,
    required this.includeStreaming,
    required this.streamingTextListenable,
    required this.streamUpdatesEnabledListenable,
  });

  final bool hasVisibleGroups;
  final bool includeStreaming;
  final ValueListenable<String?> streamingTextListenable;
  final ValueListenable<bool> streamUpdatesEnabledListenable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: streamingTextListenable,
      builder: (context, streamingText, _) {
        if (includeStreaming && streamingText != null) {
          return StreamingChatMessageView(
            key: const ValueKey<String>('streaming-message'),
            textListenable: streamingTextListenable,
            updatesEnabledListenable: streamUpdatesEnabledListenable,
          );
        }
        if (hasVisibleGroups) return const SizedBox.shrink();
        return Padding(
          key: const ValueKey<String>('timeline-filter-empty'),
          padding: const EdgeInsets.symmetric(
            horizontal: TsPhoneSpacing.xLarge,
            vertical: TsPhoneSpacing.xxLarge,
          ),
          child: Text(
            context.l10n.timelineFilterEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

class _EarlierMessagesControl extends StatelessWidget {
  const _EarlierMessagesControl({
    required this.visible,
    required this.loading,
    required this.onPressed,
  });

  final bool visible;
  final bool loading;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextButton.icon(
          key: const ValueKey<String>('load-earlier-messages'),
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(AppIcons.history_rounded, size: 18),
          label: Text(
            loading
                ? context.l10n.loadingEarlierMessages
                : context.l10n.loadEarlierMessages,
          ),
        ),
      ),
    );
  }
}
