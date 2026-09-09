import 'dart:convert';

import 'package:voice_social_app/core/network/api_exception.dart';
import 'room_models.dart';

enum GiftSendState { queued, unknown, succeeded, rejected, notSent }

/// One economic write. Transport/session fields are frozen too; no token is
/// stored, and a restored command is never rebound to another room lease.
class GiftSendCommand {
  GiftSendCommand({
    required this.actorId,
    required this.requestId,
    required this.roomId,
    required this.sessionId,
    required this.giftId,
    required this.receiverUserId,
    required this.quantity,
  }) {
    if (actorId <= 0 ||
        receiverUserId <= 0 ||
        actorId == receiverUserId ||
        quantity < 1 ||
        quantity > 999 ||
        roomId.isEmpty ||
        sessionId.isEmpty ||
        giftId.isEmpty ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(requestId)) {
      throw const FormatException('Invalid frozen gift command');
    }
  }

  final int actorId;
  final String requestId;
  final String roomId;
  final String sessionId;
  final String giftId;
  final int receiverUserId;
  final int quantity;

  Map<String, Object?> get body => Map.unmodifiable({
    'roomId': roomId,
    'giftId': giftId,
    'receiverUserId': receiverUserId,
    'quantity': quantity,
    'source': 'WALLET',
    'sessionId': sessionId,
  });
  String get encodedBody => jsonEncode(body);

  void validateReceipt(GiftReceipt receipt, {bool queried = false}) {
    if (!receipt.success ||
        receipt.requestId != requestId ||
        receipt.roomId != roomId ||
        receipt.senderUserId != actorId ||
        receipt.receiverUserId != receiverUserId ||
        receipt.giftId != giftId ||
        receipt.quantity != quantity ||
        receipt.source != 'WALLET' ||
        receipt.providerInvocation != false ||
        receipt.transferId?.isNotEmpty != true ||
        (queried && receipt.reconciled != true)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物回执与原请求不一致，结果仍待确认',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'actorId': '$actorId',
    'requestId': requestId,
    ...body,
  };
  factory GiftSendCommand.fromJson(Map<String, Object?> json) {
    if (json.keys.toSet().difference(const {
          'actorId',
          'requestId',
          'roomId',
          'sessionId',
          'giftId',
          'receiverUserId',
          'quantity',
          'source',
        }).isNotEmpty ||
        json['source'] != 'WALLET') {
      throw const FormatException('Invalid stored gift command');
    }
    return GiftSendCommand(
      actorId: int.parse(json['actorId'] as String),
      requestId: json['requestId'] as String,
      roomId: json['roomId'] as String,
      sessionId: json['sessionId'] as String,
      giftId: json['giftId'] as String,
      receiverUserId: json['receiverUserId'] as int,
      quantity: json['quantity'] as int,
    );
  }
}

class GiftSendEntry {
  GiftSendEntry(this.command, {this.state = GiftSendState.queued});
  final GiftSendCommand command;
  GiftSendState state;
  String? transferId;
  bool get terminal =>
      state == GiftSendState.succeeded ||
      state == GiftSendState.rejected ||
      state == GiftSendState.notSent;
}

class GiftSendPlan {
  GiftSendPlan({required this.unitCoins, required List<GiftSendEntry> entries})
    : entries = List.unmodifiable(entries) {
    if (unitCoins <= BigInt.zero ||
        entries.isEmpty ||
        entries.length > 9 ||
        entries.map((e) => e.command.receiverUserId).toSet().length !=
            entries.length ||
        entries.map((e) => e.command.requestId).toSet().length !=
            entries.length ||
        entries.any(
          (e) =>
              e.command.actorId != command.actorId ||
              e.command.roomId != command.roomId ||
              e.command.sessionId != command.sessionId ||
              e.command.giftId != command.giftId ||
              e.command.quantity != command.quantity,
        )) {
      throw const FormatException('Invalid gift plan');
    }
  }
  final BigInt unitCoins;
  final List<GiftSendEntry> entries;
  GiftSendCommand get command => entries.first.command;
  BigInt get totalCoins =>
      unitCoins * BigInt.from(command.quantity) * BigInt.from(entries.length);
  bool get terminal => entries.every((e) => e.terminal);
  int get succeeded =>
      entries.where((e) => e.state == GiftSendState.succeeded).length;

  String encode() => jsonEncode({
    'version': 1,
    'unitCoins': '$unitCoins',
    'entries': [
      for (final e in entries)
        {
          'command': e.command.toJson(),
          'state': e.state.name,
          if (e.transferId != null) 'transferId': e.transferId,
        },
    ],
  });
  factory GiftSendPlan.decode(String raw, int actor) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != 1 ||
        json['unitCoins'] is! String ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(json['unitCoins'] as String)) {
      throw const FormatException('Invalid stored gift plan');
    }
    final plan = GiftSendPlan(
      unitCoins: BigInt.parse(json['unitCoins'] as String),
      entries: (json['entries'] as List).map((rawEntry) {
        final e = rawEntry as Map<String, dynamic>;
        final entry = GiftSendEntry(
          GiftSendCommand.fromJson(
            Map<String, Object?>.from(e['command'] as Map),
          ),
          state: GiftSendState.values.byName(e['state'] as String),
        );
        entry.transferId = e['transferId'] as String?;
        if (entry.state == GiftSendState.succeeded &&
            entry.transferId?.isNotEmpty != true) {
          throw const FormatException('Stored success has no receipt');
        }
        return entry;
      }).toList(),
    );
    if (plan.command.actorId != actor)
      throw const FormatException('Gift account mismatch');
    return plan;
  }
}

/// Separate from the legacy single-recipient API: old callers retain their
/// parameters, while the multi-recipient flow owns immutable commands.
abstract interface class GiftCommandRepository {
  GiftSendCommand freezeGift({
    required int actorId,
    required String roomId,
    required String giftId,
    required int receiverUserId,
    required int quantity,
    required String requestId,
  });
  Future<GiftReceipt> sendGiftCommand(
    GiftSendCommand command, {
    required void Function() requireIdentity,
  });
  Future<GiftReceipt> queryGiftCommand(GiftSendCommand command);
}
