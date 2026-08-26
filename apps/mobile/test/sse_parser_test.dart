import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/sse_parser.dart';

void main() {
  test('parses multiline SSE records and ignores heartbeats', () {
    final parser = SseParser();
    expect(parser.addLine(': heartbeat'), isNull);
    expect(parser.addLine(''), isNull);
    expect(parser.addLine('id: epoch:2'), isNull);
    expect(parser.addLine('event: message_update'), isNull);
    expect(parser.addLine('data: {"first":'), isNull);
    expect(parser.addLine('data: true}'), isNull);
    final record = parser.addLine('');

    expect(record?.id, 'epoch:2');
    expect(record?.event, 'message_update');
    expect(record?.data, '{"first":\ntrue}');
  });
}
