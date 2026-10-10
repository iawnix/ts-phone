import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../data/corhub_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../l10n/host_monitor_localizations.dart';
import '../../models/host_monitor.dart';
import '../../models/workspace.dart';
import '../../navigation/adaptive_page_route.dart';
import '../../widgets/presentation.dart';
import 'monitor_controller.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({
    super.key,
    required this.workspace,
    required this.gateway,
    required this.sessionId,
    this.sessionTitle,
    this.readOnly = false,
    this.onOpenFiles,
  });
  final WorkspaceSummary workspace;
  final HostMonitorGateway gateway;
  final String sessionId;
  final String? sessionTitle;
  final bool readOnly;
  final VoidCallback? onOpenFiles;
  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> with WidgetsBindingObserver {
  late final MonitorController controller;
  bool jobsTab = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = MonitorController(
      widget.gateway,
      widget.workspace.id,
      widget.sessionId,
    )..addListener(_changed);
    unawaited(controller.start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      controller.foreground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) => widget.gateway.monitorRequest(
    widget.workspace.id,
    widget.sessionId,
    method,
    params: params,
  );
  void open(
    String title,
    Future<Map<String, Object?>> Function(String?) load,
    List<Widget> Function(Map<String, Object?>) build,
  ) {
    unawaited(
      pushCorHubPage<void>(
        context: context,
        builder: (_) =>
            _MonitorReadPage(title: title, load: load, content: build),
      ),
    );
  }

  Widget stateLabel(String value) => _StateLabel(value);
  Future<void> taskControl(
    MonitorTask task,
    String action, {
    String? jobs,
  }) async {
    if (widget.readOnly) return;
    if (action == 'pause') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(c.l10n.monitorPause),
          content: Text(c.l10n.monitorPauseHint),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(c.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(c.l10n.monitorPause),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    await controller.control('monitor/task/$action', {
      'user_task_id': task.id,
      'expected_revision': task.revision,
      'jobs': ?jobs,
    });
  }

  Future<void> cancelTask(MonitorTask task) async {
    final policy = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.l10n.monitorCancel),
        content: Text(c.l10n.monitorCancelHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(c.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'keep'),
            child: Text(c.l10n.monitorKeepJobs),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'cancel'),
            child: Text(c.l10n.monitorCancelJobs),
          ),
        ],
      ),
    );
    if (policy != null && mounted) {
      await taskControl(task, 'cancel', jobs: policy);
    }
  }

  void taskDetails(MonitorTask task) => open(
    context.l10n.monitorDetails,
    (_) => request('monitor/task/read', {'user_task_id': task.id}),
    (data) {
      final current = MonitorTask(monitorObject(data['task']));
      return [
        SelectableText(
          current.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        stateLabel(current.state),
        _Detail(context.l10n.monitorGoal, current.objective),
        if (current.reason != null)
          _Detail(context.l10n.monitorReason, current.reason!),
        if (current.progress != null)
          _Detail(context.l10n.monitorProgress, current.progress!),
        _Detail(
          context.l10n.monitorCriteria,
          (current.raw['criteria'] as List? ?? [])
              .map((x) => (x as Map)['description'])
              .join('\n'),
        ),
        if (current.raw['completion'] case final List evidence)
          _Detail(
            context.l10n.monitorEvidence,
            evidence
                .map(
                  (x) =>
                      '${(x as Map)['criterion_id']}: ${(x['evidence_refs'] as List? ?? []).join(', ')}',
                )
                .join('\n'),
          ),
        if (current.raw['cancel_jobs'] case final Map cancellations)
          _Detail(
            context.l10n.monitorCancelPending,
            _diagnostic(cancellations),
          ),
        ..._research(data),
      ];
    },
  );
  List<Widget> _research(Map<String, Object?> data) {
    final snapshot = data['research'];
    if (snapshot is! Map ||
        snapshot['schema_version'] != 'research-snapshot/3') {
      return [];
    }
    final research = snapshot['research'];
    if (research is! Map) return [];
    final nodes = (research['nodes'] as List? ?? []).whereType<Map>().toList();
    final cards = (snapshot['nodes'] as List? ?? []).whereType<Map>();
    final nodeIds = nodes.map((node) => node['id']).toSet();
    final focus = (research['focus_node_ids'] as List? ?? []).toSet();
    final result = <Widget>[_Detail(context.l10n.monitorResearch, '')];
    if (nodes.isEmpty) result.add(Text(context.l10n.monitorResearchEmpty));
    for (final node in nodes) {
      final card = cards.where((card) => card['id'] == node['id']).firstOrNull;
      result.add(
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: focus.contains(node['id'])
              ? Tooltip(
                  message: context.l10n.monitorFocus,
                  child: const Icon(LucideIcons.focus),
                )
              : null,
          title: Text('${node['title']}'),
          subtitle: stateLabel('${node['status']}'),
          children: [
            if (node['plan'] != null)
              _Detail(context.l10n.monitorPlan, '${node['plan']}'),
            if (node['content_omitted'] == true)
              Text(context.l10n.monitorExcerpt),
            if (node['assessment_ref'] != null)
              _Detail(
                context.l10n.monitorEvidence,
                '${node['assessment_ref']}',
              ),
            for (final value
                in (card?['recent_results'] as List? ?? []).whereType<Map>())
              _Detail('${value['id']}', '${value['summary']}'),
          ],
        ),
      );
    }
    String label(Object? id) =>
        '${nodes.where((n) => n['id'] == id).firstOrNull?['title'] ?? id}';
    final relations = (research['relations'] as List? ?? []).whereType<Map>();
    for (final edge in relations) {
      final kind = switch (edge['kind']) {
        'part_of' => context.l10n.monitorPartOf,
        'requires' => context.l10n.monitorRequires,
        'alternative_to' => context.l10n.monitorAlternative,
        _ => '${edge['kind']}',
      };
      result.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${label(edge['source'])} · $kind · ${label(edge['target'])}',
          ),
        ),
      );
    }
    final sessionJobs = (data['session_job_ids'] as List? ?? []).toSet();
    final seenJobs = <Object?>{};
    for (final raw in [
      ...(snapshot['running_jobs'] as List? ?? []),
      ...(snapshot['uncollected_jobs'] as List? ?? []),
    ].whereType<Map>()) {
      if (!nodeIds.contains(raw['node_id']) || !seenJobs.add(raw['job_id'])) {
        continue;
      }
      final scoped = sessionJobs.contains(raw['job_id']);
      result.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${raw['job_id']}'),
          subtitle: scoped ? null : Text(context.l10n.monitorOutsideSession),
          trailing: scoped ? const Icon(LucideIcons.chevronRight) : null,
          onTap: scoped
              ? () => jobDetails(
                  MonitorJob({
                    'job_id': raw['job_id'],
                    'state': raw['state'] ?? 'unknown',
                  }),
                )
              : null,
        ),
      );
    }
    if (research['omitted'] case final Map omitted) {
      if (omitted.values.any((v) => v is num && v > 0)) {
        result.add(Text(context.l10n.monitorExcerpt));
      }
    }
    return result;
  }

  void history() => open(
    context.l10n.monitorHistory,
    (cursor) => request('monitor/tasks', {'limit': 30, 'cursor': ?cursor}),
    (data) => monitorItems(data['items']).map((row) {
      final task = MonitorTask(row);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(task.title),
        subtitle: stateLabel(task.state),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => taskDetails(task),
      );
    }).toList(),
  );
  void runs(MonitorTask? task) => open(
    context.l10n.monitorRuns,
    (cursor) => request('monitor/runs', {
      'limit': 30,
      if (task != null) 'user_task_id': task.id,
      'cursor': ?cursor,
    }),
    (data) => monitorItems(data['items'])
        .map(
          (run) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.history),
            title: Text('${run['producer']}'),
            subtitle: Text('${run['state']} · ${run['generation_count']}'),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => open(
              context.l10n.monitorExecution,
              (cursor) => request('monitor/run/read', {
                'run_id': run['run_id'],
                'limit': 30,
                'cursor': ?cursor,
              }),
              (detail) => monitorItems(detail['items'])
                  .map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: SelectableText(
                        '${entry['tool_name'] ?? entry['kind']}',
                      ),
                      subtitle: SelectableText(
                        [
                          entry['state'],
                          entry['outcome'],
                          if (entry['error'] != null)
                            _diagnostic(entry['error']),
                        ].whereType<String>().join('\n'),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        )
        .toList(),
  );
  void health() => open(
    context.l10n.monitorHealth,
    (_) => request('monitor/health'),
    (data) => [_Detail(context.l10n.monitorHealth, _diagnostic(data))],
  );
  void allJobs({MonitorTask? task}) => open(
    context.l10n.monitorJobs,
    (cursor) => request('monitor/jobs', {
      'limit': 30,
      if (task != null) 'user_task_id': task.id,
      'cursor': ?cursor,
    }),
    (data) =>
        monitorItems(data['items']).map((v) => jobRow(MonitorJob(v))).toList(),
  );
  Widget jobRow(MonitorJob job) => ListTile(
    key: ValueKey('job-${job.id}'),
    contentPadding: EdgeInsets.zero,
    leading: Icon(_stateIcon(job.state), size: 20),
    title: Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: stateLabel(job.state),
    trailing: const Icon(LucideIcons.chevronRight, size: 18),
    onTap: () => jobDetails(job),
  );
  void jobDetails(MonitorJob original) => open(
    context.l10n.monitorJobs,
    (_) => request('monitor/job/read', {'job_id': original.id}),
    (data) {
      final job = MonitorJob(monitorObject(data['job']));
      return [
        SelectableText(
          job.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        stateLabel(job.state),
        _Detail(
          context.l10n.monitorCollection,
          '${job.raw['collection_state'] ?? context.l10n.monitorUnknown}',
        ),
        Text(
          context.l10n.monitorAnalysis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (job.raw['error'] != null)
          _Detail(context.l10n.monitorReason, _diagnostic(job.raw['error'])),
        if (job.raw['result_receipt'] != null)
          _Detail(
            context.l10n.monitorEvidence,
            _diagnostic(job.raw['result_receipt']),
          ),
        if (widget.onOpenFiles != null)
          TextButton.icon(
            onPressed: widget.onOpenFiles,
            icon: const Icon(LucideIcons.folder),
            label: Text(context.l10n.monitorFiles),
          ),
        if (job.cancellable &&
            !widget.readOnly &&
            controller.capabilities.contains('monitor/job/cancel'))
          _JobCancelButton(job: job, controller: controller),
      ];
    },
  );
  Widget quick(IconData icon, String label, VoidCallback action) => Expanded(
    child: TextButton(
      onPressed: action,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 8),
            Text(label),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final l = context.l10n,
        overview = controller.overview,
        task = overview?.task;
    final pending = controller.pending != null;
    final canControl = !widget.readOnly && !controller.busy && !pending;
    final error = controller.error;
    final jobs = overview?.jobs ?? [];
    final related = task == null
        ? <MonitorJob>[]
        : jobs.where((j) => j.taskId == task.id).toList();
    return Scaffold(
      appBar: TsGlassAppBar(
        title: Text(l.monitorTitle),
        actions: [
          PopupMenuButton<String>(
            tooltip: l.monitorMore,
            icon: const Icon(LucideIcons.ellipsis),
            onSelected: (value) {
              if (value == 'history') history();
              if (value == 'refresh') unawaited(controller.refresh());
              if (value == 'health') health();
              if (value == 'cancel' && task != null) {
                unawaited(cancelTask(task));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'history', child: Text(l.monitorHistory)),
              PopupMenuItem(value: 'refresh', child: Text(l.monitorRefresh)),
              PopupMenuItem(value: 'health', child: Text(l.monitorHealth)),
              if (task != null &&
                  !task.terminal &&
                  canControl &&
                  controller.capabilities.contains('monitor/task/cancel'))
                PopupMenuItem(value: 'cancel', child: Text(l.monitorCancel)),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (widget.sessionTitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  widget.sessionTitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(l.monitorTasks)),
                ButtonSegment(value: true, label: Text(l.monitorJobs)),
              ],
              selected: {jobsTab},
              onSelectionChanged: (v) => setState(() => jobsTab = v.single),
            ),
            const SizedBox(height: 24),
            if (pending) ...[
              Text(l.monitorUncertain),
              TextButton.icon(
                onPressed: controller.busy || widget.readOnly
                    ? null
                    : () => unawaited(controller.retry()),
                icon: const Icon(LucideIcons.refreshCw),
                label: Text(l.monitorRetry),
              ),
            ],
            if (error != null) _MonitorError(error, stale: overview != null),
            if (overview == null && error == null)
              const Center(child: CircularProgressIndicator()),
            if (overview != null && jobsTab) ...[
              if (jobs.isEmpty) Text(l.monitorJobsEmpty),
              ...jobs.map(jobRow),
              if (overview.nextCursor != null)
                TextButton(onPressed: allJobs, child: Text(l.monitorLoadMore)),
            ],
            if (overview != null && !jobsTab) ...[
              if (task == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(l.monitorEmpty),
                ),
              if (task != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          stateLabel(task.state),
                        ],
                      ),
                    ),
                    if (!task.terminal)
                      IconButton.filledTonal(
                        key: const ValueKey('monitor-task-control'),
                        tooltip: {'paused', 'blocked'}.contains(task.state)
                            ? l.monitorResume
                            : l.monitorPause,
                        onPressed:
                            canControl &&
                                controller.capabilities.contains(
                                  'monitor/task/${{'paused', 'blocked'}.contains(task.state) ? 'resume' : 'pause'}',
                                )
                            ? () => taskControl(
                                task,
                                {'paused', 'blocked'}.contains(task.state)
                                    ? 'resume'
                                    : 'pause',
                              )
                            : null,
                        icon: controller.busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                {'paused', 'blocked'}.contains(task.state)
                                    ? LucideIcons.play
                                    : LucideIcons.pause,
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (widget.onOpenFiles != null)
                      quick(
                        LucideIcons.folder,
                        l.monitorFiles,
                        widget.onOpenFiles!,
                      ),
                    quick(
                      LucideIcons.listChecks,
                      l.monitorDetails,
                      () => taskDetails(task),
                    ),
                    quick(LucideIcons.history, l.monitorRuns, () => runs(task)),
                  ],
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.monitorJobs,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: l.monitorJobs,
                      icon: const Icon(LucideIcons.arrowUpRight, size: 18),
                      onPressed: () => allJobs(task: task),
                    ),
                  ],
                ),
                if (related.isEmpty) Text(l.monitorJobsEmpty),
                ...related.map(jobRow),
              ],
              if (overview.controller['error'] != null)
                TextButton.icon(
                  onPressed: health,
                  icon: const Icon(LucideIcons.circleAlert),
                  label: Text(l.monitorBlocked),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

IconData _stateIcon(String state) => switch (state) {
  'completed' || 'succeeded' || 'success' => LucideIcons.circleCheck,
  'paused' => LucideIcons.pause,
  'queued' || 'waiting' || 'pending' => LucideIcons.clock3,
  'blocked' || 'failed' || 'error' => LucideIcons.circleAlert,
  'cancelled' => LucideIcons.circleX,
  _ => LucideIcons.activity,
};

class _StateLabel extends StatelessWidget {
  const _StateLabel(this.state);
  final String state;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(_stateIcon(state), size: 16),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          context.l10n.hostMonitorState(state),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        if (value.isNotEmpty) SelectableText(value),
      ],
    ),
  );
}

