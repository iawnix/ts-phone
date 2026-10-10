import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/file_reference.dart';
import '../l10n/app_localizations_extensions.dart';

class FileReferenceChip extends StatelessWidget {
  const FileReferenceChip({super.key, required this.reference, this.onRemove});
  final FileReference reference;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => InputChip(
    avatar: const Icon(LucideIcons.file, size: 18),
    label: Text(reference.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    tooltip: reference.name,
    deleteButtonTooltipMessage: context.l10n.filesRemove,
    onDeleted: onRemove,
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reference.name),
        content: SingleChildScrollView(
          child: SelectableText(reference.details),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    ),
  );
}
