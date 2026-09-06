import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../models/workspace.dart';
import '../../navigation/adaptive_page_route.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';
import '../chat/chat_page.dart';
import '../management/management_dialogs.dart';

typedef SessionGatewayBuilder =
    TsPhoneGateway Function(ConnectionSettings settings);

class SessionListPage extends StatefulWidget {
  const SessionListPage({
    super.key,
    required this.settings,
    required this.workspace,
    this.initialSessions,
    this.gatewayBuilder,
  });

  final ConnectionSettings settings;
  final WorkspaceSummary workspace;
  final List<SessionSummary>? initialSessions;
  final SessionGatewayBuilder? gatewayBuilder;

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage>
    with WidgetsBindingObserver {
  late final TsPhoneGateway _api;
  List<SessionSummary>? _sessions;
  TsPhoneProblem? _problem;
  bool _refreshing = false;
  int _refreshGeneration = 0;
  String? _openingSessionId;
  String? _mutatingSessionId;
  bool _creatingSession = false;
  LifecycleState _lifecycleState = LifecycleState.active;

  TsPhoneManagementGateway? get _managementApi {
    final api = _api;
    return api is TsPhoneManagementGateway
        ? api as TsPhoneManagementGateway
        : null;
  }

  bool get _interactionLocked =>
      _openingSessionId != null ||
      _mutatingSessionId != null ||
      _creatingSession;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api =
        widget.gatewayBuilder?.call(widget.settings) ??
        TsPhoneApi(widget.settings);
    _sessions = widget.initialSessions == null
        ? null
        : _prioritizeSessions(widget.initialSessions!);
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _api.close();
    super.dispose();
  }

