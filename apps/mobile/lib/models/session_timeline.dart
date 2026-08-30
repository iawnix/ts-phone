import 'chat_message.dart';

const String timelineCapability = 'history.timeline';
const String timelinePaginationCapability = 'history.pagination';
const String timelineBranchesCapability = 'history.branches';
const String promptCapability = 'command.prompt';
const String abortCapability = 'command.abort';

sealed class SessionTimelineItem {
  const SessionTimelineItem({required this.id, this.turnId});

  factory SessionTimelineItem.fromJson(Object? value) {
    final json = _asMap(value, 'Timeline item');
    final id = json['id'];
    final turnId = json['turnId'];
    final kind = json['kind'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{8}$').hasMatch(id) ||
        (turnId != null &&
            (turnId is! String ||
                !RegExp(r'^[0-9a-f]{8}$').hasMatch(turnId)))) {
      throw const FormatException('Timeline item identity is invalid');
    }
    return switch (kind) {
      'message' => TimelineMessageItem(
        id: id,
        turnId: turnId as String?,
        message: ChatMessage.fromJson(json['message']),
      ),
      'activity' => TimelineActivityItem(
        id: id,
        turnId: turnId as String?,
        activity: TimelineActivity.fromJson(json['activity']),
      ),
      _ => throw const FormatException('Timeline item kind is invalid'),
    };
  }

  final String id;
  final String? turnId;
}

final class TimelineMessageItem extends SessionTimelineItem {
  const TimelineMessageItem({
    required super.id,
    super.turnId,
    required this.message,
  });

  final ChatMessage message;

  TimelineMessageItem copyWith({ChatMessage? message}) => TimelineMessageItem(
    id: id,
    turnId: turnId,
    message: message ?? this.message,
  );
}

final class TimelineActivityItem extends SessionTimelineItem {
  const TimelineActivityItem({
    required super.id,
    super.turnId,
    required this.activity,
  });

  final TimelineActivity activity;
}

enum TimelineActivityCategory {
  subagent,
  research,
  review,
  workspace,
  configuration,
  context,
  system;

  static TimelineActivityCategory parse(Object? value) => switch (value) {
    'subagent' => TimelineActivityCategory.subagent,
    'research' => TimelineActivityCategory.research,
    'review' => TimelineActivityCategory.review,
    'workspace' => TimelineActivityCategory.workspace,
    'configuration' => TimelineActivityCategory.configuration,
    'context' => TimelineActivityCategory.context,
    'system' => TimelineActivityCategory.system,
    _ => throw FormatException('Unknown timeline activity category: $value'),
  };
}

enum TimelineActivityStatus {
  completed,
  failed,
  recorded;

  static TimelineActivityStatus parse(Object? value) => switch (value) {
    'completed' => TimelineActivityStatus.completed,
    'failed' => TimelineActivityStatus.failed,
    'recorded' => TimelineActivityStatus.recorded,
    _ => throw FormatException('Unknown timeline activity status: $value'),
  };
}

class TimelineActivity {
  const TimelineActivity({
    required this.category,
    required this.status,
    required this.title,
    this.role,
    this.operation,
    this.nodeRefs = const <String>[],
    this.detail,
    this.stage,
    this.durationMs,
    this.totalTokens,
    this.retrySafe,
    this.reference,
    this.at,
  });

  factory TimelineActivity.fromJson(Object? value) {
    final json = _asMap(value, 'Timeline activity');
    final title = json['title'];
    final nodeRefs = json['nodeRefs'];
    if (title is! String ||
        title.isEmpty ||
        (nodeRefs != null &&
            (nodeRefs is! List || nodeRefs.any((item) => item is! String)))) {
      throw const FormatException('Timeline activity is invalid');
    }
    final durationMs = _optionalNonNegativeInt(
      json['durationMs'],
      'durationMs',
    );
    final totalTokens = _optionalNonNegativeInt(
      json['totalTokens'],
      'totalTokens',
    );
    final at = json['at'];
    if (at != null && at is! String) {
      throw const FormatException('Timeline activity timestamp is invalid');
    }
    final parsedNodeRefs = nodeRefs == null
        ? const <String>[]
        : List<String>.unmodifiable((nodeRefs as List).cast<String>());
    final parsedAt = at == null ? null : DateTime.parse(at as String);
    return TimelineActivity(
      category: TimelineActivityCategory.parse(json['category']),
      status: TimelineActivityStatus.parse(json['status']),
      title: title,
      role: _optionalString(json['role'], 'role'),
      operation: _optionalString(json['operation'], 'operation'),
      nodeRefs: parsedNodeRefs,
      detail: _optionalString(json['detail'], 'detail'),
      stage: _optionalString(json['stage'], 'stage'),
      durationMs: durationMs,
      totalTokens: totalTokens,
      retrySafe: _optionalBool(json['retrySafe'], 'retrySafe'),
      reference: _optionalString(json['reference'], 'reference'),
      at: parsedAt,
    );
  }

