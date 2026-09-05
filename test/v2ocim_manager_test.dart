import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orangecloud_im_client/orangecloud_im_client.dart';
import 'package:orangecloud_im_client/src/v2ocim/internal/v2ocim_connection.dart';

/// 可控的 SignalR 连接替身：记录调用、可指定返回值、可手动触发服务端事件与关闭。
class _FakeConnection implements V2OCIMConnection {
  _FakeConnection(this.url);

  final String url;
  final List<String> calls = <String>[];
  final Map<String, void Function(List<Object?>? args)> handlers =
      <String, void Function(List<Object?>? args)>{};
  void Function()? closeHandler;

  bool startShouldFail = false;
  bool stopped = false;
  Object? invokeResult;
  Object? invokeThrows;

  /// 最近一次 invoke 的实参
  List<Object>? lastInvokeArgs;

  /// 最近一次 send 的实参，按方法名归档
  final Map<String, List<Object>> lastSendArgs = <String, List<Object>>{};

  @override
  Future<void> start() async {
    calls.add('start');
    if (startShouldFail) {
      throw Exception('connect refused');
    }
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    stopped = true;
  }

  @override
  Future<void> send(String method, List<Object> args) async {
    calls.add('send:$method');
    lastSendArgs[method] = args;
  }

  @override
  Future<Object?> invoke(String method, List<Object> args) async {
    calls.add('invoke:$method');
    lastInvokeArgs = args;
    if (invokeThrows != null) {
      throw invokeThrows!;
    }
    return invokeResult;
  }

  @override
  void on(String method, void Function(List<Object?>? args) handler) {
    handlers[method] = handler;
  }

  @override
  void onClose(void Function() handler) {
    closeHandler = handler;
  }

  /// 模拟服务端推送
  void emit(String event, [List<Object?> args = const <Object?>[]]) {
    handlers[event]?.call(args);
  }

  /// 模拟连接断开
  void triggerClose() => closeHandler?.call();
}

Map<String, Object?> _sendOk({
  String msgID = 'srv-1',
  int seq = 1,
  int timestampMs = 1700000000000,
}) {
  return <String, Object?>{
    'success': true,
    'msgID': msgID,
    'sequenceNumber': seq,
    'serverTimestamp': timestampMs,
  };
}

String _groupMessage({
  required String msgID,
  required int seq,
  String groupId = 'room-1',
  String sender = 'peer',
  String content = 'hi',
}) {
  return jsonEncode(<String, Object?>{
    'messageType': 'text',
    'msgID': msgID,
    'groupId': groupId,
    'sequenceNumber': seq,
    'serverTimestamp': 1700000000000,
    'senderInfo': <String, Object?>{'userId': sender, 'nickName': 'Peer'},
    'data': <String, Object?>{'content': content},
  });
}

/// 本轮用例里工厂造出的全部连接，按创建顺序。重连会追加新的。
late List<_FakeConnection> connections;

/// 当前活跃连接（最后一个被造出来的）
_FakeConnection get conn => connections.last;

