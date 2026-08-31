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
        setState(() => _initialTimelinePositioned = true);
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
        await _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
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
        await _scroll.animateTo(
          _scroll.position.minScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
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

  void _showSessionRuntimeDetails() {
    final runtime = _controller.sessionRuntime;
    if (runtime == null) return;
    ActionFeedback.selection();
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SessionRuntimeDetailsSheet(
        runtime: runtime,
        workspaceName: widget.workspace.name,
        accessMode: _controller.accessMode,
        runtimeState: _controller.runtimeState,
        sessionShortId: widget.session.shortId,
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
      builder: (context, child) => Scaffold(
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
            title:
                _controller.sessionTitle ??
                widget.session.localizedDisplayName(l10n),
            workspaceName: widget.workspace.name,
            accessMode: _controller.accessMode,
            runtimeState: _controller.runtimeState,
            historyOnly: _controller.historyOnly,
            connectionState: _controller.eventConnectionState,
            sessionShortId: widget.session.shortId,
            runtime: _controller.sessionRuntime,
            onRuntimeTap: _showSessionRuntimeDetails,
          ),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                onPressed:
                    !_controller.canRefresh ||
                        _controller.commandInFlight ||
                        _syncing
                    ? null
                    : _sync,
                tooltip: _syncing ? l10n.syncing : l10n.syncMessages,
                icon: _syncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 22),
              ),
            ),
          ],
        ),
        body: TsPageBackdrop(
          child: SafeArea(
            child: Column(
              children: <Widget>[
                ?_priorityBanner(),
                if (!_controller.historyOnly &&
                    _controller.accessMode == SessionAccessMode.observer)
                  const _ObserverBanner(),
                if (_controller.statuses.isNotEmpty ||
                    _controller.activity != null)
                  _StatusBand(controller: _controller),
                for (final entry in _controller.widgets.entries)
                  _WidgetBand(title: entry.key, lines: entry.value),
                Expanded(child: child!),
                _buildComposer(context),
              ],
            ),
          ),
        ),
      ),
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
        onLoadEarlier: _loadEarlierMessages,
        onLoadAll: _loadAllHistory,
        onSelectBranch: _selectTimelineBranch,
      ),
      builder: (context, child) => _buildMessagesForState(child!),
    );
  }

  Widget _buildMessagesForState(Widget timeline) {
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
      if (_controller.isSynchronizing ||
          _controller.runtimeState == RuntimeState.connecting) {
        return const _SessionConnectingView();
      }
      if (_controller.runtimeState == RuntimeState.offline) {
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
      if (_controller.runtimeState == RuntimeState.recoveryRequired) {
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
    final running = _controller.runtimeState == RuntimeState.running;
    final canSend =
        _controller.canSend &&
        !_controller.commandInFlight &&
        !_sending &&
        _hasDraft;
    final canAbort = running && !_controller.commandInFlight && !_aborting;
    final sendButton = IconButton.filled(
      onPressed: canSend ? _send : null,
      tooltip: _sending ? l10n.sending : l10n.send,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        maximumSize: const Size.square(40),
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
    final stopButton = IconButton.filled(
      onPressed: canAbort ? _abort : null,
      tooltip: _aborting ? l10n.aborting : l10n.abortGeneration,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        maximumSize: const Size.square(40),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
        foregroundColor: colors.onError,
        backgroundColor: colors.error,
        disabledForegroundColor: colors.onSurface.withValues(alpha: 0.38),
        disabledBackgroundColor: colors.surfaceContainerHighest.withValues(
          alpha: 0.72,
        ),
      ),
      icon: _aborting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.stop_rounded, size: 20),
    );
    final showSend = !running || _hasDraft || _sending;
    return TsGlassBar(
      edge: TsGlassBarEdge.top,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: AnimatedBuilder(
            animation: _composerFocus,
            builder: (context, _) {
              final focused = _composerFocus.hasFocus && _controller.canSend;
              return AnimatedContainer(
                key: const ValueKey<String>('chat-composer'),
                duration: TsPhoneMotion.quick,
                curve: Curves.easeOut,
                padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
                decoration: BoxDecoration(
                  color: TsPhoneGlassTheme.resolve(context).elevatedSurface,
                  borderRadius: BorderRadius.circular(TsPhoneRadii.composer),
                  border: Border.all(
                    color: focused
                        ? colors.primary.withValues(alpha: 0.5)
                        : TsPhoneGlassTheme.resolve(context).border,
                    width: focused ? 1 : 0.6,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: TsPhoneGlassTheme.resolve(context).shadow,
                      blurRadius: focused ? 14 : 9,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _composer,
                        focusNode: _composerFocus,
                        enabled: _controller.canSend,
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
                    AnimatedSize(
                      key: const ValueKey<String>('composer-actions'),
                      alignment: Alignment.centerRight,
                      duration: TsPhoneMotion.quick,
                      curve: Curves.easeOut,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (showSend)
                            SizedBox.square(
                              key: const ValueKey<String>('composer-send'),
                              dimension: 40,
                              child: sendButton,
                            ),
                          if (showSend && running)
                            const SizedBox(width: TsPhoneSpacing.xSmall),
                          if (running)
                            SizedBox.square(
                              key: const ValueKey<String>('composer-stop'),
                              dimension: 40,
                              child: stopButton,
                            ),
                        ],
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
    if (_controller.problem case final problem?) {
      return _ErrorBanner(
        message: problem.localizedMessage(context.l10n),
        onRetry: _retryConnection,
      );
    }
    if (_controller.runtimeState == RuntimeState.recoveryRequired ||
        widget.recoveredSession) {
      return const _RecoveryBanner();
    }
    if (_controller.runtimeState == RuntimeState.offline) {
      if (_controller.historyOnly) return null;
      return _OfflineBanner(onCopy: _copyStartCommand);
    }
    return null;
  }

  String _composerHint() {
    final l10n = context.l10n;
    if (_controller.isSynchronizing ||
        _controller.runtimeState == RuntimeState.connecting) {
      return l10n.composerSynchronizing;
    }
    if (_controller.runtimeState == RuntimeState.offline) {
      if (_controller.historyOnly) return l10n.composerHistory;
      return l10n.composerOffline;
    }
    if (_controller.runtimeState == RuntimeState.recoveryRequired) {
      return l10n.composerRecovery;
    }
    if (_controller.viewingInactiveBranch) {
      return l10n.composerHistoricalBranch;
    }
    if (_controller.eventConnectionState != EventConnectionState.connected) {
      return l10n.composerReconnecting;
    }
    return l10n.composerMessage;
  }
}

class _ChatNavigationTitle extends StatelessWidget {
  const _ChatNavigationTitle({
    required this.title,
    required this.workspaceName,
    required this.accessMode,
    required this.runtimeState,
    required this.historyOnly,
    required this.connectionState,
    required this.sessionShortId,
    required this.runtime,
    required this.onRuntimeTap,
  });

  final String title;
  final String workspaceName;
  final SessionAccessMode accessMode;
  final RuntimeState runtimeState;
  final bool historyOnly;
  final EventConnectionState connectionState;
  final String sessionShortId;
  final SessionRuntimeSnapshot? runtime;
  final VoidCallback onRuntimeTap;

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
        _SessionContextLine(
          workspaceName: workspaceName,
          accessMode: accessMode,
          runtimeState: runtimeState,
          historyOnly: historyOnly,
          connectionState: connectionState,
          sessionShortId: sessionShortId,
          runtime: runtime,
          onRuntimeTap: onRuntimeTap,
        ),
      ],
    );
  }
}

class _SessionContextLine extends StatelessWidget {
  const _SessionContextLine({
    required this.workspaceName,
    required this.accessMode,
    required this.runtimeState,
    required this.historyOnly,
    required this.connectionState,
    required this.sessionShortId,
    required this.runtime,
    required this.onRuntimeTap,
  });

  final String workspaceName;
  final SessionAccessMode accessMode;
  final RuntimeState runtimeState;
  final bool historyOnly;
  final EventConnectionState connectionState;
  final String sessionShortId;
  final SessionRuntimeSnapshot? runtime;
  final VoidCallback onRuntimeTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = TsPhoneStatusTheme.resolve(context);
    final l10n = context.l10n;
    final (connectionColor, connectionMessage) = switch (connectionState) {
      EventConnectionState.connected => (
        status.connected,
        l10n.liveSyncConnected,
      ),
      EventConnectionState.suspended => (
        theme.colorScheme.outline,
        l10n.liveSyncSuspended,
      ),
      EventConnectionState.closed => (
        theme.colorScheme.outline,
        l10n.liveSyncClosed,
      ),
      EventConnectionState.failed => (status.error, l10n.liveSyncFailed),
      EventConnectionState.reconnecting => (
        status.warning,
        l10n.liveSyncRestoring,
      ),
      EventConnectionState.connecting => (
        status.warning,
        l10n.liveSyncConnecting,
      ),
    };
    final stateLabel = historyOnly
        ? l10n.historySession
        : runtimeState.localizedCompactLabel(l10n);
    final contextLabel = runtime == null
        ? '${stateLabel.toUpperCase()} · ${l10n.sessionToken(sessionShortId)}'
        : _compactRuntimeLabel(runtime!);
    final tooltip = <String>[
      workspaceName,
      if (!historyOnly) accessMode.localizedLabel(l10n),
      connectionMessage,
      if (runtime != null) runtime!.model.id,
    ].join(' · ');
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TsStatusDot(
          color: connectionColor,
          size: 7,
          pulsing: connectionState == EventConnectionState.connected,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: TsMonoText(
            contextLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    return Tooltip(
      message: runtime == null
          ? tooltip
          : '$tooltip · ${l10n.sessionRuntimeTapHint}',
      child: runtime == null
          ? content
          : Semantics(
              button: true,
              label: l10n.sessionRuntimeTapHint,
              child: InkWell(
                key: const ValueKey<String>('session-runtime-summary'),
                onTap: onRuntimeTap,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 2,
                  ),
                  child: content,
                ),
              ),
            ),
    );
  }
}

class _SessionRuntimeDetailsSheet extends StatelessWidget {
  const _SessionRuntimeDetailsSheet({
    required this.runtime,
    required this.workspaceName,
    required this.accessMode,
    required this.runtimeState,
    required this.sessionShortId,
  });

  final SessionRuntimeSnapshot runtime;
  final String workspaceName;
  final SessionAccessMode accessMode;
  final RuntimeState runtimeState;
  final String sessionShortId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final usage = runtime.context;
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final used = usage?.usedTokens;
    final contextValue = usage == null
        ? l10n.sessionContextUnavailable
        : '${used == null ? '—' : number.format(used)} / ${number.format(usage.limitTokens)}';
    final remaining = usage?.remainingTokens;
    final remainingPercent = usage?.percent == null
        ? null
        : (100 - usage!.percent!).clamp(0, 100).round();
    final remainingValue = remaining == null || remainingPercent == null
        ? l10n.sessionContextUnavailable
        : '${number.format(remaining)} · $remainingPercent%';
    final updated = runtime.updatedAt.toLocal();
    final updatedValue = [
      MaterialLocalizations.of(context).formatMediumDate(updated),
      MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(updated)),
    ].join(' · ');
    final lastKnown =
        runtimeState == RuntimeState.offline ||
        runtimeState == RuntimeState.recoveryRequired;
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
            icon: Icons.smart_toy_outlined,
            label: l10n.sessionModel,
            value: runtime.model.id,
          ),
          _RuntimeDetailRow(
            icon: Icons.route_outlined,
            label: l10n.sessionProvider,
            value: runtime.model.provider,
          ),
          _RuntimeDetailRow(
            icon: Icons.data_usage_rounded,
            label: l10n.sessionContextWindow,
            value: contextValue,
          ),
          _RuntimeDetailRow(
            icon: Icons.battery_5_bar_rounded,
            label: l10n.sessionContextRemaining,
            value: remainingValue,
          ),
          _RuntimeDetailRow(
            icon: Icons.calculate_outlined,
            label: l10n.sessionContextSource,
            value: l10n.sessionContextEstimate,
          ),
          _RuntimeDetailRow(
            icon: Icons.schedule_rounded,
            label: l10n.sessionRuntimeUpdated,
            value: updatedValue,
          ),
          const Divider(height: TsPhoneSpacing.xLarge),
          _RuntimeDetailRow(
            icon: Icons.folder_outlined,
            label: l10n.approvalWorkspace,
            value: workspaceName,
          ),
          _RuntimeDetailRow(
            icon: Icons.tag_rounded,
            label: l10n.approvalSession,
            value: l10n.sessionToken(sessionShortId),
          ),
          _RuntimeDetailRow(
            icon: Icons.shield_outlined,
            label: l10n.auth,
            value: accessMode.localizedLabel(l10n),
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
  });

  final IconData icon;
  final String label;
  final String value;

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
        ],
      ),
    );
  }
}

