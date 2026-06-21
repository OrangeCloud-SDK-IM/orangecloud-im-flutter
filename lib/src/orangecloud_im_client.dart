import 'dart:async';
import 'package:flutter/services.dart';

import 'models/im_message.dart';
import 'models/text_message.dart';
import 'models/gift_message.dart';
import 'models/system_notice.dart';
import 'models/custom_message.dart';

/// 连接状态枚举（与原生侧 IMConnectionState 对齐）
enum IMConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  restoring,
}

/// 状态恢复结果信息
class StateRestoredInfo {
  final List<String> restoredGroupIds;
  final int backfilledMessageCount;

  StateRestoredInfo({
    required this.restoredGroupIds,
    required this.backfilledMessageCount,
  });

  factory StateRestoredInfo.fromMap(Map<dynamic, dynamic> map) {
    return StateRestoredInfo(
      restoredGroupIds:
          (map['restoredGroupIds'] as List?)?.cast<String>() ?? const [],
      backfilledMessageCount: (map['backfilledMessageCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 重连尝试信息
class ReconnectAttemptInfo {
  final int attemptNumber;
  final int nextDelayMs;

  ReconnectAttemptInfo({
    required this.attemptNumber,
    required this.nextDelayMs,
  });

  factory ReconnectAttemptInfo.fromMap(Map<dynamic, dynamic> map) {
    return ReconnectAttemptInfo(
      attemptNumber: (map['attemptNumber'] as num?)?.toInt() ?? 0,
      nextDelayMs: (map['nextDelayMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// OrangeCloud IM Flutter 客户端
///
/// 本类为**桥接层**：所有 IM 核心能力（连接、去重、间隙补发、断线重连、心跳）
/// 均由原生 SDK（Android AAR / iOS XCFramework）实现，Dart 侧仅通过
/// MethodChannel 下发命令、通过 EventChannel 接收事件。
///
/// 公开 API 与旧版（纯 Dart 实现）保持兼容，业务代码无需改动。
class OrangeCloudIMClient {
  static const MethodChannel _methodChannel =
      MethodChannel('com.orangecloud.im/methods');
  static const EventChannel _eventChannel =
      EventChannel('com.orangecloud.im/events');

  StreamSubscription<dynamic>? _eventSub;
  IMConnectionState _connectionState = IMConnectionState.disconnected;

  /// 最大重连次数，-1 表示无限重连
  int maxReconnectAttempts = -1;

  // === 事件流控制器 ===
  final _messageReceivedController = StreamController<String>.broadcast();
  final _userJoinedController = StreamController<String>.broadcast();
  final _userLeftController = StreamController<String>.broadcast();
  final _onlineCountChangedController = StreamController<int>.broadcast();
  final _mutedController = StreamController<String>.broadcast();
  final _unmutedController = StreamController<String>.broadcast();
  final _roomClosedController = StreamController<void>.broadcast();
  final _connectionStateChangedController =
      StreamController<IMConnectionState>.broadcast();

  final _textMessageReceivedController =
      StreamController<TextMessage>.broadcast();
  final _giftMessageReceivedController =
      StreamController<GiftMessage>.broadcast();
  final _systemNoticeReceivedController =
      StreamController<SystemNotice>.broadcast();
  final _customMessageReceivedController =
      StreamController<CustomMessage>.broadcast();

  final _broadcastReceivedController = StreamController<IMMessage>.broadcast();
  final _batchMessageReceivedController =
      StreamController<List<IMMessage>>.broadcast();
  final _stateRestoredController =
      StreamController<StateRestoredInfo>.broadcast();
  final _reconnectAttemptController =
      StreamController<ReconnectAttemptInfo>.broadcast();
  final _reconnectFailedController = StreamController<void>.broadcast();
  final _groupMemberListController = StreamController<String>.broadcast();

  OrangeCloudIMClient() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
          _handleNativeEvent,
          onError: (_) {},
        );
  }

  // === Getters: 事件流 ===
  IMConnectionState get connectionState => _connectionState;
  Stream<String> get onMessageReceived => _messageReceivedController.stream;
  Stream<String> get onUserJoined => _userJoinedController.stream;
  Stream<String> get onUserLeft => _userLeftController.stream;
  Stream<int> get onOnlineCountChanged => _onlineCountChangedController.stream;
  Stream<String> get onMuted => _mutedController.stream;
  Stream<String> get onUnmuted => _unmutedController.stream;
  Stream<void> get onRoomClosed => _roomClosedController.stream;
  Stream<IMConnectionState> get onConnectionStateChanged =>
      _connectionStateChangedController.stream;

  Stream<TextMessage> get onTextMessageReceived =>
      _textMessageReceivedController.stream;
  Stream<GiftMessage> get onGiftMessageReceived =>
      _giftMessageReceivedController.stream;
  Stream<SystemNotice> get onSystemNoticeReceived =>
      _systemNoticeReceivedController.stream;
  Stream<CustomMessage> get onCustomMessageReceived =>
      _customMessageReceivedController.stream;

  Stream<IMMessage> get onBroadcastReceived =>
      _broadcastReceivedController.stream;
  Stream<List<IMMessage>> get onBatchMessageReceived =>
      _batchMessageReceivedController.stream;
  Stream<StateRestoredInfo> get onStateRestored =>
      _stateRestoredController.stream;
  Stream<ReconnectAttemptInfo> get onReconnectAttempt =>
      _reconnectAttemptController.stream;
  Stream<void> get onReconnectFailed => _reconnectFailedController.stream;
  Stream<String> get onGroupMemberList => _groupMemberListController.stream;

  // === 连接管理 ===

  Future<void> login(
      String hubUrl, String appId, String userId, String userSig) async {
    await _methodChannel.invokeMethod('login', {
      'hubUrl': hubUrl,
      'appId': appId,
      'userId': userId,
      'userSig': userSig,
      'maxReconnectAttempts': maxReconnectAttempts,
    });
  }

  Future<void> logout() async {
    await _methodChannel.invokeMethod('logout');
  }

  Future<void> joinGroup(String groupId) async {
    await _methodChannel.invokeMethod('joinGroup', {'groupId': groupId});
  }

  Future<void> quitGroup(String groupId) async {
    await _methodChannel.invokeMethod('quitGroup', {'groupId': groupId});
  }

  Future<void> sendGroupMsg(String groupId, String messageJson) async {
    await _methodChannel.invokeMethod('sendGroupMsg', {
      'groupId': groupId,
      'messageJson': messageJson,
    });
  }

  Future<void> getGroupMemberList(String groupId) async {
    await _methodChannel.invokeMethod('getGroupMemberList', {'groupId': groupId});
  }

  // === 类型安全发送方法 ===

  Future<void> sendTextMessage(String groupId, String content) async {
    await _methodChannel.invokeMethod('sendTextMessage', {
      'groupId': groupId,
      'content': content,
    });
  }

  Future<void> sendGiftMessage(String groupId, GiftInfo giftInfo) async {
    await _methodChannel.invokeMethod('sendGiftMessage', {
      'groupId': groupId,
      'giftInfo': giftInfo.toJson(),
    });
  }

  Future<void> sendCustomMessage(
      String groupId, String customType, Map<String, dynamic> payload) async {
    await _methodChannel.invokeMethod('sendCustomMessage', {
      'groupId': groupId,
      'customType': customType,
      'payload': payload,
    });
  }

  /// 获取指定群组的最后序列号（由原生侧维护）
  Future<int> getLastSequenceNumber(String groupId) async {
    final result = await _methodChannel
        .invokeMethod<int>('getLastSequenceNumber', {'groupId': groupId});
    return result ?? 0;
  }

  Future<void> dispose() async {
    try {
      await _methodChannel.invokeMethod('dispose');
    } catch (_) {}
    await _eventSub?.cancel();
    _eventSub = null;
    _messageReceivedController.close();
    _userJoinedController.close();
    _userLeftController.close();
    _onlineCountChangedController.close();
    _mutedController.close();
    _unmutedController.close();
    _roomClosedController.close();
    _connectionStateChangedController.close();
    _textMessageReceivedController.close();
    _giftMessageReceivedController.close();
    _systemNoticeReceivedController.close();
    _customMessageReceivedController.close();
    _broadcastReceivedController.close();
    _batchMessageReceivedController.close();
    _stateRestoredController.close();
    _reconnectAttemptController.close();
    _reconnectFailedController.close();
    _groupMemberListController.close();
  }

  // === 原生事件分发 ===

  /// 原生侧统一通过 EventChannel 推送 `{ "event": "<名称>", "data": <载荷> }`。
  void _handleNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = raw['event'] as String?;
    final data = raw['data'];
    if (event == null) return;

    switch (event) {
      case 'connectionStateChanged':
        _connectionState = _parseConnectionState(data as String?);
        _connectionStateChangedController.add(_connectionState);
        break;
      case 'messageReceived':
        final json = data as String;
        _messageReceivedController.add(json);
        _dispatchTypedMessage(json);
        break;
      case 'userJoined':
        _userJoinedController.add(data as String);
        break;
      case 'userLeft':
        _userLeftController.add(data as String);
        break;
      case 'onlineCountChanged':
        _onlineCountChangedController.add((data as num).toInt());
        break;
      case 'muted':
        _mutedController.add(data as String);
        break;
      case 'unmuted':
        _unmutedController.add(data as String);
        break;
      case 'roomClosed':
        _roomClosedController.add(null);
        break;
      case 'broadcastReceived':
        final msg = _parseMessage(data as String);
        if (msg != null) _broadcastReceivedController.add(msg);
        break;
      case 'batchMessageReceived':
        final list = (data as List)
            .map((e) => _parseMessage(e as String))
            .whereType<IMMessage>()
            .toList();
        if (list.isNotEmpty) _batchMessageReceivedController.add(list);
        break;
      case 'stateRestored':
        _stateRestoredController
            .add(StateRestoredInfo.fromMap(data as Map));
        _connectionState = IMConnectionState.connected;
        _connectionStateChangedController.add(_connectionState);
        break;
      case 'reconnectAttempt':
        _reconnectAttemptController
            .add(ReconnectAttemptInfo.fromMap(data as Map));
        break;
      case 'reconnectFailed':
        _reconnectFailedController.add(null);
        break;
      case 'groupMemberList':
        _groupMemberListController.add(data as String);
        break;
    }
  }

  IMConnectionState _parseConnectionState(String? value) {
    switch (value) {
      case 'connecting':
        return IMConnectionState.connecting;
      case 'connected':
        return IMConnectionState.connected;
      case 'reconnecting':
        return IMConnectionState.reconnecting;
      case 'restoring':
        return IMConnectionState.restoring;
      case 'disconnected':
      default:
        return IMConnectionState.disconnected;
    }
  }

  IMMessage? _parseMessage(String rawJson) {
    try {
      return IMMessage.fromJsonString(rawJson);
    } catch (_) {
      return null;
    }
  }

  void _dispatchTypedMessage(String rawJson) {
    final message = _parseMessage(rawJson);
    if (message == null) return;
    switch (message.messageType) {
      case IMMessageType.text:
        _textMessageReceivedController.add(message as TextMessage);
        break;
      case IMMessageType.gift:
        _giftMessageReceivedController.add(message as GiftMessage);
        break;
      case IMMessageType.systemNotice:
        _systemNoticeReceivedController.add(message as SystemNotice);
        break;
      case IMMessageType.custom:
        _customMessageReceivedController.add(message as CustomMessage);
        break;
    }
  }
}