  final TimelineActivityCategory category;
  final TimelineActivityStatus status;
  final String title;
  final String? role;
  final String? operation;
  final List<String> nodeRefs;
  final String? detail;
  final String? stage;
  final int? durationMs;
  final int? totalTokens;
  final bool? retrySafe;
  final String? reference;
  final DateTime? at;
}

class TimelineBranchSummary {
  const TimelineBranchSummary({
    required this.id,
    required this.active,
    required this.itemCount,
    required this.messageCount,
    required this.activityCount,
    required this.turnCount,
    this.name,
    this.updatedAt,
  });

  factory TimelineBranchSummary.fromJson(Object? value) {
    final json = _asMap(value, 'Timeline branch');
    final id = json['id'];
    final active = json['active'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{8}$').hasMatch(id) ||
        active is! bool) {
      throw const FormatException('Timeline branch is invalid');
    }
    final updatedAt = json['updatedAt'];
    if (updatedAt != null && updatedAt is! String) {
      throw const FormatException('Timeline branch timestamp is invalid');
    }
    final parsedUpdatedAt = updatedAt == null
        ? null
        : DateTime.parse(updatedAt as String);
    return TimelineBranchSummary(
      id: id,
      active: active,
      itemCount: _requiredNonNegativeInt(json['itemCount'], 'itemCount'),
      messageCount: _requiredNonNegativeInt(
        json['messageCount'],
        'messageCount',
      ),
      activityCount: _requiredNonNegativeInt(
        json['activityCount'],
        'activityCount',
      ),
      turnCount: _requiredNonNegativeInt(json['turnCount'], 'turnCount'),
      name: _optionalString(json['name'], 'name'),
      updatedAt: parsedUpdatedAt,
    );
  }

  final String id;
  final bool active;
  final int itemCount;
  final int messageCount;
  final int activityCount;
  final int turnCount;
  final String? name;
  final DateTime? updatedAt;
}

class TimelineHistorySummary {
  const TimelineHistorySummary({
    required this.totalItems,
    required this.messageCount,
    required this.activityCount,
    required this.turnCount,
    required this.branches,
    this.activeBranchId,
    this.selectedBranchId,
  });

  factory TimelineHistorySummary.fromJson(Object? value) {
    final json = _asMap(value, 'Timeline history');
    final rawBranches = json['branches'];
    final branchCount = _requiredNonNegativeInt(
      json['branchCount'],
      'branchCount',
    );
    if (rawBranches is! List || rawBranches.length != branchCount) {
      throw const FormatException('Timeline branch summary is invalid');
    }
    final branches = rawBranches
        .map(TimelineBranchSummary.fromJson)
        .toList(growable: false);
    final activeBranchId = _optionalCursor(
      json['activeBranchId'],
      'activeBranchId',
    );
    final selectedBranchId = _optionalCursor(
      json['selectedBranchId'],
      'selectedBranchId',
    );
    final branchIds = branches.map((branch) => branch.id).toSet();
    if ((activeBranchId != null && !branchIds.contains(activeBranchId)) ||
        (selectedBranchId != null && !branchIds.contains(selectedBranchId)) ||
        branches.where((branch) => branch.active).length > 1 ||
        (activeBranchId != null &&
            !branches.any(
              (branch) => branch.id == activeBranchId && branch.active,
            ))) {
      throw const FormatException('Timeline branch identity is inconsistent');
    }
    return TimelineHistorySummary(
      totalItems: _requiredNonNegativeInt(json['totalItems'], 'totalItems'),
      messageCount: _requiredNonNegativeInt(
        json['messageCount'],
        'messageCount',
      ),
      activityCount: _requiredNonNegativeInt(
        json['activityCount'],
        'activityCount',
      ),
      turnCount: _requiredNonNegativeInt(json['turnCount'], 'turnCount'),
      activeBranchId: activeBranchId,
      selectedBranchId: selectedBranchId,
      branches: List<TimelineBranchSummary>.unmodifiable(branches),
    );
  }

  final int totalItems;
  final int messageCount;
  final int activityCount;
  final int turnCount;
  final String? activeBranchId;
  final String? selectedBranchId;
  final List<TimelineBranchSummary> branches;

  bool get selectedBranchIsActive =>
      selectedBranchId == null || selectedBranchId == activeBranchId;
}

Map<String, Object?> _asMap(Object? value, String label) {
  if (value is! Map) throw FormatException('$label is invalid');
  return value.cast<String, Object?>();
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$field is invalid');
  return value;
}

bool? _optionalBool(Object? value, String field) {
  if (value == null) return null;
  if (value is! bool) throw FormatException('$field is invalid');
  return value;
}

int _requiredNonNegativeInt(Object? value, String field) {
  if (value is! int || value < 0) throw FormatException('$field is invalid');
  return value;
}

int? _optionalNonNegativeInt(Object? value, String field) {
  if (value == null) return null;
  return _requiredNonNegativeInt(value, field);
}

String? _optionalCursor(Object? value, String field) {
  final parsed = _optionalString(value, field);
  if (parsed != null && !RegExp(r'^[0-9a-f]{8}$').hasMatch(parsed)) {
    throw FormatException('$field is invalid');
  }
  return parsed;
}
