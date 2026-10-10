import 'dart:async';

import 'package:flutter/material.dart';
import 'package:corhub/theme/app_icons.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

import '../../data/host_gateway.dart';
import '../../data/corhub_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/chat_message.dart';
import '../../models/connection_settings.dart';
import '../../models/workspace.dart';
import '../../models/host_monitor.dart';
import '../../models/workspace_file.dart';
import '../../models/file_reference.dart';
import '../files/files_page.dart';
import '../monitors/monitor_page.dart';
import '../../navigation/adaptive_page_route.dart';
import '../../theme/corhub_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/chat_message_view.dart';
import '../../widgets/presentation.dart';
import 'chat_controller.dart';
import 'chat_composer.dart';
import 'chat_view_memory.dart';
import 'session_notice.dart';
import 'session_view_state.dart';
import 'model_picker.dart';
import 'model_presentation.dart';

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
    this.embedded = false,
  });

  final ConnectionSettings settings;
  final WorkspaceSummary workspace;
  final SessionSummary session;
  final bool recoveredSession;
  final CorHubGateway? gateway;
  final CorHubGateway Function()? gatewayFactory;
  final ChatViewMemory? memory;
  final bool embedded;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  late final ChatViewMemory _memory;
  late final ChatController _controller;
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  final _scroll = ScrollController();
  final _streamUpdatesEnabled = ValueNotifier<bool>(true);
  bool _following = true;
  bool _positioned = false;
  int _scrollGeneration = 0;
  bool _scrollUpdateScheduled = false;
  bool _sending = false;
  bool _aborting = false;
  bool _abortConfirmationOpen = false;
  bool _hasDraft = false;
  bool _syncingDraft = false;
  List<FileReference> _files = [];
  String get _wireDraft => ReferencedDraft(_composer.text, _files).wire;
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
    final draft = ReferencedDraft.parse(_memory.draft);
    _files = draft.files;
    _composer.text = draft.text;
    _hasDraft = _wireDraft.trim().isNotEmpty;
    if (widget.memory?.preview?.revision == widget.session.sessionRevision &&
        widget.memory?.following == false) {
      _following = false;
      _streamUpdatesEnabled.value = false;
    }
    _composer.addListener(_onComposerChanged);
    _memory.addListener(_onDraftChanged);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _memory.removeListener(_onDraftChanged);
    _memory.draft = _wireDraft;
    final preview = _controller.historyPreview;
    _memory.preview = preview.isBounded ? preview : null;
    _memory.following = _following;
    _memory.scrollOffset = _scroll.hasClients ? _scroll.offset : 0;
    WidgetsBinding.instance.removeObserver(this);
    _controller.streamingTextUpdates.removeListener(_onStreamingTextUpdate);
    _controller
      ..removeListener(_onControllerUpdate)
      ..dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    _streamUpdatesEnabled.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resumeEventStream();
    } else if (state != AppLifecycleState.inactive) {
      _controller.suspendEventStream();
    }
  }

  void _onControllerUpdate() {
    _scheduleScrollUpdate();
  }

  void _onStreamingTextUpdate() {
    if (_following) _scheduleScrollUpdate();
  }

  void _scheduleScrollUpdate() {
    if (_scrollUpdateScheduled) return;
    _scrollUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollUpdateScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      if (!_positioned) {
        _positioned = true;
        if (!_following) {
          _scroll.jumpTo(
            _memory.scrollOffset.clamp(0, _scroll.position.maxScrollExtent),
          );
        } else {
          unawaited(_settleLatest());
        }
      } else if (_following && !_scroll.position.isScrollingNotifier.value) {
        unawaited(_settleLatest());
      }
    });
  }

  void _resumeTailFollow() {
    _scrollGeneration++;
    setState(() {
      _following = true;
      _streamUpdatesEnabled.value = true;
    });
    _scheduleScrollUpdate();
  }

  bool _settlingLatest = false;
  Future<void> _settleLatest() async {
    if (_settlingLatest) return;
    _settlingLatest = true;
    final generation = _scrollGeneration;
    try {
      for (var i = 0; i < _controller.messages.length + 2; i++) {
        if (!mounted ||
            !_following ||
            !_scroll.hasClients ||
            generation != _scrollGeneration) {
          return;
        }
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scroll.hasClients) return;
        if ((_scroll.position.maxScrollExtent - _scroll.offset).abs() < .5) {
          return;
        }
      }
    } finally {
      _settlingLatest = false;
    }
  }

  void _jumpToStart() {
    if (!_scroll.hasClients) return;
    _scrollGeneration++;
    setState(() {
      _following = false;
      _streamUpdatesEnabled.value = false;
    });
    _scroll.jumpTo(0);
  }

  void _showDetails() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _navigationTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(widget.workspace.name),
                if (_controller.selectedModelReference case final model?)
                  _ContextDetailRow(
                    label: context.l10n.sessionModel,
                    value: model,
                  ),
                const SizedBox(height: 12),
                SelectableText(widget.session.sessionId),
                TextButton.icon(
                  icon: const Icon(AppIcons.copy_rounded),
                  label: Text(context.l10n.copySessionId),
                  onPressed: () async {
                    try {
                      await Clipboard.setData(
                        ClipboardData(text: widget.session.sessionId),
                      );
                      if (mounted) {
                        _showActionMessage(this.context.l10n.sessionIdCopied);
                      }
                    } catch (_) {
                      if (mounted) {
                        _showActionMessage(
                          this.context.l10n.copySessionIdFailed,
                        );
                      }
                    }
                  },
                ),
                if (_controller.sessionRuntime?.context case final usage?)
                  _ContextUsageSheet(usage: usage),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: _buildTranscript(),
      builder: (context, transcript) {
        final state = SessionViewState.fromController(_controller);
        final retry = _controller.outbox.messages
            .where((m) => m.state == ChatDeliveryState.uncertain)
            .firstOrNull;
        return Scaffold(
          appBar: TsGlassAppBar(
            toolbarHeight: 62,
            centerTitle: false,
            titleSpacing: 0,
            automaticallyImplyLeading: false,
            leading: BackButton(
              key: const ValueKey('chat-back'),
              onPressed: _goBack,
            ),
            title: Tooltip(
              message: context.l10n.sessionRuntimeDetails,
              child: InkWell(
                key: const ValueKey('chat-session-details'),
                onTap: _showDetails,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: _ChatNavigationTitle(
                    key: const ValueKey('chat-session-title'),
                    title: _navigationTitle,
                    workspace: widget.workspace.name,
                  ),
                ),
              ),
            ),
            actions: [
              if (_controller.api is HostMonitorGateway)
                IconButton(
                  key: const ValueKey('chat-monitor'),
                  tooltip: context.l10n.monitorTitle,
                  icon: const Icon(AppIcons.motion_photos_on_outlined),
                  onPressed: () => pushCorHubPage<void>(
                    context: context,
                    builder: (_) => MonitorPage(
                      workspace: widget.workspace,
                      sessionId: widget.session.sessionId,
                      sessionTitle: _navigationTitle,
                      gateway: _controller.api as HostMonitorGateway,
                      readOnly:
                          _controller.accessMode == SessionAccessMode.observer,
                      onOpenFiles: _controller.api is WorkspaceFileGateway
                          ? _openFiles
                          : null,
                    ),
                  ),
                ),
              if (_controller.messages.length > 12)
                IconButton(
                  key: const ValueKey('chat-jump-to-start'),
                  tooltip: context.l10n.jumpToStart,
                  icon: const Icon(AppIcons.vertical_align_top),
                  onPressed: _jumpToStart,
                ),
              _SessionStatusButton(
                state: state,
                runtimeState: _controller.runtimeState,
                onPressed: _showSessionStatus,
              ),
            ],
          ),
          body: TsPageBackdrop(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    if (state.notice != null)
                      SessionNoticeView(
                        state: state,
                        problem: _controller.problem,
                        onRetry: _retryConnection,
                      ),
                    Expanded(child: transcript!),
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_following)
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                key: const ValueKey('jump-to-latest'),
                                tooltip: context.l10n.jumpToLatest,
                                icon: const Icon(
                                  AppIcons.arrow_downward_rounded,
                                ),
                                onPressed: _resumeTailFollow,
                              ),
                            ),
                          if (retry != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                key: const ValueKey('retry-message'),
                                onPressed:
                                    _controller.canSend &&
                                        !_controller.commandInFlight &&
                                        !_sending
                                    ? () => _send(retryText: retry.text)
                                    : null,
                                icon: const Icon(AppIcons.refresh_rounded),
                                label: Text(context.l10n.retry),
                              ),
                            ),
                          _buildComposer(
                            context,
                            maxLines:
                                MediaQuery.sizeOf(context).height -
                                        MediaQuery.viewInsetsOf(
                                          context,
                                        ).bottom <
                                    500
                                ? 2
                                : 5,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTranscript() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _controller.messagesUpdates,
        _controller.streamingTextUpdates,
      ]),
      builder: (context, _) {
        final messages = _controller.messages;
        if (messages.isEmpty && !_controller.hasStreamingText) {
          return const _EmptyConversationView();
        }
        return NotificationListener<UserScrollNotification>(
          onNotification: (event) {
            if (event.direction != ScrollDirection.idle) {
              _scrollGeneration++;
              final following = event.metrics.extentAfter <= 24;
              if (_following != following) {
                setState(() {
                  _following = following;
                  _streamUpdatesEnabled.value = following;
                });
              }
            }
            return false;
          },
          child: ListView.builder(
            key: const ValueKey('chat-transcript'),
            controller: _scroll,

            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: messages.length + 1,
            itemBuilder: (context, index) {
              if (index == messages.length) {
                return StreamingChatMessageView(
                  textListenable: _controller.streamingTextUpdates,
                  updatesEnabledListenable: _streamUpdatesEnabled,
                );
              }
              final message = messages[index];
              return ChatMessageView(
                key: ValueKey(message.clientMessageId ?? 'message-$index'),
                message: message,
                animate: false,
              );
            },
          ),
        );
      },
    );
  }

  void _onComposerChanged() {
    if (_syncingDraft) return;
    _memory.draft = _wireDraft;
    final hasDraft = _wireDraft.trim().isNotEmpty;
    if (hasDraft != _hasDraft && mounted) {
      setState(() => _hasDraft = hasDraft);
    }
  }

  void _onDraftChanged() {
    if (_wireDraft == _memory.draft) return;
    final draft = ReferencedDraft.parse(_memory.draft);
    _syncingDraft = true;
    _files = draft.files;
    _composer.value = TextEditingValue(
      text: draft.text,
      selection: TextSelection.collapsed(offset: draft.text.length),
    );
    _syncingDraft = false;
    if (mounted) setState(() => _hasDraft = _wireDraft.trim().isNotEmpty);
  }

  Future<void> _send({String? retryText}) async {
    if (_sending) return;
    final text = retryText ?? _wireDraft;
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
        animationStyle: CorHubMotion.resolveAnimationStyle(context),
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
        _controller.messages.isNotEmpty || _controller.hasStreamingText;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: CorHubMotion.resolveAnimationStyle(context),
      builder: (context) => _SessionStatusSheet(
        state: state,
        runtimeState: _controller.runtimeState,
        problem: _controller.problem,
        hasCachedContent: hasCachedContent,
        onRetry: () => unawaited(_retryConnection()),
      ),
    );
  }

  void _showContextUsage(SessionContextUsage usage) {
    ActionFeedback.selection();
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: CorHubMotion.resolveAnimationStyle(context),
      builder: (context) => _ContextUsageSheet(usage: usage),
    );
  }

  void _goBack() {
    ActionFeedback.selection();
    Navigator.of(context).maybePop();
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
            CorHubSpacing.medium,
            0,
            CorHubSpacing.medium,
            CorHubSpacing.large,
          ),
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

  Widget _buildComposer(BuildContext context, {required int maxLines}) {
    final viewState = SessionViewState.fromController(_controller);
    final canDraft = !viewState.isHistorical;
    final modelReference = _controller.selectedModelReference;
    final separator = modelReference?.indexOf('/') ?? -1;
    final provider = separator > 0
        ? modelReference!.substring(0, separator)
        : null;
    final modelId = separator >= 0
        ? modelReference!.substring(separator + 1)
        : modelReference;
    final contextUsage = _controller.sessionRuntime?.context;
    return ChatComposer(
      controller: _composer,
      focusNode: _composerFocus,
      canEdit: viewState.canCompose || canDraft,
      canSend: viewState.canCompose && !_sending && _hasDraft,
      sending: _sending,
      maxLines: maxLines,
      onSend: _send,
      files: _files,
      onRemoveFile: (file) {
        setState(() => _files.remove(file));
        _onComposerChanged();
      },
      onOpenFiles: _controller.api is WorkspaceFileGateway ? _openFiles : null,
      hint: viewState.canCompose
          ? context.l10n.composerMessage
          : _composerHint(),
      status: viewState.canCompose || _controller.commandInFlight
          ? null
          : _composerHint(),
      modelLabel: modelId,
      modelProvider: provider,
      modelHint: _modelSelectionHint,
      canSelectModel: _controller.canSelectModel,
      onSelectModel: _chooseModel,
      contextUsage: contextUsage,
      onContextTap: contextUsage == null
          ? null
          : () => _showContextUsage(contextUsage),
      onAbort: viewState.canAbort ? _confirmAbort : null,
      aborting: _aborting,
    );
  }

  void _openFiles() {
    final gateway = _controller.api;
    if (gateway is! WorkspaceFileGateway) return;
    unawaited(
      pushCorHubPage<void>(
        context: context,
        builder: (_) => FilesPage(
          gateway: gateway as WorkspaceFileGateway,
          workspaceId: widget.workspace.id,
          onReference: SessionViewState.fromController(_controller).isHistorical
              ? null
              : (reference) {
                  if (!mounted) return;
                  setState(() => _files.add(reference));
                  _onComposerChanged();
                  final route = ModalRoute.of(context);
                  Navigator.of(
                    context,
                  ).popUntil((candidate) => candidate == route);
                  _composerFocus.requestFocus();
                },
        ),
      ),
    );
  }

  String _composerHint() {
    final l10n = context.l10n;
    if (!_controller.canSend &&
        _controller.accessMode == SessionAccessMode.observer) {
      return l10n.composerReadOnly;
    }
    return switch (SessionViewState.fromController(_controller).phase) {
      SessionUiPhase.failed => l10n.composerReconnecting,
      SessionUiPhase.recovery => l10n.composerRecovery,
      SessionUiPhase.offline =>
        _controller.historyOnly ? l10n.composerHistory : l10n.composerOffline,
      SessionUiPhase.history => l10n.composerReadOnly,
      SessionUiPhase.synchronizing => l10n.composerSynchronizing,
      SessionUiPhase.running => l10n.composerMessage,
      SessionUiPhase.reconnecting => l10n.composerReconnecting,
      SessionUiPhase.ready => l10n.composerMessage,
    };
  }
}

