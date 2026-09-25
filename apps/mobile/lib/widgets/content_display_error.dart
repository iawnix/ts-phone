import 'package:flutter/material.dart';
import 'package:ts_phone/theme/app_icons.dart';

import '../l10n/app_localizations_extensions.dart';

/// Flutter still reports the exception; only its unbounded visual fallback changes.
class ContentDisplayError extends StatelessWidget {
  const ContentDisplayError({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              AppIcons.error_outline_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.contentDisplayFailed,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
