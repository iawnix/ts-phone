import '../../models/chat_message.dart';
import '../../models/session_timeline.dart';

/// App-scoped display cache. Nothing here grants permission to send commands.
class ConversationMemory {
  final _views = <(String, String), ChatViewMemory>{};

  ChatViewMemory view(String workspace, String session) {
    final key = (workspace, session);
    final view = _views.remove(key) ?? ChatViewMemory();
    _views[key] = view;
    while (_views.length > 8) {
      _views.remove(_views.keys.first);
    }
    return view;
  }
}

class ChatViewMemory {
  String draft = '';
  double scrollOffset = 0;
  bool following = true;
  ChatHistoryPreview? preview;
}

class ChatHistoryPreview {
  const ChatHistoryPreview({
    required this.revision,
    required this.messages,
    required this.messageIds,
    required this.items,
    required this.history,
    required this.hasMore,
    required this.before,
  });

  final String revision;
  final List<ChatMessage> messages;
  final List<String?> messageIds;
  final List<SessionTimelineItem> items;
  final TimelineHistorySummary? history;
  final bool hasMore;
  final String? before;

  bool get isBounded {
    if (messages.length + items.length > 1000) return false;
    var characters = 0;
    for (final message in messages) {
      characters += message.text.length;
      for (final tool in message.tools) {
        characters += tool.body.length;
      }
    }
    for (final item in items.whereType<TimelineActivityItem>()) {
      characters += item.activity.detail?.length ?? 0;
    }
    return characters <= 512 * 1024;
  }
}
