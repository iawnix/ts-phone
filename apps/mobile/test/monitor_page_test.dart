import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/features/monitors/monitor_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/host_monitor.dart';
import 'package:ts_phone/models/workspace.dart';

void main() {
  testWidgets('shows task status and persists enable/disable through Host', (
    tester,
  ) async {
    final gateway = _Monitors();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MonitorPage(
          workspace: const WorkspaceSummary(
            id: 'project-a',
            name: 'Project A',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            liveSessionCount: 0,
            sessionCount: 0,
          ),
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Project A · Task monitors'), findsOneWidget);
    expect(find.text('Calculation'), findsOneWidget);
    expect(find.textContaining('Running'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('monitor-m-1')));
    await tester.pumpAndSettle();
    expect(gateway.enabled, isFalse);
    expect(gateway.changedWorkspace, 'project-a');
    expect(find.textContaining('Monitoring paused'), findsOneWidget);
  });
}

class _Monitors implements HostMonitorGateway {
  bool enabled = true;
  String? changedWorkspace;
  HostMonitor get monitor => HostMonitor(
    id: 'm-1',
    title: 'Calculation',
    enabled: enabled,
    state: 'running',
    pendingCount: 1,
  );
  @override
  Future<List<HostMonitor>> listMonitors(String workspaceId) async => [monitor];
  @override
  Future<HostMonitor> setMonitorEnabled(
    String workspaceId,
    String monitorId,
    bool enabled,
  ) async {
    changedWorkspace = workspaceId;
    this.enabled = enabled;
    return monitor;
  }
}
