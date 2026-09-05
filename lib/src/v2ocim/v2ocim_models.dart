import 'dart:typed_data';

import 'v2ocim_constants.dart';

/// 用户信息（对齐 V2TimUserInfo）
class V2OCIMUserInfo {
  final String userID;
  final String nickName;
  final String faceURL;

  const V2OCIMUserInfo({
    this.userID = '',
    this.nickName = '',
    this.faceURL = '',
  });

  factory V2OCIMUserInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const V2OCIMUserInfo();
    return V2OCIMUserInfo(
      userID: _str(map['userID']),
      nickName: _str(map['nickName']),
      faceURL: _str(map['faceURL']),
    );
  }
}

/// 群成员信息（对齐 V2TimGroupMemberInfo）
///
/// [nameCard]（群名片）自研无此概念，恒为空串（收下不生效，见契约 §7）。
class V2OCIMGroupMemberInfo {
  final String userID;
  final String nickName;
  final String faceURL;
  final String nameCard;

  const V2OCIMGroupMemberInfo({
    this.userID = '',
    this.nickName = '',
    this.faceURL = '',
    this.nameCard = '',
  });

  factory V2OCIMGroupMemberInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const V2OCIMGroupMemberInfo();
    return V2OCIMGroupMemberInfo(
      userID: _str(map['userID']),
      nickName: _str(map['nickName']),
      faceURL: _str(map['faceURL']),
      nameCard: _str(map['nameCard']),
    );
  }
}

/// 文本元素（对齐 V2TimTextElem）
class V2OCIMTextElem {
  final String text;

  const V2OCIMTextElem({this.text = ''});
}

/// 自定义元素（对齐 V2TimCustomElem）
///
/// [data] 为业务自定义数据；[description] / [extension] 自研无对应概念，恒空串。
class V2OCIMCustomElem {
  final Uint8List data;
  final String description;
  final String extension;

  V2OCIMCustomElem({
    Uint8List? data,
    this.description = '',
    this.extension = '',
  }) : data = data ?? Uint8List(0);
}

/// 消息（对齐 V2TimMessage）
///
/// 契约见 §4。只有 [V2OCIMConstants.v2ocimElemTypeText] 与
/// [V2OCIMConstants.v2ocimElemTypeCustom] 两种 elemType。
class V2OCIMMessage {
  /// 服务端生成的 32 位 GUID hex
  final String msgID;

  /// 服务端时间，**Unix 秒**（与腾讯一致；服务端下发的是毫秒，SDK 内部已除以 1000）
  final int timestamp;

  /// 发送者 userID
  final String sender;
  final String nickName;
  final String faceURL;

  /// 群名片，自研无此概念恒空串
  final String nameCard;

  /// 群消息才有，C2C 为空串
  final String groupID;

  /// C2C 才有，群消息为空串
  final String userID;

  /// 见 [V2OCIMConstants] 的 `v2ocimMsgStatus*`
  final int status;
  final bool isSelf;

  /// 见 [V2OCIMConstants] 的 `v2ocimElemType*`
  final int elemType;
  final V2OCIMTextElem? textElem;
  final V2OCIMCustomElem? customElem;

  /// ⚠ 自研扩展：群内单调序列号，用于去重与断连补发。C2C 消息恒为 0。
  final int sequenceNumber;

  const V2OCIMMessage({
    this.msgID = '',
    this.timestamp = 0,
    this.sender = '',
    this.nickName = '',
    this.faceURL = '',
    this.nameCard = '',
    this.groupID = '',
    this.userID = '',
    this.status = V2OCIMConstants.v2ocimMsgStatusSendSucc,
    this.isSelf = false,
    this.elemType = V2OCIMConstants.v2ocimElemTypeNone,
    this.textElem,
    this.customElem,
    this.sequenceNumber = 0,
  });

  /// 是否群消息（groupID 非空）
  bool get isGroupMessage => groupID.isNotEmpty;

  /// 便捷取发送者的群成员信息
  V2OCIMGroupMemberInfo toGroupMemberInfo() => V2OCIMGroupMemberInfo(
        userID: sender,
        nickName: nickName,
        faceURL: faceURL,
        nameCard: nameCard,
      );

  /// 便捷取发送者的用户信息
  V2OCIMUserInfo toUserInfo() =>
      V2OCIMUserInfo(userID: sender, nickName: nickName, faceURL: faceURL);

