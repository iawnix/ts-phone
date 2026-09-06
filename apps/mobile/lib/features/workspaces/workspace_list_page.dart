import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../models/workspace.dart';
import '../../navigation/adaptive_page_route.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';
import '../../widgets/ts_phone_brand_mark.dart';
import '../chat/chat_page.dart';
import '../management/management_dialogs.dart';
import '../sessions/session_list_page.dart';

typedef TsPhoneGatewayBuilder =
    TsPhoneGateway Function(ConnectionSettings settings);

class WorkspaceListPage extends StatefulWidget {
  const WorkspaceListPage({
    super.key,
    required this.settings,
    required this.onOpenSettings,
    this.gatewayBuilder,
  });

  final ConnectionSettings settings;
  final VoidCallback onOpenSettings;
  final TsPhoneGatewayBuilder? gatewayBuilder;

  @override
  State<WorkspaceListPage> createState() => _WorkspaceListPageState();
}

class _WorkspaceListPageState extends State<WorkspaceListPage>
    with WidgetsBindingObserver {
  late TsPhoneGateway _api;
  List<WorkspaceSummary>? _workspaces;
  TsPhoneProblem? _problem;
  bool _refreshing = false;
  int _refreshGeneration = 0;
  Duration? _latency;
  DateTime? _lastSync;
  String? _openingWorkspaceId;
  String? _mutatingWorkspaceId;
  bool _creatingWorkspace = false;
  LifecycleState _lifecycleState = LifecycleState.active;
  int _openGeneration = 0;

  TsPhoneManagementGateway? get _managementApi {
    final api = _api;
    return api is TsPhoneManagementGateway
        ? api as TsPhoneManagementGateway
        : null;
  }

  bool get _interactionLocked =>
      _openingWorkspaceId != null ||
      _mutatingWorkspaceId != null ||
      _creatingWorkspace;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = _createGateway();
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh(force: true));
  }

  @override
  void didUpdateWidget(covariant WorkspaceListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.serverUrl != widget.settings.serverUrl ||
        oldWidget.settings.token != widget.settings.token) {
      _openGeneration += 1;
      _openingWorkspaceId = null;
      _api.close();
      _api = _createGateway();
      unawaited(_refresh(force: true));
    }
  }

  TsPhoneGateway _createGateway() =>
      widget.gatewayBuilder?.call(widget.settings) ??
      TsPhoneApi(widget.settings);

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
    final stopwatch = Stopwatch()..start();
    try {
      final management = _managementApi;
      final workspaces = management == null
          ? await _api.listWorkspaces()
          : await management.listWorkspacesByLifecycle(_lifecycleState);
      stopwatch.stop();
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _workspaces = workspaces;
        _problem = null;
        _latency = stopwatch.elapsed;
        _lastSync = DateTime.now();
      });
      if (announce) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.l10n.researchDirectoriesRefreshed),
              duration: const Duration(milliseconds: 1400),
            ),
          );
      }
    } on Object catch (error) {
      if (!mounted || generation != _refreshGeneration) return;
      if (announce) ActionFeedback.error();
      final problem = describeTsPhoneProblem(error);
      setState(() {
        _problem = problem;
      });
      if (announce) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(problem.localizedMessage(context.l10n)),
              duration: const Duration(seconds: 2),
            ),
          );
      }
    } finally {
      if (mounted && generation == _refreshGeneration) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _open(WorkspaceSummary workspace) async {
    if (_interactionLocked ||
        workspace.lifecycleState != LifecycleState.active) {
      return;
    }
    final generation = ++_openGeneration;
    final gateway = _api;
    setState(() => _openingWorkspaceId = workspace.id);
    ActionFeedback.selection();
    try {
      final sessions = await gateway.listSessions(workspace.id);
      if (!mounted ||
          generation != _openGeneration ||
          !identical(gateway, _api)) {
        return;
      }
      final management = _managementApi;
      var session = sessions.length == 1 ? sessions.single : null;
      if (session != null &&
          !session.canPrompt &&
          session.canActivate &&
          management != null) {
        session = await management.activateSession(
          workspace.id,
          session.sessionId,
          session.managementRevision,
        );
      }
      if (!mounted ||
          generation != _openGeneration ||
          !identical(gateway, _api)) {
        return;
      }
      final sessionCanOpen =
          session != null && (session.canPrompt || session.historyAvailable);
      final page = sessionCanOpen
          ? ChatPage(
              settings: widget.settings,
              workspace: workspace,
              session: session,
              recoveredSession:
                  session.runtimeState == RuntimeState.recoveryRequired,
            )
          : SessionListPage(
              settings: widget.settings,
              workspace: workspace,
              initialSessions: sessions,
              gatewayBuilder: widget.gatewayBuilder,
            );
      await pushTsPhonePage<void>(context: context, builder: (context) => page);
    } on Object catch (error) {
      if (!mounted ||
          generation != _openGeneration ||
          !identical(gateway, _api)) {
        return;
      }
      ActionFeedback.error();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              describeTsPhoneProblem(error).localizedMessage(context.l10n),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    } finally {
      if (mounted && generation == _openGeneration) {
        setState(() => _openingWorkspaceId = null);
      }
    }
    if (mounted && generation == _openGeneration) await _refresh();
  }

  void _selectLifecycle(LifecycleState value) {
    if (_lifecycleState == value || _interactionLocked) return;
    ActionFeedback.selection();
    setState(() {
      _lifecycleState = value;
      _workspaces = null;
      _problem = null;
    });
    unawaited(_refresh(force: true));
  }

  Future<void> _createProject() async {
    final management = _managementApi;
    if (management == null || _interactionLocked) return;
    final name = await showNameEditor(
      context,
      title: context.l10n.newProject,
      fieldLabel: context.l10n.projectName,
      actionLabel: context.l10n.createProject,
    );
    if (!mounted || name == null) return;
    setState(() => _creatingWorkspace = true);
    try {
      final created = await management.createWorkspace(name);
      if (!mounted) return;
      setState(() {
        _creatingWorkspace = false;
        _lifecycleState = LifecycleState.active;
      });
      await _refresh(force: true);
      if (mounted) await _open(created.workspace);
    } on Object catch (error) {
      if (mounted) _showProblem(error);
    } finally {
      if (mounted && _creatingWorkspace) {
        setState(() => _creatingWorkspace = false);
      }
    }
  }

  Future<void> _renameProject(WorkspaceSummary workspace) async {
    final name = await showNameEditor(
      context,
      title: context.l10n.rename,
      fieldLabel: context.l10n.projectName,
      actionLabel: context.l10n.save,
      initialValue: workspace.name,
    );
    if (!mounted || name == null || name == workspace.name) return;
    await _runProjectMutation(
      workspace.id,
      (management) => management.renameWorkspace(
        workspace.id,
        workspace.managementRevision,
        name,
      ),
    );
  }

  Future<void> _archiveProject(WorkspaceSummary workspace) =>
      _runProjectMutation(
        workspace.id,
        (management) => management.archiveWorkspace(
          workspace.id,
          workspace.managementRevision,
        ),
      );

  Future<void> _restoreProject(WorkspaceSummary workspace) =>
      _runProjectMutation(
        workspace.id,
        (management) => management.restoreWorkspace(
          workspace.id,
          workspace.managementRevision,
        ),
      );

  Future<void> _trashProject(WorkspaceSummary workspace) async {
    final preflight = await _loadDeletionPreflight(workspace.id);
    if (preflight == null || !mounted) return;
    if (!preflight.canDelete) {
      await showDeletionBlockers(context, preflight);
      return;
    }
    if (!await confirmMoveToTrash(context, project: true) || !mounted) {
      return;
    }
    await _runProjectMutation(
      workspace.id,
      (management) =>
          management.trashWorkspace(workspace.id, preflight.managementRevision),
    );
  }

  Future<void> _purgeProject(WorkspaceSummary workspace) async {
    final preflight = await _loadDeletionPreflight(workspace.id);
    if (preflight == null || !mounted) return;
    if (!preflight.canDelete) {
      await showDeletionBlockers(context, preflight);
      return;
    }
    if (!await confirmPermanentDeletion(context, resourceId: workspace.id) ||
        !mounted) {
      return;
    }
    await _runProjectMutation(
      workspace.id,
      (management) =>
          management.purgeWorkspace(workspace.id, preflight.managementRevision),
    );
  }

  Future<WorkspaceDeletionPreflight?> _loadDeletionPreflight(
    String workspaceId,
  ) async {
    final management = _managementApi;
    if (management == null || _interactionLocked) return null;
    setState(() => _mutatingWorkspaceId = workspaceId);
    try {
      return await management.workspaceDeletionPreflight(workspaceId);
    } on Object catch (error) {
      if (mounted) _showProblem(error);
      return null;
    } finally {
      if (mounted) setState(() => _mutatingWorkspaceId = null);
    }
  }

  Future<void> _runProjectMutation(
    String workspaceId,
    Future<void> Function(TsPhoneManagementGateway management) mutation,
  ) async {
    final management = _managementApi;
    if (management == null || _interactionLocked) return;
    setState(() => _mutatingWorkspaceId = workspaceId);
    try {
      await mutation(management);
      if (mounted) await _refresh(force: true);
    } on Object catch (error) {
      if (mounted) _showProblem(error);
    } finally {
      if (mounted) setState(() => _mutatingWorkspaceId = null);
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

  void _handleProjectAction(
    WorkspaceSummary workspace,
    _WorkspaceAction action,
  ) {
    switch (action) {
      case _WorkspaceAction.rename:
        unawaited(_renameProject(workspace));
      case _WorkspaceAction.archive:
        unawaited(_archiveProject(workspace));
      case _WorkspaceAction.restore:
        unawaited(_restoreProject(workspace));
      case _WorkspaceAction.trash:
        unawaited(_trashProject(workspace));
      case _WorkspaceAction.purge:
        unawaited(_purgeProject(workspace));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: TsGlassAppBar(
        toolbarHeight: 64,
        centerTitle: false,
        titleSpacing: TsPhoneSpacing.large,
        title: Row(
          children: <Widget>[
            const TsPhoneBrandBadge(size: 32),
            const SizedBox(width: TsPhoneSpacing.medium),
            Flexible(
              child: Text(
                l10n.workspaces,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        actions: <Widget>[
          if (_managementApi != null)
            IconButton(
              key: const ValueKey<String>('create-project'),
              onPressed: _interactionLocked ? null : _createProject,
              tooltip: l10n.newProject,
              icon: _creatingWorkspace
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
            ),
          IconButton(
            onPressed: _refreshing ? null : () => _refresh(announce: true),
            tooltip: _refreshing ? l10n.refreshing : l10n.refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            key: const ValueKey<String>('workspace-settings'),
            onPressed: !_interactionLocked
                ? () {
                    ActionFeedback.selection();
                    widget.onOpenSettings();
                  }
                : null,
            tooltip: l10n.settings,
            icon: const Icon(Icons.settings_outlined),
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
    if (_workspaces == null && _problem == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_workspaces == null) {
      return _ErrorView(
        problem: _problem!,
        onRetry: () {
          ActionFeedback.tap();
          unawaited(_refresh());
        },
        onOpenSettings: widget.onOpenSettings,
      );
    }
    final managementAvailable = _managementApi != null;
    final list = RefreshIndicator(
      onRefresh: () => _refresh(),
      child: _workspaces!.isEmpty
          ? ListView(
              children: <Widget>[
                const SizedBox(height: 96),
                TsEmptyState(
                  icon: switch (_lifecycleState) {
                    LifecycleState.active => Icons.folder_open_outlined,
                    LifecycleState.archived => Icons.archive_outlined,
                    LifecycleState.trashed => Icons.delete_outline,
                  },
                  title: switch (_lifecycleState) {
                    LifecycleState.active => l10n.noWorkspacesTitle,
                    LifecycleState.archived => l10n.archiveEmptyTitle,
                    LifecycleState.trashed => l10n.trashEmptyTitle,
                  },
                  message: switch (_lifecycleState) {
                    LifecycleState.active => l10n.noWorkspacesMessage,
                    LifecycleState.archived => l10n.archivedItemsMessage,
                    LifecycleState.trashed => l10n.recentlyDeletedMessage,
                  },
                  action: _lifecycleState == LifecycleState.active
                      ? managementAvailable
                            ? FilledButton.icon(
                                onPressed: _interactionLocked
                                    ? null
                                    : _createProject,
                                icon: const Icon(Icons.add_rounded),
                                label: Text(l10n.createProject),
                              )
                            : TextButton.icon(
                                onPressed: () {
                                  ActionFeedback.selection();
                                  widget.onOpenSettings();
                                },
                                icon: const Icon(Icons.settings_outlined),
                                label: Text(l10n.connectionSettings),
                              )
                      : null,
                ),
              ],
            )
          : ListView.separated(
              key: const ValueKey<String>('workspace-list'),
              padding: const EdgeInsets.fromLTRB(
                TsPhoneSpacing.large,
                TsPhoneSpacing.medium,
                TsPhoneSpacing.large,
                TsPhoneSpacing.xLarge,
              ),
              itemCount: _workspaces!.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _ServiceSyncHeader(
                    latency: _latency,
                    lastSync: _lastSync,
                  );
                }
                final workspace = _workspaces![index - 1];
                return _WorkspaceTile(
                  workspace: workspace,
                  busy:
                      _openingWorkspaceId == workspace.id ||
                      _mutatingWorkspaceId == workspace.id,
                  progressKey: ValueKey<String>(
                    _openingWorkspaceId == workspace.id
                        ? 'workspace-opening-${workspace.id}'
                        : 'workspace-mutation-${workspace.id}',
                  ),
                  onTap:
                      !_interactionLocked &&
                          _lifecycleState == LifecycleState.active
                      ? () => _open(workspace)
                      : null,
                  onAction: managementAvailable && !_interactionLocked
                      ? (action) => _handleProjectAction(workspace, action)
                      : null,
                );
              },
              separatorBuilder: (context, index) =>
                  const SizedBox(height: TsPhoneSpacing.small),
            ),
    );
    final content = Column(
      children: <Widget>[
        if (managementAvailable)
          Padding(
            padding: const EdgeInsets.only(top: TsPhoneSpacing.medium),
            child: LifecycleSwitcher(
              value: _lifecycleState,
              onChanged: _selectLifecycle,
            ),
          ),
        if (_problem != null) _WorkspaceLoadProblemBand(problem: _problem!),
        Expanded(child: list),
      ],
    );
    return content;
  }
}

enum _WorkspaceAction { rename, archive, restore, trash, purge }

class _WorkspaceLoadProblemBand extends StatelessWidget {
  const _WorkspaceLoadProblemBand({required this.problem});

  final TsPhoneProblem problem;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TsInfoBand(
      icon: Icons.cloud_off_outlined,
      message: l10n.workspaceStateStale(problem.localizedMessage(l10n)),
      tone: TsInfoTone.error,
    );
  }
}

class _ServiceSyncHeader extends StatelessWidget {
  const _ServiceSyncHeader({required this.latency, required this.lastSync});

  final Duration? latency;
  final DateTime? lastSync;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sync = lastSync?.toLocal();
    final syncLabel = sync == null
        ? '\u2014'
        : '${sync.hour.toString().padLeft(2, '0')}:${sync.minute.toString().padLeft(2, '0')}';
    final latencyLabel = latency == null
        ? '\u2014'
        : '${latency!.inMilliseconds} ms';
    return TsSectionHeader(
      title: l10n.tsPhoneService,
      caption:
          '${l10n.latency} $latencyLabel \u00b7 ${l10n.lastSync} $syncLabel',
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.busy,
    required this.progressKey,
    required this.onTap,
    required this.onAction,
  });

  final WorkspaceSummary workspace;
  final bool busy;
  final Key progressKey;
  final VoidCallback? onTap;
  final ValueChanged<_WorkspaceAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = TsPhoneStatusTheme.resolve(context);
    final l10n = context.l10n;
    final stateColor = switch (workspace.runtimeState) {
      RuntimeState.running || RuntimeState.connecting => status.warning,
      RuntimeState.idle => status.connected,
      RuntimeState.recoveryRequired => status.error,
      RuntimeState.offline => colors.onSurfaceVariant,
    };
    final stateLabel = switch (workspace.runtimeState) {
      RuntimeState.running => l10n.statusRunning,
      RuntimeState.idle => l10n.statusReady,
      RuntimeState.connecting => l10n.statusConnecting,
      RuntimeState.recoveryRequired => l10n.statusRecovery,
      RuntimeState.offline => l10n.runtimeOffline,
    };
    final title = workspace.name == workspace.id
        ? TsMonoText(
            workspace.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          )
        : Text(
            workspace.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          );
    return Material(
      key: ValueKey<String>('workspace-row-${workspace.id}'),
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TsPhoneRadii.panel),
        side: BorderSide(color: colors.outlineVariant, width: 0.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TsPhoneSpacing.medium,
              TsPhoneSpacing.medium,
              TsPhoneSpacing.small,
              TsPhoneSpacing.medium,
            ),
            child: Row(
              children: <Widget>[
                ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 28,
                    child: Icon(
                      Icons.folder_outlined,
                      size: 21,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: TsPhoneSpacing.small),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Wrap(
                        spacing: TsPhoneSpacing.small,
                        runSpacing: TsPhoneSpacing.xSmall,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          title,
                          if (workspace.runtimeState == RuntimeState.idle)
                            TsReadyStatusIcon(label: stateLabel)
                          else
                            TsInlineStatus(
                              label: stateLabel,
                              color: stateColor,
                              pulsing:
                                  workspace.runtimeState ==
                                      RuntimeState.running ||
                                  workspace.runtimeState ==
                                      RuntimeState.connecting,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: TsPhoneSpacing.medium,
                        runSpacing: 5,
                        children: <Widget>[
                          if (workspace.liveSessionCount > 0)
                            TsMetadataItem(
                              icon: Icons.sensors_rounded,
                              text: l10n.statusLive(workspace.liveSessionCount),
                            ),
                          if (workspace.name != workspace.id)
                            TsMonoText(
                              workspace.id,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: TsPhoneSpacing.xSmall),
                if (busy)
                  Semantics(
                    label: l10n.opening,
                    liveRegion: true,
                    child: ExcludeSemantics(
                      child: SizedBox.square(
                        key: progressKey,
                        dimension: 20,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else ...<Widget>[
                  if (onTap != null)
                    ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_right,
                        size: 21,
                        color: colors.outline,
                      ),
                    ),
                  if (onAction != null)
                    _WorkspaceMenu(
                      lifecycleState: workspace.lifecycleState,
                      onSelected: onAction!,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceMenu extends StatelessWidget {
  const _WorkspaceMenu({
    required this.lifecycleState,
    required this.onSelected,
  });

  final LifecycleState lifecycleState;
  final ValueChanged<_WorkspaceAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actions = switch (lifecycleState) {
      LifecycleState.active => <(_WorkspaceAction, IconData, String)>[
        (_WorkspaceAction.rename, Icons.edit_outlined, l10n.rename),
        (_WorkspaceAction.archive, Icons.archive_outlined, l10n.archive),
        (
          _WorkspaceAction.trash,
          Icons.delete_outline,
          l10n.moveToRecentlyDeleted,
        ),
      ],
      LifecycleState.archived => <(_WorkspaceAction, IconData, String)>[
        (_WorkspaceAction.rename, Icons.edit_outlined, l10n.rename),
        (_WorkspaceAction.restore, Icons.unarchive_outlined, l10n.restore),
        (
          _WorkspaceAction.trash,
          Icons.delete_outline,
          l10n.moveToRecentlyDeleted,
        ),
      ],
      LifecycleState.trashed => <(_WorkspaceAction, IconData, String)>[
        (
          _WorkspaceAction.restore,
          Icons.restore_from_trash_outlined,
          l10n.restore,
        ),
        (
          _WorkspaceAction.purge,
          Icons.delete_forever_outlined,
          l10n.deletePermanently,
        ),
      ],
    };
    return PopupMenuButton<_WorkspaceAction>(
      key: const ValueKey<String>('project-menu'),
      tooltip: l10n.manage,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: onSelected,
      itemBuilder: (context) => actions
          .map(
            (entry) => PopupMenuItem<_WorkspaceAction>(
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.problem,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final TsPhoneProblem problem;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final icon = switch (problem.kind) {
      TsPhoneProblemKind.authentication => Icons.lock_outline,
      TsPhoneProblemKind.incompatible => Icons.sync_problem_outlined,
      TsPhoneProblemKind.unavailable => Icons.cloud_off_outlined,
      TsPhoneProblemKind.request => Icons.error_outline_rounded,
    };
    return TsEmptyState(
      icon: icon,
      title: l10n.loadWorkspacesFailed,
      message: problem.localizedMessage(l10n),
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: TsPhoneSpacing.small,
        runSpacing: TsPhoneSpacing.small,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.retry),
          ),
          TextButton.icon(
            onPressed: () {
              ActionFeedback.selection();
              onOpenSettings();
            },
            icon: const Icon(Icons.settings_outlined),
            label: Text(l10n.connectionSettings),
          ),
        ],
      ),
    );
  }
}
