import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orangecloud_im_client/orangecloud_im_client.dart';
import 'package:orangecloud_im_client/src/v2ocim/internal/v2ocim_wire.dart';

void main() {
  group('组装消息（wire format，四端必须逐字一致）', () {
    test('文本消息字段名是 data.content，不是 data.text', () {
      final json = jsonDecode(V2OCIMWire.buildTextJson('hello', 'cid-1'))
          as Map<String, Object?>;
      expect(json['messageType'], 'text');
      // clientMsgId 是投递层元数据，放顶层（业务字段才放 data）
      expect(json['clientMsgId'], 'cid-1');
      // 服务端的长度校验读的就是 data.content 这个路径
      expect((json['data'] as Map)['content'], 'hello');
    });

    test('自定义消息把二进制 Base64 放 data.customData', () {
      final bytes = Uint8List.fromList(utf8.encode('{"Type":"gift"}'));
      final json = jsonDecode(V2OCIMWire.buildCustomJson(bytes, 'cid-2'))
          as Map<String, Object?>;
      expect(json['messageType'], 'custom');
      expect(json['clientMsgId'], 'cid-2');
      final encoded = (json['data'] as Map)['customData'] as String;
      expect(utf8.decode(base64.decode(encoded)), '{"Type":"gift"}');
      // Base64 不能带换行，否则服务端解不出来
      expect(encoded.contains('\n'), isFalse);
    });
  });

  group('解析发送结果', () {
    test('camelCase 字段全取到', () {
      final result = V2OCIMWire.parseSendResult(<String, Object?>{
        'success': true,
        'msgID': 'abc',
        'sequenceNumber': 12,
        'serverTimestamp': 1700000000000,
        'rejectCode': null,
      });
      expect(result.success, isTrue);
      expect(result.msgID, 'abc');
      expect(result.sequenceNumber, 12);
      expect(result.serverTimestamp, 1700000000000);
    });

    test('被拒时带 rejectCode，success 为 false', () {
      final result = V2OCIMWire.parseSendResult(<String, Object?>{
        'success': false,
        'rejectCode': 'muted',
      });
      expect(result.success, isFalse);
      expect(result.rejectCode, 'muted');
    });

    test('非 Map / null 退化为失败，不抛异常', () {
      expect(V2OCIMWire.parseSendResult(null).success, isFalse);
      expect(V2OCIMWire.parseSendResult('boom').success, isFalse);
    });
  });

  group('解析服务端消息', () {
    test('text 消息 → textElem，元数据来自顶层与 senderInfo', () {
      final msg = V2OCIMWire.parseMessage(
        jsonEncode({
          'messageType': 'text',
          'msgID': 'm1',
          'groupId': 'room-1',
          'sequenceNumber': 9,
          'serverTimestamp': 1700000000000,
          'senderInfo': {
            'userId': 'u1',
            'nickName': 'Alice',
            'faceUrl': 'http://a.png',
          },
          'data': {'content': 'hi'},
        }),
        'me',
      );
      expect(msg, isNotNull);
      expect(msg!.elemType, V2OCIMConstants.v2ocimElemTypeText);
      expect(msg.textElem?.text, 'hi');
      expect(msg.msgID, 'm1');
      expect(msg.groupID, 'room-1');
      expect(msg.sequenceNumber, 9);
      // 服务端下发毫秒，模型用秒（与腾讯一致）
      expect(msg.timestamp, 1700000000);
      expect(msg.sender, 'u1');
      expect(msg.nickName, 'Alice');
      expect(msg.faceURL, 'http://a.png');
      expect(msg.isSelf, isFalse);
    });

    test('custom 消息 → customElem，Base64 解回原始字节', () {
      final payload = '{"Type":"SEND_BIG_GIFT"}';
      final msg = V2OCIMWire.parseMessage(
        jsonEncode({
          'messageType': 'custom',
          'msgID': 'm2',
          'groupId': 'room-1',
          'data': {'customData': base64.encode(utf8.encode(payload))},
        }),
        null,
      );
      expect(msg!.elemType, V2OCIMConstants.v2ocimElemTypeCustom);
      expect(utf8.decode(msg.customElem!.data), payload);
    });

    test('服务端广播不带 customData 时，整个 data 原文交给业务层', () {
      // GiftBLL / RoomBLL 直接广播业务 JSON，没有 customData 字段 —— 不能丢信息
      final msg = V2OCIMWire.parseMessage(
        jsonEncode({
          'messageType': 'custom',
          'data': {'Type': 'ANotice', 'Notice': 'hello'},
        }),
        null,
      );
      final decoded =
          jsonDecode(utf8.decode(msg!.customElem!.data)) as Map<String, Object?>;
      expect(decoded['Type'], 'ANotice');
      expect(decoded['Notice'], 'hello');
    });

    test('customData 不是合法 Base64 时退化为原文字节，不丢消息', () {
      final msg = V2OCIMWire.parseMessage(
        jsonEncode({
          'messageType': 'custom',
          'data': {'customData': 'not-base64-!!!'},
        }),
        null,
      );
      expect(utf8.decode(msg!.customElem!.data), 'not-base64-!!!');
    });

    test('未知 messageType 一律按 custom 处理', () {
      final msg = V2OCIMWire.parseMessage(
        jsonEncode({'messageType': 'gift', 'data': {'x': 1}}),
        null,
      );
      expect(msg!.elemType, V2OCIMConstants.v2ocimElemTypeCustom);
    });

    test('isSelf 按 senderInfo.userId 与登录用户比对', () {
      String encode(String sender) => jsonEncode({
            'messageType': 'text',
            'senderInfo': {'userId': sender},
            'data': {'content': 'x'},
          });
      expect(V2OCIMWire.parseMessage(encode('me'), 'me')!.isSelf, isTrue);
      expect(V2OCIMWire.parseMessage(encode('other'), 'me')!.isSelf, isFalse);
      // 发送者为空时不能误判成自己
      expect(V2OCIMWire.parseMessage(encode(''), '')!.isSelf, isFalse);
    });

    test('非法 JSON / 空串返回 null，不抛异常', () {
      expect(V2OCIMWire.parseMessage('', 'me'), isNull);
      expect(V2OCIMWire.parseMessage('{oops', 'me'), isNull);
      expect(V2OCIMWire.parseMessage('[1,2]', 'me'), isNull);
    });

    test('数值以字符串下发时也能解析（不同端 JSON 库差异）', () {
      final msg = V2OCIMWire.parseMessage(
        jsonEncode({
          'messageType': 'text',
          'sequenceNumber': '15',
          'serverTimestamp': '1700000000000',
          'data': {'content': 'x'},
        }),
        null,
      );
      expect(msg!.sequenceNumber, 15);
      expect(msg.timestamp, 1700000000);
    });
  });

  group('解析群事件', () {
    test('UserJoined 兼容 camelCase 与 PascalCase', () {
      final a = V2OCIMWire.parseGroupMember(
        jsonEncode({'userId': 'u1', 'nickName': 'A', 'faceUrl': 'f'}),
      );
      expect(a!.userID, 'u1');
      expect(a.nickName, 'A');

      final b = V2OCIMWire.parseGroupMember(
        jsonEncode({'UserKey': 'u2', 'NickName': 'B', 'FaceUrl': 'g'}),
      );
      expect(b!.userID, 'u2');
      expect(b.nickName, 'B');
      expect(b.faceURL, 'g');
    });

    test('UserJoined 缺 userId 返回 null', () {
      expect(V2OCIMWire.parseGroupMember(jsonEncode({'nickName': 'x'})), isNull);
    });

    test('OnMuted 取 muteUntil，回退 muteTime', () {
      expect(
        V2OCIMWire.parseMuteInfo(
          jsonEncode({'userId': 'u1', 'muteUntil': 1700009999}),
        )!.muteTime,
        1700009999,
      );
      expect(
        V2OCIMWire.parseMuteInfo(
          jsonEncode({'UserKey': 'u2', 'muteTime': 123}),
        )!.muteTime,
        123,
      );
      // 解禁：两个字段都缺 → muteTime 为 0
      expect(
        V2OCIMWire.parseMuteInfo(jsonEncode({'userId': 'u3'}))!.muteTime,
        0,
      );
    });
  });

  group('批量消息拆包', () {
    test('取 messages 数组逐条还原（实际格式多了 type/count 两个字段）', () {
      final items = V2OCIMWire.splitBatch(jsonEncode({
        'type': 'batch',
        'count': 2,
        'messages': [
          {'msgID': 'a'},
          {'msgID': 'b'},
        ],
      }));
      expect(items, hasLength(2));
      expect(jsonDecode(items[0])['msgID'], 'a');
      expect(jsonDecode(items[1])['msgID'], 'b');
    });

    test('messages 里已是字符串时原样返回', () {
      final items = V2OCIMWire.splitBatch(
        jsonEncode({'messages': ['{"msgID":"a"}']}),
      );
      expect(items.single, '{"msgID":"a"}');
    });

    test('缺字段 / 非法 JSON 返回空列表', () {
      expect(V2OCIMWire.splitBatch('{}'), isEmpty);
      expect(V2OCIMWire.splitBatch('boom'), isEmpty);
      expect(V2OCIMWire.splitBatch(jsonEncode({'messages': 5})), isEmpty);
    });
  });

  group('服务端原因码 → SDK 错误码', () {
    test('鉴权失败码逐项映射', () {
      expect(
        V2OCIMAuthFailureCode.toErrorCode('user_sig_expired'),
        V2OCIMErrorCode.userSigExpired,
      );
      expect(
        V2OCIMAuthFailureCode.toErrorCode('app_disabled'),
        V2OCIMErrorCode.appUnavailable,
      );
      expect(
        V2OCIMAuthFailureCode.toErrorCode('dau_limit'),
        V2OCIMErrorCode.quotaExceeded,
      );
      expect(
        V2OCIMAuthFailureCode.toErrorCode('domain_not_allowed'),
        V2OCIMErrorCode.domainNotAllowed,
      );
      expect(
        V2OCIMAuthFailureCode.toErrorCode('missing_params'),
        V2OCIMErrorCode.sdkNotInitialized,
      );
      expect(
        V2OCIMAuthFailureCode.toErrorCode('something-new'),
        V2OCIMErrorCode.unknown,
      );
      expect(V2OCIMAuthFailureCode.toErrorCode(null), V2OCIMErrorCode.unknown);
    });

    test('发送拒绝码逐项映射', () {
      expect(
        V2OCIMSendRejectCode.toErrorCode('muted'),
        V2OCIMErrorCode.muted,
      );
      expect(
        V2OCIMSendRejectCode.toErrorCode('message_too_long'),
        V2OCIMErrorCode.messageTooLong,
      );
      expect(
        V2OCIMSendRejectCode.toErrorCode('rate_limited'),
        V2OCIMErrorCode.rateLimited,
      );
      expect(
        V2OCIMSendRejectCode.toErrorCode('daily_limit'),
        V2OCIMErrorCode.dailyLimit,
      );
      expect(
        V2OCIMSendRejectCode.toErrorCode('empty_message'),
        V2OCIMErrorCode.emptyMessage,
      );
      expect(
        V2OCIMSendRejectCode.toErrorCode('not_authenticated'),
        V2OCIMErrorCode.notLoggedIn,
      );
      expect(V2OCIMSendRejectCode.toErrorCode(null), V2OCIMErrorCode.unknown);
    });
  });
}
