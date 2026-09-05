/// V2OCIM 常量（取值与腾讯 V2TIM 一致，迁移时全局替换 V2TIM -> V2OCIM 即可）
///
/// 契约见 `clients/V2OCIM-API-契约定稿.md` §2。
class V2OCIMConstants {
  const V2OCIMConstants._();

  // === 登录状态（对齐 V2TIM_STATUS_*）===
  static const int v2ocimStatusLogined = 1;
  static const int v2ocimStatusLogining = 2;
  static const int v2ocimStatusLogout = 3;

  // === 消息优先级 ===
  // ⚠ 收下但不生效：服务端没有优先级队列。保留是为了让腾讯的调用代码不用改。
  static const int v2ocimPriorityDefault = 0;
  static const int v2ocimPriorityHigh = 1;
  static const int v2ocimPriorityNormal = 2;
  static const int v2ocimPriorityLow = 3;

  // === 消息元素类型 ===
  // 只有 text 与 custom 两种。礼物 / 系统通知 / 公告等业务消息全部走 custom
  // （业务自行在 customData 里定 JSON），与腾讯生态一致。
  static const int v2ocimElemTypeNone = 0;
  static const int v2ocimElemTypeText = 1;
  static const int v2ocimElemTypeCustom = 2;

  // === 消息发送状态 ===
  static const int v2ocimMsgStatusSending = 1;
  static const int v2ocimMsgStatusSendSucc = 2;
  static const int v2ocimMsgStatusSendFail = 3;
}

/// 错误码（沿用腾讯的数值，使迁移方原有的错误码判断逻辑可直接复用）
///
/// 契约见 §6.4。
class V2OCIMErrorCode {
  const V2OCIMErrorCode._();

  static const int success = 0;

  /// SDK 未初始化（未调 initSDK 或 setServerConfig）
  static const int sdkNotInitialized = 6013;

  /// 未登录 / 连接不可用
  static const int notLoggedIn = 6014;

  /// 被禁言
  static const int muted = 7013;

  /// 消息为空
  static const int emptyMessage = 8001;

  /// 消息超长
  static const int messageTooLong = 8002;

  /// 触发频率限制
  static const int rateLimited = 8003;

  /// 今日消息数达上限
  static const int dailyLimit = 8004;

  /// UserSig 已过期
  static const int userSigExpired = 9508;

  /// UserSig 校验失败
  static const int userSigInvalid = 9509;

  /// 应用被禁用 / 已到期
  static const int appUnavailable = 10004;

  /// 超出连接数 / DAU 上限
  static const int quotaExceeded = 10005;

  /// 域名或包名不在白名单
  static const int domainNotAllowed = 10006;

  /// 未分类错误（desc 带服务端原文）
  static const int unknown = -1;

  /// 该能力不支持（见契约 §8 不支持清单）
  static const int notSupported = -2;
}
