String? conversationTimeLabel(DateTime? value, {bool seconds = false}) {
  final local = value?.toLocal();
  if (local == null) return null;
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  if (!seconds) return '$hour:$minute';
  final second = local.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}