  /// 原生侧下发的 map → 消息对象
  ///
  /// 原生只在对应 elemType 下带 `text` / `customData` 其中之一，
  /// 这里据此构造 textElem / customElem，避免上层判空判两处。
  factory V2OCIMMessage.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const V2OCIMMessage();
    final elemType = _int(map['elemType']);
    return V2OCIMMessage(
      msgID: _str(map['msgID']),
      timestamp: _int(map['timestamp']),
      sender: _str(map['sender']),
      nickName: _str(map['nickName']),
      faceURL: _str(map['faceURL']),
      nameCard: _str(map['nameCard']),
      groupID: _str(map['groupID']),
      userID: _str(map['userID']),
      status: map['status'] == null
          ? V2OCIMConstants.v2ocimMsgStatusSendSucc
          : _int(map['status']),
      isSelf: map['isSelf'] == true,
      elemType: elemType,
      textElem: elemType == V2OCIMConstants.v2ocimElemTypeText
          ? V2OCIMTextElem(text: _str(map['text']))
          : null,
      customElem: elemType == V2OCIMConstants.v2ocimElemTypeCustom
          ? V2OCIMCustomElem(data: _bytes(map['customData']))
          : null,
      sequenceNumber: _int(map['sequenceNumber']),
    );
  }
}

/// 群成员变更信息（对齐 V2TimGroupMemberChangeInfo）
///
/// 自研的禁言 / 解禁事件映射到这里：解禁时 [muteTime] 为 0。
class V2OCIMGroupMemberChangeInfo {
  final String userID;

  /// 禁言截止时间（Unix 秒）；0 表示未禁言 / 已解禁
  final int muteTime;

  const V2OCIMGroupMemberChangeInfo({this.userID = '', this.muteTime = 0});

  factory V2OCIMGroupMemberChangeInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const V2OCIMGroupMemberChangeInfo();
    return V2OCIMGroupMemberChangeInfo(
      userID: _str(map['userID']),
      muteTime: _int(map['muteTime']),
    );
  }
}

/// ⚠ 自研扩展：服务端下发的生效限制项（`ServerConfig` 事件）
///
/// 腾讯没有这个机制。客户端可据此做本地预校验
/// （MetaLive 已有「按后端配置决定实际可发送长度」的机制，正好对接）。
class V2OCIMServerLimits {
  /// 单条消息最大字符数
  final int maxMessageLength;

  /// 单用户每秒最大消息数
  final int maxMessagesPerSecond;

  /// 服务端补发缓冲区保留条数
  final int bufferMaxSize;

  const V2OCIMServerLimits({
    this.maxMessageLength = 500,
    this.maxMessagesPerSecond = 5,
    this.bufferMaxSize = 500,
  });

  factory V2OCIMServerLimits.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const V2OCIMServerLimits();
    final len = _int(map['maxMessageLength']);
    final rate = _int(map['maxMessagesPerSecond']);
    final buf = _int(map['bufferMaxSize']);
    return V2OCIMServerLimits(
      maxMessageLength: len > 0 ? len : 500,
      maxMessagesPerSecond: rate > 0 ? rate : 5,
      bufferMaxSize: buf > 0 ? buf : 500,
    );
  }
}

/// 无返回值结果（对齐腾讯 Flutter SDK 的 `V2TimCallback`）
///
/// 腾讯 Flutter SDK 不用回调对象而是把结果放在 Future 里，本 SDK 与之保持一致 ——
/// Android / iOS 侧才是 `callback.onSuccess/onError` 形状（契约 §3.3）。
class V2OCIMCallback {
  /// 0 = 成功，其余见 [V2OCIMErrorCode]
  final int code;
  final String desc;

  const V2OCIMCallback({required this.code, this.desc = ''});

  bool get isSuccess => code == V2OCIMErrorCode.success;

  static const V2OCIMCallback success =
      V2OCIMCallback(code: V2OCIMErrorCode.success);
}

/// 带返回值结果（对齐腾讯 Flutter SDK 的 `V2TimValueCallback<T>`）
class V2OCIMValueCallback<T> {
  /// 0 = 成功，其余见 [V2OCIMErrorCode]
  final int code;
  final String desc;

  /// 失败时为 null
  final T? data;

  const V2OCIMValueCallback({required this.code, this.desc = '', this.data});

  bool get isSuccess => code == V2OCIMErrorCode.success;
}

// ─── 私有解析工具（原生 map 的值类型在两端有细微差异，统一收口）───

String _str(Object? v) => v is String ? v : '';

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

Uint8List _bytes(Object? v) {
  if (v is Uint8List) return v;
  if (v is List<int>) return Uint8List.fromList(v);
  return Uint8List(0);
}
