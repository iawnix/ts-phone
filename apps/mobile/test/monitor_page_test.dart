import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corhub/data/corhub_api.dart';
import 'package:corhub/features/monitors/monitor_page.dart';
import 'package:corhub/features/monitors/monitor_controller.dart';
import 'package:corhub/l10n/app_localizations.dart';
import 'package:corhub/models/host_monitor.dart';
import 'package:corhub/models/workspace.dart';

void main() {
  Widget app(FakeMonitor gateway, {bool readOnly = false}) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    home: MonitorPage(
      workspace: const WorkspaceSummary(
        id: 'project-a',
        name: 'Project A',
        runtimeState: RuntimeState.idle,
        isStreaming: false,
        liveSessionCount: 0,
        sessionCount: 1,
      ),
      sessionId: 'session-a',
      gateway: gateway,
      readOnly: readOnly,
      onOpenFiles: () {},
    ),
  );
  testWidgets('narrow, large-text task controls preserve cancel policy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeMonitor();
    await tester.pumpWidget(app(gateway));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel task'));
    await tester.pumpAndSettle();
    expect(gateway.mutations, isEmpty);
    await tester.tap(find.text('Keep jobs'));
    await tester.pumpAndSettle();
    expect(gateway.mutations.single.$1, 'monitor/task/cancel');
    expect(gateway.mutations.single.$2['jobs'], 'keep');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('read-only monitor exposes no task mutation', (tester) async {
    final gateway = FakeMonitor();
    await tester.pumpWidget(app(gateway, readOnly: true));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('monitor-task-control')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Cancel task'), findsNothing);
    expect(gateway.mutations, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('task pause is explicit and does not cancel the running job', (
    tester,
  ) async {
    final gateway = FakeMonitor();
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
            sessionCount: 1,
          ),
          sessionId: 'session-a',
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Compare conformers'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.byKey(const ValueKey('monitor-task-control')));
    await tester.pumpAndSettle();
    expect(gateway.mutations, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Pause task'));
    await tester.pumpAndSettle();
    expect(gateway.task['state'], 'paused');
    expect(gateway.mutations.single.$1, 'monitor/task/pause');
    expect(find.text('Running'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'uncertain control survives navigation and retries unchanged identity/revision',
    () async {
      final gateway = FakeMonitor()..loseReceipt = true;
      var c = MonitorController(gateway, 'project-a', 'session-a');
      await c.start();
      await c.control('monitor/task/pause', {
        'user_task_id': 'task-a',
        'expected_revision': 1,
      });
      expect(c.pending, isNotNull);
      final first = gateway.mutations.single.$2;
      c.dispose();
      c = MonitorController(gateway, 'project-a', 'session-a');
      await c.start();
      expect(c.overview!.task!.revision, 2);
      await c.retry();
      expect(gateway.mutations.last.$2, first);
      expect(c.pending, isNull);
      c.dispose();
    },
  );
  test(
    'revision rejection refreshes without silently replaying a new command',
    () async {
      final gateway = FakeMonitor()..conflict = true;
      final c = MonitorController(gateway, 'project-a', 'session-a');
      await c.start();
      await c.control('monitor/task/pause', {
        'user_task_id': 'task-a',
        'expected_revision': 1,
      });
      expect(c.pending, isNull);
      expect(c.error, isA<CorHubApiException>());
      expect(gateway.mutations.length, 1);
      c.dispose();
    },
  );
}

class FakeMonitor implements HostMonitorGateway {
  Map<String, Object?> task = {
    'schema_version': 'coragent-user-task/2',
    'user_task_id': 'task-a',
    'title': 'Compare conformers',
    'state': 'waiting',
    'revision': 1,
    'objective': 'Compare energies',
    'criteria': [],
  };
  final mutations = <(String, Map<String, Object?>)>[];
  bool loseReceipt = false, conflict = false;
  @override
  Future<Set<String>> monitorCapabilities() async => {
    'monitor/overview',
    'monitor/task/pause',
    'monitor/task/resume',
    'monitor/task/cancel',
    'monitor/job/cancel',
  };
  @override
  Stream<void> monitorChanges(String workspaceId, String sessionId) =>
      const Stream.empty();
  @override
  Future<Map<String, Object?>> monitorRequest(
    String workspaceId,
    String sessionId,
    String method, {
    Map<String, Object?> params = const {},
  }) async {
    expect(workspaceId, 'project-a');
    expect(sessionId, 'session-a');
    if (method == 'monitor/overview') {
      return {
        'schema_version': 'coragent-monitor/1',
        'task': Map.of(task),
        'jobs': {
          'items': [
            {'job_id': 'job-a', 'user_task_id': 'task-a', 'state': 'running'},
          ],
          'next_cursor': null,
        },
        'task_controller': {},
        'updated_at': '2026-10-10T00:00:00Z',
      };
    }
    mutations.add((method, Map.of(params)));
    if (conflict) {
      throw const CorHubApiException('changed', code: 'task_revision_conflict');
    }
    task = {...task, 'state': 'paused', 'revision': 2};
    if (loseReceipt) {
      loseReceipt = false;
      throw const CorHubApiException('lost', code: 'request_timeout');
    }
    return {'task': task, 'jobs_policy': null};
  }
}
