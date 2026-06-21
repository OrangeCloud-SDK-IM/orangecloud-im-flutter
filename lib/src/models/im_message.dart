import 'dart:convert';

import 'text_message.dart';
import 'gift_message.dart';
import 'system_notice.dart';
import 'custom_message.dart';

/// 消息类型枚举
enum IMMessageType {
  text,
  gift,
  systemNotice,
  custom,
}

/// 发送者信息
class SenderInfo {
  final String userId;
  final String nickName;
  final String faceUrl;
  final String level;
  final bool isAdmin;
  final bool isAnchor;

  SenderInfo({
    required this.userId,
    required this.nickName,
    this.faceUrl = '',
    this.level = '0',
    this.isAdmin = false,
    this.isAnchor = false,
  });

  factory SenderInfo.fromJson(Map<String, dynamic> json) {
    return SenderInfo(
      userId: json['userId'] as String? ?? '',
      nickName: json['nickName'] as String? ?? '',
      faceUrl: json['faceUrl'] as String? ?? '',
      level: json['level']?.toString() ?? '0',
      isAdmin: json['isAdmin'] as bool? ?? false,
      isAnchor: json['isAnchor'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'nickName': nickName,
        'faceUrl': faceUrl,
        'level': level,
        'isAdmin': isAdmin,
        'isAnchor': isAnchor,
      };
}

/// 消息基类
abstract class IMMessage {
  final IMMessageType messageType;
  final SenderInfo senderInfo;
  final int timestamp;
  final int sequenceNumber;
  final String groupId;

  IMMessage({
    required this.messageType,
    required this.senderInfo,
    required this.timestamp,
    required this.sequenceNumber,
    required this.groupId,
  });

  /// 从 JSON 反序列化，根据 messageType 字段创建对应子类
  factory IMMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['messageType'] as String? ?? 'custom';
    switch (typeStr) {
      case 'text':
        return TextMessage.fromJson(json);
      case 'gift':
        return GiftMessage.fromJson(json);
      case 'systemNotice':
        return SystemNotice.fromJson(json);
      case 'custom':
      default:
        return CustomMessage.fromJson(json);
    }
  }

  /// 从 JSON 字符串反序列化
  static IMMessage fromJsonString(String raw) {
    return IMMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson();

  /// 获取消息类型字符串
  String get messageTypeString {
    switch (messageType) {
      case IMMessageType.text:
        return 'text';
      case IMMessageType.gift:
        return 'gift';
      case IMMessageType.systemNotice:
        return 'systemNotice';
      case IMMessageType.custom:
        return 'custom';
    }
  }
}