class _ChatNavigationTitle extends StatelessWidget {
  const _ChatNavigationTitle({
    super.key,
    required this.title,
    required this.workspace,
  });

  final String title;
  final String workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
        if (workspace.trim().isNotEmpty) ...<Widget>[
          const SizedBox(width: 8),
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
        ],
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
            duration: CorHubMotion.resolveFade(context, CorHubMotion.quick),
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
          TsStatusGlyph(
            kind: visual.kind,
            color: visual.color,
            icon: visual.icon,
            pulsing: visual.pulsing,
          ),
          if (runtimeRunning && visual.kind != TsStatusGlyphKind.dot)
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
  final CorHubProblem? problem;
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
        CorHubSpacing.large,
        0,
        CorHubSpacing.large,
        CorHubSpacing.large + MediaQuery.viewPaddingOf(context).bottom,
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
              const SizedBox(width: CorHubSpacing.medium),
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
          const SizedBox(height: CorHubSpacing.small),
          if (runtimeState == RuntimeState.running &&
              state.phase != SessionUiPhase.running)
            Text(
              runtimeState.localizedCompactLabel(l10n),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (hasCachedContent && canRetry) ...<Widget>[
            const SizedBox(height: CorHubSpacing.xSmall),
            Text(
              l10n.sessionRuntimeLastKnown,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (problem != null && !_isTransportProblem(problem)) ...<Widget>[
            const SizedBox(height: CorHubSpacing.small),
            Text(
              problem!.localizedMessage(l10n),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (canRetry) ...<Widget>[
            const SizedBox(height: CorHubSpacing.medium),
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

class _ContextUsageSheet extends StatelessWidget {
  const _ContextUsageSheet({required this.usage});

  final SessionContextUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = usage.usedTokens;
    final remaining = usage.remainingTokens;
    final percent = usage.percent;
    final color = percent == null
        ? theme.colorScheme.onSurfaceVariant
        : percent >= 85
        ? theme.colorScheme.error
        : percent >= 70
        ? CorHubStatusTheme.resolve(context).warning
        : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.sessionRuntimeDetails,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  used == null
                      ? context.l10n.sessionContextUnavailable
                      : '${formatTokenCount(used)} / ${formatTokenCount(usage.limitTokens)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (percent != null)
                Text(
                  '${percent.round()}%',
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: ((percent ?? 0) / 100).clamp(0.0, 1.0),
              backgroundColor: color.withValues(alpha: .14),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 18),
          _ContextDetailRow(
            label: context.l10n.sessionContextWindow,
            value: formatTokenCount(usage.limitTokens),
          ),
          _ContextDetailRow(
            label: context.l10n.sessionContextRemaining,
            value: remaining == null
                ? context.l10n.sessionContextUnavailable
                : formatTokenCount(remaining),
          ),
          _ContextDetailRow(
            label: context.l10n.sessionContextSource,
            value: context.l10n.sessionContextEstimate,
          ),
        ],
      ),
    );
  }
}

class _ContextDetailRow extends StatelessWidget {
  const _ContextDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
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
        padding: const EdgeInsets.all(CorHubSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              AppIcons.chat_bubble_outline_rounded,
              size: 28,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: CorHubSpacing.small),
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
    required this.kind,
    required this.color,
    this.icon,
    this.pulsing = false,
  });

  final TsStatusGlyphKind kind;
  final IconData? icon;
  final Color color;
  final bool pulsing;
}

_SessionStatusVisual _sessionStatusVisual(
  BuildContext context,
  SessionViewState state,
) {
  final theme = Theme.of(context);
  final status = CorHubStatusTheme.resolve(context);
  return switch (state.phase) {
    SessionUiPhase.failed => _SessionStatusVisual(
      kind: TsStatusGlyphKind.icon,
      icon: AppIcons.error_outline_rounded,
      color: status.error,
    ),
    SessionUiPhase.recovery => _SessionStatusVisual(
      kind: TsStatusGlyphKind.icon,
      icon: AppIcons.restore_rounded,
      color: status.error,
    ),
    SessionUiPhase.history => _SessionStatusVisual(
      kind: TsStatusGlyphKind.icon,
      icon: AppIcons.history_rounded,
      color: theme.colorScheme.onSurfaceVariant,
    ),
    SessionUiPhase.offline => _SessionStatusVisual(
      kind: TsStatusGlyphKind.hollow,
      color: theme.colorScheme.outline,
    ),
    SessionUiPhase.synchronizing => _SessionStatusVisual(
      kind: TsStatusGlyphKind.ring,
      color: status.warning,
      pulsing: true,
    ),
    SessionUiPhase.reconnecting => _SessionStatusVisual(
      kind: TsStatusGlyphKind.hollow,
      color: status.warning,
      pulsing: true,
    ),
    SessionUiPhase.running => _SessionStatusVisual(
      kind: TsStatusGlyphKind.dot,
      color: status.connected,
      pulsing: true,
    ),
    SessionUiPhase.ready => _SessionStatusVisual(
      kind: TsStatusGlyphKind.dot,
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
    runtimeState == RuntimeState.running &&
        state.phase != SessionUiPhase.running
    ? '${_sessionStatusLabel(context, state)} · ${runtimeState.localizedCompactLabel(context.l10n)}'
    : _sessionStatusLabel(context, state);

bool _isTransportProblem(CorHubProblem? problem) =>
    problem?.code == CorHubProblemCode.serviceUnavailable ||
    problem?.code == CorHubProblemCode.connectionFailed ||
    problem?.code == CorHubProblemCode.requestTimeout ||
    problem?.code == CorHubProblemCode.networkRetrying ||
    problem?.code == CorHubProblemCode.sessionOffline;
