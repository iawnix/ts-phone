import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/features/sessions/context_switcher.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';

void main() {
  testWidgets('context switcher renders and selects a session', (tester) async {
    const workspace = WorkspaceSummary(
      id: 'workspace',
      name: 'Project A',
      runtimeState: RuntimeState.idle,
      isStreaming: false,
      liveSessionCount: 0,
      sessionCount: 1,
    );
    const session = SessionSummary(
      sessionId: 'session',
      sessionRevision: 'revision',
      sessionName: 'Conversation A',
      runtimeState: RuntimeState.idle,
      isStreaming: false,
    );
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                useSafeArea: true,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => ContextSwitcherSheet(
                  workspaces: const [workspace],
                  selectedWorkspace: workspace,
                  selectedSession: null,
                  initialSessions: const [session],
                  loadSessions: (_) async => const [session],
                  onSessionSelected: (_, _) => selected = true,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Project A'), findsOneWidget);
    expect(find.text('Conversation A'), findsOneWidget);
    await tester.tap(find.text('Conversation A'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(tester.takeException(), isNull);
  });
}
