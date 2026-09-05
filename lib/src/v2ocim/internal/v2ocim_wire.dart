import 'dart:convert';
import 'dart:typed_data';

import '../v2ocim_constants.dart';
import '../v2ocim_models.dart';

/// 服务端 `SendGroupMsg` / `SendC2CMsg` 的返回值。
///
/// ⚠ 判定成败一律看 [success]，**不要看 [sequenceNumber]** ——
/// C2C 消息不分配会话内序列号（恒为 0），用 seq 判断会把成功的私信误判为失败。
class V2OCIMSendResult {
  const V2OCIMSendResult({
    this.success = false,
    this.msgID = '',
    this.sequenceNumber = 0,
    this.serverTimestamp = 0,
    this.rejectCode,
  });

  final bool success;
  final String msgID;
  final int sequenceNumber;

  /// Unix **毫秒**（服务端口径）
  final int serverTimestamp;
  final String? rejectCode;
}

/// 传输层 wire format 编解码。
///
/// 契约见 `clients/V2OCIM-API-契约定稿.md` §9。**客户端不可见，四端实现必须逐字一致**
/// —— 对照实现是 Android 的 `V2OCIMCodec.kt`，改这里必须同步改那边。
class V2OCIMWire {
  const V2OCIMWire._();

  static const String messageTypeText = 'text';
  static const String messageTypeCustom = 'custom';

  /// 组装文本消息。
  ///
  /// ⚠ 字段名是 `data.content` 而不是 `data.text` —— 服务端的消息长度校验读的就是这个路径。
  static String buildTextJson(String text, String clientMsgId) {
    return jsonEncode(<String, Object?>{
      'messageType': messageTypeText,
      'clientMsgId': clientMsgId,
      'data': <String, Object?>{'content': text},
    });
  }

  /// 组装自定义消息。`customData` 用 Base64 编码，保证任意二进制安全。
  static String buildCustomJson(Uint8List customData, String clientMsgId) {
    return jsonEncode(<String, Object?>{
      'messageType': messageTypeCustom,
      'clientMsgId': clientMsgId,
      'data': <String, Object?>{'customData': base64.encode(customData)},
    });
  }

  /// 解析服务端返回的 SendMessageResult（SignalR JSON 协议下是 camelCase 的 Map）。
  static V2OCIMSendResult parseSendResult(Object? raw) {
    if (raw is! Map) {
      return const V2OCIMSendResult();
    }
    return V2OCIMSendResult(
      success: raw['success'] == true,
      msgID: _str(raw['msgID']),
      sequenceNumber: _int(raw['sequenceNumber']),
      serverTimestamp: _int(raw['serverTimestamp']),
      rejectCode: raw['rejectCode']?.toString(),
    );
  }

  /// 服务端消息 JSON → [V2OCIMMessage]；解析失败返回 null。
  ///
  /// [selfUserId] 用于判定 `isSelf`。
  static V2OCIMMessage? parseMessage(String messageJson, String? selfUserId) {
    final root = _decodeMap(messageJson);
    if (root == null) {
      return null;
    }

    final messageType = _str(root['messageType']);
    final data = _asMap(root['data']);
    final senderInfo = _asMap(root['senderInfo']);
    final sender = _str(senderInfo['userId']);
    // 服务端下发的是 Unix 毫秒；V2OCIMMessage.timestamp 用秒（与腾讯一致）
    final serverTimestampMs = _int(root['serverTimestamp']);

    final int elemType;
    V2OCIMTextElem? textElem;
    V2OCIMCustomElem? customElem;

    if (messageType == messageTypeText) {
      elemType = V2OCIMConstants.v2ocimElemTypeText;
      textElem = V2OCIMTextElem(text: _str(data['content']));
    } else {
      // 除 text 外一律按 custom 处理：礼物 / 系统通知 / 公告等业务消息都走 custom。
      // 服务端广播的业务消息（GiftBLL / RoomBLL 等）可能不带 customData 字段，
      // 这时把整个 data 原文当作自定义负载交给业务层，避免信息丢失。
      elemType = V2OCIMConstants.v2ocimElemTypeCustom;
      customElem = V2OCIMCustomElem(data: _decodeCustomData(data));
    }

    return V2OCIMMessage(
      msgID: _str(root['msgID']),
      timestamp: serverTimestampMs > 0 ? serverTimestampMs ~/ 1000 : 0,
      sender: sender,
      nickName: _str(senderInfo['nickName']),
      faceURL: _str(senderInfo['faceUrl']),
      groupID: _str(root['groupId']),
      userID: _str(root['targetUserId']),
      status: V2OCIMConstants.v2ocimMsgStatusSendSucc,
      isSelf: sender.isNotEmpty && sender == selfUserId,
      elemType: elemType,
      textElem: textElem,
      customElem: customElem,
      sequenceNumber: _int(root['sequenceNumber']),
    );
  }

  static Uint8List _decodeCustomData(Map<Object?, Object?> data) {
    final encoded = _str(data['customData']);
    if (encoded.isEmpty) {
      // 没有 customData 字段：把整个 data 原文交给业务层
      return Uint8List.fromList(utf8.encode(jsonEncode(_toStringKeyed(data))));
    }
    try {
      return Uint8List.fromList(base64.decode(encoded));
    } catch (_) {
      // 不是合法 Base64（服务端直接塞了明文）时退化为原文字节
      return Uint8List.fromList(utf8.encode(encoded));
    }
  }