  Future<void> _refresh({bool announce = false, bool force = false}) async {
    if (_refreshing && !force) return;
    final generation = ++_refreshGeneration;
    setState(() => _refreshing = true);
    if (announce) ActionFeedback.tap();
    try {
      final management = _managementApi;
      final sessions = management == null
          ? await _api.listSessions(widget.workspace.id)
          : await management.listSessionsByLifecycle(
              widget.workspace.id,
              _lifecycleState,
            );
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _sessions = _prioritizeSessions(sessions);
        _problem = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _refreshGeneration) return;
      if (announce) ActionFeedback.error();
      setState(() => _problem = describeTsPhoneProblem(error));
    } finally {
      if (mounted && generation == _refreshGeneration) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _open(SessionSummary session) async {
    if (_interactionLocked || session.lifecycleState != LifecycleState.active) {
      return;
    }
    if (!session.canPrompt &&
        !session.historyAvailable &&
        !(session.canActivate && _managementApi != null)) {
      return;
    }
    setState(() => _openingSessionId = session.sessionId);
    ActionFeedback.selection();
    try {
      var selected = session;
      final management = _managementApi;
      if (!selected.canPrompt && selected.canActivate && management != null) {
        selected = await management.activateSession(
          widget.workspace.id,
          selected.sessionId,
          selected.managementRevision,
        );
      }
      if (!mounted) return;
      await pushTsPhonePage<void>(
        context: context,
        builder: (context) => ChatPage(
          settings: widget.settings,
          workspace: widget.workspace,
          session: selected,
          recoveredSession:
              selected.runtimeState == RuntimeState.recoveryRequired,
        ),
      );
      if (mounted) await _refresh();
    } on Object catch (error) {
      if (mounted) _showProblem(error);
    } finally {
      if (mounted) setState(() => _openingSessionId = null);
    }
  }

  void _selectLifecycle(LifecycleState value) {
    if (_lifecycleState == value || _interactionLocked) return;
    ActionFeedback.selection();
    setState(() {
      _lifecycleState = value;
      _sessions = null;
      _problem = null;
    });
    unawaited(_refresh(force: true));
  }

  Future<void> _createManagedSession() async {
    final management = _managementApi;
    if (management == null || _interactionLocked) return;
    final draft = await showSessionCreator(context);
    if (!mounted || draft == null) return;
    setState(() => _creatingSession = true);
    try {
      final created = await management.createSession(
        widget.workspace.id,
        accessMode: draft.accessMode,
        name: draft.name,
        model: draft.model,
      );
      if (!mounted) return;
      setState(() {
        _creatingSession = false;
        _lifecycleState = LifecycleState.active;
      });
      await _refresh(force: true);
      if (mounted &&
          (created.canPrompt ||
              created.historyAvailable ||
              (created.canActivate && _managementApi != null))) {
        await _open(created);
      }
    } on Object catch (error) {
      if (mounted) _showProblem(error);
    } finally {
      if (mounted && _creatingSession) {
        setState(() => _creatingSession = false);
      }
    }
  }

  Future<void> _renameSession(SessionSummary session) async {
    final name = await showNameEditor(
      context,
      title: context.l10n.rename,
      fieldLabel: context.l10n.sessionNameOptional,
      actionLabel: context.l10n.save,
      initialValue: session.sessionName ?? '',
    );
    if (!mounted || name == null || name == session.sessionName) return;
    await _runSessionMutation(
      session.sessionId,
      (management) => management.renameSession(
        widget.workspace.id,
        session.sessionId,
        session.managementRevision,
        name,
      ),
    );
  }

  Future<void> _archiveSession(SessionSummary session) => _runSessionMutation(
    session.sessionId,
    (management) => management.archiveSession(
      widget.workspace.id,
      session.sessionId,
      session.managementRevision,
    ),
  );

  Future<void> _restoreSession(SessionSummary session) => _runSessionMutation(
    session.sessionId,
    (management) => management.restoreSession(
      widget.workspace.id,
      session.sessionId,
      session.managementRevision,
    ),
  );

  Future<void> _trashSession(SessionSummary session) async {
    if (!await confirmMoveToTrash(context, project: false) || !mounted) {
      return;
    }
    await _runSessionMutation(
      session.sessionId,
      (management) => management.trashSession(
        widget.workspace.id,
        session.sessionId,
        session.managementRevision,
      ),
    );
  }

  Future<void> _purgeSession(SessionSummary session) async {
    if (!await confirmPermanentDeletion(
          context,
          resourceId: session.sessionId,
        ) ||
        !mounted) {
      return;
    }
    await _runSessionMutation(
      session.sessionId,
      (management) => management.purgeSession(
        widget.workspace.id,
        session.sessionId,
        session.managementRevision,
      ),
    );
  }

  Future<void> _runSessionMutation(
    String sessionId,
    Future<void> Function(TsPhoneManagementGateway management) mutation,
  ) async {
    final management = _managementApi;
    if (management == null || _interactionLocked) return;
    setState(() => _mutatingSessionId = sessionId);
    try {
      await mutation(management);
      if (mounted) await _refresh(force: true);
    } on Object catch (error) {
      if (mounted) _showProblem(error);
    } finally {
      if (mounted) setState(() => _mutatingSessionId = null);
    }
  }

  void _showProblem(Object error) {
    ActionFeedback.error();
    final message = describeTsPhoneProblem(
      error,
    ).localizedMessage(context.l10n);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  void _handleSessionAction(SessionSummary session, _SessionAction action) {
    switch (action) {
      case _SessionAction.rename:
        unawaited(_renameSession(session));
      case _SessionAction.archive:
        unawaited(_archiveSession(session));
      case _SessionAction.restore:
        unawaited(_restoreSession(session));
      case _SessionAction.trash:
        unawaited(_trashSession(session));
      case _SessionAction.purge:
        unawaited(_purgeSession(session));
    }
  }

  Future<void> _copyStartCommand() async {
    ActionFeedback.tap();
    await Clipboard.setData(
      ClipboardData(text: './TSPi --workspace ${widget.workspace.id} --phone'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.startCommandCopied),
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: TsGlassAppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
        title: Text(widget.workspace.name),
        actions: <Widget>[
          if (_managementApi != null &&
              _lifecycleState == LifecycleState.active)
            IconButton(
              key: const ValueKey<String>('create-session'),
              onPressed: _interactionLocked ? null : _createManagedSession,
              tooltip: l10n.newSession,
              icon: _creatingSession
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_comment_outlined),
            ),
          IconButton(
            onPressed: _refreshing ? null : () => _refresh(announce: true),
            tooltip: _refreshing ? l10n.refreshing : l10n.refreshSessions,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: TsPageBackdrop(
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: TsPhoneSpacing.xLarge),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = context.l10n;
    if (_sessions == null && _problem == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sessions == null) {
      return _SessionError(problem: _problem!, onRetry: _refresh);
    }
    if (_sessions!.isEmpty) {
      return Column(
        children: <Widget>[
          if (_managementApi != null)
            Padding(
              padding: const EdgeInsets.only(top: TsPhoneSpacing.medium),
              child: LifecycleSwitcher(
                value: _lifecycleState,
                onChanged: _selectLifecycle,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 72, 0, 24),
                children: <Widget>[
                  TsEmptyState(
                    icon: switch (_lifecycleState) {
                      LifecycleState.active => Icons.chat_bubble_outline,
                      LifecycleState.archived => Icons.archive_outlined,
                      LifecycleState.trashed => Icons.delete_outline,
                    },
                    title: switch (_lifecycleState) {
                      LifecycleState.active => l10n.noSessionHistoryTitle,
                      LifecycleState.archived => l10n.archiveEmptyTitle,
                      LifecycleState.trashed => l10n.trashEmptyTitle,
                    },
                    message: switch (_lifecycleState) {
                      LifecycleState.active => l10n.noSessionHistoryMessage,
                      LifecycleState.archived => l10n.archivedItemsMessage,
                      LifecycleState.trashed => l10n.recentlyDeletedMessage,
                    },
                    action: _lifecycleState == LifecycleState.active
                        ? _managementApi != null
                              ? FilledButton.icon(
                                  onPressed: _interactionLocked
                                      ? null
                                      : _createManagedSession,
                                  icon: const Icon(Icons.add_comment_outlined),
                                  label: Text(l10n.createSession),
                                )
                              : FilledButton.icon(
                                  onPressed: _copyStartCommand,
                                  icon: const Icon(Icons.copy_rounded),
                                  label: Text(l10n.copyStartCommand),
                                )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: <Widget>[
        if (_managementApi != null)
          Padding(
            padding: const EdgeInsets.only(top: TsPhoneSpacing.medium),
            child: LifecycleSwitcher(
              value: _lifecycleState,
              onChanged: _selectLifecycle,
            ),
          ),
        if (_problem != null)
          TsInfoBand(
            icon: Icons.cloud_off_outlined,
            message: l10n.sessionStateStale(_problem!.localizedMessage(l10n)),
            tone: TsInfoTone.error,
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: TsPhoneSpacing.xLarge),
              itemCount: _sessions!.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final liveCount = _sessions!
                      .where((session) => session.canPrompt)
                      .length;
                  return TsSectionHeader(
                    title: l10n.sessions,
                    caption:
                        '${l10n.sessionCount(_sessions!.length)} · ${l10n.liveSessionCount(liveCount)}',
                  );
                }
                final session = _sessions![index - 1];
                return _SessionTile(
                  session: session,
                  busy:
                      _openingSessionId == session.sessionId ||
                      _mutatingSessionId == session.sessionId,
                  onTap:
                      !_interactionLocked &&
                          _lifecycleState == LifecycleState.active &&
                          (session.canPrompt ||
                              session.historyAvailable ||
                              session.canActivate)
                      ? () => _open(session)
                      : null,
                  onAction: _managementApi != null && !_interactionLocked
                      ? (action) => _handleSessionAction(session, action)
                      : null,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

enum _SessionAction { rename, archive, restore, trash, purge }

List<SessionSummary> _prioritizeSessions(List<SessionSummary> sessions) {
  final indexed = sessions.asMap().entries.toList(growable: false);
  indexed.sort((left, right) {
    final priority = _sessionDisplayPriority(
      left.value,
    ).compareTo(_sessionDisplayPriority(right.value));
    return priority != 0 ? priority : left.key.compareTo(right.key);
  });
  return indexed.map((entry) => entry.value).toList(growable: false);
}

int _sessionDisplayPriority(SessionSummary session) {
  if (session.isStreaming || session.runtimeState == RuntimeState.running) {
    return 0;
  }
  if (session.canPrompt && session.runtimeState == RuntimeState.idle) return 1;
  if (session.canPrompt || session.runtimeState == RuntimeState.connecting) {
    return 2;
  }
  if (session.runtimeState == RuntimeState.recoveryRequired) return 3;
  return 4;
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.busy,
    required this.onTap,
    required this.onAction,
  });

  final SessionSummary session;
  final bool busy;
  final VoidCallback? onTap;
  final ValueChanged<_SessionAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = TsPhoneStatusTheme.resolve(context);
    final l10n = context.l10n;
    final stateColor = switch (session.runtimeState) {
      RuntimeState.running || RuntimeState.connecting => status.warning,
      RuntimeState.idle => status.connected,
      RuntimeState.recoveryRequired => status.error,
      RuntimeState.offline => colors.onSurfaceVariant,
    };
    final accessIcon = session.historyOnly
        ? Icons.history_rounded
        : switch (session.accessMode) {
            SessionAccessMode.controller => Icons.admin_panel_settings_outlined,
            SessionAccessMode.observer => Icons.visibility_outlined,
          };
    final accessLabel = <String>[
      session.historyOnly
          ? l10n.historySession
          : session.accessMode.localizedLabel(l10n),
      if (session.displayModel != null) session.displayModel!,
    ].join(' · ');
    return TsStatusListTile(
      statusColor: stateColor,
      icon: accessIcon,
      title: session.localizedDisplayName(l10n),
      titleTrailing: session.runtimeState == RuntimeState.idle
          ? TsReadyStatusIcon(
              label: session.runtimeState.localizedCompactLabel(l10n),
            )
          : TsInlineStatus(
              label: session.runtimeState.localizedCompactLabel(l10n),
              color: stateColor,
              pulsing:
                  session.runtimeState == RuntimeState.running ||
                  session.runtimeState == RuntimeState.connecting,
            ),
      subtitle: accessLabel,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            accessLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          TsMonoText(
            l10n.sessionToken(session.shortId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
      trailing: busy
          ? Semantics(
              label: l10n.opening,
              liveRegion: true,
              child: ExcludeSemantics(
                child: SizedBox.square(
                  key: ValueKey<String>('session-opening-${session.sessionId}'),
                  dimension: 20,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : onAction == null
          ? null
          : _SessionMenu(
              lifecycleState: session.lifecycleState,
              onSelected: onAction!,
            ),
      onTap: onTap,
    );
  }
}

class _SessionMenu extends StatelessWidget {
  const _SessionMenu({required this.lifecycleState, required this.onSelected});

  final LifecycleState lifecycleState;
  final ValueChanged<_SessionAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actions = switch (lifecycleState) {
      LifecycleState.active => <(_SessionAction, IconData, String)>[
        (_SessionAction.rename, Icons.edit_outlined, l10n.rename),
        (_SessionAction.archive, Icons.archive_outlined, l10n.archive),
        (
          _SessionAction.trash,
          Icons.delete_outline,
          l10n.moveToRecentlyDeleted,
        ),
      ],
      LifecycleState.archived => <(_SessionAction, IconData, String)>[
        (_SessionAction.rename, Icons.edit_outlined, l10n.rename),
        (_SessionAction.restore, Icons.unarchive_outlined, l10n.restore),
        (
          _SessionAction.trash,
          Icons.delete_outline,
          l10n.moveToRecentlyDeleted,
        ),
      ],
      LifecycleState.trashed => <(_SessionAction, IconData, String)>[
        (
          _SessionAction.restore,
          Icons.restore_from_trash_outlined,
          l10n.restore,
        ),
        (
          _SessionAction.purge,
          Icons.delete_forever_outlined,
          l10n.deletePermanently,
        ),
      ],
    };
    return PopupMenuButton<_SessionAction>(
      tooltip: l10n.manage,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: onSelected,
      itemBuilder: (context) => actions
          .map(
            (entry) => PopupMenuItem<_SessionAction>(
              value: entry.$1,
              child: Row(
                children: <Widget>[
                  Icon(entry.$2, size: 20),
                  const SizedBox(width: TsPhoneSpacing.medium),
                  Flexible(child: Text(entry.$3)),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SessionError extends StatelessWidget {
  const _SessionError({required this.problem, required this.onRetry});

  final TsPhoneProblem problem;
  final Future<void> Function({bool announce}) onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TsEmptyState(
      icon: Icons.cloud_off_outlined,
      title: l10n.loadSessionsFailed,
      message: problem.localizedMessage(l10n),
      action: IconButton.filledTonal(
        onPressed: () => onRetry(announce: true),
        tooltip: l10n.retry,
        icon: const Icon(Icons.refresh_rounded),
      ),
    );
  }
}