String _diagnostic(Object? data) {
  if (data is Map) {
    return data.entries
        .map((e) => '${e.key}: ${_diagnostic(e.value)}')
        .join('\n');
  }
  if (data is List) return data.map(_diagnostic).join('\n');
  return data?.toString() ?? '—';
}

class _MonitorError extends StatelessWidget {
  const _MonitorError(this.error, {this.stale = false});
  final Object error;
  final bool stale;
  @override
  Widget build(BuildContext context) {
    final conflict =
        error is CorHubApiException &&
        (error as CorHubApiException).code?.contains('revision') == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Semantics(
        liveRegion: true,
        child: Text(
          conflict
              ? context.l10n.monitorConflict
              : '${stale ? '${context.l10n.monitorStale}\n' : ''}${describeCorHubProblem(error).localizedMessage(context.l10n)}',
        ),
      ),
    );
  }
}

class _MonitorReadPage extends StatefulWidget {
  const _MonitorReadPage({
    required this.title,
    required this.load,
    required this.content,
  });
  final String title;
  final Future<Map<String, Object?>> Function(String?) load;
  final List<Widget> Function(Map<String, Object?>) content;
  @override
  State<_MonitorReadPage> createState() => _MonitorReadPageState();
}

class _MonitorReadPageState extends State<_MonitorReadPage> {
  final pages = <Map<String, Object?>>[];
  Object? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await widget.load(
        reset || pages.isEmpty ? null : pages.last['next_cursor'] as String?,
      );
      if (mounted) {
        setState(() {
          if (reset) pages.clear();
          pages.add(page);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: TsGlassAppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: context.l10n.monitorRefresh,
          onPressed: busy ? null : () => load(reset: true),
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final page in pages) ...widget.content(page),
        if (pages.length == 1 &&
            pages.single['items'] is List &&
            (pages.single['items'] as List).isEmpty)
          Text(context.l10n.monitorRecordsEmpty),
        if (error != null) ...[
          _MonitorError(error!),
          TextButton(
            onPressed: () => load(reset: pages.isEmpty),
            child: Text(context.l10n.monitorRetry),
          ),
        ],
        if (busy) const Center(child: CircularProgressIndicator()),
        if (!busy && pages.isNotEmpty && pages.last['next_cursor'] != null)
          TextButton(
            onPressed: load,
            child: Text(context.l10n.monitorLoadMore),
          ),
      ],
    ),
  );
}

