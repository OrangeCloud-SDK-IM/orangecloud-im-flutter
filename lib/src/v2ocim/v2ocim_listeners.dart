import 'dart:typed_data';

import 'v2ocim_models.dart';

/// 简单消息监听器（对齐 V2TimSimpleMsgListener）
///
/// 与腾讯 Flutter SDK 一样用「构造函数传回调」的形状，只写关心的回调即可：
/// ```dart
/// V2OCIMManager.instance.addSimpleMsgListener(
///   listener: V2OCIMSimpleMsgListener(
///     onRecvGroupTextMessage: (msgID, groupID, sender, text) { ... },
///   ),
/// );
/// ```
class V2OCIMSimpleMsgListener {
  final void Function(
    String msgID,
    String groupID,
    V2OCIMGroupMemberInfo sender,
    String text,
  )? onRecvGroupTextMessage;

  final void Function(
    String msgID,
    String groupID,
    V2OCIMGroupMemberInfo sender,
    Uint8List customData,
  )? onRecvGroupCustomMessage;

  final void Function(String msgID, V2OCIMUserInfo sender, String text)?
      onRecvC2CTextMessage;

  final void Function(
    String msgID,
    V2OCIMUserInfo sender,
    Uint8List customData,
  )? onRecvC2CCustomMessage;

  const V2OCIMSimpleMsgListener({
    this.onRecvGroupTextMessage,
    this.onRecvGroupCustomMessage,
    this.onRecvC2CTextMessage,
    this.onRecvC2CCustomMessage,
  });
}

/// 高级消息监听器（对齐 V2TimAdvancedMsgListener）
///
/// 收到的是完整 [V2OCIMMessage]，适合需要区分 elemType 或读取 sequenceNumber 的场景。
/// 与 [V2OCIMSimpleMsgListener] 会**同时**触发，接入方按需选一种，
/// 不要两种都处理同一条消息（会重复上屏）。
class V2OCIMAdvancedMsgListener {
  final void Function(V2OCIMMessage msg)? onRecvNewMessage;

  const V2OCIMAdvancedMsgListener({this.onRecvNewMessage});
}

/// 群组事件监听器（对齐 V2TimGroupListener）
///
/// 自研的房间事件按语义归入腾讯的群事件体系，映射见契约 §3.4：
/// - `UserJoined` → [onMemberEnter]
/// - `UserLeft` → [onMemberLeave]
/// - `RoomClosed` → [onGroupDismissed]
/// - `OnMuted` / `OnUnmuted` → [onMemberInfoChanged]（muteTime 变化，解禁为 0）
/// - `OnlineCountChanged` → [onGroupOnlineMemberCountChanged]（⚠ 自研扩展）
class V2OCIMGroupListener {
  final void Function(String groupID, List<V2OCIMGroupMemberInfo> memberList)?
      onMemberEnter;

  final void Function(String groupID, V2OCIMGroupMemberInfo member)?
      onMemberLeave;

  /// 群被解散（自研对应房间关闭 / 关播）。
  /// `opUser` 为操作者，自研的 RoomClosed 不带操作者信息，恒为 null。
  final void Function(String groupID, V2OCIMGroupMemberInfo? opUser)?
      onGroupDismissed;

  /// 群成员信息变更。自研目前只用于承载禁言状态变化。
  final void Function(
    String groupID,
    List<V2OCIMGroupMemberChangeInfo> changeInfoList,
  )? onMemberInfoChanged;

  /// ⚠ 自研扩展：群在线人数变化（服务端主动推送）
  ///
  /// 腾讯需要主动调接口查询在线人数，没有推送回调，所以这是能力增强而非对齐项。
  final void Function(String groupID, int count)?
      onGroupOnlineMemberCountChanged;

  const V2OCIMGroupListener({
    this.onMemberEnter,
    this.onMemberLeave,
    this.onGroupDismissed,
    this.onMemberInfoChanged,
    this.onGroupOnlineMemberCountChanged,
  });
}

/// SDK 事件监听器（对齐 V2TimSDKListener）
class V2OCIMSDKListener {
  final void Function()? onConnecting;
  final void Function()? onConnectSuccess;

  /// `code` 见 [V2OCIMErrorCode]
  final void Function(int code, String error)? onConnectFailed;

  /// 被踢下线（单点登录互踢）
  ///
  /// 收到后应视为已下线：SDK 已停止自动重连，业务层需提示
  /// 「账号在其他设备登录」并走登出流程。
  final void Function()? onKickedOffline;

  /// UserSig 已过期
  ///
  /// SDK 已**停止自动重连**（重连也会因同一原因失败）。
  /// 业务层需向自己的服务端重新签发 UserSig，再调用一次 `login`。
  final void Function()? onUserSigExpired;

  /// ⚠ 自研扩展：服务端下发生效限制项
  ///
  /// 腾讯没有这个回调。连接建立后触发一次，可用于本地预校验输入长度。
  final void Function(V2OCIMServerLimits limits)? onServerConfigUpdated;

  const V2OCIMSDKListener({
    this.onConnecting,
    this.onConnectSuccess,
    this.onConnectFailed,
    this.onKickedOffline,
    this.onUserSigExpired,
    this.onServerConfigUpdated,
  });
}
