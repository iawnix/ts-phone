class HostMonitor {
  const HostMonitor({
    required this.id,
    required this.title,
    required this.enabled,
    required this.state,
    required this.pendingCount,
    this.sessionId,
    this.lastObservedAt,
    this.lastError,
  });

  factory HostMonitor.fromJson(Map<String, Object?> json) {
    final id = json['monitor_id'];
    if (id is! String || id.isEmpty || json['enabled'] is! bool) {
      throw const FormatException('Invalid monitor');
    }
    return HostMonitor(
      id: id,
      title: (json['node_id'] ?? json['job_id'] ?? id).toString(),
      enabled: json['enabled'] == true,
      state: json['last_state']?.toString() ?? 'unknown',
      sessionId: json['session_id'] as String?,
      lastObservedAt: DateTime.tryParse(
        json['last_observed_at']?.toString() ?? '',
      ),
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      lastError: json['last_error']?.toString(),
    );
  }

  final String id;
  final String title;
  final bool enabled;
  final String state;
  final int pendingCount;
  final String? sessionId;
  final DateTime? lastObservedAt;
  final String? lastError;
}

abstract interface class HostMonitorGateway {
  Future<List<HostMonitor>> listMonitors(String workspaceId);
  Future<HostMonitor> setMonitorEnabled(
    String workspaceId,
    String monitorId,
    bool enabled,
  );
}
