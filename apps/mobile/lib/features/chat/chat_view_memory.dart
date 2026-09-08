import 'package:flutter/foundation.dart';

import '../../models/chat_message.dart';
import '../../models/session_timeline.dart';
import 'chat_outbox.dart';

/// App-scoped drafts, receipts and bounded previews. These never grant authority.
class ConversationMemory {
  final _views = <(String, String), ChatViewMemory>{};

  ChatViewMemory view(String workspace, String session) {
    final key = (workspace, session);
    final view = _views.remove(key) ?? ChatViewMemory();
    _views[key] = view;
    while (_views.length > 8) {
      final evictable = _views.keys
          .where(
            (candidate) =>
                candidate != key && !_views[candidate]!.outbox.hasUnresolved,
          )
          .firstOrNull;
      if (evictable == null) break;
      _views.remove(evictable);
    }
    return view;
  }
}

class ChatViewMemory extends ChangeNotifier {
  final outbox = ChatOutbox();
  String _draft = '';
  int _draftRevision = 0;
  String get draft => _draft;
  set draft(String value) {
    if (_draft == value) return;
    _draft = value;
    _draftRevision++;
    notifyListeners();
  }

  int takeDraft() {
    draft = '';
    return _draftRevision;
  }

  void restoreDraft(String value, int clearedRevision) {
    if (_draftRevision == clearedRevision) draft = value;
  }

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
    this.hasLater = false,
    this.after,
    this.viewingHistoryWindow = false,
  });

  final String revision;
  final List<ChatMessage> messages;
  final List<String?> messageIds;
  final List<SessionTimelineItem> items;
  final TimelineHistorySummary? history;
  final bool hasMore;
  final String? before;
  final bool hasLater;
  final String? after;
  final bool viewingHistoryWindow;

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