void main() {
  final manager = V2OCIMManager.instance;

  /// 建立一个已登录的连接
  Future<void> loginOk() async {
    await manager.setServerConfig(
      hubUrl: 'https://im.example.com/hubs/live',
      appId: 'im-app-1',
    );
    await manager.initSDK();
    final result = await manager.login(userID: 'me', userSig: 'sig');
    expect(result.isSuccess, isTrue);
  }

  setUp(() async {
    await manager.resetForTest();
    connections = <_FakeConnection>[];
    manager.setConnectionFactoryForTest((url) {
      final fake = _FakeConnection(url);
      connections.add(fake);
      return fake;
    });
  });

  tearDown(() async {
    await manager.resetForTest();
  });

  group('初始化与登录', () {
    test('没 setServerConfig 时 initSDK 返回 false，login 报未初始化', () async {
      expect(await manager.initSDK(), isFalse);
      final result = await manager.login(userID: 'me', userSig: 'sig');
      expect(result.code, V2OCIMErrorCode.sdkNotInitialized);
    });

    test('登录成功后状态为已登录，并回调 onConnecting / onConnectSuccess', () async {
      final events = <String>[];
      manager.addIMSDKListener(
        listener: V2OCIMSDKListener(
          onConnecting: () => events.add('connecting'),
          onConnectSuccess: () => events.add('success'),
        ),
      );

      await loginOk();

      expect(events, <String>['connecting', 'success']);
      expect(await manager.getLoginStatus(), V2OCIMConstants.v2ocimStatusLogined);
      expect(await manager.getLoginUser(), 'me');
    });

    test('鉴权三个参数都做 URL 编码（userSig 的 + / = 不能裸传）', () async {
      await manager.setServerConfig(
        hubUrl: 'https://im.example.com/hubs/live',
        appId: 'app+1',
      );
      await manager.initSDK();
      await manager.login(userID: 'me', userSig: 'a+b/c=');

      // '+' 裸传会被服务端解码成空格 → 签名校验失败
      expect(conn.url, contains('appId=app%2B1'));
      expect(conn.url, contains('userSig=a%2Bb%2Fc%3D'));
      expect(conn.url, contains('userId=me'));
    });

    test('hubUrl 已带 query 时用 & 拼接', () async {
      await manager.setServerConfig(
        hubUrl: 'https://im.example.com/hubs/live?x=1',
        appId: 'app',
      );
      await manager.initSDK();
      await manager.login(userID: 'me', userSig: 'sig');
      expect(conn.url, contains('?x=1&appId=app'));
    });

    test('连接失败回调 onConnectFailed 并返回错误', () async {
      var failed = 0;
      manager.addIMSDKListener(
        listener: V2OCIMSDKListener(onConnectFailed: (_, __) => failed++),
      );
      await manager.setServerConfig(
        hubUrl: 'https://im.example.com/hubs/live',
        appId: 'app',
      );
      await manager.initSDK();
      manager.setConnectionFactoryForTest((url) {
        final fake = _FakeConnection(url)..startShouldFail = true;
        connections.add(fake);
        return fake;
      });
      // 不让它无限重连拖慢用例
      manager.maxReconnectAttempts = 0;

      final result = await manager.login(userID: 'me', userSig: 'sig');
      expect(result.isSuccess, isFalse);
      expect(failed, 1);
      expect(await manager.getLoginStatus(), V2OCIMConstants.v2ocimStatusLogout);
    });

    test('logout 停连接、清状态', () async {
      await loginOk();
      final active = conn;
      final result = await manager.logout();
      expect(result.isSuccess, isTrue);
      expect(active.stopped, isTrue);
      expect(await manager.getLoginStatus(), V2OCIMConstants.v2ocimStatusLogout);
    });
  });

  group('群组', () {
    test('joinGroup 自动带上该群 lastSequenceNumber（首次为 0）', () async {
      await loginOk();
      final result = await manager.joinGroup(groupID: 'room-1');
      expect(result.isSuccess, isTrue);
      expect(conn.lastSendArgs['JoinGroup'], <Object>['room-1', 0]);
    });

    test('收过消息后再入群，带上已知的最后序列号做补发', () async {
      await loginOk();
      await manager.joinGroup(groupID: 'room-1');
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a', seq: 7)]);

      await manager.joinGroup(groupID: 'room-1');
      expect(conn.lastSendArgs['JoinGroup'], <Object>['room-1', 7]);
    });

    test('未连接时 joinGroup 返回未登录', () async {
      final result = await manager.joinGroup(groupID: 'room-1');
      expect(result.code, V2OCIMErrorCode.notLoggedIn);
    });

    test('quitGroup 清掉该群序列号', () async {
      await loginOk();
      await manager.joinGroup(groupID: 'room-1');
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a', seq: 7)]);
      expect(await manager.getLastSequenceNumber(groupID: 'room-1'), 7);

      await manager.quitGroup(groupID: 'room-1');
      expect(await manager.getLastSequenceNumber(groupID: 'room-1'), 0);
    });
  });

  group('发送消息', () {
    test('文本消息 wire format 正确，成功后返回服务端 msgID/时间/序列号', () async {
      await loginOk();
      conn.invokeResult = _sendOk(msgID: 'srv-9', seq: 3);

      final result = await manager.sendGroupTextMessage(
        text: 'hello',
        groupID: 'room-1',
      );

      expect(result.isSuccess, isTrue);
      expect(conn.calls, contains('invoke:SendGroupMsg'));
      expect(conn.lastInvokeArgs![0], 'room-1');
      final wire = jsonDecode(conn.lastInvokeArgs![1] as String) as Map;
      expect(wire['messageType'], 'text');
      expect((wire['data'] as Map)['content'], 'hello');
      expect(wire['clientMsgId'], isA<String>());

      final msg = result.data!;
      expect(msg.msgID, 'srv-9');
      expect(msg.sequenceNumber, 3);
      expect(msg.timestamp, 1700000000);
      expect(msg.isSelf, isTrue);
      expect(msg.sender, 'me');
      expect(msg.groupID, 'room-1');
      expect(msg.elemType, V2OCIMConstants.v2ocimElemTypeText);
      expect(msg.textElem?.text, 'hello');
    });

    test('自定义消息把字节 Base64 塞进 data.customData', () async {
      await loginOk();
      conn.invokeResult = _sendOk();
      final payload = utf8.encode('{"Type":"SEND_BIG_GIFT"}');

      final result = await manager.sendGroupCustomMessage(
        customData: Uint8List.fromList(payload),
        groupID: 'room-1',
      );

      expect(result.isSuccess, isTrue);
      final wire = jsonDecode(conn.lastInvokeArgs![1] as String) as Map;
      expect(wire['messageType'], 'custom');
      final encoded = (wire['data'] as Map)['customData'] as String;
      expect(utf8.decode(base64.decode(encoded)), '{"Type":"SEND_BIG_GIFT"}');
      expect(result.data!.elemType, V2OCIMConstants.v2ocimElemTypeCustom);
    });

    test('C2C 走 SendC2CMsg，groupID 为空、userID 有值', () async {
      await loginOk();
      conn.invokeResult = _sendOk(seq: 0);

      final result =
          await manager.sendC2CTextMessage(text: 'hi', userID: 'peer-1');

      expect(conn.calls, contains('invoke:SendC2CMsg'));
      expect(conn.lastInvokeArgs![0], 'peer-1');
      expect(result.data!.groupID, isEmpty);
      expect(result.data!.userID, 'peer-1');
      // C2C 不分配序列号，判定成败只能看 success（不能看 seq）
      expect(result.data!.sequenceNumber, 0);
      expect(result.isSuccess, isTrue);
    });

    test('被拒绝时按 rejectCode 映射错误码', () async {
      await loginOk();
      conn.invokeResult = <String, Object?>{
        'success': false,
        'rejectCode': 'muted',
      };
      final result =
          await manager.sendGroupTextMessage(text: 'x', groupID: 'room-1');
      expect(result.isSuccess, isFalse);
      expect(result.code, V2OCIMErrorCode.muted);
    });

    test('invoke 抛异常时返回 unknown，不把异常冒给业务层', () async {
      await loginOk();
      conn.invokeThrows = Exception('socket closed');
      final result =
          await manager.sendGroupTextMessage(text: 'x', groupID: 'room-1');
      expect(result.code, V2OCIMErrorCode.unknown);
      expect(result.desc, contains('socket closed'));
    });

    test('未连接时发送返回未登录', () async {
      final result =
          await manager.sendGroupTextMessage(text: 'x', groupID: 'room-1');
      expect(result.code, V2OCIMErrorCode.notLoggedIn);
    });
  });

  group('收消息与可靠性', () {
    test('同时回调 advanced 与 simple listener', () async {
      final advanced = <String>[];
      final simple = <String>[];
      manager.addAdvancedMsgListener(
        listener: V2OCIMAdvancedMsgListener(
          onRecvNewMessage: (msg) => advanced.add(msg.msgID),
        ),
      );
      manager.addSimpleMsgListener(
        listener: V2OCIMSimpleMsgListener(
          onRecvGroupTextMessage: (msgID, groupID, sender, text) =>
              simple.add('$msgID|$groupID|${sender.userID}|$text'),
        ),
      );

      await loginOk();
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a', seq: 1)]);

      expect(advanced, <String>['a']);
      expect(simple, <String>['a|room-1|peer|hi']);
    });

    test('序列号去重：seq 不前进的重复投递被丢弃', () async {
      final received = <String>[];
      manager.addAdvancedMsgListener(
        listener: V2OCIMAdvancedMsgListener(
          onRecvNewMessage: (msg) => received.add(msg.msgID),
        ),
      );
      await loginOk();

      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a', seq: 5)]);
      // 补发与实时推送重叠时会重复投递
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a2', seq: 5)]);
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a3', seq: 4)]);

      expect(received, <String>['a']);
    });

    test('间隙检测：seq 跳号时自动请求补发', () async {
      await loginOk();
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a', seq: 5)]);
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'b', seq: 9)]);
      await Future<void>.delayed(Duration.zero);

      expect(conn.calls, contains('send:RequestBackfill'));
      expect(conn.lastSendArgs['RequestBackfill'], <Object>['room-1', 5]);
    });

    test('首条消息（lastSeq=0）不触发补发', () async {
      await loginOk();
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a', seq: 42)]);
      await Future<void>.delayed(Duration.zero);
      expect(conn.calls.any((c) => c == 'send:RequestBackfill'), isFalse);
    });

    test('批量推送拆条逐个投递', () async {
      final received = <String>[];
      manager.addAdvancedMsgListener(
        listener: V2OCIMAdvancedMsgListener(
          onRecvNewMessage: (msg) => received.add(msg.msgID),
        ),
      );
      await loginOk();

      conn.emit('ReceiveBatchMessage', <Object?>[
        jsonEncode(<String, Object?>{
          'type': 'batch',
          'count': 2,
          'messages': <Object?>[
            jsonDecode(_groupMessage(msgID: 'x', seq: 1)),
            jsonDecode(_groupMessage(msgID: 'y', seq: 2)),
          ],
        }),
      ]);

      expect(received, <String>['x', 'y']);
    });

    test('⚠ 自发消息过滤：批量推送不排除发送者，靠 msgID 集合兜底', () async {
      final received = <String>[];
      manager.addAdvancedMsgListener(
        listener: V2OCIMAdvancedMsgListener(
          onRecvNewMessage: (msg) => received.add(msg.msgID),
        ),
      );
      await loginOk();
      conn.invokeResult = _sendOk(msgID: 'mine-1', seq: 1);
      await manager.sendGroupTextMessage(text: 'x', groupID: 'room-1');

      // 服务端把自己发的这条又推回来（批量路径就是这样）
      conn.emit('ReceiveMessage',
          <Object?>[_groupMessage(msgID: 'mine-1', seq: 2, sender: 'me')]);
      // 别人的消息照常收
      conn.emit('ReceiveMessage',
          <Object?>[_groupMessage(msgID: 'other-1', seq: 3)]);

      expect(received, <String>['other-1']);
    });

    test('广播与私信不参与序列号检查（服务端不注入 seq）', () async {
      final received = <String>[];
      manager.addAdvancedMsgListener(
        listener: V2OCIMAdvancedMsgListener(
          onRecvNewMessage: (msg) => received.add(msg.msgID),
        ),
      );
      await loginOk();
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a', seq: 9)]);
      // 广播的 seq 比当前小，若参与去重会被误丢
      conn.emit('ReceiveBroadcast',
          <Object?>[_groupMessage(msgID: 'bc', seq: 1)]);
      conn.emit('ReceivePrivateMessage',
          <Object?>[_groupMessage(msgID: 'pm', seq: 1)]);

      expect(received, <String>['a', 'bc', 'pm']);
    });

    test('BufferOverflow 重置该群序列号（断连过久需重新对齐）', () async {
      await loginOk();
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a', seq: 30)]);
      expect(await manager.getLastSequenceNumber(groupID: 'room-1'), 30);

      conn.emit('BufferOverflow', <Object?>[
        <String, Object?>{'groupId': 'room-1'},
      ]);
      expect(await manager.getLastSequenceNumber(groupID: 'room-1'), 0);
    });

    test('单个 listener 抛异常不影响其它 listener', () async {
      final ok = <String>[];
      manager.addAdvancedMsgListener(
        listener: V2OCIMAdvancedMsgListener(
          onRecvNewMessage: (_) => throw Exception('boom'),
        ),
      );
      manager.addAdvancedMsgListener(
        listener: V2OCIMAdvancedMsgListener(
          onRecvNewMessage: (msg) => ok.add(msg.msgID),
        ),
      );
      await loginOk();
      conn.emit('ReceiveMessage', <Object?>[_groupMessage(msgID: 'a', seq: 1)]);
      expect(ok, <String>['a']);
    });
  });

  group('群事件翻译', () {
    test('OnMuted / OnUnmuted → onMemberInfoChanged', () async {
      final changes = <String>[];
      manager.addGroupListener(
        listener: V2OCIMGroupListener(
          onMemberInfoChanged: (groupID, list) => changes
              .add('$groupID|${list.single.userID}|${list.single.muteTime}'),
        ),
      );
      await loginOk();
      await manager.joinGroup(groupID: 'room-1');

      conn.emit('OnMuted', <Object?>[
        jsonEncode(<String, Object?>{'userId': 'u1', 'muteUntil': 1700009999}),
      ]);
      conn.emit('OnUnmuted', <Object?>['u2']);

      expect(changes, <String>['room-1|u1|1700009999', 'room-1|u2|0']);
    });

    test('RoomClosed → onGroupDismissed', () async {
      final dismissed = <String>[];
      manager.addGroupListener(
        listener: V2OCIMGroupListener(
          onGroupDismissed: (groupID, _) => dismissed.add(groupID),
        ),
      );
      await loginOk();
      await manager.joinGroup(groupID: 'room-1');
      conn.emit('RoomClosed');
      expect(dismissed, <String>['room-1']);
    });

    test('UserJoined / UserLeft / OnlineCountChanged', () async {
      final log = <String>[];
      manager.addGroupListener(
        listener: V2OCIMGroupListener(
          onMemberEnter: (g, list) => log.add('enter:${list.single.userID}'),
          onMemberLeave: (g, m) => log.add('leave:${m.userID}'),
          onGroupOnlineMemberCountChanged: (g, c) => log.add('count:$c'),
        ),
      );
      await loginOk();
      await manager.joinGroup(groupID: 'room-1');

      conn.emit('UserJoined', <Object?>[
        jsonEncode(<String, Object?>{'UserKey': 'u1', 'NickName': 'A'}),
      ]);
      conn.emit('UserLeft', <Object?>['u2']);
      conn.emit('OnlineCountChanged', <Object?>[42]);

      expect(log, <String>['enter:u1', 'leave:u2', 'count:42']);
    });

    test('ServerConfig 存下限制项并回调', () async {
      V2OCIMServerLimits? got;
      manager.addIMSDKListener(
        listener: V2OCIMSDKListener(onServerConfigUpdated: (l) => got = l),
      );
      await loginOk();
      conn.emit('ServerConfig', <Object?>[
        <String, Object?>{
          'maxMessageLength': 800,
          'maxMessagesPerSecond': 20,
          'bufferMaxSize': 1000,
        },
      ]);

      expect(got?.maxMessageLength, 800);
      expect(got?.maxMessagesPerSecond, 20);
      expect((await manager.getServerLimits())?.bufferMaxSize, 1000);
    });

    test('RateLimited 经 onConnectFailed 通知，带冷却时间', () async {
      final failures = <String>[];
      manager.addIMSDKListener(
        listener: V2OCIMSDKListener(
          onConnectFailed: (code, desc) => failures.add('$code|$desc'),
        ),
      );
      await loginOk();
      conn.emit('RateLimited', <Object?>[
        <String, Object?>{'cooldownMs': 800},
      ]);
      expect(failures.single, contains('${V2OCIMErrorCode.rateLimited}|'));
      expect(failures.single, contains('800'));
    });
  });

  group('鉴权失败与互踢：必须停止重连', () {
    test('AuthFailed(user_sig_expired) → onUserSigExpired，且断开后不再重连', () async {
      var expired = 0;
      manager.addIMSDKListener(
        listener: V2OCIMSDKListener(onUserSigExpired: () => expired++),
      );
      await loginOk();
      final active = conn;

      active.emit('AuthFailed', <Object?>[
        <String, Object?>{'code': 'user_sig_expired', 'message': '过期'},
      ]);
      expect(expired, 1);

      // 服务端随后 Abort → 关闭回调不应再拉起重连
      active.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(connections, hasLength(1));
    });

    test('AuthFailed(其它码) → onConnectFailed 且映射错误码', () async {
      final failures = <int>[];
      manager.addIMSDKListener(
        listener: V2OCIMSDKListener(
          onConnectFailed: (code, _) => failures.add(code),
        ),
      );
      await loginOk();
      conn.emit('AuthFailed', <Object?>[
        <String, Object?>{'code': 'app_disabled', 'message': 'x'},
      ]);
      expect(failures, <int>[V2OCIMErrorCode.appUnavailable]);
    });

    test('KickedOffline → onKickedOffline，且不再重连', () async {
      var kicked = 0;
      manager.addIMSDKListener(
        listener: V2OCIMSDKListener(onKickedOffline: () => kicked++),
      );
      await loginOk();
      final active = conn;

      active.emit('KickedOffline');
      expect(kicked, 1);

      active.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(connections, hasLength(1));
    });

    test('重新 login 解除重连封锁', () async {
      await loginOk();
      conn.emit('KickedOffline');
      expect(await manager.getLoginStatus(), V2OCIMConstants.v2ocimStatusLogout);

      final again = await manager.login(userID: 'me', userSig: 'new-sig');
      expect(again.isSuccess, isTrue);
      expect(await manager.getLoginStatus(), V2OCIMConstants.v2ocimStatusLogined);
    });
  });

  group('网络恢复立即重连（notifyNetworkAvailable）', () {
    test('退避序列最长 10 秒 —— 不能是 30 秒（直播场景公屏黑屏上限）', () {
      expect(V2OCIMManager.defaultReconnectDelaysMs.last, 10000);
      expect(V2OCIMManager.defaultReconnectDelaysMs.first, 0);
      // Android/iOS 原生有系统级网络监听，纯 Dart 没有，所以尾巴必须更短
      expect(V2OCIMManager.defaultReconnectDelaysMs, isNot(contains(30000)));
    });

    test('断开后调用会立即重连，不等退避计时', () async {
      await loginOk();
      manager.maxReconnectAttempts = 0; // 关掉自动重连，确保重连来自本方法
      conn.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(connections, hasLength(1), reason: '自动重连已关闭');

      await manager.notifyNetworkAvailable();

      expect(connections, hasLength(2));
      expect(await manager.getLoginStatus(), V2OCIMConstants.v2ocimStatusLogined);
    });

    test('已连上时是空操作（强行重建连接会造成消息空洞）', () async {
      await loginOk();
      await manager.notifyNetworkAvailable();
      expect(connections, hasLength(1));
    });

    test('主动 logout 后是空操作', () async {
      await loginOk();
      await manager.logout();
      await manager.notifyNetworkAvailable();
      expect(connections, hasLength(1));
    });

    test('鉴权失败停连后是空操作（重连必然再失败）', () async {
      await loginOk();
      conn.emit('AuthFailed', <Object?>[
        <String, Object?>{'code': 'user_sig_expired'},
      ]);
      await manager.notifyNetworkAvailable();
      expect(connections, hasLength(1));
    });

    test('没登录过（无凭据）时是空操作，不崩', () async {
      await expectLater(manager.notifyNetworkAvailable(), completes);
      expect(connections, isEmpty);
    });

    test('重复调用不会叠加连接', () async {
      await loginOk();
      manager.maxReconnectAttempts = 0;
      conn.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await Future.wait<void>(<Future<void>>[
        manager.notifyNetworkAvailable(),
        manager.notifyNetworkAvailable(),
        manager.notifyNetworkAvailable(),
      ]);

      expect(connections, hasLength(2));
    });

    test('恢复后把退避重置回第一档（不再按旧的长间隔等）', () async {
      await loginOk();
      // 连续失败若干次，把退避推到尾档
      manager.setConnectionFactoryForTest((url) {
        final fake = _FakeConnection(url)..startShouldFail = true;
        connections.add(fake);
        return fake;
      });
      conn.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      manager.maxReconnectAttempts = 0; // 冻住自动重连，避免干扰计数

      // 网络恢复：换回能连上的工厂，立即重连应当成功
      manager.setConnectionFactoryForTest((url) {
        final fake = _FakeConnection(url);
        connections.add(fake);
        return fake;
      });
      await manager.notifyNetworkAvailable();

      expect(await manager.getLoginStatus(), V2OCIMConstants.v2ocimStatusLogined);
    });
  });

  group('重连', () {
    test('意外断开会自动重连（首次退避 0 秒）', () async {
      await loginOk();
      expect(connections, hasLength(1));

      conn.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(connections.length, greaterThanOrEqualTo(2));
      expect(await manager.getLoginStatus(), V2OCIMConstants.v2ocimStatusLogined);
    });

    test('主动 logout 后断开不重连', () async {
      await loginOk();
      final active = conn;
      await manager.logout();

      active.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(connections, hasLength(1));
    });

    test('⚠ 旧连接的 close 回调不会多起一轮重连（身份判断）', () async {
      await loginOk();
      final first = connections[0];

      // 触发一次重连，产生第二个连接
      first.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final countAfterReconnect = connections.length;

      // 旧连接此时才回调 close —— 不加身份判断会凭空再起一轮，
      // 表现为连接抖动、重连计数虚增、退避节奏被打乱
      first.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(connections.length, countAfterReconnect);
    });

    test('maxReconnectAttempts 为 0 时不重连', () async {
      await loginOk();
      manager.maxReconnectAttempts = 0;
      conn.triggerClose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(connections, hasLength(1));
    });
  });

  group('群成员列表（服务端以独立事件返回，且不回传 groupID）', () {
    test('收到事件后 Future 完成，返回原始 JSON', () async {
      await loginOk();
      const raw = '{"Count":1,"Users":[{"UserKey":"u1"}]}';

      final future = manager.getGroupMemberList(groupID: 'room-1');
      await Future<void>.delayed(Duration.zero);
      conn.emit('ReceiveGroupMemberList', <Object?>[raw]);

      final result = await future;
      expect(result.isSuccess, isTrue);
      expect(result.data, raw);
      expect(conn.lastSendArgs['GetGroupMemberList'], <Object>['room-1']);
    });

    test('未连接时直接返回未登录', () async {
      final result = await manager.getGroupMemberList(groupID: 'room-1');
      expect(result.code, V2OCIMErrorCode.notLoggedIn);
    });

    test('同群组重复请求时，前一个以错误收尾不会悬挂', () async {
      await loginOk();
      final first = manager.getGroupMemberList(groupID: 'room-1');
      await Future<void>.delayed(Duration.zero);
      final second = manager.getGroupMemberList(groupID: 'room-1');
      await Future<void>.delayed(Duration.zero);

      final firstResult = await first;
      expect(firstResult.isSuccess, isFalse);

      conn.emit('ReceiveGroupMemberList', <Object?>['{"Count":0,"Users":[]}']);
      expect((await second).isSuccess, isTrue);
    });

    test('logout 时把待回调以错误收尾（不留悬挂 Future）', () async {
      await loginOk();
      final future = manager.getGroupMemberList(groupID: 'room-1');
      await Future<void>.delayed(Duration.zero);
      await manager.logout();

      final result = await future;
      expect(result.code, V2OCIMErrorCode.notLoggedIn);
    });
  });

  group('心跳', () {
    test('登录后启动心跳（30 秒一次，不在用例里等）', () async {
      await loginOk();
      // 只断言连接已建立且未因心跳报错；周期本身由 Timer.periodic 保证
      expect(conn.calls, contains('start'));
      expect(conn.calls.any((c) => c == 'send:Heartbeat'), isFalse);
    });
  });
}
