import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../data/corhub_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/workspace_file.dart';
import '../../models/file_reference.dart';
import '../../navigation/adaptive_page_route.dart';
import '../../widgets/presentation.dart';
import 'structure.dart';
import 'structure_view.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({
    super.key,
    required this.gateway,
    required this.workspaceId,
    this.path = '',
    this.onReference,
  });
  final WorkspaceFileGateway gateway;
  final String workspaceId, path;
  final ValueChanged<FileReference>? onReference;
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  final files = <WorkspaceFile>[];
  String? cursor;
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
      if (!await widget.gateway.supportsFiles()) {
        throw const CorHubApiException(
          'Files unavailable',
          code: 'method_not_found',
        );
      }
      final page = await widget.gateway.listFiles(
        widget.workspaceId,
        widget.path,
        cursor: reset ? null : cursor,
      );
      if (mounted) {
        setState(() {
          if (reset) files.clear();
          files.addAll(page.files);
          cursor = page.cursor;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(WorkspaceFile file) async {
    await pushCorHubPage<void>(
      context: context,
      builder: (_) => file.directory
          ? FilesPage(
              gateway: widget.gateway,
              workspaceId: widget.workspaceId,
              path: file.path,
              onReference: widget.onReference,
            )
          : FilePreviewPage(
              gateway: widget.gateway,
              workspaceId: widget.workspaceId,
              file: file,
              onReference: widget.onReference,
            ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: TsGlassAppBar(
      title: Text(context.l10n.filesTitle),
      actions: [
        IconButton(
          tooltip: context.l10n.monitorRefresh,
          onPressed: busy ? null : () => load(reset: true),
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () => load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.path.isNotEmpty)
            SelectableText(
              widget.path,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (error != null) ...[
            FileProblem(error!),
            TextButton(
              onPressed: () => load(reset: true),
              child: Text(context.l10n.monitorRetry),
            ),
          ],
          if (!busy && error == null && files.isEmpty)
            Text(context.l10n.filesEmpty),
          for (final file in files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                file.directory ? LucideIcons.folder : _fileIcon(file.extension),
              ),
              title: Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: file.directory ? null : Text(_size(file.size)),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: () => open(file),
            ),
          if (busy) const Center(child: CircularProgressIndicator()),
          if (!busy && cursor != null)
            TextButton(
              onPressed: load,
              child: Text(context.l10n.monitorLoadMore),
            ),
        ],
      ),
    ),
  );
}

const structureExtensions = {'xyz', 'mol', 'sdf', 'pdb', 'cif', 'mmcif'};
IconData _fileIcon(String extension) => structureExtensions.contains(extension)
    ? LucideIcons.box
    : {'png', 'jpg', 'jpeg'}.contains(extension)
    ? LucideIcons.image
    : {'csv', 'tsv'}.contains(extension)
    ? LucideIcons.table2
    : LucideIcons.fileText;
String _size(int size) => size < 1024
    ? '$size B'
    : size < 1024 * 1024
    ? '${(size / 1024).toStringAsFixed(1)} KB'
    : '${(size / 1024 / 1024).toStringAsFixed(1)} MB';

class FilePreviewPage extends StatefulWidget {
  const FilePreviewPage({
    super.key,
    required this.gateway,
    required this.workspaceId,
    required this.file,
    this.onReference,
  });
  final WorkspaceFileGateway gateway;
  final String workspaceId;
  final WorkspaceFile file;
  final ValueChanged<FileReference>? onReference;
  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  Uint8List? bytes;
  String? text;
  Object? error, parseError;
  MolecularStructure? structure;
  bool raw = false, closed = false, pinning = false, canReference = false;
  List<int> selection = [];
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }

  Future<void> load() async {
    try {
      canReference =
          widget.onReference != null &&
          await widget.gateway.supportsFileReferences();
      final data = await widget.gateway.readFile(
        widget.workspaceId,
        widget.file,
        cancelled: () => closed,
      );
      if (closed) return;
      final ext = widget.file.extension;
      if (!{'png', 'jpg', 'jpeg', 'pdf'}.contains(ext)) {
        text = utf8.decode(data, allowMalformed: true);
      }
      if (structureExtensions.contains(ext)) {
        try {
          structure = await compute(parseStructure, {
            'text': text!,
            'extension': ext,
          });
        } catch (e) {
          parseError = e;
        }
      }
      if (mounted) setState(() => bytes = data);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> attach() async {
    if (pinning) return;
    setState(() => pinning = true);
    try {
      final ref = await widget.gateway.pinFile(widget.workspaceId, widget.file);
      if (!mounted) return;
      final payload = {
        ...ref,
        'workspace_id': widget.workspaceId,
        if (selection.isNotEmpty && structure != null)
          'selection': {
            'model': structure!.frame,
            'display_atom_indices_1based': selection.map((i) => i + 1).toList(),
            'source_atom_ids': selection
                .map((i) => structure!.atoms[i].source)
                .toList(),
            'coordinate_units': 'angstrom',
          },
      };
      widget.onReference?.call(FileReference(payload));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: FileProblem(e)));
      }
    } finally {
      if (mounted) setState(() => pinning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, file = widget.file;
    return Scaffold(
      appBar: TsGlassAppBar(
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (text != null)
            IconButton(
              tooltip: raw ? l.filesPreview : l.filesRaw,
              onPressed: () => setState(() => raw = !raw),
              icon: Icon(raw ? LucideIcons.box : LucideIcons.code),
            ),
        ],
      ),
      bottomNavigationBar: canReference && bytes != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: pinning ? null : attach,
                  icon: const Icon(LucideIcons.plus),
                  label: Text(l.filesAttach),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SelectableText(
            file.path,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (error != null)
            FileProblem(error!)
          else if (bytes == null)
            const Center(child: CircularProgressIndicator())
          else if (raw && text != null)
            SelectableText(
              _boundedText(text!),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            )
          else if (structure != null)
            StructureView(
              structure: structure!,
              initialSelection: selection,
              onSelection: (v) => selection = v,
            )
          else if (parseError != null) ...[
            Text(l.filesInvalid),
            TextButton(
              onPressed: () => setState(() => raw = true),
              child: Text(l.filesRaw),
            ),
          ] else if ({'png', 'jpg', 'jpeg'}.contains(file.extension))
            InteractiveViewer(
              child: Image.memory(
                bytes!,
                cacheWidth: 2048,
                errorBuilder: (_, e, stack) => Text(l.filesInvalid),
              ),
            )
          else if (file.extension == 'csv' || file.extension == 'tsv')
            _TablePreview(
              text!,
              delimiter: file.extension == 'tsv' ? '\t' : ',',
            )
          else if (text != null)
            SelectableText(_boundedText(text!))
          else
            Text(l.filesUnsupported),
        ],
      ),
    );
  }
}

String _boundedText(String text) =>
    text.length <= 200000 ? text : '${text.substring(0, 200000)}\n…';

class FileProblem extends StatelessWidget {
  const FileProblem(this.error, {super.key});
  final Object error;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final message = switch (error) {
      CorHubApiException(code: 'file_too_large') => l.filesTooLarge,
      CorHubApiException(code: 'file_changed') => l.filesChanged,
      _ => describeCorHubProblem(error).localizedMessage(l),
    };
    return Semantics(liveRegion: true, child: SelectableText(message));
  }
}

