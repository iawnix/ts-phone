import 'dart:convert';

/// A visible text reference on the existing input protocol, not an upload.
class FileReference {
  FileReference(Map<String, Object?> value) : data = Map.unmodifiable(value);
  final Map<String, Object?> data;
  String get name => (data['source_path'] as String).split('/').last;
  String get details => const JsonEncoder.withIndent('  ').convert(data);
  String get wire => '\n\n[CoRHub file]\n```json\n${jsonEncode(data)}\n```';
}

/// Preserve the exact wire draft in conversation memory and the durable outbox.
/// Only validated file blocks at the end are collapsed into UI chips.
class ReferencedDraft {
  ReferencedDraft(this.text, this.files);
  final String text;
  final List<FileReference> files;
  String get wire => text + files.map((f) => f.wire).join();
  static ReferencedDraft parse(String value) {
    final files = <FileReference>[];
    const marker = '\n\n[CoRHub file]\n```json\n';
    // input/send trims surrounding whitespace, including a file-only draft's
    // leading separator. Recognize that same reference when reading history.
    var text = value.startsWith('[CoRHub file]\n```json\n')
        ? '\n\n$value'
        : value;
    while (text.endsWith('\n```')) {
      final start = text.lastIndexOf(marker);
      if (start < 0) break;
      try {
        final data = jsonDecode(
          text.substring(start + marker.length, text.length - 4),
        );
        if (data is! Map<String, dynamic> ||
            data['source_path'] is! String ||
            data['path'] is! String ||
            data['workspace_id'] is! String ||
            data['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['sha256'] as String)) {
          break;
        }
        files.insert(0, FileReference(data));
        text = text.substring(0, start);
      } on FormatException {
        break;
      }
    }
    return ReferencedDraft(files.isEmpty ? value : text, files);
  }
}
