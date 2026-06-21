import 'im_message.dart';

/// 文本消息
class TextMessage extends IMMessage {
  final String content;

  TextMessage({
    required SenderInfo senderInfo,
    required int timestamp,
    required int sequenceNumber,
    required String groupId,
    required this.content,
  }) : super(
          messageType: IMMessageType.text,
          senderInfo: senderInfo,
          timestamp: timestamp,
          sequenceNumber: sequenceNumber,
          groupId: groupId,
        );

  factory TextMessage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return TextMessage(
      senderInfo: SenderInfo.fromJson(
          json['senderInfo'] as Map<String, dynamic>? ?? {}),
      timestamp: json['serverTimestamp'] as int? ?? json['timestamp'] as int? ?? 0,
      sequenceNumber: json['sequenceNumber'] as int? ?? 0,
      groupId: json['groupId'] as String? ?? '',
      content: data['content'] as String? ?? '',
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
          'content': content,
        },
      };
}
