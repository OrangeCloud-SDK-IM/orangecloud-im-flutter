import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orangecloud_im_client/orangecloud_im_client.dart';

/// V2OCIM 模型解析测试
///
/// 覆盖 Dart ⇄ 原生 的 map 契约：原生（Kotlin/Swift）按 elemType 只带
/// `text` 或 `customData` 其中之一，Dart 侧据此构造 textElem / customElem。
/// 这层是纯逻辑，不需要真机也不需要原生二进制。
void main() {
  group('V2OCIMMessage.fromMap', () {
    test('文本消息构造 textElem，customElem 为 null', () {
      final msg = V2OCIMMessage.fromMap({
        'msgID': 'abc123',
        'timestamp': 1730000000,
        'sender': 'u_1',
        'nickName': '小明',
        'faceURL': 'https://cdn/a.png',
        'nameCard': '',
        'groupID': 'room_1',
        'userID': '',
        'status': V2OCIMConstants.v2ocimMsgStatusSendSucc,
        'isSelf': false,
        'elemType': V2OCIMConstants.v2ocimElemTypeText,
        'text': '大家好',
        'sequenceNumber': 42,
      });

      expect(msg.msgID, 'abc123');
      expect(msg.elemType, V2OCIMConstants.v2ocimElemTypeText);
      expect(msg.textElem?.text, '大家好');
      expect(msg.customElem, isNull);
      expect(msg.sequenceNumber, 42);
      expect(msg.isGroupMessage, isTrue);
      expect(msg.toGroupMemberInfo().nickName, '小明');
    });

    test('自定义消息构造 customElem，textElem 为 null', () {
      final payload = Uint8List.fromList([1, 2, 3, 250]);
      final msg = V2OCIMMessage.fromMap({
        'msgID': 'gift_1',
        'groupID': 'room_1',
        'elemType': V2OCIMConstants.v2ocimElemTypeCustom,
        'customData': payload,
      });

      expect(msg.elemType, V2OCIMConstants.v2ocimElemTypeCustom);
      expect(msg.textElem, isNull);
      expect(msg.customElem?.data, payload);
      // description / extension 自研无对应概念，恒空串
      expect(msg.customElem?.description, '');
      expect(msg.customElem?.extension, '');
    });

    test('C2C 消息 groupID 为空、isGroupMessage 为 false', () {
      final msg = V2OCIMMessage.fromMap({
        'msgID': 'c2c_1',
        'sender': 'u_1',
        'userID': 'u_2',
        'elemType': V2OCIMConstants.v2ocimElemTypeText,
        'text': 'hi',
      });

      expect(msg.isGroupMessage, isFalse);
      expect(msg.userID, 'u_2');
      expect(msg.toUserInfo().userID, 'u_1');
    });

    test('缺字段 / 空 map 全部走默认值，不抛异常', () {
      final msg = V2OCIMMessage.fromMap(const {});
      expect(msg.msgID, '');
      expect(msg.elemType, V2OCIMConstants.v2ocimElemTypeNone);
      expect(msg.textElem, isNull);
      expect(msg.customElem, isNull);
      // 未显式给 status 时按发送成功处理（收到的消息必然已到达服务端）
      expect(msg.status, V2OCIMConstants.v2ocimMsgStatusSendSucc);

      final nullMsg = V2OCIMMessage.fromMap(null);
      expect(nullMsg.msgID, '');
    });

    test('数值字段以字符串下发时也能解析（两端类型差异兜底）', () {
      final msg = V2OCIMMessage.fromMap({
        'timestamp': '1730000000',
        'sequenceNumber': '7',
        'elemType': '1',
      });
      expect(msg.timestamp, 1730000000);
      expect(msg.sequenceNumber, 7);
      expect(msg.elemType, V2OCIMConstants.v2ocimElemTypeText);
    });

    test('customData 以 List<int> 下发时转成 Uint8List', () {
      final msg = V2OCIMMessage.fromMap({
        'elemType': V2OCIMConstants.v2ocimElemTypeCustom,
        'customData': <int>[7, 8, 9],
      });
      expect(msg.customElem?.data, isA<Uint8List>());
      expect(msg.customElem?.data.toList(), [7, 8, 9]);
    });
  });

  group('V2OCIMServerLimits.fromMap', () {
    test('正常下发按服务端值', () {
      final limits = V2OCIMServerLimits.fromMap({
        'maxMessageLength': 2000,
        'maxMessagesPerSecond': 20,
        'bufferMaxSize': 1000,
      });
      expect(limits.maxMessageLength, 2000);
      expect(limits.maxMessagesPerSecond, 20);
      expect(limits.bufferMaxSize, 1000);
    });

    test('0 或缺失回落默认值 500/5/500', () {
      // 服务端用 0 表示「该应用未单独配置，走全局默认」
      final limits = V2OCIMServerLimits.fromMap({
        'maxMessageLength': 0,
        'maxMessagesPerSecond': 0,
      });
      expect(limits.maxMessageLength, 500);
      expect(limits.maxMessagesPerSecond, 5);
      expect(limits.bufferMaxSize, 500);
    });
  });

  group('结果对象', () {
    test('code == 0 判定成功', () {
      expect(const V2OCIMCallback(code: 0).isSuccess, isTrue);
      expect(
        const V2OCIMCallback(code: V2OCIMErrorCode.muted).isSuccess,
        isFalse,
      );
      expect(
        const V2OCIMValueCallback<String>(code: 0, data: 'x').isSuccess,
        isTrue,
      );
    });

    test('错误码沿用腾讯数值，便于迁移方直接复用判断逻辑', () {
      expect(V2OCIMErrorCode.muted, 7013);
      expect(V2OCIMErrorCode.userSigExpired, 9508);
      expect(V2OCIMErrorCode.notLoggedIn, 6014);
    });
  });

  group('成员信息解析', () {
    test('群成员与用户信息字段映射', () {
      final member = V2OCIMGroupMemberInfo.fromMap({
        'userID': 'u_9',
        'nickName': '主播',
        'faceURL': 'https://cdn/b.png',
        'nameCard': '',
      });
      expect(member.userID, 'u_9');
      expect(member.nickName, '主播');

      final user = V2OCIMUserInfo.fromMap({'userID': 'u_10'});
      expect(user.userID, 'u_10');
      expect(user.nickName, '');
    });

    test('禁言变更解禁时 muteTime 为 0', () {
      final change = V2OCIMGroupMemberChangeInfo.fromMap({
        'userID': 'u_1',
        'muteTime': 0,
      });
      expect(change.muteTime, 0);
    });
  });
}