String _compactRuntimeLabel(SessionRuntimeSnapshot runtime) {
  final usage = runtime.context;
  if (usage == null) return runtime.model.id;
  final used = usage.usedTokens;
  return '${runtime.model.id} · ${used == null ? '—' : _compactTokenCount(used)} / ${_compactTokenCount(usage.limitTokens)}';
}

String _compactTokenCount(int value) {
  if (value < 1000) return '$value';
  final thousands = value / 1000;
  final digits = thousands < 10 && thousands != thousands.roundToDouble()
      ? 1
      : 0;
  return '${thousands.toStringAsFixed(digits)}k';
}

class _MessageTimeline extends StatelessWidget {
  const _MessageTimeline({
    required this.controller,
    required this.messagesListenable,
    required this.streamingTextListenable,
    required this.streamUpdatesEnabledListenable,
    required this.scrollController,
    required this.onScrollNotification,
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
        final turnNumbers = <String, int>{};
        for (final item in items) {
          final turnId = item.turnId;
          if (turnId != null) turnNumbers.putIfAbsent(turnId, () => 0);
        }
        final firstTurnNumber =
            (controller.timelineTurnCount - turnNumbers.length + 1).clamp(
              1,
              controller.timelineTurnCount == 0
                  ? 1
                  : controller.timelineTurnCount,
            );
        var nextTurnNumber = firstTurnNumber;
        for (final turnId in turnNumbers.keys) {
          turnNumbers[turnId] = nextTurnNumber;
          nextTurnNumber += 1;
        }
        return _list(
          itemCount: items.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return TimelineHistoryControl(
                controller: controller,
                onLoadEarlier: onLoadEarlier,
                onLoadAll: onLoadAll,
                onSelectBranch: onSelectBranch,
              );
            }
            final itemIndex = index - 1;
            if (itemIndex == items.length) return _streamingMessage();
            final item = items[itemIndex];
            final previousTurnId = itemIndex == 0
                ? null
                : items[itemIndex - 1].turnId;
            final showTurn =
                item.turnId != null && item.turnId != previousTurnId;
            return Column(
              key: ValueKey<String>('timeline-${item.id}'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (showTurn)
                  TimelineTurnDivider(
                    number: turnNumbers[item.turnId] ?? firstTurnNumber,
                  ),
                switch (item) {
                  TimelineMessageItem(:final message) => ChatMessageView(
                    message: message,
                  ),
                  TimelineActivityItem(:final activity) => TimelineActivityView(
                    activity: activity,
                  ),
                },
              ],
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
    return NotificationListener<ScrollNotification>(
      onNotification: onScrollNotification,
      child: ListView.builder(
        key: const ValueKey<String>('chat-message-list'),
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
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

class _ObserverBanner extends StatelessWidget {
  const _ObserverBanner();

  @override
  Widget build(BuildContext context) {
    return TsInfoBand(
      icon: Icons.visibility_outlined,
      message: context.l10n.observerMode,
      tone: TsInfoTone.info,
    );
  }
}

class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner();

  @override
  Widget build(BuildContext context) {
    return TsInfoBand(
      icon: Icons.warning_amber_rounded,
      message: context.l10n.generationDisconnectedBanner,
      tone: TsInfoTone.error,
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onCopy});

  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return TsInfoBand(
      icon: Icons.terminal_outlined,
      message: context.l10n.tspiDisconnectedBanner,
      action: IconButton(
        onPressed: onCopy,
        tooltip: context.l10n.copyStartCommand,
        icon: const Icon(Icons.copy_outlined),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TsInfoBand(
      icon: Icons.cloud_off_outlined,
      message: message,
      tone: TsInfoTone.error,
      action: IconButton(
        onPressed: onRetry,
        tooltip: context.l10n.reconnect,
        color: colors.onErrorContainer,
        icon: const Icon(Icons.refresh),
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

class _StatusBand extends StatelessWidget {
  const _StatusBand({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final values = <String>[
      if (controller.activity != null)
        _plain(controller.activity!.localizedMessage(l10n)),
      for (final value in controller.statuses.values) _plain(value),
    ];
    return TsInfoBand(
      icon: Icons.monitor_heart_outlined,
      message: values.join(' · '),
      tone: TsInfoTone.neutral,
      maxLines: null,
    );
  }
}

class _WidgetBand extends StatelessWidget {
  const _WidgetBand({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      dense: true,
      leading: const Icon(Icons.monitor_heart_outlined, size: 19),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            lines.map(_plain).join('\n'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

String _plain(String value) {
  return value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
}
