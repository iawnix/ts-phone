import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:corhub/models/file_reference.dart';
import 'package:corhub/features/chat/chat_page.dart';
import 'package:corhub/features/chat/chat_view_memory.dart';
import 'package:corhub/l10n/app_localizations.dart';
import 'package:corhub/widgets/file_reference_chip.dart';
import 'package:corhub/features/chat/chat_composer.dart';
import 'package:corhub/theme/corhub_theme.dart';
import 'package:corhub/features/files/structure.dart';
import 'package:corhub/features/files/files_page.dart';
import 'conversation_shell_test.dart' as fixture;

void main() {
  final reference = FileReference({
    'workspace_id': 'ts_001',
    'path': 'inputs/phone-references/${'a' * 64}.xyz',
    'source_path': 'inputs/molecule.xyz',
    'sha256': 'a' * 64,
  });
  test(
    'file references round-trip without eating ordinary JSON or draft text',
    () {
      final draft = ReferencedDraft('Compare these\n', [reference, reference]);
      final parsed = ReferencedDraft.parse(draft.wire);
      expect(parsed.text, draft.text);
      expect(parsed.files.length, 2);
      expect(parsed.wire, draft.wire);
      expect(
        ReferencedDraft.parse(reference.wire.trim()).files.single.name,
        'molecule.xyz',
      );
      const invalid = 'Keep this\n\n[CoRHub file]\n```json\n{"path":"x"}\n```';
      expect(ReferencedDraft.parse(invalid).text, invalid);
    },
  );
  testWidgets(
    'file chips retain the draft across navigation at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final memory = ChatViewMemory()
        ..draft = ReferencedDraft('Compare', [reference]).wire;
      Widget app() => MaterialApp(
        theme: CorHubTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ChatPage(
          settings: fixture.settings,
          workspace: fixture.appServer,
          session: fixture.session('one'),
          gateway: fixture.ConversationGateway(),
          memory: memory,
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(FileReferenceChip), findsOneWidget);
      expect(find.text('Compare'), findsOneWidget);
      expect(find.textContaining('sha256'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'Compare energies',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(ReferencedDraft.parse(memory.draft).text, 'Compare energies');
      expect(
        ReferencedDraft.parse(memory.draft).files.single.name,
        'molecule.xyz',
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove file'));
      await tester.pumpAndSettle();
      expect(memory.draft, 'Compare energies');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('XYZ keeps coordinates, atom identity and measured distance', () {
    final s = parseStructure({
      'extension': 'xyz',
      'text': '2\nAngstrom\nC 0 0 0\nO 1.5 0 0\n',
    });
    expect(s.atoms[0].source, '1');
    expect(s.atoms[0].distance(s.atoms[1]), 1.5);
    expect(s.inferred, isTrue);
    expect(s.bonds, [(0, 1)]);
  });
  testWidgets('a file-only draft can be explicitly sent', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    var sent = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            focusNode: focus,
            canEdit: true,
            canSend: true,
            sending: false,
            maxLines: 4,
            hint: '',
            files: [reference],
            onSend: () => sent++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    expect(sent, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus.dispose();
  });
  test('invalid coordinates cannot create misleading geometry', () {
    expect(
      () => parseStructure({'extension': 'xyz', 'text': '1\ntest\nC NaN 0 0'}),
      throwsFormatException,
    );
    expect(
      () => parseStructure({'extension': 'xyz', 'text': '2\ntest\nC 0 0 0'}),
      throwsFormatException,
    );
  });
  test(
    'mmCIF uses atom_site coordinates and first model, retaining labels',
    () {
      final s = parseStructure({
        'extension': 'mmcif',
        'text': '''data_fixture
loop_
_atom_site.id
_atom_site.type_symbol
_atom_site.Cartn_x
_atom_site.Cartn_y
_atom_site.Cartn_z
_atom_site.label_asym_id
_atom_site.label_seq_id
_atom_site.label_comp_id
_atom_site.pdbx_PDB_model_num
1 C 0 0 0 A 12 GLY 1
2 O 1.2 0 0 A 12 GLY 1
3 C 9 9 9 A 12 GLY 2
#
''',
      });
      expect(s.atoms.length, 2);
      expect(s.atoms.last.group, 'A / 12 / GLY');
    },
  );
  test('quoted table cells retain embedded comma and newline', () {
    expect(parseDelimited('name,value\n"a,b","two\nlines"\n'), [
      ['name', 'value'],
      ['a,b', 'two\nlines'],
    ]);
    expect(parseDelimited('a\tb\n1\t2', delimiter: '\t'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
  });
  test(
    'MOL explicit zero bonds are not invented and PDB retains calcium identity',
    () {
      final mol = parseStructure({
        'extension': 'mol',
        'text':
            'fixture\n\n\n  2  0  0  0  0  0            999 V2000\n    0.0000    0.0000    0.0000 C   0\n    1.2000    0.0000    0.0000 O   0\nM  END\n',
      });
      expect(mol.bonds, isEmpty);
      expect(mol.inferred, isFalse);
      final pdb = parseStructure({
        'extension': 'pdb',
        'text': 'HETATM    7 CA   CA  A   1       0.000   0.000   0.000\nEND\n',
      });
      expect(pdb.atoms.single.element, 'Ca');
      expect(pdb.atoms.single.source, '7');
    },
  );
}
