import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

import 'package:orangecloud_im_client/src/models/im_message.dart';
import 'package:orangecloud_im_client/src/models/text_message.dart';
import 'package:orangecloud_im_client/src/models/gift_message.dart';
import 'package:orangecloud_im_client/src/models/system_notice.dart';
import 'package:orangecloud_im_client/src/models/custom_message.dart';

/// **Validates: Requirements 6.2**
/// Property 9: Message Serialization Round-Trip
/// For any valid IMMessage instance, serializing to JSON and then deserializing back
/// SHALL produce an equivalent object with all fields preserved.
void main() {
  group('Property 9: Message Serialization Round-Trip', () {
    final random = Random(42);

    String randomString(int length) {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
    }

    SenderInfo randomSenderInfo() {
      return SenderInfo(
        userId: 'user_${random.nextInt(10000)}',
        nickName: randomString(8),
        faceUrl: 'https://example.com/${randomString(5)}.png',
        level: '${random.nextInt(100)}',
        isAdmin: random.nextBool(),
        isAnchor: random.nextBool(),
      );
    }

    test('TextMessage round-trip preserves all fields (100 iterations)', () {
      for (var i = 0; i < 100; i++) {
        final original = TextMessage(
          senderInfo: randomSenderInfo(),
          timestamp: random.nextInt(2000000000),
          sequenceNumber: random.nextInt(100000) + 1,
          groupId: 'group_${random.nextInt(100)}',
          content: randomString(random.nextInt(200) + 1),
        );

        final json = original.toJson();
        final jsonStr = jsonEncode(json);
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final restored = IMMessage.fromJson(decoded) as TextMessage;

        expect(restored.messageType, equals(original.messageType),
            reason: 'Iteration $i: messageType mismatch');
        expect(restored.sequenceNumber, equals(original.sequenceNumber),
            reason: 'Iteration $i: sequenceNumber mismatch');
        expect(restored.timestamp, equals(original.timestamp),
            reason: 'Iteration $i: timestamp mismatch');
        expect(restored.groupId, equals(original.groupId),
            reason: 'Iteration $i: groupId mismatch');
        expect(restored.content, equals(original.content),
            reason: 'Iteration $i: content mismatch');
        expect(restored.senderInfo.userId, equals(original.senderInfo.userId),
            reason: 'Iteration $i: senderInfo.userId mismatch');
        expect(restored.senderInfo.nickName, equals(original.senderInfo.nickName),
            reason: 'Iteration $i: senderInfo.nickName mismatch');
        expect(restored.senderInfo.isAdmin, equals(original.senderInfo.isAdmin),
            reason: 'Iteration $i: senderInfo.isAdmin mismatch');
        expect(restored.senderInfo.isAnchor, equals(original.senderInfo.isAnchor),
            reason: 'Iteration $i: senderInfo.isAnchor mismatch');
      }
    });

    test('GiftMessage round-trip preserves all fields (100 iterations)', () {
      for (var i = 0; i < 100; i++) {
        final original = GiftMessage(
          senderInfo: randomSenderInfo(),
          timestamp: random.nextInt(2000000000),
          sequenceNumber: random.nextInt(100000) + 1,
          groupId: 'group_${random.nextInt(100)}',
          giftInfo: GiftInfo(
            giftId: 'gift_${random.nextInt(1000)}',
            giftName: randomString(6),
            giftCount: random.nextInt(99) + 1,
            giftPrice: random.nextInt(10000),
            animationUrl: 'https://cdn.example.com/${randomString(8)}.json',
          ),
        );

        final json = original.toJson();
        final jsonStr = jsonEncode(json);
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final restored = IMMessage.fromJson(decoded) as GiftMessage;

        expect(restored.messageType, equals(original.messageType));
        expect(restored.sequenceNumber, equals(original.sequenceNumber));
        expect(restored.timestamp, equals(original.timestamp));
        expect(restored.groupId, equals(original.groupId));
        expect(restored.giftInfo.giftId, equals(original.giftInfo.giftId));
        expect(restored.giftInfo.giftName, equals(original.giftInfo.giftName));
        expect(restored.giftInfo.giftCount, equals(original.giftInfo.giftCount));
        expect(restored.giftInfo.giftPrice, equals(original.giftInfo.giftPrice));
        expect(restored.giftInfo.animationUrl, equals(original.giftInfo.animationUrl));
      }
    });

    test('SystemNotice round-trip preserves all fields (100 iterations)', () {
      final noticeTypes = ['announcement', 'reward', 'warning'];
      for (var i = 0; i < 100; i++) {
        final original = SystemNotice(
          senderInfo: randomSenderInfo(),
          timestamp: random.nextInt(2000000000),
          sequenceNumber: random.nextInt(100000) + 1,
          groupId: 'group_${random.nextInt(100)}',
          noticeType: noticeTypes[random.nextInt(noticeTypes.length)],
          title: randomString(random.nextInt(30) + 1),
          content: randomString(random.nextInt(100) + 1),
        );

        final json = original.toJson();
        final jsonStr = jsonEncode(json);
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final restored = IMMessage.fromJson(decoded) as SystemNotice;

        expect(restored.messageType, equals(original.messageType));
        expect(restored.sequenceNumber, equals(original.sequenceNumber));
        expect(restored.timestamp, equals(original.timestamp));
        expect(restored.groupId, equals(original.groupId));
        expect(restored.noticeType, equals(original.noticeType));
        expect(restored.title, equals(original.title));
        expect(restored.content, equals(original.content));
      }
    });

    test('CustomMessage round-trip preserves all fields (100 iterations)', () {
      for (var i = 0; i < 100; i++) {
        final payload = <String, dynamic>{
          'key1': randomString(5),
          'key2': random.nextInt(1000),
          'key3': random.nextBool(),
        };

        final original = CustomMessage(
          senderInfo: randomSenderInfo(),
          timestamp: random.nextInt(2000000000),
          sequenceNumber: random.nextInt(100000) + 1,
          groupId: 'group_${random.nextInt(100)}',
          customType: randomString(10),
          payload: payload,
        );

        final json = original.toJson();
        final jsonStr = jsonEncode(json);
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final restored = IMMessage.fromJson(decoded) as CustomMessage;

        expect(restored.messageType, equals(original.messageType));
        expect(restored.sequenceNumber, equals(original.sequenceNumber));
        expect(restored.timestamp, equals(original.timestamp));
        expect(restored.groupId, equals(original.groupId));
        expect(restored.customType, equals(original.customType));
        expect(restored.payload['key1'], equals(original.payload['key1']));
        expect(restored.payload['key2'], equals(original.payload['key2']));
        expect(restored.payload['key3'], equals(original.payload['key3']));
      }
    });

    test('IMMessage.fromJson correctly dispatches by messageType', () {
      final textJson = {
        'messageType': 'text',
        'sequenceNumber': 1,
        'serverTimestamp': 1700000000000,
        'groupId': 'g1',
        'senderInfo': {'userId': 'u1', 'nickName': 'User1'},
        'data': {'content': 'hello'},
      };
      expect(IMMessage.fromJson(textJson), isA<TextMessage>());

      final giftJson = {
        'messageType': 'gift',
        'sequenceNumber': 2,
        'serverTimestamp': 1700000000000,
        'groupId': 'g1',
        'senderInfo': {'userId': 'u1', 'nickName': 'User1'},
        'data': {'giftId': 'g1', 'giftName': 'Rocket', 'giftCount': 1, 'giftPrice': 100},
      };
      expect(IMMessage.fromJson(giftJson), isA<GiftMessage>());

      final noticeJson = {
        'messageType': 'systemNotice',
        'sequenceNumber': 3,
        'serverTimestamp': 1700000000000,
        'groupId': 'g1',
        'senderInfo': {'userId': 'system', 'nickName': 'System'},
        'data': {'noticeType': 'announcement', 'title': 'Test', 'content': 'Notice'},
      };
      expect(IMMessage.fromJson(noticeJson), isA<SystemNotice>());

      final customJson = {
        'messageType': 'custom',
        'sequenceNumber': 4,
        'serverTimestamp': 1700000000000,
        'groupId': 'g1',
        'senderInfo': {'userId': 'u1', 'nickName': 'User1'},
        'data': {'customType': 'myType', 'payload': {'key': 'value'}},
      };
      expect(IMMessage.fromJson(customJson), isA<CustomMessage>());
    });
  });
}
