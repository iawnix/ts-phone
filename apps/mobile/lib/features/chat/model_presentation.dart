String modelProviderLabel(String provider) {
  final normalized = provider.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '',
  );
  return switch (normalized) {
    'openai' => 'OpenAI',
    'anthropic' || 'claude' => 'Anthropic',
    'google' || 'gemini' => 'Google',
    'deepseek' => 'DeepSeek',
    'qwen' || 'tongyi' => 'Qwen',
    'mistral' => 'Mistral',
    'moonshot' || 'kimi' => 'Moonshot',
    'zhipu' || 'glm' => '智谱',
    'xai' || 'grok' => 'xAI',
    _ => provider.trim().isEmpty ? 'Model' : provider.trim(),
  };
}

String modelBrandLabel(String provider, {String? modelId}) {
  final providerLabel = modelProviderLabel(provider);
  final normalizedProvider = provider.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '',
  );
  if (normalizedProvider != 'cpa' && providerLabel != provider.trim()) {
    return providerLabel;
  }
  final normalizedModel = (modelId ?? '').toLowerCase();
  if (normalizedModel.startsWith('gpt-') ||
      normalizedModel.startsWith('o1') ||
      normalizedModel.startsWith('o3') ||
      normalizedModel.startsWith('o4')) {
    return 'OpenAI';
  }
  if (normalizedModel.startsWith('claude')) return 'Anthropic';
  if (normalizedModel.startsWith('gemini')) return 'Google';
  if (normalizedModel.startsWith('deepseek')) return 'DeepSeek';
  if (normalizedModel.startsWith('qwen')) return 'Qwen';
  if (normalizedModel.startsWith('mistral')) return 'Mistral';
  if (normalizedModel.startsWith('kimi') ||
      normalizedModel.startsWith('moonshot')) {
    return 'Moonshot';
  }
  if (normalizedModel.startsWith('glm')) return '智谱';
  if (normalizedModel.startsWith('grok')) return 'xAI';
  return providerLabel;
}

String modelDisplayName(String value) {
  final text = value.trim();
  if (text.isEmpty) return text;
  final parts = text
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) {
        final lower = part.toLowerCase();
        if (const {'gpt', 'glm', 'qwen', 'xai'}.contains(lower)) {
          return lower.toUpperCase();
        }
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
  return parts;
}

String formatTokenCount(int tokens) {
  if (tokens >= 1000000) {
    final value = tokens / 1000000;
    return '${value == value.roundToDouble() ? value.toInt() : value.toStringAsFixed(1)}M';
  }
  if (tokens >= 1000) {
    final value = tokens / 1000;
    return '${value == value.roundToDouble() ? value.toInt() : value.toStringAsFixed(1)}k';
  }
  return '$tokens';
}
