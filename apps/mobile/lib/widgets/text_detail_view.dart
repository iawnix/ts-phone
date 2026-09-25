import 'package:flutter/material.dart';
import 'package:ts_phone/theme/app_icons.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations_extensions.dart';
import '../navigation/adaptive_page_route.dart';

/// Keep editable/scrollable text out of animated timeline disclosures.
class TextDetailPreview extends StatelessWidget {
  const TextDetailPreview({
    super.key,
    required this.text,
    required this.title,
    this.style,
  });

  final String text;
  final String title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final preview = text.characters.take(1600).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          preview,
          maxLines: 10,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: IconButton(
            tooltip: context.l10n.viewFullOutput,
            icon: const Icon(AppIcons.open_in_full_rounded, size: 18),
            onPressed: () => pushTsPhonePage<void>(
              context: context,
              builder: (_) => _TextDetailPage(text: text, title: title),
            ),
          ),
        ),
      ],
    );
  }
}

class _TextDetailPage extends StatelessWidget {
  _TextDetailPage({required this.text, required this.title})
    : paragraphs = text.split('\n');

  final String text;
  final String title;
  final List<String> paragraphs;

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.outputCopied)));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.outputCopyFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: context.l10n.copyOutput,
          icon: const Icon(AppIcons.copy_rounded),
          onPressed: () => _copy(context),
        ),
      ],
    ),
    body: SafeArea(
      child: SelectionArea(
        child: ListView.builder(
          key: const ValueKey('full-output-list'),
          padding: const EdgeInsets.all(16),
          itemCount: paragraphs.length,
          itemBuilder: (context, index) => Text(
            paragraphs[index].isEmpty ? ' ' : paragraphs[index],
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.45,
            ),
          ),
        ),
      ),
    ),
  );
}
