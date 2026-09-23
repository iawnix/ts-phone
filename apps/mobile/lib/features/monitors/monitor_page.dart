import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../l10n/host_monitor_localizations.dart';
import '../../models/host_monitor.dart';
import '../../models/workspace.dart';

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
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _updating.remove(monitor.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final monitors = _monitors;
    return Scaffold(
      appBar: AppBar(
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
                    Card(
                      child: SwitchListTile(
                        key: ValueKey('monitor-${monitor.id}'),
                        title: Text(monitor.title),
                        isThreeLine: true,
                        value: monitor.enabled,
                        onChanged: _updating.contains(monitor.id)
                            ? null
                            : (enabled) => _setEnabled(monitor, enabled),
                        subtitle: Text(
                          [
                            '${l10n.hostMonitorState(monitor.state)} · ${monitor.enabled ? l10n.hostMonitorEnabled : l10n.hostMonitorDisabled}',
                            if (monitor.lastObservedAt case final at?)
                              l10n.hostMonitorObserved(
                                DateFormat.yMd(
                                  l10n.localeName,
                                ).add_Hm().format(at.toLocal()),
                              ),
                            if (monitor.pendingCount > 0)
                              l10n.hostMonitorPending(monitor.pendingCount),
                            ?monitor.lastError,
                          ].join('\n'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
