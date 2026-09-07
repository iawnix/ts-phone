import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, ScrollDirection;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
    this.onOpenNavigation,
    this.onNewSession,
    this.creatingSession = false,
    this.embedded = false,
  });

  final ConnectionSettings settings;
  final WorkspaceSummary workspace;
  final SessionSummary session;
  final bool recoveredSession;
  final TsPhoneGateway? gateway;
  final TsPhoneGateway Function()? gatewayFactory;
  final ChatViewMemory? memory;
  final VoidCallback? onOpenNavigation;
  final VoidCallback? onNewSession;
  final bool creatingSession;
  final bool embedded;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  late final ChatController _controller;
  late final StreamSubscription<ExtensionUiRequest> _uiSubscription;
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _bottomDockKey = GlobalKey(debugLabel: 'chat-bottom-dock');
  final Queue<ExtensionUiRequest> _pendingUiRequests =
      Queue<ExtensionUiRequest>();
  final ValueNotifier<bool> _streamUpdatesEnabled = ValueNotifier<bool>(true);
  _ChatScrollMode _scrollMode = _ChatScrollMode.following;
  bool _scrollUpdateScheduled = false;
  bool _scrollingToStart = false;
  bool _scrollingToLatest = false;
  bool _showJumpToStart = false;
  bool _showJumpToLatest = false;
  bool _drainingUiRequests = false;
  bool _syncing = false;
  bool _sending = false;
  bool _aborting = false;
  bool _abortConfirmationOpen = false;
  bool _hasDraft = false;
  bool _activating = false;
  TimelineViewFilter _timelineFilter = TimelineViewFilter.all;
  bool _initialTimelinePositioned = false;
  bool _bottomDockMeasureScheduled = false;
  double _bottomDockHeight = 72;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ChatController(
      api:
          widget.gateway ??
          widget.gatewayFactory?.call() ??
          TsPhoneApi(widget.settings),
      workspaceId: widget.workspace.id,
      sessionId: widget.session.sessionId,
      initialSessionRevision: widget.session.sessionRevision,
      initialSessionTitle: widget.session.sessionName,
      initialSessionRuntime: widget.session.runtime,
      initialActiveAgentRunId: widget.session.activeAgentRunId,
      initialRuntimeState: widget.session.runtimeState,
      accessMode: widget.session.accessMode,
      initialHistoryAvailable: widget.session.historyAvailable,
      initialCanPrompt: widget.session.canPrompt,
      initialCapabilities: widget.session.capabilities,
      recoveredSession: widget.recoveredSession,
      initialPreview: widget.memory?.preview,
    )..addListener(_onControllerUpdate);
    _controller.streamingTextUpdates.addListener(_onStreamingTextUpdate);
    _uiSubscription = _controller.uiRequests.listen(_queueUiRequest);
    _composer.text = widget.memory?.draft ?? '';
    _hasDraft = _composer.text.trim().isNotEmpty;
    if (widget.memory?.preview?.revision == widget.session.sessionRevision &&
        widget.memory?.following == false) {
      _scrollMode = _ChatScrollMode.reading;
      _streamUpdatesEnabled.value = false;
    }
    _composer.addListener(_onComposerChanged);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
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
    if (notification.metrics.axis != Axis.vertical) return false;
    final userStarted =
        notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final userScrolling =
        notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    if (userStarted || userScrolling) {
      _setScrollMode(_ChatScrollMode.reading);
    }

    final userStopped =
        notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle);
    if (userStopped && _isAtTail(notification.metrics)) {
      _setScrollMode(_ChatScrollMode.following);
    }
    if ((userScrolling || userStopped) &&
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
    if (notification.metrics.axis != Axis.vertical ||
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
    final showStart = metrics.extentBefore > _jumpToStartThreshold;
    final showLatest =
        _scrollMode == _ChatScrollMode.reading && !_isAtTail(metrics);
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
    if (_scrollingToStart || _scrollingToLatest) return;
    ActionFeedback.selection();
    _setScrollMode(_ChatScrollMode.following);
    setState(() {
      _showJumpToLatest = false;
      _scrollingToLatest = true;
    });
    try {
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
      if (mounted) {
        setState(() => _scrollingToLatest = false);
        if (_scrollMode == _ChatScrollMode.following) {
          _scheduleScrollUpdate();
        }
      }
    }
  }

  Future<void> _jumpToStart() async {
    if (_scrollingToStart || _scrollingToLatest) return;
    ActionFeedback.selection();
    _setScrollMode(_ChatScrollMode.reading);
    setState(() {
      _showJumpToStart = false;
      _scrollingToStart = true;
    });
    try {
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
      if (mounted) {
        setState(() => _scrollingToStart = false);
        if (_scroll.hasClients) {
          _updateTimelineNavigationVisibility(_scroll.position);
        }
      }
    }
  }

  Future<void> _loadEarlierMessages() async {
    if (!_controller.canLoadEarlierMessages) return;
    _setScrollMode(_ChatScrollMode.reading);
    final oldPixels = _scroll.hasClients ? _scroll.position.pixels : null;
    final oldMaxExtent = _scroll.hasClients
        ? _scroll.position.maxScrollExtent
        : null;
    final loaded = await _controller.loadEarlierMessages();
    if (!loaded || !mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
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
    _updateTimelineNavigationVisibility(_scroll.position);
  }

  Future<void> _loadAllHistory() async {
    if (!_controller.canLoadEarlierMessages || _controller.loadingAllHistory) {
      return;
    }
    _setScrollMode(_ChatScrollMode.reading);
    final oldPixels = _scroll.hasClients ? _scroll.position.pixels : null;
    final oldMaxExtent = _scroll.hasClients
        ? _scroll.position.maxScrollExtent
        : null;
    await _controller.loadAllHistory();
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
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
  }

  Future<void> _selectTimelineBranch(String branchId) async {
    ActionFeedback.selection();
    await _controller.selectTimelineBranch(branchId);
    if (!mounted) return;
    _resumeTailFollow();
  }

  void _onComposerChanged() {
    final hasDraft = _composer.text.trim().isNotEmpty;
    if (hasDraft != _hasDraft && mounted) {
      setState(() => _hasDraft = hasDraft);
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    ActionFeedback.tap();
    setState(() => _sending = true);
    try {
      final sent = await _controller.send(_composer.text);
      if (!mounted) return;
      if (sent) {
        _composer.clear();
        _resumeTailFollow();
      } else {
        ActionFeedback.error();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool get _canActivate =>
      widget.session.canActivate &&
      _controller.api is TsPhoneManagementGateway &&
      !_controller.viewingInactiveBranch &&
      _controller.runtimeState == RuntimeState.offline;

  Future<void> _activateSession() async {
    if (_activating || !_canActivate) return;
    setState(() => _activating = true);
    try {
      final selected = await (_controller.api as TsPhoneManagementGateway)
          .activateSession(
            widget.workspace.id,
            widget.session.sessionId,
            widget.session.managementRevision,
          );
      if (!mounted) return;
      await _controller.acceptActivation(selected);
    } on Object catch (error) {
      if (mounted) {
        _showActionMessage(
          describeTsPhoneProblem(error).localizedMessage(context.l10n),
        );
      }
    } finally {
      if (mounted) setState(() => _activating = false);
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
        builder: (dialogContext) => AlertDialog(
          icon: Icon(Icons.stop_circle_outlined, color: colors.error),
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

  void _goBack() {
    ActionFeedback.selection();
    Navigator.of(context).maybePop();
  }

  Future<void> _copyStartCommand() async {
    ActionFeedback.tap();
    await Clipboard.setData(ClipboardData(text: _startCommand));
    if (mounted) _showActionMessage(context.l10n.startCommandCopied);
  }

  String get _startCommand =>
      './TSPi --workspace ${widget.workspace.id} --phone';

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
      builder: (context) => _SessionDetailsSheet(
        runtime: _controller.sessionRuntime,
        workspaceName: widget.workspace.name,
        accessMode: _controller.accessMode,
        runtimeState: _controller.runtimeState,
        sessionId: widget.session.sessionId,
      ),
    );
  }

  void _queueUiRequest(ExtensionUiRequest request) {
    _pendingUiRequests.add(request);
    unawaited(_drainUiRequests());
  }

  Future<void> _drainUiRequests() async {
    if (_drainingUiRequests) return;
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
          appBar: AppBar(
            toolbarHeight: _chatToolbarHeight,
            centerTitle: true,
            titleSpacing: 0,
            automaticallyImplyLeading: false,
            leading: widget.onOpenNavigation != null
                ? IconButton(
                    tooltip: l10n.openSidebar,
                    onPressed: widget.onOpenNavigation,
                    icon: const Icon(Icons.menu_rounded),
                  )
                : widget.embedded
                ? null
                : BackButton(
                    key: const ValueKey<String>('chat-back'),
                    onPressed: _goBack,
                  ),
            title: InkWell(
              key: const ValueKey('chat-session-details'),
              onTap: _showSessionDetails,
              child: _ChatNavigationTitle(
                title: _navigationTitle,
                runtimeState: _controller.runtimeState,
                isHistorical: viewState.isHistorical && !_canActivate,
                compactStatus: MediaQuery.textScalerOf(context).scale(12) > 18,
                connectionState: _controller.eventConnectionState,
                workspace: widget.embedded ? widget.workspace.name : null,
              ),
            ),
            actions: <Widget>[
              if (widget.onNewSession case final create?)
                IconButton(
                  key: const ValueKey('chat-new-session'),
                  tooltip: l10n.newSession,
                  onPressed: widget.creatingSession ? null : create,
                  icon: widget.creatingSession
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_comment_outlined, size: 22),
                ),
              PopupMenuButton<String>(
                key: const ValueKey('chat-menu'),
                tooltip: l10n.sessionRuntimeDetails,
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (action) {
                  if (action == 'start') {
                    unawaited(_jumpToStart());
                  } else if (action == 'sync') {
                    unawaited(_sync());
                  } else {
                    _showSessionDetails();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'details',
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 20),
                        const SizedBox(width: 12),
                        Flexible(child: Text(l10n.sessionRuntimeDetails)),
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
                        const Icon(Icons.sync, size: 20),
                        const SizedBox(width: 12),
                        Flexible(child: Text(l10n.syncMessages)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'start',
                    enabled: _showJumpToStart,
                    child: Row(
                      children: [
                        const Icon(Icons.vertical_align_top, size: 20),
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
    final showLiveRun =
        viewState.hasLiveRun ||
        _controller.activity?.kind == ChatActivityKind.toolFailed;
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
                if (showLiveRun)
                  LiveRunStrip(
                    activity: _controller.activity,
                    canAbort: viewState.canAbort,
                    aborting: _aborting,
                    onAbort: _confirmAbort,
                  ),
                if (showLiveRun) const SizedBox(height: TsPhoneSpacing.small),
                if (_canActivate || _activating)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('continue-session'),
                      onPressed: _activating ? null : _activateSession,
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        textStyle: Theme.of(context).textTheme.bodySmall,
                      ),
                      icon: _activating
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_outlined, size: 20),
                      label: Text(
                        _activating
                            ? context.l10n.preparingSession
                            : context.l10n.continueSession,
                      ),
                    ),
                  ),
                if (!viewState.isHistorical || _canActivate || _activating)
                  _buildComposer(
                    context,
                    maxLines: _composerMaxLines(
                      context,
                      availableHeight: availableHeight,
                      showLiveRun: showLiveRun,
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
    required bool showLiveRun,
  }) {
    if (!availableHeight.isFinite) return 5;
    final scaler = MediaQuery.textScalerOf(context);
    final scaledLineHeight = scaler.scale(16) * 1.45;
    final extraLineHeight = (scaledLineHeight - 23.2).clamp(0, double.infinity);
    final liveRunReserve = showLiveRun ? 64 + extraLineHeight * 1.5 : 0;
    final navigationReserve = _showJumpToLatest ? 52.0 : 0;
    final activationReserve = _canActivate || _activating
        ? (16 + scaler.scale(12) * 1.4 * 2).clamp(44, double.infinity)
        : 0;
    // A multiline composer reserves its own action row below the text.
    final dockChrome =
        78.0 +
        MediaQuery.paddingOf(context).bottom.clamp(8, double.infinity) +
        (showLiveRun ? TsPhoneSpacing.small : 0) +
        (navigationReserve > 0 ? TsPhoneSpacing.small : 0);
    final lineBudget =
        availableHeight -
        liveRunReserve -
        navigationReserve -
        activationReserve -
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
      if (_canActivate && _controller.problem == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.chatWelcome,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
      }
      if (_controller.problem case final problem?) {
        return _ConnectionProblemView(
          message: problem.localizedMessage(context.l10n),
          retrying:
              _controller.eventConnectionState ==
                  EventConnectionState.connecting ||
              _controller.eventConnectionState ==
                  EventConnectionState.reconnecting,
          onRetry: _retryConnection,
        );
      }
      if (viewState.phase == SessionUiPhase.synchronizing) {
        return const _SessionConnectingView();
      }
      if (viewState.phase == SessionUiPhase.offline) {
        return _OfflineWorkspaceView(
          command: _startCommand,
          retrying:
              _controller.eventConnectionState ==
                  EventConnectionState.connecting ||
              _controller.eventConnectionState ==
                  EventConnectionState.reconnecting,
          onCopy: _copyStartCommand,
          onRetry: _retryConnection,
        );
      }
      if (viewState.phase == SessionUiPhase.recovery) {
        return _RecoveryWorkspaceView(
          command: _startCommand,
          retrying:
              _controller.eventConnectionState ==
                  EventConnectionState.connecting ||
              _controller.eventConnectionState ==
                  EventConnectionState.reconnecting,
          onCopy: _copyStartCommand,
          onRetry: _retryConnection,
        );
      }
      return Center(child: Text(context.l10n.noMessages));
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
        if (positioningInitialTimeline) const _SessionConnectingView(),
      ],
    );
  }

  Widget _buildTimelineNavigation() {
    final color = Theme.of(context).colorScheme.primary;
    final navigationBusy = _scrollingToStart || _scrollingToLatest;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_showJumpToLatest)
            IconButton(
              key: const ValueKey<String>('jump-to-latest'),
              onPressed: navigationBusy ? null : _jumpToLatest,
              tooltip: context.l10n.jumpToLatest,
              color: color,
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, {required int maxLines}) {
    final viewState = SessionViewState.fromController(_controller);
    final canDraft =
        _canActivate ||
        _activating ||
        (!viewState.isHistorical &&
            _controller.accessMode == SessionAccessMode.controller);
    return ChatComposer(
      controller: _composer,
      focusNode: _composerFocus,
      canEdit: viewState.canCompose || canDraft,
      canSend: viewState.canCompose && !_sending && _hasDraft,
      sending: _sending,
      maxLines: maxLines,
      onSend: _send,
      hint: canDraft ? context.l10n.composerMessage : _composerHint(),
    );
  }

  Widget? _priorityBanner() {
    if (_controller.messages.isEmpty &&
        _controller.timelineItems.isEmpty &&
        !_controller.hasStreamingText) {
      return null;
    }
    return SessionNoticeView(
      state: SessionViewState.fromController(_controller),
      problem: _controller.problem,
      onRetry: _retryConnection,
      onCopyStartCommand: _copyStartCommand,
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
  const _ChatNavigationTitle({
    required this.title,
    required this.runtimeState,
    required this.isHistorical,
    required this.compactStatus,
    required this.connectionState,
    this.workspace,
  });

  final String title;
  final RuntimeState runtimeState;
  final bool isHistorical;
  final bool compactStatus;
  final EventConnectionState connectionState;
  final String? workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (workspace != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 6),
              _SessionStatusLine(
                runtimeState: runtimeState,
                isHistorical: isHistorical,
                compact: true,
                connectionState: connectionState,
              ),
            ],
          ),
          if (!compactStatus)
            Text(
              workspace!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      );
    }
    if (compactStatus) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _SessionStatusLine(
            runtimeState: runtimeState,
            isHistorical: isHistorical,
            compact: true,
            connectionState: connectionState,
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 1),
        _SessionStatusLine(
          runtimeState: runtimeState,
          isHistorical: isHistorical,
          compact: compactStatus,
          connectionState: connectionState,
        ),
      ],
    );
  }
}

class _SessionStatusLine extends StatelessWidget {
  const _SessionStatusLine({
    required this.runtimeState,
    required this.isHistorical,
    required this.compact,
    required this.connectionState,
  });

  final RuntimeState runtimeState;
  final bool isHistorical;
  final bool compact;
  final EventConnectionState connectionState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = TsPhoneStatusTheme.resolve(context);
    final l10n = context.l10n;
    final (color, label, pulsing) = isHistorical
        ? (
            theme.colorScheme.onSurfaceVariant,
            l10n.historyReadOnlyStatus,
            false,
          )
        : switch (connectionState) {
            EventConnectionState.connected => switch (runtimeState) {
              RuntimeState.idle => (
                status.connected,
                runtimeState.localizedLabel(l10n),
                false,
              ),
              RuntimeState.running || RuntimeState.connecting => (
                status.warning,
                runtimeState.localizedLabel(l10n),
                true,
              ),
              RuntimeState.recoveryRequired => (
                status.error,
                runtimeState.localizedLabel(l10n),
                false,
              ),
              RuntimeState.offline => (
                theme.colorScheme.onSurfaceVariant,
                runtimeState.localizedLabel(l10n),
                false,
              ),
            },
            EventConnectionState.suspended => (
              theme.colorScheme.onSurfaceVariant,
              l10n.liveSyncSuspended,
              false,
            ),
            EventConnectionState.closed => (
              theme.colorScheme.onSurfaceVariant,
              l10n.liveSyncClosed,
              false,
            ),
            EventConnectionState.failed => (
              status.error,
              l10n.liveSyncFailed,
              false,
            ),
            EventConnectionState.reconnecting => (
              status.warning,
              l10n.liveSyncRestoring,
              true,
            ),
            EventConnectionState.connecting => (
              status.warning,
              l10n.liveSyncConnecting,
              true,
            ),
          };
    if (compact) {
      final compactIcon = switch (connectionState) {
        EventConnectionState.connected => switch (runtimeState) {
          RuntimeState.offline => Icons.cloud_off_outlined,
          RuntimeState.recoveryRequired => Icons.error_outline_rounded,
          RuntimeState.running => Icons.hourglass_top_rounded,
          RuntimeState.connecting => Icons.sync_rounded,
          RuntimeState.idle => Icons.check_circle_outline_rounded,
        },
        EventConnectionState.suspended => Icons.pause_circle_outline_rounded,
        EventConnectionState.closed => Icons.cloud_off_outlined,
        EventConnectionState.failed => Icons.error_outline_rounded,
        EventConnectionState.reconnecting => Icons.sync_problem_rounded,
        EventConnectionState.connecting => Icons.sync_rounded,
      };
      return Semantics(
        key: ValueKey<String>(
          isHistorical ? 'chat-history-status' : 'chat-compact-status',
        ),
        label: label,
        child: ExcludeSemantics(
          child: Tooltip(
            message: label,
            child: Icon(
              isHistorical ? Icons.lock_outline_rounded : compactIcon,
              size: 18,
              color: color,
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TsStatusDot(color: color, size: 7, pulsing: pulsing),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionDetailsSheet extends StatelessWidget {
  const _SessionDetailsSheet({
    required this.runtime,
    required this.workspaceName,
    required this.accessMode,
    required this.runtimeState,
    required this.sessionId,
  });

  final SessionRuntimeSnapshot? runtime;
  final String workspaceName;
  final SessionAccessMode accessMode;
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
          Text(
            l10n.sessionRuntimeDetails,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
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
          Padding(
            key: const ValueKey<String>('session-identity-group'),
            padding: const EdgeInsets.symmetric(
              horizontal: TsPhoneSpacing.medium,
            ),
            child: Column(
              children: <Widget>[
                _RuntimeDetailRow(
                  icon: Icons.folder_outlined,
                  label: l10n.approvalWorkspace,
                  value: workspaceName,
                ),
                const _RuntimeDetailDivider(),
                _RuntimeDetailRow(
                  icon: Icons.shield_outlined,
                  label: l10n.accessPermission,
                  value: accessMode.localizedLabel(l10n),
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
                    icon: Icons.smart_toy_outlined,
                    label: l10n.sessionModel,
                    value: runtime!.model.knownId ?? l10n.dataNotProvided,
                  ),
                  const _RuntimeDetailDivider(),
                  _RuntimeDetailRow(
                    icon: Icons.route_outlined,
                    label: l10n.sessionProvider,
                    value: runtime!.model.knownProvider ?? l10n.dataNotProvided,
                  ),
                  if (usage != null) ...<Widget>[
                    const _RuntimeDetailDivider(),
                    _RuntimeDetailRow(
                      icon: Icons.data_usage_rounded,
                      label: l10n.sessionContextWindow,
                      value: contextValue!,
                    ),
                    const _RuntimeDetailDivider(),
                    _RuntimeDetailRow(
                      icon: Icons.battery_5_bar_rounded,
                      label: l10n.sessionContextRemaining,
                      value: remainingValue!,
                    ),
                    const _RuntimeDetailDivider(),
                    _RuntimeDetailRow(
                      icon: Icons.calculate_outlined,
                      label: l10n.sessionContextSource,
                      value: l10n.sessionContextEstimate,
                    ),
                  ],
                  const _RuntimeDetailDivider(),
                  _RuntimeDetailRow(
                    icon: Icons.schedule_rounded,
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
            title: Text(
              l10n.technicalDetails,
              style: theme.textTheme.bodyMedium,
            ),
            children: [
              _RuntimeDetailRow(
                icon: Icons.tag,
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
        duration: TsPhoneMotion.resolve(context, TsPhoneMotion.quick),
        child: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
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
            Icons.history_toggle_off_rounded,
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
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: onScrollMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: onScrollNotification,
        child: ListView.builder(
          key: const ValueKey<String>('chat-message-list'),
          controller: scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(0, 8, 0, bottomContentInset + 8),
          itemCount: itemCount + headerOffset,
          itemBuilder: (context, index) {
            if (header != null && index == 0) return header!;
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
              : const Icon(Icons.history_rounded, size: 18),
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

class _OfflineWorkspaceView extends StatelessWidget {
  const _OfflineWorkspaceView({
    required this.command,
    required this.retrying,
    required this.onCopy,
    required this.onRetry,
  });

  final String command;
  final bool retrying;
  final VoidCallback onCopy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _WorkspaceWaitingView(
      icon: Icons.terminal_outlined,
      title: l10n.tspiNotStartedTitle,
      description: l10n.tspiNotStartedDescription,
      command: command,
      status: l10n.waitingForTspi,
      retrying: retrying,
      onCopy: onCopy,
      onRetry: onRetry,
    );
  }
}

class _RecoveryWorkspaceView extends StatelessWidget {
  const _RecoveryWorkspaceView({
    required this.command,
    required this.retrying,
    required this.onCopy,
    required this.onRetry,
  });

  final String command;
  final bool retrying;
  final VoidCallback onCopy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _WorkspaceWaitingView(
      icon: Icons.warning_amber_rounded,
      title: l10n.generationDisconnectedTitle,
      description: l10n.generationDisconnectedDescription,
      command: command,
      status: l10n.waitingForRecovery,
      retrying: retrying,
      onCopy: onCopy,
      onRetry: onRetry,
      warning: true,
    );
  }
}

class _WorkspaceWaitingView extends StatelessWidget {
  const _WorkspaceWaitingView({
    required this.icon,
    required this.title,
    required this.description,
    required this.command,
    required this.status,
    required this.retrying,
    required this.onCopy,
    required this.onRetry,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String command;
  final String status;
  final bool retrying;
  final VoidCallback onCopy;
  final VoidCallback onRetry;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 48, color: warning ? colors.error : colors.outline),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(description, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    command,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  onPressed: onCopy,
                  tooltip: context.l10n.copyStartCommand,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (retrying)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.hourglass_top_rounded,
                  size: 18,
                  color: colors.outline,
                ),
              const SizedBox(width: 8),
              Text(status),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: retrying ? null : onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.checkAgain),
          ),
        ],
      ),
    );
  }
}

class _SessionConnectingView extends StatelessWidget {
  const _SessionConnectingView();

  @override
  Widget build(BuildContext context) {
    return TsEmptyState(
      icon: Icons.cloud_sync_outlined,
      title: context.l10n.sessionSynchronizingTitle,
      message: context.l10n.sessionSynchronizingMessage,
      action: const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ConnectionProblemView extends StatelessWidget {
  const _ConnectionProblemView({
    required this.message,
    required this.retrying,
    required this.onRetry,
  });

  final String message;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return TsEmptyState(
      icon: Icons.cloud_off_outlined,
      title: context.l10n.liveSyncInterrupted,
      message: message,
      action: OutlinedButton.icon(
        onPressed: retrying ? null : onRetry,
        icon: retrying
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded),
        label: Text(
          retrying ? context.l10n.reconnecting : context.l10n.reconnect,
        ),
      ),
    );
  }
}
