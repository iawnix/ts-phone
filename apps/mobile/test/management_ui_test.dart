import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/management/management_dialogs.dart';
import 'package:ts_phone/features/sessions/session_list_page.dart';
import 'package:ts_phone/features/workspaces/workspace_list_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';

final _settings = ConnectionSettings(
  serverUrl: 'https://phone.test',
  token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
);

void main() {
  for (final locale in <String>['en', 'zh']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'management layout $locale $brightness at narrow large text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 740);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final gateway = _ManagementGateway();
          await tester.pumpWidget(
            _app(
              SessionListPage(
                settings: _settings,
                workspace: _workspace(),
                gatewayBuilder: (_) => gateway,
              ),
              locale: Locale(locale),
              brightness: brightness,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.byKey(const ValueKey<String>('create-session')),
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          final field = find.byType(TextField).last;
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          expect(tester.getRect(field).bottom, lessThanOrEqualTo(460));
          expect(tester.takeException(), isNull);
          await _capture(tester, 'session-editor-$locale-${brightness.name}');
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('project management standard width $brightness', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _ManagementGateway(
        workspaces: {
          LifecycleState.active: [
            _workspace(),
            _workspace(id: 'ts_006', name: 'Metal-catalyzed pathway'),
          ],
        },
      );
      await tester.pumpWidget(
        _app(
          WorkspaceListPage(
            settings: _settings,
            onOpenSettings: () {},
            gatewayBuilder: (_) => gateway,
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, 'projects-${brightness.name}');
    });
  }

  testWidgets('project creation uses the entered name and opens its sessions', (
    tester,
  ) async {
    final gateway = _ManagementGateway();

    await tester.pumpWidget(
      _app(
        WorkspaceListPage(
          settings: _settings,
          onOpenSettings: () {},
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('create-project')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Catalytic cycle');
    await tester.tap(find.text('Create project').last);
    await tester.pumpAndSettle();

    expect(gateway.createdWorkspaceNames, <String>['Catalytic cycle']);
    expect(find.byType(SessionListPage), findsOneWidget);
    expect(find.text('Catalytic cycle'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project rename archive and restore follow lifecycle views', (
    tester,
  ) async {
    final gateway = _ManagementGateway(
      workspaces: <LifecycleState, List<WorkspaceSummary>>{
        LifecycleState.active: <WorkspaceSummary>[_workspace()],
        LifecycleState.archived: <WorkspaceSummary>[],
        LifecycleState.trashed: <WorkspaceSummary>[],
      },
    );

    await tester.pumpWidget(
      _app(
        WorkspaceListPage(
          settings: _settings,
          onOpenSettings: () {},
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Revised pathway');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gateway.renamedWorkspaceNames, <String>['Revised pathway']);
    expect(find.text('Revised pathway'), findsOneWidget);

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(gateway.archiveWorkspaceCalls, 1);
    expect(find.text('Revised pathway'), findsNothing);

    await _selectLifecycle(tester, 'Archived');
    await tester.pumpAndSettle();
    expect(find.text('Revised pathway'), findsOneWidget);
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(gateway.restoreWorkspaceCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delayed refresh cannot replace the selected lifecycle view', (
    tester,
  ) async {
    final delayed = Completer<List<SessionSummary>>();
    final gateway = _ManagementGateway(
      activeSessionResponse: delayed,
      sessions: {
        LifecycleState.archived: [
          _session(
            sessionName: 'Archived review',
            lifecycleState: LifecycleState.archived,
          ),
        ],
      },
    );
    await tester.pumpWidget(
      _app(
        SessionListPage(
          settings: _settings,
          workspace: _workspace(),
          initialSessions: [_session()],
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pump();
    await _selectLifecycle(tester, 'Archived');
    await tester.pumpAndSettle();
    expect(find.text('Archived review'), findsOneWidget);
    delayed.complete([_session(sessionName: 'Stale active session')]);
    await tester.pumpAndSettle();
    expect(find.text('Archived review'), findsOneWidget);
    expect(find.text('Stale active session'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session creation preserves access mode name and model', (
    tester,
  ) async {
    final gateway = _ManagementGateway();

    await tester.pumpWidget(
      _app(
        SessionListPage(
          settings: _settings,
          workspace: _workspace(),
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('create-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read-only session'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Session name (optional)'),
      'Independent review',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Model (optional)'),
      'cpa/gpt-5.6-sol',
    );
    await tester.tap(find.text('Create session').last);
    await tester.pumpAndSettle();

    expect(gateway.createdSessions, hasLength(1));
    expect(
      gateway.createdSessions.single.accessMode,
      SessionAccessMode.observer,
    );
    expect(gateway.createdSessions.single.name, 'Independent review');
    expect(gateway.createdSessions.single.model, 'cpa/gpt-5.6-sol');
    expect(find.text('Independent review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session rename archive and restore follow lifecycle views', (
    tester,
  ) async {
    final gateway = _ManagementGateway(
      sessions: <LifecycleState, List<SessionSummary>>{
        LifecycleState.active: <SessionSummary>[_session()],
        LifecycleState.archived: <SessionSummary>[],
        LifecycleState.trashed: <SessionSummary>[],
      },
    );

    await tester.pumpWidget(
      _app(
        SessionListPage(
          settings: _settings,
          workspace: _workspace(),
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Follow-up review');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gateway.renamedSessionNames, <String>['Follow-up review']);

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(gateway.archiveSessionCalls, 1);

    await _selectLifecycle(tester, 'Archived');
    await tester.pumpAndSettle();
    expect(find.text('Follow-up review'), findsOneWidget);
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(gateway.restoreSessionCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project deletion preflight exposes deterministic blockers', (
    tester,
  ) async {
    final gateway = _ManagementGateway(
      workspaces: <LifecycleState, List<WorkspaceSummary>>{
        LifecycleState.active: <WorkspaceSummary>[_workspace()],
        LifecycleState.archived: <WorkspaceSummary>[
          _workspace(
            id: 'ts_004',
            name: 'Archived path',
            lifecycleState: LifecycleState.archived,
          ),
        ],
        LifecycleState.trashed: <WorkspaceSummary>[],
      },
      preflight: const WorkspaceDeletionPreflight(
        workspaceId: 'ts_005',
        managementRevision: _revision,
        activeWorkers: 1,
        remoteCalculations: 2,
        pendingApprovals: 0,
        unresolvedRemoteEffects: 1,
        canDelete: false,
      ),
    );

    await tester.pumpWidget(
      _app(
        WorkspaceListPage(
          settings: _settings,
          onOpenSettings: () {},
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('create-project')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Recently Deleted'));
    await tester.pumpAndSettle();

    expect(find.text('Project cannot be deleted'), findsOneWidget);
    expect(find.text('Active sessions'), findsOneWidget);
    expect(gateway.workspacePreflightCalls, 1);
    expect(gateway.trashWorkspaceCalls, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _selectLifecycle(tester, 'Archived');
    await tester.pumpAndSettle();
    expect(find.text('Archived path'), findsOneWidget);
    expect(
      gateway.workspaceLifecycleRequests,
      contains(LifecycleState.archived),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('session trash is scoped to conversation history', (
    tester,
  ) async {
    final gateway = _ManagementGateway(
      sessions: <LifecycleState, List<SessionSummary>>{
        LifecycleState.active: <SessionSummary>[_session()],
        LifecycleState.archived: <SessionSummary>[],
        LifecycleState.trashed: <SessionSummary>[],
      },
    );

    await tester.pumpWidget(
      _app(
        SessionListPage(
          settings: _settings,
          workspace: _workspace(),
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Recently Deleted'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Only this conversation history is moved to Recently Deleted. '
        'Scientific project data is not removed.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Move to Recently Deleted').last);
    await tester.pumpAndSettle();

    expect(gateway.trashSessionCalls, 1);
    expect(gateway.trashWorkspaceCalls, 0);
    expect(find.text('No sessions yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening offline history does not wait for explicit activation', (
    tester,
  ) async {
    final activation = Completer<SessionSummary>();
    final gateway = _ManagementGateway(
      sessions: <LifecycleState, List<SessionSummary>>{
        LifecycleState.active: <SessionSummary>[_session(canActivate: true)],
        LifecycleState.archived: <SessionSummary>[],
        LifecycleState.trashed: <SessionSummary>[],
      },
      activation: activation,
    );

    await tester.pumpWidget(
      _app(
        SessionListPage(
          settings: _settings,
          workspace: _workspace(),
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Primary session'));
    await tester.pumpAndSettle();

    expect(gateway.activateSessionCalls, 0);
    expect(find.byKey(const ValueKey('continue-session')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('continue-session')));
    await tester.pump();
    expect(gateway.activateSessionCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permanent session deletion requires the exact session id', (
    tester,
  ) async {
    final gateway = _ManagementGateway(
      sessions: <LifecycleState, List<SessionSummary>>{
        LifecycleState.active: <SessionSummary>[],
        LifecycleState.archived: <SessionSummary>[],
        LifecycleState.trashed: <SessionSummary>[
          _session(lifecycleState: LifecycleState.trashed),
        ],
      },
    );

    await tester.pumpWidget(
      _app(
        SessionListPage(
          settings: _settings,
          workspace: _workspace(),
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectLifecycle(tester, 'Recently Deleted');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    final deleteButton = find.widgetWithText(
      FilledButton,
      'Delete permanently',
    );
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'wrong-id');
    await tester.pump();
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'session_1');
    await tester.pump();
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNotNull);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(gateway.purgeSessionCalls, 1);
    expect(find.text('Recently Deleted is empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _selectLifecycle(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('lifecycle-filter')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.tap(find.text(label));
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['TS_PHONE_CAPTURE_UI'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey<String>('capture-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory('build/management-previews');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  theme: brightness == Brightness.light
      ? TsPhoneTheme.light()
      : TsPhoneTheme.dark(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(
      key: const ValueKey<String>('capture-root'),
      child: child!,
    ),
  ),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: home,
);

const _revision = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

WorkspaceSummary _workspace({
  String id = 'ts_005',
  String name = 'Diels-Alder study',
  LifecycleState lifecycleState = LifecycleState.active,
}) => WorkspaceSummary(
  id: id,
  name: name,
  runtimeState: RuntimeState.offline,
  isStreaming: false,
  liveSessionCount: 0,
  sessionCount: 1,
  lifecycleState: lifecycleState,
  managementRevision: _revision,
  managed: true,
);

SessionSummary _session({
  String sessionId = 'session_1',
  String sessionName = 'Primary session',
  LifecycleState lifecycleState = LifecycleState.active,
  bool canActivate = false,
}) => SessionSummary(
  sessionId: sessionId,
  sessionRevision: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  sessionName: sessionName,
  runtimeState: RuntimeState.offline,
  isStreaming: false,
  accessMode: SessionAccessMode.controller,
  lifecycleState: lifecycleState,
  managementRevision: _revision,
  managed: true,
  canActivate: canActivate,
  activation: const SessionActivation(
    modes: {SessionAccessMode.controller, SessionAccessMode.observer},
  ),
  capabilities: const {'session.activate_mode'},
  canPrompt: false,
);

class _ManagementGateway extends Fake
    implements TsPhoneGateway, TsPhoneManagementGateway {
  _ManagementGateway({
    Map<LifecycleState, List<WorkspaceSummary>>? workspaces,
    Map<LifecycleState, List<SessionSummary>>? sessions,
    this.preflight = const WorkspaceDeletionPreflight(
      workspaceId: 'ts_005',
      managementRevision: _revision,
      activeWorkers: 0,
      remoteCalculations: 0,
      pendingApprovals: 0,
      unresolvedRemoteEffects: 0,
      canDelete: true,
    ),
    this.activation,
    this.activeSessionResponse,
  }) : workspaces =
           workspaces ??
           <LifecycleState, List<WorkspaceSummary>>{
             for (final state in LifecycleState.values)
               state: <WorkspaceSummary>[],
           },
       sessions =
           sessions ??
           <LifecycleState, List<SessionSummary>>{
             for (final state in LifecycleState.values)
               state: <SessionSummary>[],
           };

  final Map<LifecycleState, List<WorkspaceSummary>> workspaces;
  final Map<LifecycleState, List<SessionSummary>> sessions;
  final WorkspaceDeletionPreflight preflight;
  final Completer<SessionSummary>? activation;
  final Completer<List<SessionSummary>>? activeSessionResponse;
  final List<LifecycleState> workspaceLifecycleRequests = <LifecycleState>[];
  int workspacePreflightCalls = 0;
  int trashWorkspaceCalls = 0;
  int trashSessionCalls = 0;
  int purgeSessionCalls = 0;
  int activateSessionCalls = 0;
  int archiveWorkspaceCalls = 0;
  int restoreWorkspaceCalls = 0;
  int archiveSessionCalls = 0;
  int restoreSessionCalls = 0;
  final List<String> createdWorkspaceNames = <String>[];
  final List<String> renamedWorkspaceNames = <String>[];
  final List<String> renamedSessionNames = <String>[];
  final List<SessionDraft> createdSessions = <SessionDraft>[];

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() =>
      listWorkspacesByLifecycle(LifecycleState.active);

  @override
  Future<List<WorkspaceSummary>> listWorkspacesByLifecycle(
    LifecycleState lifecycleState,
  ) async {
    workspaceLifecycleRequests.add(lifecycleState);
    return List<WorkspaceSummary>.of(workspaces[lifecycleState] ?? const []);
  }

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) =>
      listSessionsByLifecycle(workspaceId, LifecycleState.active);

  @override
  Future<List<SessionSummary>> listSessionsByLifecycle(
    String workspaceId,
    LifecycleState lifecycleState,
  ) async {
    if (lifecycleState == LifecycleState.active &&
        activeSessionResponse != null) {
      return activeSessionResponse!.future;
    }
    return List<SessionSummary>.of(sessions[lifecycleState] ?? const []);
  }

  @override
  Future<WorkspaceCreationResult> createWorkspace(String name) async {
    createdWorkspaceNames.add(name);
    final workspace = _workspace(id: 'ts_006', name: name);
    final session = _session(sessionName: name);
    workspaces[LifecycleState.active]?.add(workspace);
    sessions[LifecycleState.active]?.add(session);
    return WorkspaceCreationResult(workspace: workspace, session: session);
  }

  @override
  Future<WorkspaceSummary> renameWorkspace(
    String workspaceId,
    String managementRevision,
    String name,
  ) async {
    renamedWorkspaceNames.add(name);
    final renamed = _workspace(id: workspaceId, name: name);
    _replaceWorkspace(workspaceId, renamed);
    return renamed;
  }

  @override
  Future<WorkspaceSummary> archiveWorkspace(
    String workspaceId,
    String managementRevision,
  ) async {
    archiveWorkspaceCalls += 1;
    final current = _removeWorkspace(workspaceId);
    final archived = _workspace(
      id: current.id,
      name: current.name,
      lifecycleState: LifecycleState.archived,
    );
    workspaces[LifecycleState.archived]?.add(archived);
    return archived;
  }

  @override
  Future<WorkspaceSummary> restoreWorkspace(
    String workspaceId,
    String managementRevision,
  ) async {
    restoreWorkspaceCalls += 1;
    final current = _removeWorkspace(workspaceId);
    final restored = _workspace(id: current.id, name: current.name);
    workspaces[LifecycleState.active]?.add(restored);
    return restored;
  }

  @override
  Future<SessionSummary> createSession(
    String workspaceId, {
    required SessionAccessMode accessMode,
    String? name,
    String? model,
  }) async {
    createdSessions.add(
      SessionDraft(accessMode: accessMode, name: name, model: model),
    );
    final created = _session(
      sessionId: 'session_2',
      sessionName: name ?? 'session_2',
    );
    sessions[LifecycleState.active]?.add(created);
    return created;
  }

  @override
  Future<SessionSummary> renameSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
    String name,
  ) async {
    renamedSessionNames.add(name);
    final renamed = _session(sessionId: sessionId, sessionName: name);
    _replaceSession(sessionId, renamed);
    return renamed;
  }

  @override
  Future<SessionSummary> archiveSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  ) async {
    archiveSessionCalls += 1;
    final current = _removeSession(sessionId);
    final archived = _session(
      sessionId: current.sessionId,
      sessionName: current.sessionName!,
      lifecycleState: LifecycleState.archived,
    );
    sessions[LifecycleState.archived]?.add(archived);
    return archived;
  }

  @override
  Future<SessionSummary> restoreSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  ) async {
    restoreSessionCalls += 1;
    final current = _removeSession(sessionId);
    final restored = _session(
      sessionId: current.sessionId,
      sessionName: current.sessionName!,
    );
    sessions[LifecycleState.active]?.add(restored);
    return restored;
  }

  @override
  Future<WorkspaceDeletionPreflight> workspaceDeletionPreflight(
    String workspaceId,
  ) async {
    workspacePreflightCalls += 1;
    return preflight;
  }

  @override
  Future<WorkspaceSummary> trashWorkspace(
    String workspaceId,
    String managementRevision,
  ) async {
    trashWorkspaceCalls += 1;
    return _workspace(lifecycleState: LifecycleState.trashed);
  }

  @override
  Future<SessionSummary> trashSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  ) async {
    trashSessionCalls += 1;
    sessions[LifecycleState.active]?.clear();
    final trashed = _session(lifecycleState: LifecycleState.trashed);
    sessions[LifecycleState.trashed]?.add(trashed);
    return trashed;
  }

  @override
  Future<void> purgeSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  ) async {
    purgeSessionCalls += 1;
    sessions[LifecycleState.trashed]?.clear();
  }

  @override
  Future<SessionSummary> activateSession(
    String workspaceId,
    String sessionId,
    String managementRevision, {
    SessionAccessMode? accessMode,
    String? requestId,
    SessionActivationConflict? switchFrom,
  }) {
    activateSessionCalls += 1;
    return activation?.future ?? Future<SessionSummary>.value(_session());
  }

  void _replaceWorkspace(String id, WorkspaceSummary replacement) {
    _removeWorkspace(id);
    workspaces[replacement.lifecycleState]?.add(replacement);
  }

  WorkspaceSummary _removeWorkspace(String id) {
    for (final values in workspaces.values) {
      final index = values.indexWhere((workspace) => workspace.id == id);
      if (index >= 0) return values.removeAt(index);
    }
    throw StateError('Workspace $id was not found');
  }

  void _replaceSession(String id, SessionSummary replacement) {
    _removeSession(id);
    sessions[replacement.lifecycleState]?.add(replacement);
  }

  SessionSummary _removeSession(String id) {
    for (final values in sessions.values) {
      final index = values.indexWhere((session) => session.sessionId == id);
      if (index >= 0) return values.removeAt(index);
    }
    throw StateError('Session $id was not found');
  }

  @override
  void close() {}
}
