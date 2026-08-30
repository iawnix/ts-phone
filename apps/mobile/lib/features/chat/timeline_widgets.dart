import 'package:flutter/material.dart';

import '../../l10n/app_localizations_extensions.dart';
import '../../models/session_timeline.dart';
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

class TimelineActivityView extends StatelessWidget {
  const TimelineActivityView({required this.activity, super.key});

  final TimelineActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final failed = activity.status == TimelineActivityStatus.failed;
    final tone = failed ? colors.error : colors.tertiary;
    final roleOperation = <String>[
      ?activity.role?.trim(),
      ?activity.operation?.trim(),
    ].where((value) => value.isNotEmpty).map(_humanizeIdentifier).join(' · ');
    final primaryDetail = roleOperation.isNotEmpty
        ? roleOperation
        : _activityTitleLabel(context, activity.title);
    final metadata = <String>[
      ...activity.nodeRefs,
      if (activity.durationMs case final duration?)
        context.l10n.timelineDuration((duration / 1000).toStringAsFixed(1)),
      if (activity.totalTokens case final tokens?)
        context.l10n.timelineTokens(tokens),
    ];
    return Semantics(
      label: failed ? context.l10n.timelineFailed : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: tone, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                _activityIcon(activity.category),
                color: tone,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          <String>[
                            _activityCategoryLabel(context, activity.category),
                            if (primaryDetail.isNotEmpty) primaryDetail,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      if (failed)
                        Icon(Icons.error_outline_rounded, color: tone, size: 18)
                      else if (activity.status ==
                          TimelineActivityStatus.completed)
                        Icon(Icons.check_rounded, color: tone, size: 18),
                    ],
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
                  if (activity.detail case final detail?) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _activityIcon(TimelineActivityCategory category) => switch (category) {
  TimelineActivityCategory.subagent => Icons.hub_outlined,
  TimelineActivityCategory.research => Icons.science_outlined,
  TimelineActivityCategory.review => Icons.fact_check_outlined,
  TimelineActivityCategory.workspace => Icons.folder_open_outlined,
  TimelineActivityCategory.configuration => Icons.tune_rounded,
  TimelineActivityCategory.context => Icons.compress_rounded,
  TimelineActivityCategory.system => Icons.info_outline_rounded,
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