  /// 解析 `UserJoined` 的用户信息 JSON。服务端两种大小写都出现过，都兼容。
  static V2OCIMGroupMemberInfo? parseGroupMember(String json) {
    final obj = _decodeMap(json);
    if (obj == null) {
      return null;
    }
    final userId = _firstNonEmpty([obj['userId'], obj['UserKey']]);
    if (userId.isEmpty) {
      return null;
    }
    return V2OCIMGroupMemberInfo(
      userID: userId,
      nickName: _firstNonEmpty([obj['nickName'], obj['NickName']]),
      faceURL: _firstNonEmpty([obj['faceUrl'], obj['FaceUrl']]),
    );
  }

  /// 解析 `OnMuted` 的禁言信息 JSON → (userID, 禁言截止秒)；失败返回 null。
  static V2OCIMGroupMemberChangeInfo? parseMuteInfo(String json) {
    final obj = _decodeMap(json);
    if (obj == null) {
      return null;
    }
    final userId = _firstNonEmpty([obj['userId'], obj['UserKey']]);
    if (userId.isEmpty) {
      return null;
    }
    final muteUntil = _int(obj['muteUntil']);
    return V2OCIMGroupMemberChangeInfo(
      userID: userId,
      muteTime: muteUntil > 0 ? muteUntil : _int(obj['muteTime']),
    );
  }

  /// 从批量推送负载里取出各条消息的 JSON。
  ///
  /// 服务端实际格式是 `{type,messages:[...],count}`（文档里写的是 `{messages:[...]}`，
  /// 多两个字段，兼容）。
  static List<String> splitBatch(String batchJson) {
    final root = _decodeMap(batchJson);
    if (root == null) {
      return const <String>[];
    }
    final messages = root['messages'];
    if (messages is! List) {
      return const <String>[];
    }
    return messages
        .map((item) => item is String ? item : jsonEncode(item))
        .toList(growable: false);
  }

  // ─── 私有解析工具（缺字段 / 类型不符时给默认值，绝不抛异常）───

  static Map<Object?, Object?>? _decodeMap(String json) {
    if (json.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(json);
      return decoded is Map ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Map<Object?, Object?> _asMap(Object? value) =>
      value is Map ? value : const <Object?, Object?>{};

  static Map<String, Object?> _toStringKeyed(Map<Object?, Object?> source) {
    return source.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _str(Object? value) {
    if (value == null) {
      return '';
    }
    return value is String ? value : value.toString();
  }

  static String _firstNonEmpty(List<Object?> candidates) {
    for (final candidate in candidates) {
      final value = _str(candidate);
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

/// 服务端下发的鉴权失败原因码（`AuthFailed` 事件的 code 字段）。
///
/// 与服务端 `OrangeCloud.SignalR/Models/AuthFailureCode.cs` 一一对应。
/// **全部原因都要求 SDK 停止自动重连** —— 它们都不是网络抖动，重连必然再次失败。
class V2OCIMAuthFailureCode {
  const V2OCIMAuthFailureCode._();

  static const String userSigExpired = 'user_sig_expired';
  static const String userSigInvalid = 'user_sig_invalid';
  static const String missingParams = 'missing_params';
  static const String appNotFound = 'app_not_found';
  static const String appDisabled = 'app_disabled';
  static const String appExpired = 'app_expired';
  static const String connectionLimit = 'connection_limit';
  static const String dauLimit = 'dau_limit';
  static const String domainNotAllowed = 'domain_not_allowed';

  static int toErrorCode(String? code) {
    switch (code) {
      case userSigExpired:
        return V2OCIMErrorCode.userSigExpired;
      case userSigInvalid:
        return V2OCIMErrorCode.userSigInvalid;
      case appDisabled:
      case appExpired:
      case appNotFound:
        return V2OCIMErrorCode.appUnavailable;
      case connectionLimit:
      case dauLimit:
        return V2OCIMErrorCode.quotaExceeded;
      case domainNotAllowed:
        return V2OCIMErrorCode.domainNotAllowed;
      case missingParams:
        return V2OCIMErrorCode.sdkNotInitialized;
      default:
        return V2OCIMErrorCode.unknown;
    }
  }
}

/// 服务端拒绝发送的原因码（`SendMessageResult.rejectCode`）。
///
/// 与服务端 `SendRejectCode` 一一对应。
class V2OCIMSendRejectCode {
  const V2OCIMSendRejectCode._();

  static const String notAuthenticated = 'not_authenticated';
  static const String dailyLimit = 'daily_limit';
  static const String muted = 'muted';
  static const String emptyMessage = 'empty_message';
  static const String messageTooLong = 'message_too_long';
  static const String rateLimited = 'rate_limited';

  static int toErrorCode(String? code) {
    switch (code) {
      case notAuthenticated:
        return V2OCIMErrorCode.notLoggedIn;
      case dailyLimit:
        return V2OCIMErrorCode.dailyLimit;
      case muted:
        return V2OCIMErrorCode.muted;
      case emptyMessage:
        return V2OCIMErrorCode.emptyMessage;
      case messageTooLong:
        return V2OCIMErrorCode.messageTooLong;
      case rateLimited:
        return V2OCIMErrorCode.rateLimited;
      default:
        return V2OCIMErrorCode.unknown;
    }
  }
}
