import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../models/workspace.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';
import '../../widgets/ts_phone_brand_mark.dart';
import '../chat/chat_page.dart';
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
      final workspaces = await _api.listWorkspaces();
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
    ActionFeedback.selection();
    try {
      final sessions = await _api.listSessions(workspace.id);
      if (!mounted) return;
      final page = sessions.length == 1
          ? ChatPage(
              settings: widget.settings,
              workspace: workspace,
              session: sessions.single,
              recoveredSession:
                  sessions.single.runtimeState == RuntimeState.recoveryRequired,
            )
          : SessionListPage(
              settings: widget.settings,
              workspace: workspace,
              initialSessions: sessions,
            );
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (context) => page));
    } on Object catch (error) {
      if (!mounted) return;
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
    }
    await _refresh();
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
                l10n.appTitle,
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
          IconButton(
            onPressed: _refreshing ? null : () => _refresh(announce: true),
            tooltip: _refreshing ? l10n.refreshing : l10n.refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () {
              ActionFeedback.selection();
              widget.onOpenSettings();
            },
            tooltip: l10n.settings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: TsPageBackdrop(child: _buildBody()),
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
    final list = RefreshIndicator(
      onRefresh: () => _refresh(),
      child: _workspaces!.isEmpty
          ? ListView(
              children: <Widget>[
                const SizedBox(height: 96),
                TsEmptyState(
                  icon: Icons.folder_off_outlined,
                  title: l10n.noWorkspacesTitle,
                  message: l10n.noWorkspacesMessage,
                  action: TextButton.icon(
                    onPressed: () {
                      ActionFeedback.selection();
                      widget.onOpenSettings();
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l10n.connectionSettings),
                  ),
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
              itemCount: _workspaces!.length,
              itemBuilder: (context, index) {
                final workspace = _workspaces![index];
                return _WorkspaceTile(
                  workspace: workspace,
                  latency: _latency,
                  lastSync: _lastSync,
                  onTap: () => _open(workspace),
                );
              },
              separatorBuilder: (context, index) =>
                  const SizedBox(height: TsPhoneSpacing.small),
            ),
    );
    if (_problem == null) return list;
    return Column(
      children: <Widget>[
        _WorkspaceLoadProblemBand(problem: _problem!),
        Expanded(child: list),
      ],
    );
  }
}

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

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.latency,
    required this.lastSync,
    required this.onTap,
  });

  final WorkspaceSummary workspace;
  final Duration? latency;
  final DateTime? lastSync;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = TsPhoneStatusTheme.resolve(context);
    final l10n = context.l10n;
    final stateColor = switch (workspace.runtimeState) {
      RuntimeState.running || RuntimeState.connecting => status.warning,
      RuntimeState.idle => status.connected,
      RuntimeState.recoveryRequired => status.error,
      RuntimeState.offline => colors.outline,
    };
    final stateLabel = switch (workspace.runtimeState) {
      RuntimeState.running => l10n.statusRunning,
      RuntimeState.idle => l10n.statusReady,
      RuntimeState.connecting => l10n.statusConnecting,
      RuntimeState.recoveryRequired => l10n.statusRecovery,
      RuntimeState.offline => l10n.runtimeOffline,
    };
    final sync = lastSync?.toLocal();
    final syncLabel = sync == null
        ? '—'
        : '${sync.hour.toString().padLeft(2, '0')}:${sync.minute.toString().padLeft(2, '0')}';
    final latencyLabel = latency == null
        ? '—'
        : '${latency!.inMilliseconds} ms';
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
                          TsMetadataItem(
                            icon: Icons.speed_rounded,
                            text: '${l10n.tsPhoneService} · $latencyLabel',
                            tooltip: l10n.latency,
                            maxLines: 3,
                          ),
                          TsMetadataItem(
                            icon: Icons.sync_rounded,
                            text: '${l10n.lastSync} · $syncLabel',
                            tooltip: l10n.lastSync,
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: TsPhoneSpacing.xSmall),
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right,
                    size: 21,
                    color: colors.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      TsPhoneProblemKind.request => Icons.error_outline,
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
            icon: const Icon(Icons.refresh),
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
