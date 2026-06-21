import 'im_message.dart';

/// 礼物信息
class GiftInfo {
  final String giftId;
  final String giftName;
  final int giftCount;
  final int giftPrice;
  final String animationUrl;

  GiftInfo({
    required this.giftId,
    required this.giftName,
    this.giftCount = 1,
    this.giftPrice = 0,
    this.animationUrl = '',
  });

  factory GiftInfo.fromJson(Map<String, dynamic> json) {
    return GiftInfo(
      giftId: json['giftId'] as String? ?? '',
      giftName: json['giftName'] as String? ?? '',
      giftCount: json['giftCount'] as int? ?? 1,
      giftPrice: json['giftPrice'] as int? ?? 0,
      animationUrl: json['animationUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'giftId': giftId,
        'giftName': giftName,
        'giftCount': giftCount,
        'giftPrice': giftPrice,
        'animationUrl': animationUrl,
      };
}

/// 礼物消息
class GiftMessage extends IMMessage {
  final GiftInfo giftInfo;

  GiftMessage({
    required SenderInfo senderInfo,
    required int timestamp,
    required int sequenceNumber,
    required String groupId,
    required this.giftInfo,
  }) : super(
          messageType: IMMessageType.gift,
          senderInfo: senderInfo,
          timestamp: timestamp,
          sequenceNumber: sequenceNumber,
          groupId: groupId,
        );

  // 便捷访问器（与 Web / iOS / Android 一致的扁平字段，推荐写法）
  String get giftId => giftInfo.giftId;
  String get giftName => giftInfo.giftName;
  int get giftCount => giftInfo.giftCount;
  int get giftPrice => giftInfo.giftPrice;
  String get animationUrl => giftInfo.animationUrl;

  factory GiftMessage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return GiftMessage(
      senderInfo: SenderInfo.fromJson(
          json['senderInfo'] as Map<String, dynamic>? ?? {}),
      timestamp: json['serverTimestamp'] as int? ?? json['timestamp'] as int? ?? 0,
      sequenceNumber: json['sequenceNumber'] as int? ?? 0,
      groupId: json['groupId'] as String? ?? '',
      giftInfo: GiftInfo.fromJson(data),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'messageType': messageTypeString,
        'sequenceNumber': sequenceNumber,
        'serverTimestamp': timestamp,
        'groupId': groupId,
        'senderInfo': senderInfo.toJson(),
        'data': giftInfo.toJson(),
      };
}
