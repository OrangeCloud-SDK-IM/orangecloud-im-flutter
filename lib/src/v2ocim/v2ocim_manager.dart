import 'dart:async';
import 'dart:math';

// Uint8List 与 @visibleForTesting 都由 foundation 再导出
import 'package:flutter/foundation.dart';

import 'internal/v2ocim_connection.dart';
import 'internal/v2ocim_wire.dart';
import 'v2ocim_constants.dart';
import 'v2ocim_listeners.dart';
import 'v2ocim_models.dart';

/// OrangeCloud IM 客户端入口（API 对齐腾讯云 IM `V2TIMManager`）
///
/// 从腾讯迁移只需三步（详见契约 §10）：
/// 1. 全局替换 `V2TIM` / `V2Tim` → `V2OCIM`
/// 2. 在 `initSDK` 之前插一行 [setServerConfig]
/// 3. UserSig 改为向**你的业务服务端**签发接口获取（签发算法见集成文档）
///
/// ## 这是纯 Dart 实现（v3.1.0 起）
///
/// v3.0.0 及之前本包是 **plugin**（Dart 只做 MethodChannel 桥接，核心逻辑在
/// Android AAR / iOS XCFramework 里）。那套架构让 Flutter 接入方被迫携带两个原生
/// 二进制，且**每次改 SDK 都要重新构建 AAR 与 XCFramework（后者必须 macOS）**，
/// 成了发版硬阻塞。v3.1.0 改为纯 Dart：
///
/// - **公开 API 与回调时机逐字不变**，接入方无需改一行代码
/// - 不再依赖任何原生二进制，Flutter 端零原生依赖
/// - AAR / XCFramework 继续独立发布，服务 Android / iOS **原生**接入方
///
/// 与原生实现的两处行为差异（已知、可接受）：
/// 1. **没有系统级网络状态监听**（Android 版用 ConnectivityManager 在网络恢复时立即重连）。
///    纯 Dart 侧靠 SignalR 的关闭检测 + 退避重连，网络恢复后最迟一个退避周期（30 秒）重连。
/// 2. [getGroupMemberList] **加了 10 秒超时**。原生版是回调式、服务端不响应就永远不回调；
///    Dart 侧返回 Future，悬挂会让调用方永久 await，所以必须有超时。
///
/// 契约：`clients/V2OCIM-API-契约定稿.md`
class V2OCIMManager {
  V2OCIMManager._();

  static final V2OCIMManager _instance = V2OCIMManager._();

  /// 单例（对齐腾讯 `V2TIMManager.instance` / `getInstance()`）
  static V2OCIMManager get instance => _instance;

  /// 对齐腾讯 Android/iOS 的 `getInstance()` 写法
  static V2OCIMManager getInstance() => _instance;

  static const String _version = '3.1.0';
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _memberListTimeout = Duration(seconds: 10);

  /// 自发消息 msgID 记忆上限，超出按最旧淘汰
  static const int _sentMsgIdMax = 500;

  /// 自发消息 msgID 过期时间，避免无界增长
  static const Duration _sentMsgIdTtl = Duration(minutes: 5);

  /// 直播场景默认退避序列（毫秒），**最长间隔 10 秒**。
  ///
  /// ⚠ 与 Web/iOS/Android 的 `0/2/10/30` 刻意不同：那三端里 Android 有
  /// `ConnectivityManager`、iOS 有 `NWPathMonitor`，网络恢复瞬间就重连，30 秒的尾巴
  /// 基本碰不到；纯 Dart 侧没有系统级网络监听，30 秒尾巴会变成「网络回来了但公屏
  /// 还要黑最多 30 秒」—— 直播场景不能接受。
  ///
  /// 一次重试只是一个 negotiate + WebSocket 握手，10 秒一次的开销可以忽略。
  /// 想更快恢复请调 [notifyNetworkAvailable]（宿主拿到网络恢复 / 前台唤醒信号时）。
  static const List<int> defaultReconnectDelaysMs = <int>[
    0,
    1000,
    2000,
    5000,
    10000,
  ];

  /// 重连退避序列（毫秒）。可整体替换；末位会被无限复用。
  List<int> reconnectDelaysMs = defaultReconnectDelaysMs;

  // === 连接与身份 ===
  V2OCIMConnection? _connection;
  String? _hubUrl;
  String? _appId;
  String? _userId;
  String? _userSig;
  bool _sdkInitialized = false;
  int _loginStatus = V2OCIMConstants.v2ocimStatusLogout;

  /// 连接工厂。测试用 [setConnectionFactoryForTest] 替换成假实现。
  V2OCIMConnectionFactory _connectionFactory = createSignalRConnection;

  // === 重连 ===
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _manualDisconnect = false;

  /// 是否因**不可恢复原因**停止了重连（UserSig 过期 / 应用禁用 / 超限 / 被踢下线）。
  ///
  /// 这些情况重连必然再次失败，继续重试只产生无效流量并耗电，业务层还收不到任何提示。
  /// 业务层处理完后调用 [login] 会自动清除该标记。
  bool _stoppedByAuthFailure = false;

  /// 最大重连次数，-1 表示无限重连（默认）
  int maxReconnectAttempts = -1;

  // === 心跳 ===
  Timer? _heartbeatTimer;

