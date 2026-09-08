import 'package:flutter/material.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/phone_model.dart';

Future<PhoneModel?> showModelPicker(
  BuildContext context, {
  required TsPhoneModelGateway gateway,
  String? selected,
  Future<void> Function(PhoneModel)? onSelect,
  bool Function()? canSelect,
  Listenable? state,
}) => showModalBottomSheet<PhoneModel>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
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
  final TsPhoneModelGateway gateway;
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
  TsPhoneProblem? _problem;
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
      if (mounted) setState(() => _problem = describeTsPhoneProblem(error));
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
      if (mounted) setState(() => _problem = describeTsPhoneProblem(error));
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
                          icon: const Icon(Icons.close_rounded),
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
                        prefixIcon: const Icon(Icons.search_rounded),
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
                          itemCount: models.length,
                          itemBuilder: (context, index) {
                            final model = models[index];
                            final selected = model.reference == widget.selected;
                            return ListTile(
                              key: ValueKey('model-${model.reference}'),
                              enabled:
                                  !_saving && widget.canSelect?.call() != false,
                              title: Text(
                                model.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${model.provider} · ${model.id}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: selected
                                  ? const Icon(Icons.check_rounded)
                                  : null,
                              onTap: () => _select(model),
                            );
                          },
                        ),
                ),
                if (_problem != null && !_saving)
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
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
