import 'package:flutter/material.dart';
import 'package:corhub/theme/app_icons.dart';

import '../../data/corhub_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/phone_model.dart';
import '../../theme/corhub_theme.dart';
import 'model_presentation.dart';
import 'model_provider_mark.dart';

Future<PhoneModel?> showModelPicker(
  BuildContext context, {
  required CorHubModelGateway gateway,
  String? selected,
  Future<void> Function(PhoneModel)? onSelect,
  bool Function()? canSelect,
  Listenable? state,
}) => showModalBottomSheet<PhoneModel>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  sheetAnimationStyle: CorHubMotion.resolveAnimationStyle(context),
  builder: (_) => _ModelPicker(
    gateway: gateway,
    selected: selected,
    onSelect: onSelect,
    canSelect: canSelect,
    state: state,
  ),
);

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({
    required this.gateway,
    this.selected,
    this.onSelect,
    this.canSelect,
    this.state,
  });
  final CorHubModelGateway gateway;
  final String? selected;
  final Future<void> Function(PhoneModel)? onSelect;
  final bool Function()? canSelect;
  final Listenable? state;
  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  List<PhoneModel> _models = [];
  String _query = '';
  CorHubProblem? _problem;
  bool _loading = true;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    widget.state?.addListener(_changed);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state?.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    try {
      final models = await widget.gateway.models();
      if (mounted) setState(() => _models = models);
    } catch (error) {
      if (mounted) setState(() => _problem = describeCorHubProblem(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(PhoneModel model) async {
    if (_saving || widget.canSelect?.call() == false) return;
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      await widget.onSelect?.call(model);
      if (mounted) Navigator.of(context).pop(model);
    } catch (error) {
      if (mounted) setState(() => _problem = describeCorHubProblem(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final models = _models
        .where(
          (model) =>
              '${model.name} ${model.reference}'.toLowerCase().contains(_query),
        )
        .toList();
    final grouped = <String, List<PhoneModel>>{};
    for (final model in models) {
      grouped
          .putIfAbsent(modelProviderLabel(model.provider), () => [])
          .add(model);
    }
    for (final group in grouped.values) {
      group.sort((a, b) {
        final aSelected = a.reference == widget.selected;
        final bSelected = b.reference == widget.selected;
        if (aSelected != bSelected) return aSelected ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    final providerGroups = grouped.entries.toList()
      ..sort((a, b) {
        final aSelected = a.value.any(
          (model) => model.reference == widget.selected,
        );
        final bSelected = b.value.any(
          (model) => model.reference == widget.selected,
        );
        if (aSelected != bSelected) return aSelected ? -1 : 1;
        return a.key.compareTo(b.key);
      });
    final showProviderHeaders = providerGroups.length > 1;
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  (MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom -
                          80)
                      .clamp(0, 560),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.chooseModel,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (_saving)
                        const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: l10n.cancel,
                          icon: const Icon(AppIcons.close_rounded),
                        ),
                    ],
                  ),
                ),
                if (_models.length > 5)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TextField(
                      enabled: !_saving,
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: l10n.searchModels,
                        prefixIcon: const Icon(AppIcons.search_rounded),
                      ),
                    ),
                  ),
                if (_problem != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _problem!.localizedMessage(l10n),
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                Flexible(
                  child: _loading
                      ? const SizedBox(
                          height: 120,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : models.isEmpty
                      ? SizedBox(
                          height: 120,
                          child: Center(
                            child: Text(
                              _problem == null
                                  ? l10n.noModelsAvailable
                                  : l10n.problemModelCheckFailed,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: providerGroups.fold<int>(
                            0,
                            (count, group) =>
                                count +
                                group.value.length +
                                (showProviderHeaders ? 1 : 0),
                          ),
                          itemBuilder: (context, index) {
                            var cursor = index;
                            MapEntry<String, List<PhoneModel>>? group;
                            PhoneModel? model;
                            for (final candidate in providerGroups) {
                              if (showProviderHeaders) {
                                if (cursor == 0) {
                                  group = candidate;
                                  break;
                                }
                                cursor -= 1;
                              }
                              if (cursor < candidate.value.length) {
                                group = candidate;
                                model = candidate.value[cursor];
                                break;
                              }
                              cursor -= candidate.value.length;
                            }
                            if (model == null) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  4,
                                ),
                                child: Text(
                                  group!.key,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              );
                            }
                            final currentModel = model;
                            final selected =
                                currentModel.reference == widget.selected;
                            return ListTile(
                              key: ValueKey('model-${currentModel.reference}'),
                              enabled:
                                  !_saving && widget.canSelect?.call() != false,
                              leading: ModelProviderMark(
                                provider: currentModel.provider,
                                modelId: currentModel.id,
                                size: 24,
                              ),
                              title: Text(
                                modelDisplayName(currentModel.name),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  modelProviderLabel(currentModel.provider),
                                  if (currentModel.contextWindow != null)
                                    '${formatTokenCount(currentModel.contextWindow!)} ${l10n.sessionContextWindow}',
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: selected
                                  ? const Icon(AppIcons.check_rounded)
                                  : null,
                              onTap: () => _select(currentModel),
                            );
                          },
                        ),
                ),
                if (_problem != null && !_saving)
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(AppIcons.refresh_rounded),
                    label: Text(l10n.retry),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
