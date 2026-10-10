import 'dart:typed_data';

class WorkspaceFile {
  WorkspaceFile.fromJson(Map<String, Object?> data)
    : path = data['path'] as String,
      name = data['name'] as String,
      directory = data['kind'] == 'directory',
      size = data['size'] as int,
      version = data['version'] as String;
  final String path, name, version;
  final bool directory;
  final int size;
  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

class WorkspaceFilePage {
  WorkspaceFilePage(this.files, this.cursor);
  final List<WorkspaceFile> files;
  final String? cursor;
}

abstract interface class WorkspaceFileGateway {
  Future<bool> supportsFiles();
  Future<WorkspaceFilePage> listFiles(
    String workspaceId,
    String path, {
    String? cursor,
  });
  Future<Map<String, Object?>> pinFile(String workspaceId, WorkspaceFile file);
  Future<bool> supportsFileReferences();
  Future<Uint8List> readFile(
    String workspaceId,
    WorkspaceFile file, {
    required bool Function() cancelled,
  });
}
