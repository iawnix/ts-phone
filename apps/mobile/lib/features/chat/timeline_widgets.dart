import 'package:flutter/material.dart';

import '../../l10n/app_localizations_extensions.dart';
import '../../models/session_timeline.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/chat_message_view.dart';
import '../../widgets/presentation.dart';
import 'chat_controller.dart';

enum TimelineViewFilter { all, messages, activities }

enum _TimelineHistoryActionKind { loadEarlier, loadAll, selectBranch }

class TimelineFilterControl extends StatelessWidget {
  const TimelineFilterControl({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final TimelineViewFilter selected;
  final ValueChanged<TimelineViewFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      key: const ValueKey<String>('timeline-view-filter'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labels = <TimelineViewFilter, String>{
            TimelineViewFilter.all: l10n.timelineFilterAll,
            TimelineViewFilter.messages: l10n.timelineFilterMessages,
            TimelineViewFilter.activities: l10n.timelineFilterActivities,
          };
          final scaledLabelSize = MediaQuery.textScalerOf(context).scale(14);
          final useMenu = scaledLabelSize > 18 || constraints.maxWidth < 280;
          if (useMenu) {
            return Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _TimelineFilterMenu(
                selected: selected,
                labels: labels,
                onChanged: onChanged,
              ),
            );
          }
          return TsSegmentedControl<TimelineViewFilter>(
            selected: selected,
            onChanged: onChanged,
            segments: <ButtonSegment<TimelineViewFilter>>[
              for (final entry in labels.entries)
                ButtonSegment<TimelineViewFilter>(
                  value: entry.key,
                  label: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineFilterMenu extends StatelessWidget {
  const _TimelineFilterMenu({
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  final TimelineViewFilter selected;
  final Map<TimelineViewFilter, String> labels;
  final ValueChanged<TimelineViewFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = labels[selected]!;
    return PopupMenuButton<TimelineViewFilter>(
      key: const ValueKey<String>('timeline-view-filter-menu'),
      initialValue: selected,
      tooltip: label,
      onSelected: onChanged,
      itemBuilder: (context) => <PopupMenuEntry<TimelineViewFilter>>[
        for (final entry in labels.entries)
          PopupMenuItem<TimelineViewFilter>(
            value: entry.key,
            child: Row(
              children: <Widget>[
                Icon(
                  entry.key == selected
                      ? Icons.check_rounded
                      : Icons.circle_outlined,
                  size: 18,
                ),
                const SizedBox(width: TsPhoneSpacing.small),
                Expanded(child: Text(entry.value)),
              ],
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 152, minHeight: 44),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TsPhoneSpacing.medium,
              vertical: TsPhoneSpacing.xSmall,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.filter_list_rounded,
                  size: 19,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: TsPhoneSpacing.small),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: TsPhoneSpacing.xSmall),
                const Icon(Icons.arrow_drop_down_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineHistoryAction {
  const _TimelineHistoryAction(this.kind, {this.branchId});

  final _TimelineHistoryActionKind kind;
  final String? branchId;
}

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
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
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
                  l10n.timelineActivities(controller.timelineActivityCount),
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            PopupMenuButton<_TimelineHistoryAction>(
              key: const ValueKey<String>('timeline-history-menu'),
              tooltip: l10n.timelineBranches,
              onSelected: (selection) async {
                switch (selection.kind) {
                  case _TimelineHistoryActionKind.loadEarlier:
                    await onLoadEarlier();
                  case _TimelineHistoryActionKind.loadAll:
                    await onLoadAll();
                  case _TimelineHistoryActionKind.selectBranch:
                    await onSelectBranch(selection.branchId!);
                }
              },
              icon: const Icon(Icons.more_horiz_rounded, size: 22),
              itemBuilder: (context) =>
                  <PopupMenuEntry<_TimelineHistoryAction>>[
                    if (controller.canLoadEarlierMessages || loading)
                      PopupMenuItem<_TimelineHistoryAction>(
                        key: const ValueKey<String>('load-earlier-timeline'),
                        value: const _TimelineHistoryAction(
                          _TimelineHistoryActionKind.loadEarlier,
                        ),
                        enabled: !loading,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.expand_less_rounded),
                          title: Text(
                            controller.loadingEarlierMessages
                                ? l10n.loadingEarlierMessages
                                : l10n.loadEarlierMessages,
                          ),
                        ),
                      ),
                    if (controller.canLoadEarlierMessages || loading)
                      PopupMenuItem<_TimelineHistoryAction>(
                        key: const ValueKey<String>('load-all-timeline'),
                        value: const _TimelineHistoryAction(
                          _TimelineHistoryActionKind.loadAll,
                        ),
                        enabled: !loading,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.vertical_align_top_rounded),
                          title: Text(
                            controller.loadingAllHistory
                                ? l10n.loadingAllHistory
                                : l10n.loadAllHistory,
                          ),
                        ),
                      ),
                    if ((controller.canLoadEarlierMessages || loading) &&
                        controller.timelineBranches.length > 1)
                      const PopupMenuDivider(),
                    for (final branch in controller.timelineBranches)
                      if (controller.timelineBranches.length > 1)
                        PopupMenuItem<_TimelineHistoryAction>(
                          value: _TimelineHistoryAction(
                            _TimelineHistoryActionKind.selectBranch,
                            branchId: branch.id,
                          ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          context.l10n.timelineTurnLabel(number),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
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

List<TimelineTurnGroup> filterTimelineGroups(
  List<TimelineTurnGroup> groups,
  TimelineViewFilter filter,
) {
  if (filter == TimelineViewFilter.all) return groups;
  final filtered = <TimelineTurnGroup>[];
  for (final group in groups) {
    final items = group.items
        .where((item) {
          return switch (filter) {
            TimelineViewFilter.all => true,
            TimelineViewFilter.messages => item is TimelineMessageItem,
            TimelineViewFilter.activities => item is TimelineActivityItem,
          };
        })
        .toList(growable: false);
    if (items.isEmpty) continue;
    filtered.add(
      TimelineTurnGroup(
        turnId: group.turnId,
        number: group.number,
        items: List<SessionTimelineItem>.unmodifiable(items),
      ),
    );
  }
  return List<TimelineTurnGroup>.unmodifiable(filtered);
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
    return Column(
      key: ValueKey<String>('timeline-group-content-${group.identity}'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (group.turnId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                <String>[
                  context.l10n.timelineTurnLabel(group.number),
                  if (group.activityCount > 0)
                    context.l10n.timelineActivities(group.activityCount),
                ].join(' · '),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
    final operation = <String>[
      ?activity.role?.trim(),
      ?activity.operation?.trim(),
    ].where((value) => value.isNotEmpty).map(_humanizeIdentifier).join(' · ');
    final primaryDetail = operation.isNotEmpty
        ? operation
        : _activityTitleLabel(context, activity.title);
    final durationMs = activity.durationMs;
    final durationLabel = durationMs == null
        ? null
        : context.l10n.timelineDuration((durationMs / 1000).toStringAsFixed(1));
    final stateLabel = switch (activity.status) {
      TimelineActivityStatus.completed => context.l10n.timelineCompleted,
      TimelineActivityStatus.failed => context.l10n.timelineFailed,
      TimelineActivityStatus.recorded => context.l10n.timelineRecorded,
    };
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
      if (activity.totalTokens case final tokens?)
        context.l10n.timelineTokens(tokens),
      if (activity.retrySafe case final retrySafe?)
        retrySafe
            ? context.l10n.timelineRetrySafe
            : context.l10n.timelineRetryUnsafe,
    ];
    final summary = _ActivitySummary(
      activity: activity,
      tone: tone,
      primaryDetail: primaryDetail,
      stateLabel: stateLabel,
      durationLabel: durationLabel,
    );
    return Semantics(
      label: <String>[
        _activityCategoryLabel(context, activity.category),
        primaryDetail,
        stateLabel,
      ].join(' · '),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: tone.withValues(alpha: 0.72), width: 2),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: details.isEmpty
                ? ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                      child: summary,
                    ),
                  )
                : Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: ValueKey<String>(
                        'timeline-activity-details-${identity ?? activity.title}',
                      ),
                      tilePadding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
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
    required this.stateLabel,
    required this.durationLabel,
  });

  final TimelineActivity activity;
  final Color tone;
  final String primaryDetail;
  final String stateLabel;
  final String? durationLabel;

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
                primaryDetail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        _activityStateIcon(activity.status),
                        size: 14,
                        color: tone,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        stateLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (durationLabel case final duration?)
                    Text(
                      duration,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

IconData _activityIcon(TimelineActivityCategory category) => switch (category) {
  TimelineActivityCategory.subagent => Icons.account_tree_outlined,
  TimelineActivityCategory.research => Icons.science_outlined,
  TimelineActivityCategory.review => Icons.fact_check_outlined,
  TimelineActivityCategory.workspace => Icons.folder_copy_outlined,
  TimelineActivityCategory.configuration => Icons.settings_outlined,
  TimelineActivityCategory.context => Icons.compress_outlined,
  TimelineActivityCategory.system => Icons.info_outline_rounded,
};

IconData _activityStateIcon(TimelineActivityStatus status) => switch (status) {
  TimelineActivityStatus.completed => Icons.check_circle_outline_rounded,
  TimelineActivityStatus.failed => Icons.error_outline_rounded,
  TimelineActivityStatus.recorded => Icons.circle_outlined,
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
