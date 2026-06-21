import 'im_message.dart';

/// 系统通知
class SystemNotice extends IMMessage {
  final String noticeType;
  final String title;
  final String content;

  SystemNotice({
    required SenderInfo senderInfo,
    required int timestamp,
    required int sequenceNumber,
    required String groupId,
    required this.noticeType,
    required this.title,
    required this.content,
  }) : super(
          messageType: IMMessageType.systemNotice,
          senderInfo: senderInfo,
          timestamp: timestamp,
          sequenceNumber: sequenceNumber,
          groupId: groupId,
        );

  factory SystemNotice.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return SystemNotice(
      senderInfo: SenderInfo.fromJson(
          json['senderInfo'] as Map<String, dynamic>? ?? {}),
      timestamp: json['serverTimestamp'] as int? ?? json['timestamp'] as int? ?? 0,
      sequenceNumber: json['sequenceNumber'] as int? ?? 0,
      groupId: json['groupId'] as String? ?? '',
      noticeType: data['noticeType'] as String? ?? '',
      title: data['title'] as String? ?? '',
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
          'noticeType': noticeType,
          'title': title,
          'content': content,
        },
      };
}
