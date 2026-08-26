class SseRecord {
  const SseRecord({required this.id, required this.event, required this.data});

  final String? id;
  final String event;
  final String data;
}

class SseParser {
  String? _id;
  String _event = 'message';
  final List<String> _data = <String>[];

  SseRecord? addLine(String rawLine) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (line.isEmpty) {
      if (_data.isEmpty) {
        _reset();
        return null;
      }
      final record = SseRecord(id: _id, event: _event, data: _data.join('\n'));
      _reset();
      return record;
    }
    if (line.startsWith(':')) return null;
    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'id':
        if (!value.contains('\u0000')) _id = value;
      case 'event':
        _event = value.isEmpty ? 'message' : value;
      case 'data':
        _data.add(value);
    }
    return null;
  }

  void _reset() {
    _id = null;
    _event = 'message';
    _data.clear();
  }
}
