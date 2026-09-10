import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'message_models.dart';

const privateHistoryProtocol = ApiException(
  kind: ApiFailureKind.protocol,
  message: '聊天记录水位响应不可信，请重试恢复',
);

BigInt privateSequence(Object? value, {bool positive = false}) {
  if (value is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw privateHistoryProtocol;
  }
  final parsed = BigInt.parse(value);
  if (positive && parsed == BigInt.zero) throw privateHistoryProtocol;
  return parsed;
}

class PrivateHistoryWatermark {
  const PrivateHistoryWatermark(this.version, this.through);
  factory PrivateHistoryWatermark.parse(Map<String, Object?> data) =>
      PrivateHistoryWatermark(
        privateSequence(data['historyVersion']),
        privateSequence(data['clearedThroughSequence']),
      );
  final BigInt version;
  final BigInt through;
}

/// One account generation only. All visible consumers share the authoritative
/// watermark, including hidden routes/search and late HTTP/realtime recovery.
class PrivateHistoryState extends ChangeNotifier {
  final _watermarks = <int, PrivateHistoryWatermark>{};
  PrivateHistoryWatermark? forTarget(int target) => _watermarks[target];

  bool accept(int target, PrivateHistoryWatermark next) {
    final previous = _watermarks[target];
    if (previous != null) {
      if (next.version < previous.version) return false;
      if (next.through < previous.through ||
          (next.version == previous.version &&
              next.through != previous.through)) {
        throw privateHistoryProtocol;
      }
      if (next.version == previous.version) return true;
    }
    _watermarks[target] = next;
    if (next.version > BigInt.zero) notifyListeners();
    return true;
  }

  bool visible(int target, ChatMessage message) {
    final mark = forTarget(target);
    if (mark == null || mark.version == BigInt.zero) return true;
    return message.messageSequence != null &&
        message.messageSequence! > mark.through;
  }

  ConversationSummary project(ConversationSummary row) {
    final mark = forTarget(row.targetUserId);
    if (mark == null ||
        mark.version == BigInt.zero ||
        (row.lastMessageSequence != null &&
            row.lastMessageSequence! > mark.through)) {
      return row;
    }
    return row.copyWith(lastMessage: '', unreadCount: 0, clearUpdatedAt: true);
  }
}

abstract interface class ClearablePrivateHistoryRepository {
  PrivateHistoryState get privateHistory;
  bool hasPendingHistoryClear(int targetUserId);

  /// Unknown result retries reuse the account-bound original key and body,
  /// including across page disposal. A new confirmed action gets a new key.
  Future<void> clearPrivateHistory(ConversationSummary conversation);
}