class _JobCancelButton extends StatefulWidget {
  const _JobCancelButton({required this.job, required this.controller});
  final MonitorJob job;
  final MonitorController controller;
  @override
  State<_JobCancelButton> createState() => _JobCancelButtonState();
}

class _JobCancelButtonState extends State<_JobCancelButton> {
  bool submitted = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (submitted) Text(context.l10n.monitorCancelPending),
          if (c.pending != null)
            TextButton(
              onPressed: c.busy ? null : () => c.retry(),
              child: Text(context.l10n.monitorRetry),
            ),
          if (c.error != null) _MonitorError(c.error!),
          TextButton.icon(
            onPressed: c.busy || c.pending != null || submitted
                ? null
                : () async {
                    final accepted = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(ctx.l10n.monitorCancelJob),
                        content: Text(ctx.l10n.monitorJobCancelHint),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(ctx.l10n.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(ctx.l10n.monitorCancelJob),
                          ),
                        ],
                      ),
                    );
                    if (accepted != true || !mounted) return;
                    final done = await c.control('monitor/job/cancel', {
                      'job_id': widget.job.id,
                    });
                    if (mounted && done) setState(() => submitted = true);
                  },
            icon: const Icon(LucideIcons.circleX),
            label: Text(context.l10n.monitorCancelJob),
          ),
        ],
      );
    },
  );
}
