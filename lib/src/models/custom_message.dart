import 'im_message.dart';

/// 自定义消息
class CustomMessage extends IMMessage {
  final String customType;
  final Map<String, dynamic> payload;

  CustomMessage({
    required SenderInfo senderInfo,
    required int timestamp,
    required int sequenceNumber,
    required String groupId,
    required this.customType,
    this.payload = const {},
  }) : super(
          messageType: IMMessageType.custom,
          senderInfo: senderInfo,
          timestamp: timestamp,
          sequenceNumber: sequenceNumber,
          groupId: groupId,
        );

  factory CustomMessage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return CustomMessage(
      senderInfo: SenderInfo.fromJson(
          json['senderInfo'] as Map<String, dynamic>? ?? {}),
      timestamp: json['serverTimestamp'] as int? ?? json['timestamp'] as int? ?? 0,
      sequenceNumber: json['sequenceNumber'] as int? ?? 0,
      groupId: json['groupId'] as String? ?? '',
      customType: data['customType'] as String? ?? '',
      payload: data['payload'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'messageType': messageTypeString,
        'sequenceNumber': sequenceNumber,
        'serverTimestamp': timestamp,
        'groupId': groupId,
        'senderInfo': senderInfo.toJson(),
        'data': {
          'customType': customType,
          'payload': payload,
        },
      };
}
