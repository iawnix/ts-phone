import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../l10n/host_monitor_localizations.dart';
import '../../models/host_monitor.dart';
import '../../models/workspace.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({
    super.key,
    required this.workspace,
    required this.gateway,
  });

  final WorkspaceSummary workspace;
  final HostMonitorGateway gateway;

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> with WidgetsBindingObserver {
  List<HostMonitor>? _monitors;
  Object? _error;
  final _updating = <String>{};
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final monitors = await widget.gateway.listMonitors(widget.workspace.id);
      if (mounted) {
        setState(() {
          _monitors = monitors;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _setEnabled(HostMonitor monitor, bool enabled) async {
    if (_updating.contains(monitor.id)) return;
    ActionFeedback.selection();
    setState(() => _updating.add(monitor.id));
    try {
      final updated = await widget.gateway.setMonitorEnabled(
        widget.workspace.id,
        monitor.id,
        enabled,
      );
      if (mounted) {
        setState(() {
          _monitors = _monitors
              ?.map((value) => value.id == updated.id ? updated : value)
              .toList();
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        ActionFeedback.error();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                describeTsPhoneProblem(error).localizedMessage(context.l10n),
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _updating.remove(monitor.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final monitors = _monitors;
    return Scaffold(
      appBar: TsGlassAppBar(
        title: Text('${widget.workspace.name} · ${l10n.hostMonitors}'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: l10n.refreshSessions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: monitors == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error case final error?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        describeTsPhoneProblem(error).localizedMessage(l10n),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (monitors?.isEmpty == true) Text(l10n.hostMonitorsEmpty),
                  for (final monitor in monitors ?? const <HostMonitor>[])
                    _MonitorCard(
                      monitor: monitor,
                      busy: _updating.contains(monitor.id),
                      onChanged: (enabled) => _setEnabled(monitor, enabled),
                    ),
                ],
              ),
            ),
    );
  }
}

class _MonitorCard extends StatelessWidget {
  const _MonitorCard({
    required this.monitor,
    required this.busy,
    required this.onChanged,
  });

  final HostMonitor monitor;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final observed = monitor.lastObservedAt;
    final error = monitor.lastError?.trim();
    final status =
        '${l10n.hostMonitorState(monitor.state)} · ${monitor.enabled ? l10n.hostMonitorEnabled : l10n.hostMonitorDisabled}';
    final observedLabel = observed == null
        ? null
        : l10n.hostMonitorObserved(
            DateFormat.yMd(l10n.localeName).add_Hm().format(observed.toLocal()),
          );

    return Card(
      key: ValueKey('monitor-${monitor.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TsPhoneSpacing.large,
          TsPhoneSpacing.medium,
          TsPhoneSpacing.small,
          TsPhoneSpacing.medium,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TsPressable(
                onTap: busy ? null : () => onChanged(!monitor.enabled),
                borderRadius: BorderRadius.circular(TsPhoneRadii.small),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: TsPhoneSpacing.xSmall,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(monitor.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: TsPhoneSpacing.xSmall),
                      Wrap(
                        spacing: TsPhoneSpacing.small,
                        runSpacing: TsPhoneSpacing.xSmall,
                        children: <Widget>[
                          Text(
                            status,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (observedLabel != null)
                            Text(
                              observedLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      if (monitor.pendingCount > 0 ||
                          error?.isNotEmpty == true) ...[
                        const SizedBox(height: TsPhoneSpacing.small),
                        Wrap(
                          spacing: TsPhoneSpacing.small,
                          runSpacing: TsPhoneSpacing.xSmall,
                          children: <Widget>[
                            if (monitor.pendingCount > 0)
                              Text(
                                l10n.hostMonitorPending(monitor.pendingCount),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.tertiary,
                                ),
                              ),
                            if (error?.isNotEmpty == true)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 250,
                                ),
                                child: Text(
                                  error!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colors.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: TsPhoneSpacing.small),
            Semantics(
              label: monitor.title,
              value: status,
              child: Switch(
                value: monitor.enabled,
                onChanged: busy ? null : onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
