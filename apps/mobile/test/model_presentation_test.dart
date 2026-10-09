import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/features/chat/model_presentation.dart';

void main() {
  test(
    'generic providers keep their real label while model marks stay useful',
    () {
      expect(modelProviderLabel('CPA'), 'CPA');
      expect(modelBrandLabel('CPA', modelId: 'deepseek-v4-flash'), 'DeepSeek');
      expect(modelBrandLabel('openai', modelId: 'custom-model'), 'OpenAI');
    },
  );

  test('model names and token counts are compact for the phone toolbar', () {
    expect(modelDisplayName('gpt-5.6-sol'), 'GPT 5.6 Sol');
    expect(formatTokenCount(3200), '3.2k');
    expect(formatTokenCount(1050000), '1.1M');
  });
}
