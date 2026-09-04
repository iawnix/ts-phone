import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
import 'live_run_strip.dart';
import 'session_notice.dart';
import 'session_view_state.dart';
import 'timeline_widgets.dart';

enum _ChatScrollMode { following, reading }

const double _jumpToStartThreshold = 160;

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.settings,
    required this.workspace,
    required this.session,
    this.recoveredSession = false,
    this.gateway,
  });

  final ConnectionSettings settings;
  final WorkspaceSummary workspace;
  final SessionSummary session;
  final bool recoveredSession;
  final TsPhoneGateway? gateway;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  late final ChatController _controller;
  late final StreamSubscription<ExtensionUiRequest> _uiSubscription;
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
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
  bool _hasDraft = false;
  bool _initialTimelinePositioned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ChatController(
      api: widget.gateway ?? TsPhoneApi(widget.settings),
      workspaceId: widget.workspace.id,
      sessionId: widget.session.sessionId,
      initialSessionRevision: widget.session.sessionRevision,
      initialSessionTitle: widget.session.sessionName,
      initialSessionRuntime: widget.session.runtime,
      initialRuntimeState: widget.session.runtimeState,
      accessMode: widget.session.accessMode,
      initialHistoryAvailable: widget.session.historyAvailable,
      initialCanPrompt: widget.session.canPrompt,
      initialCapabilities: widget.session.capabilities,
      recoveredSession: widget.recoveredSession,
    )..addListener(_onControllerUpdate);
    _controller.streamingTextUpdates.addListener(_onStreamingTextUpdate);
    _uiSubscription = _controller.uiRequests.listen(_queueUiRequest);
    _composer.addListener(_onComposerChanged);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
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

  Future<void> _abort() async {
    if (_aborting) return;
    ActionFeedback.warning();
    setState(() => _aborting = true);
    try {
      await _controller.abort();
      if (!mounted || _controller.problem != null) return;
      _showActionMessage(context.l10n.abortRequested);
    } finally {
      if (mounted) setState(() => _aborting = false);
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
        final showContent =
            _controller.messages.isNotEmpty ||
            _controller.timelineItems.isNotEmpty ||
            _controller.hasStreamingText;
        return Scaffold(
          appBar: TsGlassAppBar(
            toolbarHeight: 62,
            centerTitle: true,
            titleSpacing: 0,
            leading: IconButton(
              key: const ValueKey<String>('chat-back'),
              onPressed: _goBack,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            ),
            title: _ChatNavigationTitle(
              title: _navigationTitle,
              runtimeState: _controller.runtimeState,
              isHistorical: viewState.isHistorical,
              connectionState: _controller.eventConnectionState,
            ),
            actions: <Widget>[
              IconButton(
                key: const ValueKey<String>('chat-sync'),
                onPressed:
                    viewState.canRefresh &&
                        !_controller.commandInFlight &&
                        !_syncing
                    ? _sync
                    : null,
                tooltip: _syncing ? l10n.syncing : l10n.syncMessages,
                icon: _syncing
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 21),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: IconButton(
                  key: const ValueKey<String>('chat-session-details'),
                  onPressed: _showSessionDetails,
                  tooltip: l10n.sessionRuntimeDetails,
                  icon: const Icon(Icons.info_outline_rounded, size: 21),
                ),
              ),
            ],
          ),
          body: TsPageBackdrop(
            child: SafeArea(
              child: Column(
                children: <Widget>[
                  if (showContent) _priorityBanner() ?? const SizedBox.shrink(),
                  Expanded(child: child!),
                  if (viewState.hasLiveRun ||
                      _controller.activity?.kind == ChatActivityKind.toolFailed)
                    LiveRunStrip(
                      activity: _controller.activity,
                      canAbort:
                          viewState.canAbort &&
                          _controller.activity?.kind !=
                              ChatActivityKind.toolFailed,
                      aborting: _aborting,
                      onAbort: _abort,
                    ),
                  if (viewState.isHistorical)
                    const _ReadOnlySessionBar()
                  else
                    _buildComposer(context),
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
      child: _MessageTimeline(
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
      ),
      builder: (context, child) => _buildMessagesForState(child!),
    );
  }

  Widget _buildMessagesForState(Widget timeline) {
    final viewState = SessionViewState.fromController(_controller);
    final messages = _controller.messages;
    final hasTimelineItems =
        _controller.usesStructuredTimeline &&
        _controller.timelineItems.isNotEmpty;
    final hasStreaming = _controller.hasStreamingText;
    if (messages.isEmpty && !hasTimelineItems && !hasStreaming) {
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
        if (!positioningInitialTimeline &&
            (_showJumpToStart || _showJumpToLatest))
          Positioned(right: 12, bottom: 12, child: _buildTimelineNavigation()),
      ],
    );
  }

  Widget _buildTimelineNavigation() {
    final color = Theme.of(context).colorScheme.primary;
    final navigationBusy = _scrollingToStart || _scrollingToLatest;
    return TsGlassSurface(
      elevated: true,
      blurSigma: 14,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_showJumpToStart)
            IconButton(
              key: const ValueKey<String>('jump-to-start'),
              onPressed: navigationBusy ? null : _jumpToStart,
              tooltip: context.l10n.jumpToStart,
              color: color,
              icon: const Icon(Icons.vertical_align_top_rounded),
            ),
          if (_showJumpToStart && _showJumpToLatest)
            SizedBox(
              width: 24,
              child: Divider(
                height: 0.5,
                thickness: 0.5,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
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

  Widget _buildComposer(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final viewState = SessionViewState.fromController(_controller);
    final canSend = viewState.canCompose && !_sending && _hasDraft;
    final sendButton = IconButton.filled(
      onPressed: canSend ? _send : null,
      tooltip: _sending ? l10n.sending : l10n.send,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        maximumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
      icon: _sending
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.arrow_upward_rounded, size: 21),
    );
    return TsGlassBar(
      edge: TsGlassBarEdge.top,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: AnimatedBuilder(
            animation: _composerFocus,
            builder: (context, _) {
              final focused = _composerFocus.hasFocus && viewState.canCompose;
              return AnimatedContainer(
                key: const ValueKey<String>('chat-composer'),
                duration: TsPhoneMotion.resolve(context, TsPhoneMotion.quick),
                curve: Curves.easeOut,
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(TsPhoneRadii.composer),
                  border: Border.all(
                    color: focused
                        ? colors.primary.withValues(alpha: 0.5)
                        : colors.outlineVariant,
                    width: focused ? 1 : 0.6,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _composer,
                        focusNode: _composerFocus,
                        enabled: viewState.canCompose,
                        minLines: 1,
                        maxLines: 7,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                        autocorrect: true,
                        enableSuggestions: true,
                        cursorColor: colors.primary,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          height: 1.32,
                        ),
                        onTapOutside: (_) => _composerFocus.unfocus(),
                        decoration: InputDecoration(
                          hintText: _composerHint(),
                          hintMaxLines: 2,
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.3,
                          ),
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.fromLTRB(
                            12,
                            9,
                            6,
                            9,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: TsPhoneSpacing.xSmall),
                    SizedBox.square(
                      key: const ValueKey<String>('composer-action-slot'),
                      dimension: 44,
                      child: AnimatedSwitcher(
                        duration: TsPhoneMotion.resolve(
                          context,
                          TsPhoneMotion.quick,
                        ),
                        child: _hasDraft || _sending
                            ? SizedBox.square(
                                key: const ValueKey<String>('composer-send'),
                                dimension: 44,
                                child: sendButton,
                              )
                            : const SizedBox.shrink(
                                key: ValueKey<String>('composer-action-empty'),
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
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

class _ReadOnlySessionBar extends StatelessWidget {
  const _ReadOnlySessionBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TsGlassBar(
      edge: TsGlassBarEdge.top,
      child: ConstrainedBox(
        key: const ValueKey<String>('chat-read-only-bar'),
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TsPhoneSpacing.large,
            vertical: TsPhoneSpacing.small,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: TsPhoneSpacing.small),
              Flexible(
                child: Text(
                  context.l10n.composerReadOnly,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatNavigationTitle extends StatelessWidget {
  const _ChatNavigationTitle({
    required this.title,
    required this.runtimeState,
    required this.isHistorical,
    required this.connectionState,
  });

  final String title;
  final RuntimeState runtimeState;
  final bool isHistorical;
  final EventConnectionState connectionState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    required this.connectionState,
  });

  final RuntimeState runtimeState;
  final bool isHistorical;
  final EventConnectionState connectionState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = TsPhoneStatusTheme.resolve(context);
    final l10n = context.l10n;
    final (color, label, pulsing) = isHistorical
        ? (theme.colorScheme.outline, l10n.historyReadOnlyStatus, false)
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
                theme.colorScheme.outline,
                runtimeState.localizedLabel(l10n),
                false,
              ),
            },
            EventConnectionState.suspended => (
              theme.colorScheme.outline,
              l10n.liveSyncSuspended,
              false,
            ),
            EventConnectionState.closed => (
              theme.colorScheme.outline,
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
    final shortSessionId = sessionId.length <= 8
        ? sessionId
        : '${sessionId.substring(0, 8)}…';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        TsPhoneSpacing.xLarge,
        0,
        TsPhoneSpacing.xLarge,
        TsPhoneSpacing.xLarge + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.memory_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: TsPhoneSpacing.medium),
              Expanded(
                child: Text(
                  l10n.sessionRuntimeDetails,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          if (lastKnown) ...<Widget>[
            const SizedBox(height: TsPhoneSpacing.medium),
            Text(
              l10n.sessionRuntimeLastKnown,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: TsPhoneSpacing.large),
          _RuntimeDetailRow(
            icon: Icons.folder_outlined,
            label: l10n.approvalWorkspace,
            value: workspaceName,
          ),
          _RuntimeDetailRow(
            icon: Icons.tag_rounded,
            label: l10n.approvalSession,
            value: shortSessionId,
            trailing: _CopySessionIdButton(sessionId: sessionId),
          ),
          _RuntimeDetailRow(
            icon: Icons.shield_outlined,
            label: l10n.auth,
            value: accessMode.localizedLabel(l10n),
          ),
          const Divider(height: TsPhoneSpacing.xLarge),
          if (runtime == null)
            _RuntimeUnavailableNote(message: l10n.sessionRuntimeUnavailable)
          else ...<Widget>[
            _RuntimeDetailRow(
              icon: Icons.smart_toy_outlined,
              label: l10n.sessionModel,
              value: runtime!.model.id,
            ),
            _RuntimeDetailRow(
              icon: Icons.route_outlined,
              label: l10n.sessionProvider,
              value: runtime!.model.provider,
            ),
            if (usage != null) ...<Widget>[
              _RuntimeDetailRow(
                icon: Icons.data_usage_rounded,
                label: l10n.sessionContextWindow,
                value: contextValue!,
              ),
              _RuntimeDetailRow(
                icon: Icons.battery_5_bar_rounded,
                label: l10n.sessionContextRemaining,
                value: remainingValue!,
              ),
              _RuntimeDetailRow(
                icon: Icons.calculate_outlined,
                label: l10n.sessionContextSource,
                value: l10n.sessionContextEstimate,
              ),
            ],
            _RuntimeDetailRow(
              icon: Icons.schedule_rounded,
              label: l10n.sessionRuntimeUpdated,
              value: updatedValue,
            ),
          ],
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
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 19;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TsPhoneSpacing.small),
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
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: TsPhoneSpacing.medium),
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
        final groups = groupTimelineItems(
          items,
          totalTurnCount: controller.timelineTurnCount,
        );
        return _list(
          itemCount: groups.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return TimelineHistoryControl(
                controller: controller,
                onLoadEarlier: onLoadEarlier,
                onLoadAll: onLoadAll,
                onSelectBranch: onSelectBranch,
              );
            }
            final groupIndex = index - 1;
            if (groupIndex == groups.length) return _streamingMessage();
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
    required int itemCount,
    required NullableIndexedWidgetBuilder itemBuilder,
  }) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: onScrollMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: onScrollNotification,
        child: ListView.builder(
          key: const ValueKey<String>('chat-message-list'),
          controller: scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
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
                  icon: const Icon(Icons.copy_outlined),
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
                Icon(Icons.hourglass_top, size: 18, color: colors.outline),
              const SizedBox(width: 8),
              Text(status),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: retrying ? null : onRetry,
            icon: const Icon(Icons.refresh),
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
            : const Icon(Icons.refresh),
        label: Text(
          retrying ? context.l10n.reconnecting : context.l10n.reconnect,
        ),
      ),
    );
  }
}
