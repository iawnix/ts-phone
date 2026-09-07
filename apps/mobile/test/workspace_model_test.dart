import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/models/workspace.dart';

void main() {
  SessionSummary session({String? model, SessionRuntimeModel? runtimeModel}) =>
      SessionSummary(
        sessionId: 'test',
        sessionRevision: 'test',
        model: model,
        runtimeState: RuntimeState.offline,
        isStreaming: false,
        accessMode: SessionAccessMode.controller,
        runtime: runtimeModel == null
            ? null
            : SessionRuntimeSnapshot(
                model: runtimeModel,
                updatedAt: DateTime.utc(2026, 9, 7),
              ),
      );

  test('a display label does not replace the full model routing reference', () {
    final summary = session(
      model: 'provider/model',
      runtimeModel: const SessionRuntimeModel(
        provider: 'provider',
        id: 'model',
      ),
    );
    expect(summary.displayModel, 'model');
    expect(summary.modelRef, 'provider/model');
    expect(
      session(
        runtimeModel: const SessionRuntimeModel(
          provider: 'provider',
          id: 'model',
        ),
      ).modelRef,
      'provider/model',
    );
  });

  test('unknown model placeholders are not displayed or used in creation', () {
    for (final model in [
      null,
      'unknown',
      'unknown/unknown',
      'provider/unknown',
    ]) {
      final summary = session(
        model: model,
        runtimeModel: const SessionRuntimeModel(
          provider: 'unknown',
          id: 'unknown',
        ),
      );
      expect(summary.displayModel, isNull);
      expect(summary.modelRef, isNull);
    }
  });
}
