enum CommandStatus {
  queued,
  starting,
  running,
  completed,
  failed,
  cancelled,
  unknown,
  acknowledged;

  static CommandStatus parse(Object? value) => values.firstWhere(
    (status) => status.name == value,
    orElse: () => throw const FormatException('Invalid command status'),
  );
}

class QueuedCommand {
  const QueuedCommand({
    required this.id,
    required this.status,
    required this.createdAt,
    this.position,
    this.sessionId,
    this.preview,
    this.model,
    this.problem,
  });

  factory QueuedCommand.fromJson(Map<String, Object?> json) {
    final id = json['clientMessageId'];
    final at = json['createdAt'];
    final position = json['position'];
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(id) ||
        at is! String ||
        DateTime.tryParse(at) == null ||
        (position != null && (position is! int || position < 1)) ||
        (json['sessionId'] != null && json['sessionId'] is! String) ||
        (json['preview'] != null && json['preview'] is! String) ||
        (json['model'] != null && json['model'] is! String) ||
        (json['problem'] != null && json['problem'] is! String)) {
      throw const FormatException('Invalid Host command');
    }
    return QueuedCommand(
      id: id,
      status: CommandStatus.parse(json['status']),
      createdAt: DateTime.parse(at),
      position: position as int?,
      sessionId: json['sessionId'] as String?,
      preview: json['preview'] as String?,
      model: json['model'] as String?,
      problem: json['problem'] as String?,
    );
  }

  static List<QueuedCommand> parseList(Object? value) {
    if (value == null) return const [];
    if (value is! List) throw const FormatException('Invalid Host queue');
    return List.unmodifiable(
      value.map((row) {
        if (row is! Map) {
          throw const FormatException('Invalid Host queue entry');
        }
        return QueuedCommand.fromJson(Map<String, Object?>.from(row));
      }),
    );
  }

  final String id;
  final CommandStatus status;
  final DateTime createdAt;
  final int? position;
  final String? sessionId;
  final String? preview;
  final String? model;
  final String? problem;
}