class _TablePreview extends StatelessWidget {
  const _TablePreview(this.text, {required this.delimiter});
  final String text, delimiter;
  @override
  Widget build(BuildContext context) {
    List<List<String>> rows;
    try {
      rows = parseDelimited(text, delimiter: delimiter);
    } catch (_) {
      return Text(context.l10n.filesInvalid);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: List.generate(
          rows.isEmpty ? 1 : rows.first.length,
          (i) => DataColumn(label: Text('${i + 1}')),
        ),
        rows: rows
            .map(
              (row) => DataRow(
                cells: List.generate(
                  rows.first.length,
                  (i) => DataCell(SelectableText(i < row.length ? row[i] : '')),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Bounded quoted CSV/TSV preview, preserving embedded delimiters/newlines.
List<List<String>> parseDelimited(String text, {String delimiter = ','}) {
  final rows = <List<String>>[];
  var row = <String>[], cell = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length && rows.length < 200; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (c == delimiter || c == '\n')) {
      row.add(cell.toString());
      cell = StringBuffer();
      if (row.length > 30) throw const FormatException('Too many columns');
      if (c == '\n') {
        rows.add(row);
        row = [];
      }
    } else if (c != '\r' || quoted) {
      if (cell.length < 10000) cell.write(c);
    }
  }
  if (quoted && rows.length < 200) {
    throw const FormatException('Unterminated quoted cell');
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    if (row.length > 30) throw const FormatException('Too many columns');
    rows.add(row);
  }
  final columns = rows.fold<int>(0, (n, r) => n > r.length ? n : r.length);
  return rows
      .map((r) => [...r, ...List.filled(columns - r.length, '')])
      .toList();
}
