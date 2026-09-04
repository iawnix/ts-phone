import 'package:flutter/material.dart';

import '../../l10n/app_localizations_extensions.dart';
import '../../models/session_timeline.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/chat_message_view.dart';
import 'chat_controller.dart';

class TimelineHistoryControl extends StatelessWidget {
  const TimelineHistoryControl({
    required this.controller,
    required this.onLoadEarlier,
    required this.onLoadAll,
    required this.onSelectBranch,
    super.key,
  });

  final ChatController controller;
  final Future<void> Function() onLoadEarlier;
  final Future<void> Function() onLoadAll;
  final Future<void> Function(String branchId) onSelectBranch;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final history = controller.timelineHistory;
    if (history == null) return const SizedBox.shrink();
    final loading =
        controller.loadingEarlierMessages || controller.loadingAllHistory;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.history_rounded, size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      <String>[
                        l10n.timelineProgress(
                          controller.loadedTimelineItemCount,
                          controller.totalTimelineItemCount,
                        ),
                        l10n.timelineTurns(controller.timelineTurnCount),
                        l10n.timelineActivities(
                          controller.timelineActivityCount,
                        ),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (controller.timelineBranches.length > 1)
                    PopupMenuButton<String>(
                      key: const ValueKey<String>('timeline-branch-menu'),
                      tooltip: l10n.timelineBranches,
                      onSelected: onSelectBranch,
                      icon: const Icon(Icons.account_tree_outlined, size: 20),
                      itemBuilder: (context) => <PopupMenuEntry<String>>[
                        for (final branch in controller.timelineBranches)
                          PopupMenuItem<String>(
                            value: branch.id,
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  branch.id == history.selectedBranchId
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    branch.name ??
                                        (branch.active
                                            ? l10n.timelineActiveBranch
                                            : l10n.timelineBranchLabel(
                                                branch.id.substring(
                                                  branch.id.length - 4,
                                                ),
                                              )),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${branch.turnCount}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              if (controller.canLoadEarlierMessages || loading) ...<Widget>[
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: <Widget>[
                    TextButton.icon(
                      key: const ValueKey<String>('load-earlier-timeline'),
                      onPressed: loading ? null : onLoadEarlier,
                      icon: const Icon(Icons.expand_less_rounded, size: 18),
                      label: Text(
                        controller.loadingEarlierMessages
                            ? l10n.loadingEarlierMessages
                            : l10n.loadEarlierMessages,
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey<String>('load-all-timeline'),
                      onPressed: loading ? null : onLoadAll,
                      icon: controller.loadingAllHistory
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.vertical_align_top_rounded,
                              size: 18,
                            ),
                      label: Text(
                        controller.loadingAllHistory
                            ? l10n.loadingAllHistory
                            : l10n.loadAllHistory,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kept as a small reusable divider for callers that render a single turn
/// outside the grouped timeline. The main timeline uses [TimelineTurnGroupView]
/// so the header and activity count stay together.
class TimelineTurnDivider extends StatelessWidget {
  const TimelineTurnDivider({required this.number, super.key});

  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 5),
      child: Row(
        children: <Widget>[
          Expanded(child: Divider(color: colors.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              context.l10n.timelineTurnLabel(number),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(child: Divider(color: colors.outlineVariant)),
        ],
      ),
    );
  }
}

/// A contiguous group of timeline records belonging to one conversational
/// turn.  Grouping is a presentation concern; the server's item ordering and
/// opaque identities remain untouched.
final class TimelineTurnGroup {
  const TimelineTurnGroup({
    required this.turnId,
    required this.number,
    required this.items,
  });

  final String? turnId;
  final int number;
  final List<SessionTimelineItem> items;

  /// Stable within the loaded page, even when a turn is split by an
  /// unscoped activity record.
  String get identity => items.first.id;

  int get activityCount => items.whereType<TimelineActivityItem>().length;
}

/// Groups a bounded page without assuming that the page starts at a turn
/// boundary.  This keeps pagination and branch replay deterministic while
/// making the visible timeline read like a sequence of turns.
List<TimelineTurnGroup> groupTimelineItems(
  List<SessionTimelineItem> items, {
  required int totalTurnCount,
}) {
  final orderedTurnIds = <String>[];
  final seenTurnIds = <String>{};
  for (final item in items) {
    final turnId = item.turnId;
    if (turnId != null && seenTurnIds.add(turnId)) {
      orderedTurnIds.add(turnId);
    }
  }
  final firstTurnNumber = (totalTurnCount - orderedTurnIds.length + 1).clamp(
    1,
    totalTurnCount == 0 ? 1 : totalTurnCount,
  );
  final turnNumbers = <String, int>{};
  for (var index = 0; index < orderedTurnIds.length; index += 1) {
    turnNumbers[orderedTurnIds[index]] = firstTurnNumber + index;
  }

  // The mutable builders are kept local so callers only receive immutable
  // lists and cannot accidentally mutate controller state.
  final groups = <TimelineTurnGroup>[];
  final builders = <_TimelineTurnGroupBuilder>[];
  String? previousTurnId;
  for (final item in items) {
    // Records without a turn are standalone system/activity rows.  Keeping
    // each one as its own list child preserves lazy viewport construction;
    // otherwise a long unscoped run becomes one giant Column and the scroll
    // extent cannot be corrected reliably while it is being laid out.
    final startsGroup = item.turnId == null || item.turnId != previousTurnId;
    if (startsGroup) {
      builders.add(
        _TimelineTurnGroupBuilder(
          turnId: item.turnId,
          number: item.turnId == null ? 0 : turnNumbers[item.turnId] ?? 1,
        ),
      );
    }
    builders.last.items.add(item);
    previousTurnId = item.turnId;
  }
  for (final builder in builders) {
    groups.add(
      TimelineTurnGroup(
        turnId: builder.turnId,
        number: builder.number,
        items: List<SessionTimelineItem>.unmodifiable(builder.items),
      ),
    );
  }
  return List<TimelineTurnGroup>.unmodifiable(groups);
}

class _TimelineTurnGroupBuilder {
  _TimelineTurnGroupBuilder({required this.turnId, required this.number});

  final String? turnId;
  final int number;
  final List<SessionTimelineItem> items = <SessionTimelineItem>[];
}

class TimelineTurnGroupView extends StatelessWidget {
  const TimelineTurnGroupView({required this.group, super.key});

  final TimelineTurnGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: ValueKey<String>('timeline-group-content-${group.identity}'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (group.turnId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: <Widget>[
                Expanded(child: Divider(color: colors.outlineVariant)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.forum_outlined,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        context.l10n.timelineTurnLabel(group.number),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (group.activityCount > 0) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          '· ${context.l10n.timelineActivities(group.activityCount)}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(child: Divider(color: colors.outlineVariant)),
              ],
            ),
          ),
        for (final item in group.items)
          switch (item) {
            TimelineMessageItem(:final message) => ChatMessageView(
              key: ValueKey<String>('timeline-message-${item.id}'),
              message: message,
            ),
            TimelineActivityItem(:final activity) => TimelineActivityView(
              key: ValueKey<String>('timeline-activity-${item.id}'),
              identity: item.id,
              activity: activity,
            ),
          },
      ],
    );
  }
}

class TimelineActivityView extends StatelessWidget {
  const TimelineActivityView({
    required this.activity,
    this.identity,
    super.key,
  });

  final TimelineActivity activity;
  final String? identity;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final failed = activity.status == TimelineActivityStatus.failed;
    final status = TsPhoneStatusTheme.resolve(context);
    final tone = failed
        ? colors.error
        : activity.status == TimelineActivityStatus.completed
        ? status.connected
        : colors.onSurfaceVariant;
    final roleOperation = <String>[
      ?activity.role?.trim(),
      ?activity.operation?.trim(),
    ].where((value) => value.isNotEmpty).map(_humanizeIdentifier).join(' · ');
    final primaryDetail = roleOperation.isNotEmpty
        ? roleOperation
        : _activityTitleLabel(context, activity.title);
    final metadata = <String>[
      ...activity.nodeRefs.map(_humanizeIdentifier),
      if (activity.durationMs case final duration?)
        context.l10n.timelineDuration((duration / 1000).toStringAsFixed(1)),
      if (activity.totalTokens case final tokens?)
        context.l10n.timelineTokens(tokens),
    ];
    final details = <String>[
      if (activity.detail case final detail? when detail.trim().isNotEmpty)
        detail,
      if (activity.stage case final stage? when stage.trim().isNotEmpty)
        '${context.l10n.timelineStage}: ${_humanizeIdentifier(stage)}',
      if (activity.nodeRefs.isNotEmpty)
        '${context.l10n.timelineNodes}: ${activity.nodeRefs.map(_humanizeIdentifier).join(', ')}',
      if (activity.reference case final reference?
          when reference.trim().isNotEmpty)
        '${context.l10n.timelineReference}: $reference',
      if (activity.retrySafe case final retrySafe?)
        retrySafe
            ? context.l10n.timelineRetrySafe
            : context.l10n.timelineRetryUnsafe,
    ];
    final summary = _ActivitySummary(
      activity: activity,
      tone: tone,
      primaryDetail: primaryDetail,
      metadata: metadata,
      failed: failed,
    );
    return Semantics(
      label: failed ? context.l10n.timelineFailed : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: tone, width: 3)),
          ),
          child: Material(
            color: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            child: details.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                    child: summary,
                  )
                : Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: ValueKey<String>(
                        'timeline-activity-details-${identity ?? activity.title}',
                      ),
                      tilePadding: const EdgeInsets.fromLTRB(10, 2, 8, 2),
                      childrenPadding: const EdgeInsets.fromLTRB(42, 0, 12, 10),
                      title: summary,
                      trailing: Icon(
                        Icons.expand_more_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                      children: <Widget>[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            details.join('\n'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({
    required this.activity,
    required this.tone,
    required this.primaryDetail,
    required this.metadata,
    required this.failed,
  });

  final TimelineActivity activity;
  final Color tone;
  final String primaryDetail;
  final List<String> metadata;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(_activityIcon(activity.category), color: tone, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                <String>[
                  _activityCategoryLabel(context, activity.category),
                  if (primaryDetail.isNotEmpty) primaryDetail,
                ].join(' · '),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (metadata.isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  metadata.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (failed)
          Icon(Icons.error_outline_rounded, color: tone, size: 18)
        else if (activity.status == TimelineActivityStatus.completed)
          Icon(Icons.check_rounded, color: tone, size: 18),
      ],
    );
  }
}

IconData _activityIcon(TimelineActivityCategory category) => switch (category) {
  TimelineActivityCategory.subagent => Icons.smart_toy_rounded,
  TimelineActivityCategory.research => Icons.science_rounded,
  TimelineActivityCategory.review => Icons.fact_check_rounded,
  TimelineActivityCategory.workspace => Icons.folder_copy_rounded,
  TimelineActivityCategory.configuration => Icons.settings_rounded,
  TimelineActivityCategory.context => Icons.compress_rounded,
  TimelineActivityCategory.system => Icons.info_rounded,
};

String _activityCategoryLabel(
  BuildContext context,
  TimelineActivityCategory category,
) => switch (category) {
  TimelineActivityCategory.subagent => context.l10n.timelineSubagent,
  TimelineActivityCategory.research => context.l10n.timelineResearch,
  TimelineActivityCategory.review => context.l10n.timelineReview,
  TimelineActivityCategory.workspace => context.l10n.timelineWorkspace,
  TimelineActivityCategory.configuration => context.l10n.timelineConfiguration,
  TimelineActivityCategory.context => context.l10n.timelineContext,
  TimelineActivityCategory.system => context.l10n.timelineSystem,
};

String _humanizeIdentifier(String value) {
  final normalized = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (normalized.isEmpty) return value;
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

String _activityTitleLabel(BuildContext context, String value) =>
    switch (value) {
      'model_change' => context.l10n.timelineModelChange,
      'thinking_level_change' => context.l10n.timelineThinkingLevelChange,
      'session_info' => context.l10n.timelineSessionInfo,
      _ => _humanizeIdentifier(value),
    };