  // === 可靠性：序列号去重 / 间隙补发 ===
  final Map<String, int> _lastSequenceNumbers = <String, int>{};

  /// 本端已发出的消息 msgID → 记录时刻（epoch ms）。
  ///
  /// 用于过滤「自己发的消息」：服务端逐条推送已用 `GroupExcept` 排除发送者，
  /// 但**批量合并推送无法排除**（异步 flush 时定位不到每条消息的发送者连接），
  /// 所以这里做最后一道防线，同时兜住服务端将来新增路径的漏排除。契约 §5。
  final Map<String, int> _sentMsgIds = <String, int>{};

  /// 服务端下发的生效限制项（`ServerConfig` 事件）
  V2OCIMServerLimits? _serverLimits;

  // === Listener ===
  final List<V2OCIMSimpleMsgListener> _simpleMsgListeners =
      <V2OCIMSimpleMsgListener>[];
  final List<V2OCIMAdvancedMsgListener> _advancedMsgListeners =
      <V2OCIMAdvancedMsgListener>[];
  final List<V2OCIMGroupListener> _groupListeners = <V2OCIMGroupListener>[];
  final List<V2OCIMSDKListener> _sdkListeners = <V2OCIMSDKListener>[];

  /// [getGroupMemberList] 的待回调，按 groupID 暂存（服务端以独立事件返回结果，
  /// 且**不回传 groupID**，所以只能按先到先出消费）
  final Map<String, Completer<V2OCIMValueCallback<String>>>
      _pendingMemberLists = <String, Completer<V2OCIMValueCallback<String>>>{};

  final Random _random = Random();

  // ============================================================
  // 测试接缝
  // ============================================================

  /// 替换连接工厂（仅测试用）。传 null 恢复默认。
  @visibleForTesting
  void setConnectionFactoryForTest(V2OCIMConnectionFactory? factory) {
    _connectionFactory = factory ?? createSignalRConnection;
  }

  /// 重置全部内部状态（仅测试用），避免单例在用例之间互相污染。
  @visibleForTesting
  Future<void> resetForTest() async {
    await logout();
    _connectionFactory = createSignalRConnection;
    _simpleMsgListeners.clear();
    _advancedMsgListeners.clear();
    _groupListeners.clear();
    _sdkListeners.clear();
    _serverLimits = null;
    _sdkInitialized = false;
    _hubUrl = null;
    _appId = null;
    _userId = null;
    _userSig = null;
    _stoppedByAuthFailure = false;
    _reconnectAttempt = 0;
    maxReconnectAttempts = -1;
    reconnectDelaysMs = defaultReconnectDelaysMs;
  }

  // ============================================================
  // 初始化
  // ============================================================

  /// ⚠ **自研扩展，必须在 [initSDK] 之前调用**
  ///
  /// 腾讯的 `initSDK` 只要 sdkAppId（服务地址由 SDK 内置），自研需要显式指定
  /// SignalR Hub 地址与字符串型 appId，这一步无法隐藏。
  ///
  /// - [hubUrl] 形如 `https://signalr.example.com/hubs/live`
  /// - [appId] IM 应用 Id（字符串），由 OrangeCloud 提供
  Future<void> setServerConfig({
    required String hubUrl,
    required String appId,
  }) async {
    _hubUrl = hubUrl;
    _appId = appId;
  }

  /// 初始化（对齐 `V2TIMManager.initSDK`）
  ///
  /// - [sdkAppId] ⚠ **收下但忽略** —— 自研 appId 是字符串，实际取 [setServerConfig] 的值
  /// - 返回是否成功；未调用 [setServerConfig] 时返回 false
  Future<bool> initSDK({int sdkAppId = 0}) async {
    if ((_hubUrl ?? '').isEmpty || (_appId ?? '').isEmpty) {
      return false;
    }
    _sdkInitialized = true;
    return true;
  }

  /// 反初始化（对齐 `V2TIMManager.unInitSDK`）
  Future<void> unInitSDK() async {
    await logout();
    _simpleMsgListeners.clear();
    _advancedMsgListeners.clear();
    _groupListeners.clear();
    _sdkListeners.clear();
    _serverLimits = null;
    _sdkInitialized = false;
  }

  /// SDK 版本（对齐 `V2TIMManager.getVersion`）
  Future<String> getVersion() async => _version;

  // ============================================================
  // 登录
  // ============================================================

  /// 登录（对齐 `V2TIMManager.login`）
  ///
  /// 内部完成 SignalR 连接建立与鉴权。断线后由 SDK 自动重连，业务层无需重复调用；
  /// 但收到 [V2OCIMSDKListener.onUserSigExpired] 后必须换新 UserSig 再调一次。
  Future<V2OCIMCallback> login({
    required String userID,
    required String userSig,
  }) async {
    if (!_sdkInitialized) {
      return const V2OCIMCallback(
        code: V2OCIMErrorCode.sdkNotInitialized,
        desc: '请先调用 setServerConfig 与 initSDK',
      );
    }
    final baseUrl = _hubUrl ?? '';
    final currentAppId = _appId ?? '';
    if (baseUrl.isEmpty || currentAppId.isEmpty) {
      return const V2OCIMCallback(
        code: V2OCIMErrorCode.sdkNotInitialized,
        desc: 'hubUrl / appId 未配置',
      );
    }

    _userId = userID;
    _userSig = userSig;
    _manualDisconnect = false;
    // 业务层重新登录视为「已处理完不可恢复错误」，解除重连封锁
    _stoppedByAuthFailure = false;
    _reconnectAttempt = 0;
    _loginStatus = V2OCIMConstants.v2ocimStatusLogining;
    _dispatchSdk((l) => l.onConnecting?.call());

    return _connect(baseUrl, currentAppId, userID, userSig);
  }

