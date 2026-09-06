import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/platform/ts_accessibility_controller.dart';

void main() {
  testWidgets('loads and follows reduce-transparency changes', (tester) async {
    final changes = StreamController<bool>();
    final controller = TsAccessibilityController(
      probe: () async => true,
      changes: changes.stream,
    );

    await controller.initialize();
    expect(controller.reduceTransparency, isTrue);

    changes.add(false);
    await tester.pump();
    expect(controller.reduceTransparency, isFalse);

    await changes.close();
    controller.dispose();
  });

  testWidgets('preserves the last value when a platform refresh fails', (
    tester,
  ) async {
    var shouldFail = false;
    final controller = TsAccessibilityController(
      probe: () async {
        if (shouldFail) {
          throw PlatformException(code: 'unavailable');
        }
        return true;
      },
      changes: const Stream<bool>.empty(),
    );

    await controller.initialize();
    expect(controller.reduceTransparency, isTrue);

    shouldFail = true;
    await controller.refresh();
    expect(controller.reduceTransparency, isTrue);

    controller.dispose();
  });

  testWidgets('a platform event supersedes an older in-flight probe', (
    tester,
  ) async {
    final probe = Completer<bool>();
    final changes = StreamController<bool>();
    final controller = TsAccessibilityController(
      probe: () => probe.future,
      changes: changes.stream,
    );

    final initialization = controller.initialize();
    await tester.pump();
    changes.add(true);
    await tester.pump();
    expect(controller.reduceTransparency, isTrue);

    probe.complete(false);
    await initialization;
    expect(controller.reduceTransparency, isTrue);

    await changes.close();
    controller.dispose();
  });

  testWidgets('ignores a platform probe that completes after disposal', (
    tester,
  ) async {
    final probe = Completer<bool>();
    final controller = TsAccessibilityController(
      probe: () => probe.future,
      changes: const Stream<bool>.empty(),
    );

    final initialization = controller.initialize();
    controller.dispose();
    probe.complete(true);
    await initialization;

    expect(controller.reduceTransparency, isFalse);
    expect(tester.takeException(), isNull);
  });
}
