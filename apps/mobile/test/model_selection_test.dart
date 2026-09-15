import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/models/phone_model.dart';
import 'package:ts_phone/models/workspace.dart';

import 'chat_controller_test.dart' as fixtures;

const first = PhoneModel(
  provider: 'cpa',
  id: 'gpt-5.6-sol',
  name: 'GPT-5.6 Sol',
  contextWindow: 128000,
);
const second = PhoneModel(
  provider: 'cpa',
  id: 'gpt-5.6-terra',
  name: 'GPT-5.6 Terra',
  contextWindow: 64000,
);
const revision = '11111111-1111-4111-8111-111111111111';

SessionSummary ready([PhoneModel model = first]) => SessionSummary(
  sessionId: 'session-test',
  sessionRevision: revision,
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  accessMode: SessionAccessMode.controller,
  historyAvailable: true,
  capabilities: const {'command.model'},
  runtime: SessionRuntimeSnapshot.fromJson(
    fixtures.sessionRuntimeJson(modelId: model.id, usedTokens: 300),
  ),
);

class ModelGateway extends fixtures.FakeGateway implements TsPhoneModelGateway {
  List<PhoneModel> available = [first, second];
  int selections = 0;
  PhoneModel? selected;

  @override
  Future<List<PhoneModel>> models() async => available;

  @override
  Future<SessionSummary> selectModel(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    PhoneModel model,
  ) async {
    expect(workspaceId, 'ts_001');
    expect(sessionId, 'session-test');
    expect(sessionRevision, revision);
    selections += 1;
    selected = model;
    return ready(model);
  }
}

ChatController controllerFor(ModelGateway gateway) => ChatController(
  api: gateway,
  workspaceId: 'ts_001',
  sessionId: 'session-test',
  initialSessionRevision: revision,
  initialRuntimeState: RuntimeState.idle,
  accessMode: SessionAccessMode.controller,
  initialCapabilities: const {'command.model'},
  initialSessionRuntime: ready().runtime,
);

void main() {
  test('model catalog comes from the App Server models service', () async {
    final gateway = ModelGateway();
    expect(await gateway.models(), [first, second]);
  });

  test(
    'model selection requires the native command.model capability',
    () async {
      final gateway = ModelGateway();
      final controller = controllerFor(gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.canSelectModel, isTrue);
      await controller.selectModel(second);
      expect(gateway.selections, 1);
      expect(controller.selectedModelReference, second.reference);
      expect(controller.sessionRevision, revision);
    },
  );
}
