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
    final state = json['state'] is Map ? json['state']! as Map : const {};
    final delivery = json['delivery'] is Map
        ? json['delivery']! as Map
        : const {};
    return HostMonitor(
      id: id,
      title: (json['intent_id'] ?? json['node_id'] ?? id).toString(),
      enabled: json['enabled'] == true,
      state: state['last_state']?.toString() ?? 'unknown',
      sessionId: json['session_id'] as String?,
      lastObservedAt: DateTime.tryParse(
        state['last_observed_at']?.toString() ?? '',
      ),
      pendingCount: (delivery['pending_count'] as num?)?.toInt() ?? 0,
      lastError: (state['last_error'] ?? delivery['last_error'])?.toString(),
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