  /// 登出（对齐 `V2TIMManager.logout`）
  Future<V2OCIMCallback> logout() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    _lastSequenceNumbers.clear();
    _sentMsgIds.clear();
    _failPendingMemberLists(
      V2OCIMErrorCode.notLoggedIn,
      'IM 已登出',
    );
    _loginStatus = V2OCIMConstants.v2ocimStatusLogout;
    final conn = _connection;
    _connection = null;
    if (conn != null) {
      try {
        await conn.stop();
      } catch (_) {
        // 已断开时 stop 可能抛异常，忽略
      }
    }
    return V2OCIMCallback.success;
  }

  /// 当前登录用户（对齐 `V2TIMManager.getLoginUser`）
  Future<String?> getLoginUser() async => _userId;

  /// 登录状态（对齐 `V2TIMManager.getLoginStatus`），取值见 [V2OCIMConstants]
  Future<int> getLoginStatus() async => _loginStatus;

  // ============================================================
  // 群组
  // ============================================================

  /// 加入群组（对齐 `V2TIMManager.joinGroup`）
  ///
  /// 原生侧会自动带上该群的 lastSequenceNumber 做断连补发，业务层无感。
  ///
  /// - [message] ⚠ 收下但忽略 —— 腾讯用于申请入群理由，直播群场景无用
  Future<V2OCIMCallback> joinGroup({
    required String groupID,
    String? message,
  }) async {
    final conn = _connection;
    if (conn == null || _loginStatus != V2OCIMConstants.v2ocimStatusLogined) {
      return const V2OCIMCallback(
        code: V2OCIMErrorCode.notLoggedIn,
        desc: 'IM 未连接',
      );
    }
    final lastSeq = _lastSequenceNumbers[groupID] ?? 0;
    try {
      await conn.send('JoinGroup', <Object>[groupID, lastSeq]);
      // 记录该群，使断连补发与 currentGroupIdHint 生效（首次入群 seq 为 0）
      _lastSequenceNumbers.putIfAbsent(groupID, () => 0);
      return V2OCIMCallback.success;
    } catch (error) {
      return V2OCIMCallback(
        code: V2OCIMErrorCode.unknown,
        desc: error.toString(),
      );
    }
  }

  /// 退出群组（对齐 `V2TIMManager.quitGroup`）
  Future<V2OCIMCallback> quitGroup({required String groupID}) async {
    final conn = _connection;
    if (conn == null) {
      return const V2OCIMCallback(
        code: V2OCIMErrorCode.notLoggedIn,
        desc: 'IM 未连接',
      );
    }
    try {
      await conn.send('QuitGroup', <Object>[groupID]);
      _lastSequenceNumbers.remove(groupID);
      return V2OCIMCallback.success;
    } catch (error) {
      return V2OCIMCallback(
        code: V2OCIMErrorCode.unknown,
        desc: error.toString(),
      );
    }
  }

  // ============================================================
  // 发送消息
  // ============================================================

  /// 发送群文本消息（对齐 `V2TIMManager.sendGroupTextMessage`）
  ///
  /// 成功时 `data` 是一条完整的 [V2OCIMMessage]（msgID / timestamp / sequenceNumber
  /// 来自服务端），业务层拿它直接上屏即可 ——
  /// **不会再从 listener 收到自己发的这条**（契约 §5）。
  ///
  /// - [priority] ⚠ 收下但不生效，服务端没有优先级队列
  Future<V2OCIMValueCallback<V2OCIMMessage>> sendGroupTextMessage({
    required String text,
    required String groupID,
    int priority = V2OCIMConstants.v2ocimPriorityDefault,
  }) {
    final clientMsgId = _nextClientMsgId();
    return _invokeSend(
      hubMethod: 'SendGroupMsg',
      target: groupID,
      messageJson: V2OCIMWire.buildTextJson(text, clientMsgId),
      buildMessage: (result) => _buildSentMessage(
        result: result,
        groupID: groupID,
        targetUserID: '',
        elemType: V2OCIMConstants.v2ocimElemTypeText,
        textElem: V2OCIMTextElem(text: text),
        customElem: null,
      ),
    );
  }

  /// 发送群自定义消息（对齐 `V2TIMManager.sendGroupCustomMessage`）
  ///
  /// 礼物 / 系统通知 / 公告等业务消息都走这里（业务自行在 customData 里定 JSON），
  /// 与腾讯生态一致 —— elemType 只有 text 与 custom 两种。
  ///
  /// - [priority] ⚠ 收下但不生效
  Future<V2OCIMValueCallback<V2OCIMMessage>> sendGroupCustomMessage({
    required Uint8List customData,
    required String groupID,
    int priority = V2OCIMConstants.v2ocimPriorityDefault,
  }) {
    final clientMsgId = _nextClientMsgId();
    return _invokeSend(
      hubMethod: 'SendGroupMsg',
      target: groupID,
      messageJson: V2OCIMWire.buildCustomJson(customData, clientMsgId),
      buildMessage: (result) => _buildSentMessage(
        result: result,
        groupID: groupID,
        targetUserID: '',
        elemType: V2OCIMConstants.v2ocimElemTypeCustom,
        textElem: null,
        customElem: V2OCIMCustomElem(data: customData),
      ),
    );
  }

  /// 发送 C2C 文本消息（对齐 `V2TIMManager.sendC2CTextMessage`）
  ///
  /// ⚠ **仅在线投递，不存离线消息** —— 接收方当前无连接则该消息丢失。
  /// 对齐腾讯需要离线消息存储 + 上线拉取 + 读位点，属独立一期工程，本期不做。
  Future<V2OCIMValueCallback<V2OCIMMessage>> sendC2CTextMessage({
    required String text,
    required String userID,
  }) {
    final clientMsgId = _nextClientMsgId();
    return _invokeSend(
      hubMethod: 'SendC2CMsg',
      target: userID,
      messageJson: V2OCIMWire.buildTextJson(text, clientMsgId),
      buildMessage: (result) => _buildSentMessage(
        result: result,
        groupID: '',
        targetUserID: userID,
        elemType: V2OCIMConstants.v2ocimElemTypeText,
        textElem: V2OCIMTextElem(text: text),
        customElem: null,
      ),
    );
  }

  /// 发送 C2C 自定义消息（对齐 `V2TIMManager.sendC2CCustomMessage`）
  ///
  /// ⚠ 仅在线投递，不存离线消息。
  Future<V2OCIMValueCallback<V2OCIMMessage>> sendC2CCustomMessage({
    required Uint8List customData,
    required String userID,
  }) {
    final clientMsgId = _nextClientMsgId();
    return _invokeSend(
      hubMethod: 'SendC2CMsg',
      target: userID,
      messageJson: V2OCIMWire.buildCustomJson(customData, clientMsgId),
      buildMessage: (result) => _buildSentMessage(
        result: result,
        groupID: '',
        targetUserID: userID,
        elemType: V2OCIMConstants.v2ocimElemTypeCustom,
        textElem: null,
        customElem: V2OCIMCustomElem(data: customData),
      ),
    );
  }

  // ============================================================
  // Listener 注册
  // ============================================================

  void addSimpleMsgListener({required V2OCIMSimpleMsgListener listener}) {
    if (!_simpleMsgListeners.contains(listener)) {
      _simpleMsgListeners.add(listener);
    }
  }

  void removeSimpleMsgListener({required V2OCIMSimpleMsgListener listener}) {
    _simpleMsgListeners.remove(listener);
  }

  void addAdvancedMsgListener({required V2OCIMAdvancedMsgListener listener}) {
    if (!_advancedMsgListeners.contains(listener)) {
      _advancedMsgListeners.add(listener);
    }
  }

  void removeAdvancedMsgListener({
    required V2OCIMAdvancedMsgListener listener,
  }) {
    _advancedMsgListeners.remove(listener);
  }

  void addGroupListener({required V2OCIMGroupListener listener}) {
    if (!_groupListeners.contains(listener)) _groupListeners.add(listener);
  }

  void removeGroupListener({required V2OCIMGroupListener listener}) {
    _groupListeners.remove(listener);
  }

  void addIMSDKListener({required V2OCIMSDKListener listener}) {
    if (!_sdkListeners.contains(listener)) _sdkListeners.add(listener);
  }

  void removeIMSDKListener({required V2OCIMSDKListener listener}) {
    _sdkListeners.remove(listener);
  }

  // ============================================================
  // 自研扩展 API（腾讯没有）
  // ============================================================

  /// ⚠ 自研扩展：拉取群成员列表，返回服务端下发的**原始 JSON**
  /// （形如 `{"Count":N,"Users":[...]}`，注意是 PascalCase）。
  ///
  /// 注意腾讯的直播群成员列表仅旗舰版支持且最多 1000 人，语义并不等价，
  /// 故不复用腾讯方法名的返回结构。
  ///
  /// ⚠ **服务端不回传 groupID**，并发对多个群调用会错配（按先到先出消费）。
  /// 10 秒无响应返回超时错误 —— 纯 Dart 版必须有这个超时，否则调用方会永久 await。
  Future<V2OCIMValueCallback<String>> getGroupMemberList({
    required String groupID,
  }) async {
    final conn = _connection;
    if (conn == null) {
      return const V2OCIMValueCallback<String>(
        code: V2OCIMErrorCode.notLoggedIn,
        desc: 'IM 未连接',
      );
    }
    // 同一群组重复请求时，先让前一个以超时收尾，避免 Completer 泄漏
    final existing = _pendingMemberLists.remove(groupID);
    if (existing != null && !existing.isCompleted) {
      existing.complete(const V2OCIMValueCallback<String>(
        code: V2OCIMErrorCode.unknown,
        desc: '被同群组的新请求取代',
      ));
    }

    final completer = Completer<V2OCIMValueCallback<String>>();
    _pendingMemberLists[groupID] = completer;
    try {
      await conn.send('GetGroupMemberList', <Object>[groupID]);
    } catch (error) {
      _pendingMemberLists.remove(groupID);
      return V2OCIMValueCallback<String>(
        code: V2OCIMErrorCode.unknown,
        desc: error.toString(),
      );
    }

    return completer.future.timeout(
      _memberListTimeout,
      onTimeout: () {
        _pendingMemberLists.remove(groupID);
        return const V2OCIMValueCallback<String>(
          code: V2OCIMErrorCode.unknown,
          desc: '获取群成员列表超时',
        );
      },
    );
  }

  /// ⚠ 自研扩展：请求服务端补发指定序列号之后的消息
  ///
  /// 正常情况下不需要手动调用 —— 内部的间隙检测会自动触发。
  Future<void> requestBackfill({
    required String groupID,
    required int afterSequenceNumber,
  }) async {
    try {
      await _connection
          ?.send('RequestBackfill', <Object>[groupID, afterSequenceNumber]);
    } catch (_) {
      // 补发请求失败静默处理，下一条消息的间隙检测会再次触发
    }
  }

  /// ⚠ 自研扩展：本端记录的该群最后序列号
  Future<int> getLastSequenceNumber({required String groupID}) async =>
      _lastSequenceNumbers[groupID] ?? 0;

  /// ⚠ 自研扩展：服务端下发的生效限制项；连接建立前为 null
  Future<V2OCIMServerLimits?> getServerLimits() async => _serverLimits;

  /// ⚠ 自研扩展：**网络恢复 / 前台唤醒时立即重连**，不等退避计时。
  ///
  /// ## 为什么需要宿主调用
  ///
  /// Android 原生 SDK 用 `ConnectivityManager`、iOS 原生用 `NWPathMonitor`，在网络恢复
  /// 的瞬间就重连。纯 Dart 侧刻意**不引入 `connectivity_plus` 这类插件依赖**
  /// （那会让本包重新变成带原生代码的依赖，也把插件的平台支持范围强加给所有接入方），
  /// 改为把这个信号交给宿主传进来 —— 宿主本来就更清楚自己用哪套网络/生命周期监听。
  ///
  /// 直播类 App **强烈建议接上**，典型两个时机：
  /// - `connectivity_plus` 的 `onConnectivityChanged` 变为有网
  /// - `WidgetsBindingObserver.didChangeAppLifecycleState` 收到 `resumed`
  ///
  /// 不接也能自愈：退避序列最长 10 秒（见 [defaultReconnectDelaysMs]）。
  ///
  /// 安全约定：主动登出、鉴权失败停连、已连上、正在连接中，四种情况一律**不做任何事**
  /// （已连上时强行重建连接反而会造成消息空洞）。可以随便重复调用。
  Future<void> notifyNetworkAvailable() async {
    if (_manualDisconnect || _stoppedByAuthFailure) {
      return;
    }
    if (_loginStatus == V2OCIMConstants.v2ocimStatusLogined ||
        _loginStatus == V2OCIMConstants.v2ocimStatusLogining) {
      return;
    }
    final baseUrl = _hubUrl;
    final currentAppId = _appId;
    final currentUserId = _userId;
    final currentUserSig = _userSig;
    if (baseUrl == null ||
        currentAppId == null ||
        currentUserId == null ||
        currentUserSig == null) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // 网络恢复视为全新一轮：退避从头开始，避免继续按旧的长间隔等待
    _reconnectAttempt = 0;
    _loginStatus = V2OCIMConstants.v2ocimStatusLogining;
    _dispatchSdk((l) => l.onConnecting?.call());
    await _connect(baseUrl, currentAppId, currentUserId, currentUserSig);
  }

  // ============================================================
  // 私有：连接
  // ============================================================

  Future<V2OCIMCallback> _connect(
    String baseUrl,
    String currentAppId,
    String currentUserId,
    String currentUserSig,
  ) async {
    // ⚠ userSig 是标准 Base64，可能含 + / = 三个字符。
    // query 里的 '+' 会被服务端解码成空格 → 签名校验失败，所以必须 URL 编码。
    final separator = baseUrl.contains('?') ? '&' : '?';
    final url = '$baseUrl$separator'
        'appId=${Uri.encodeQueryComponent(currentAppId)}'
        '&userId=${Uri.encodeQueryComponent(currentUserId)}'
        '&userSig=${Uri.encodeQueryComponent(currentUserSig)}';

    // 换连接前先停旧的
    final previous = _connection;
    _connection = null;
    if (previous != null) {
      try {
        await previous.stop();
      } catch (_) {
        // 忽略
      }
    }

    final conn = _connectionFactory(url);
    _connection = conn;
    _registerEvents(conn);

    try {
      await conn.start();
      _reconnectAttempt = 0;
      _loginStatus = V2OCIMConstants.v2ocimStatusLogined;
      _startHeartbeat();
      _dispatchSdk((l) => l.onConnectSuccess?.call());
      return V2OCIMCallback.success;
    } catch (error) {
      _loginStatus = V2OCIMConstants.v2ocimStatusLogout;
      // 若服务端已下发 AuthFailed，_stoppedByAuthFailure 会被置位，
      // 此处不再重连（避免 UserSig 过期后无限重试）
      if (!_stoppedByAuthFailure) {
        _dispatchSdk((l) => l.onConnectFailed?.call(
              V2OCIMErrorCode.unknown,
              error.toString(),
            ));
        _scheduleReconnect();
      }
      return V2OCIMCallback(
        code: V2OCIMErrorCode.unknown,
        desc: error.toString(),
      );
    }
  }

  // ============================================================
  // 私有：事件注册
  // ============================================================

  void _registerEvents(V2OCIMConnection conn) {
    conn.on('ReceiveMessage', (args) {
      _handleIncomingMessage(_argString(args));
    });

    // 批量合并推送：服务端在高并发时把多条消息打包，且**不排除发送者**，
    // 自己发的那几条靠 _sentMsgIds 过滤（契约 §5）
    conn.on('ReceiveBatchMessage', (args) {
      for (final json in V2OCIMWire.splitBatch(_argString(args))) {
        _handleIncomingMessage(json);
      }
    });

    // 全站广播（礼物飘屏等），不属于任何群组
    conn.on('ReceiveBroadcast', (args) {
      _handleIncomingMessage(_argString(args), checkSequence: false);
    });

    // C2C：服务端同时投递给接收方与发送方其它端，且不注入 sequenceNumber
    conn.on('ReceivePrivateMessage', (args) {
      _handleIncomingMessage(_argString(args), checkSequence: false);
    });

    conn.on('UserJoined', (args) {
      final member = V2OCIMWire.parseGroupMember(_argString(args));
      if (member != null) {
        _dispatchGroup(
          (l) => l.onMemberEnter?.call(_currentGroupIdHint(), <
              V2OCIMGroupMemberInfo>[member]),
        );
      }
    });

    conn.on('UserLeft', (args) {
      final userKey = _argString(args);
      _dispatchGroup((l) => l.onMemberLeave?.call(
            _currentGroupIdHint(),
            V2OCIMGroupMemberInfo(userID: userKey),
          ));
    });

    conn.on('OnlineCountChanged', (args) {
      _dispatchGroup((l) => l.onGroupOnlineMemberCountChanged
          ?.call(_currentGroupIdHint(), _argInt(args)));
    });

    // 禁言 / 解禁映射到腾讯的 onMemberInfoChanged（muteTime 变化，解禁为 0）
    conn.on('OnMuted', (args) {
      final change = V2OCIMWire.parseMuteInfo(_argString(args));
      if (change != null) {
        _dispatchGroup((l) => l.onMemberInfoChanged?.call(
              _currentGroupIdHint(),
              <V2OCIMGroupMemberChangeInfo>[change],
            ));
      }
    });

    conn.on('OnUnmuted', (args) {
      final userKey = _argString(args);
      _dispatchGroup((l) => l.onMemberInfoChanged?.call(
            _currentGroupIdHint(),
            <V2OCIMGroupMemberChangeInfo>[
              V2OCIMGroupMemberChangeInfo(userID: userKey),
            ],
          ));
    });

    conn.on('RoomClosed', (args) {
      _dispatchGroup((l) => l.onGroupDismissed?.call(_currentGroupIdHint(), null));
    });

    conn.on('ReceiveGroupMemberList', (args) {
      // 服务端未回传 groupID，取唯一待回调；有多个并发请求时按先到先出消费
      if (_pendingMemberLists.isEmpty) {
        return;
      }
      final key = _pendingMemberLists.keys.first;
      final completer = _pendingMemberLists.remove(key);
      if (completer != null && !completer.isCompleted) {
        completer.complete(V2OCIMValueCallback<String>(
          code: V2OCIMErrorCode.success,
          data: _argString(args),
        ));
      }
    });

    // 业务错误：被禁言 / 空消息 / 超长 / 今日消息数达上限
    conn.on('Error', (args) {
      final message = _argString(args);
      _dispatchSdk(
        (l) => l.onConnectFailed?.call(V2OCIMErrorCode.unknown, message),
      );
    });

    conn.on('RateLimited', (args) {
      final info = _argMap(args);
      final cooldown = info['cooldownMs']?.toString() ?? '0';
      _dispatchSdk((l) => l.onConnectFailed?.call(
            V2OCIMErrorCode.rateLimited,
            '触发频率限制，请 ${cooldown}ms 后重试',
          ));
    });

    // 补发缓冲区溢出：断连过久，业务层需重新拉取该群完整状态
    conn.on('BufferOverflow', (args) {
      final groupId = _argMap(args)['groupId']?.toString() ?? '';
      if (groupId.isNotEmpty) {
        _lastSequenceNumbers[groupId] = 0;
      }
    });

    // 单点登录互踢
    conn.on('KickedOffline', (args) {
      _stopReconnectPermanently();
      _dispatchSdk((l) => l.onKickedOffline?.call());
    });

    // 鉴权失败：区分 UserSig 过期与其它不可恢复错误，两者都停止重连
    conn.on('AuthFailed', (args) {
      final info = _argMap(args);
      final code = info['code']?.toString();
      final message = info['message']?.toString() ?? '';
      _stopReconnectPermanently();
      if (code == V2OCIMAuthFailureCode.userSigExpired) {
        _dispatchSdk((l) => l.onUserSigExpired?.call());
      } else {
        _dispatchSdk((l) => l.onConnectFailed
            ?.call(V2OCIMAuthFailureCode.toErrorCode(code), message));
      }
    });

    // ⚠ 自研扩展：服务端下发生效限制项
    conn.on('ServerConfig', (args) {
      final limits = V2OCIMServerLimits.fromMap(_argMap(args));
      _serverLimits = limits;
      _dispatchSdk((l) => l.onServerConfigUpdated?.call(limits));
    });

    conn.onClose(() {
      // ⚠ 必须先确认这是「当前」连接：重连时会先 stop 旧连接，
      // 旧连接的关闭回调同样会触发，不加这道判断会凭空多起一轮重连
      // （表现为连接抖动、重连计数虚增、退避节奏被打乱）。
      if (!identical(_connection, conn)) {
        return;
      }
      _stopHeartbeat();
      _loginStatus = V2OCIMConstants.v2ocimStatusLogout;
      if (!_manualDisconnect && !_stoppedByAuthFailure) {
        _scheduleReconnect();
      }
    });
  }

  /// 服务端的 UserJoined / UserLeft / OnMuted / RoomClosed 等事件**不回传 groupID**
  /// （历史协议如此），而本 SDK 场景下同一连接只会加入一个房间，
  /// 故取当前已知的唯一群组作为 groupID。多群同时加入时该值可能不准确。
  String _currentGroupIdHint() =>
      _lastSequenceNumbers.keys.isEmpty ? '' : _lastSequenceNumbers.keys.first;

  // ============================================================
  // 私有：收消息
  // ============================================================

  void _handleIncomingMessage(String messageJson, {bool checkSequence = true}) {
    final msg = V2OCIMWire.parseMessage(messageJson, _userId);
    if (msg == null) {
      return;
    }

    // 过滤自己发的消息：逐条推送服务端已排除，批量推送靠这里兜底（契约 §5）
    if (msg.msgID.isNotEmpty && _sentMsgIds.containsKey(msg.msgID)) {
      return;
    }

    if (checkSequence && msg.groupID.isNotEmpty && msg.sequenceNumber > 0) {
      final lastSeq = _lastSequenceNumbers[msg.groupID] ?? 0;
      // 去重：seq <= lastSeq 说明是重复投递（补发与实时推送可能重叠）
      if (msg.sequenceNumber <= lastSeq) {
        return;
      }
      // 间隙检测：中间有丢失，请求服务端补发
      if (lastSeq > 0 && msg.sequenceNumber - lastSeq > 1) {
        requestBackfill(groupID: msg.groupID, afterSequenceNumber: lastSeq);
      }
      _lastSequenceNumbers[msg.groupID] = msg.sequenceNumber;
    }

    _dispatchAdvanced((l) => l.onRecvNewMessage?.call(msg));

    final isGroup = msg.groupID.isNotEmpty;
    if (msg.elemType == V2OCIMConstants.v2ocimElemTypeText) {
      final text = msg.textElem?.text ?? '';
      if (isGroup) {
        _dispatchSimple((l) => l.onRecvGroupTextMessage
            ?.call(msg.msgID, msg.groupID, msg.toGroupMemberInfo(), text));
      } else {
        _dispatchSimple((l) =>
            l.onRecvC2CTextMessage?.call(msg.msgID, msg.toUserInfo(), text));
      }
    } else if (msg.elemType == V2OCIMConstants.v2ocimElemTypeCustom) {
      final data = msg.customElem?.data ?? Uint8List(0);
      if (isGroup) {
        _dispatchSimple((l) => l.onRecvGroupCustomMessage
            ?.call(msg.msgID, msg.groupID, msg.toGroupMemberInfo(), data));
      } else {
        _dispatchSimple((l) =>
            l.onRecvC2CCustomMessage?.call(msg.msgID, msg.toUserInfo(), data));
      }
    }
  }

  // ============================================================
  // 私有：发送
  // ============================================================

  String _nextClientMsgId() =>
      'oc-${DateTime.now().millisecondsSinceEpoch}-${_random.nextInt(100000)}';

  Future<V2OCIMValueCallback<V2OCIMMessage>> _invokeSend({
    required String hubMethod,
    required String target,
    required String messageJson,
    required V2OCIMMessage Function(V2OCIMSendResult result) buildMessage,
  }) async {
    final conn = _connection;
    if (conn == null || _loginStatus != V2OCIMConstants.v2ocimStatusLogined) {
      return const V2OCIMValueCallback<V2OCIMMessage>(
        code: V2OCIMErrorCode.notLoggedIn,
        desc: 'IM 未连接',
      );
    }
    try {
      final raw = await conn.invoke(hubMethod, <Object>[target, messageJson]);
      final result = V2OCIMWire.parseSendResult(raw);
      if (!result.success) {
        return V2OCIMValueCallback<V2OCIMMessage>(
          code: V2OCIMSendRejectCode.toErrorCode(result.rejectCode),
          desc: result.rejectCode ?? '发送失败',
        );
      }
      _rememberSentMsgId(result.msgID);
      return V2OCIMValueCallback<V2OCIMMessage>(
        code: V2OCIMErrorCode.success,
        data: buildMessage(result),
      );
    } catch (error) {
      return V2OCIMValueCallback<V2OCIMMessage>(
        code: V2OCIMErrorCode.unknown,
        desc: error.toString(),
      );
    }
  }

  V2OCIMMessage _buildSentMessage({
    required V2OCIMSendResult result,
    required String groupID,
    required String targetUserID,
    required int elemType,
    required V2OCIMTextElem? textElem,
    required V2OCIMCustomElem? customElem,
  }) {
    return V2OCIMMessage(
      msgID: result.msgID,
      // 服务端给的是毫秒，V2OCIMMessage.timestamp 用秒（与腾讯一致）
      timestamp:
          result.serverTimestamp > 0 ? result.serverTimestamp ~/ 1000 : 0,
      sender: _userId ?? '',
      groupID: groupID,
      userID: targetUserID,
      status: V2OCIMConstants.v2ocimMsgStatusSendSucc,
      isSelf: true,
      elemType: elemType,
      textElem: textElem,
      customElem: customElem,
      sequenceNumber: result.sequenceNumber,
    );
  }

  /// 记住自己发出的 msgID，并做容量与过期清理，避免无界增长
  void _rememberSentMsgId(String msgID) {
    if (msgID.isEmpty) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _sentMsgIds[msgID] = now;

    // 过期清理
    if (_sentMsgIds.length > _sentMsgIdMax ~/ 2) {
      final expiredBefore = now - _sentMsgIdTtl.inMilliseconds;
      _sentMsgIds.removeWhere((_, recordedAt) => recordedAt < expiredBefore);
    }
    // 容量兜底：仍然超限时丢弃最旧的
    if (_sentMsgIds.length > _sentMsgIdMax) {
      final entries = _sentMsgIds.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final entry in entries.take(_sentMsgIds.length - _sentMsgIdMax)) {
        _sentMsgIds.remove(entry.key);
      }
    }
  }

  // ============================================================
  // 私有：重连 / 心跳
  // ============================================================

  /// 永久停止重连。用于 UserSig 过期、应用禁用、超限、被踢下线这些
  /// **重连必然再次失败**的场景 —— 继续重试只会产生无效流量并耗电。
  /// 业务层调用 [login] 会解除封锁。
  void _stopReconnectPermanently() {
    _stoppedByAuthFailure = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    _loginStatus = V2OCIMConstants.v2ocimStatusLogout;
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _stoppedByAuthFailure) {
      return;
    }
    if (maxReconnectAttempts >= 0 &&
        _reconnectAttempt >= maxReconnectAttempts) {
      return;
    }

    final delays =
        reconnectDelaysMs.isEmpty ? defaultReconnectDelaysMs : reconnectDelaysMs;
    final delayMs = delays[min(_reconnectAttempt, delays.length - 1)];
    _reconnectAttempt++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: max(delayMs, 1)), () {
      final baseUrl = _hubUrl;
      final currentAppId = _appId;
      final currentUserId = _userId;
      final currentUserSig = _userSig;
      if (baseUrl == null ||
          currentAppId == null ||
          currentUserId == null ||
          currentUserSig == null) {
        return;
      }
      if (_manualDisconnect || _stoppedByAuthFailure) {
        return;
      }
      _loginStatus = V2OCIMConstants.v2ocimStatusLogining;
      _dispatchSdk((l) => l.onConnecting?.call());
      // 重连结果经 listener 通知，这里不需要返回值
      _connect(baseUrl, currentAppId, currentUserId, currentUserSig);
    });
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final conn = _connection;
      if (conn == null) {
        _stopHeartbeat();
        return;
      }
      // 心跳失败不做处理：真正断开会由 onClose 触发重连
      conn.send('Heartbeat', const <Object>[]).catchError((_) {});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _failPendingMemberLists(int code, String desc) {
    if (_pendingMemberLists.isEmpty) {
      return;
    }
    final pending = _pendingMemberLists.values.toList(growable: false);
    _pendingMemberLists.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.complete(
          V2OCIMValueCallback<String>(code: code, desc: desc),
        );
      }
    }
  }

  // ============================================================
  // 私有：参数与分发工具
  // ============================================================

  /// Hub 方法的第一个实参当字符串取
  static String _argString(List<Object?>? args) {
    if (args == null || args.isEmpty) {
      return '';
    }
    final first = args.first;
    if (first == null) {
      return '';
    }
    return first is String ? first : first.toString();
  }

  static int _argInt(List<Object?>? args) {
    if (args == null || args.isEmpty) {
      return 0;
    }
    final first = args.first;
    if (first is int) {
      return first;
    }
    if (first is num) {
      return first.toInt();
    }
    return int.tryParse(first?.toString() ?? '') ?? 0;
  }

  static Map<Object?, Object?> _argMap(List<Object?>? args) {
    if (args == null || args.isEmpty) {
      return const <Object?, Object?>{};
    }
    final first = args.first;
    return first is Map ? first : const <Object?, Object?>{};
  }

  void _dispatchSimple(void Function(V2OCIMSimpleMsgListener) action) =>
      _dispatch(_simpleMsgListeners, action);

  void _dispatchAdvanced(void Function(V2OCIMAdvancedMsgListener) action) =>
      _dispatch(_advancedMsgListeners, action);

  void _dispatchGroup(void Function(V2OCIMGroupListener) action) =>
      _dispatch(_groupListeners, action);

  void _dispatchSdk(void Function(V2OCIMSDKListener) action) =>
      _dispatch(_sdkListeners, action);

  // 拷贝一份再遍历：业务回调里 removeXxxListener 会改动原列表
  static void _dispatch<T>(List<T> listeners, void Function(T) action) {
    for (final listener in List<T>.of(listeners)) {
      try {
        action(listener);
      } catch (_) {
        // 单个 listener 抛异常不影响其它 listener
      }
    }
  }
}
