/// Read projections of the canonical CoRAgent Monitor contract.
/// No lifecycle is inferred from model replies or job completion.
Map<String, Object?> monitorObject(Object? value) {
  if (value is! Map) throw const FormatException('Expected Monitor object');
  return Map<String, Object?>.from(value);
}

List<Map<String, Object?>> monitorItems(Object? value) {
  if (value is! List) throw const FormatException('Expected Monitor list');
  return value.map(monitorObject).toList(growable: false);
}

class MonitorTask {
  MonitorTask(this.raw) {
    if (raw['schema_version'] != 'coragent-user-task/2' ||
        raw['user_task_id'] is! String ||
        raw['revision'] is! int ||
        revision < 1 ||
        !states.contains(state)) {
      throw const FormatException('Unsupported user task');
    }
  }
  static const states = {
    'active',
    'waiting',
    'paused',
    'blocked',
    'completing',
    'completed',
    'cancelled',
  };
  final Map<String, Object?> raw;
  String get id => raw['user_task_id'] as String;
  int get revision => raw['revision'] as int;
  String get title => raw['title'] as String? ?? id;
  String get state => raw['state'] as String? ?? '';
  String get objective => raw['objective'] as String? ?? '';
  String? get reason => raw['reason'] as String?;
  bool get terminal => state == 'completed' || state == 'cancelled';
  String? get progress => raw['progress'] is Map
      ? (raw['progress'] as Map)['summary'] as String?
      : null;
}

class MonitorJob {
  MonitorJob(this.raw) {
    if (raw['job_id'] is! String || raw['state'] is! String) {
      throw const FormatException('Invalid job observation');
    }
  }
  final Map<String, Object?> raw;
  String get id => raw['job_id'] as String;
  String get title =>
      raw['title'] as String? ?? raw['job_name'] as String? ?? id;
  String get state => raw['state'] as String;
  String? get taskId => raw['user_task_id'] as String?;
  bool get cancellable => const {
    'queued',
    'pending',
    'running',
    'submitted',
    'unknown',
  }.contains(state);
}

class MonitorOverview {
  MonitorOverview(Map<String, Object?> raw)
    : task = raw['task'] == null
          ? null
          : MonitorTask(monitorObject(raw['task'])),
      jobs = monitorItems(
        monitorObject(raw['jobs'])['items'],
      ).map(MonitorJob.new).toList(),
      nextCursor = monitorObject(raw['jobs'])['next_cursor'] as String?,
      controller = monitorObject(raw['task_controller']),
      updatedAt = DateTime.tryParse(raw['updated_at'] as String? ?? '') {
    if (raw['schema_version'] != 'coragent-monitor/1') {
      throw const FormatException('Unsupported Monitor overview');
    }
  }
  final MonitorTask? task;
  final List<MonitorJob> jobs;
  final String? nextCursor;
  final Map<String, Object?> controller;
  final DateTime? updatedAt;
}

abstract interface class HostMonitorGateway {
  Future<Set<String>> monitorCapabilities();
  Stream<void> monitorChanges(String workspaceId, String sessionId);
  Future<Map<String, Object?>> monitorRequest(
    String workspaceId,
    String sessionId,
    String method, {
    Map<String, Object?> params = const {},
  });
}
