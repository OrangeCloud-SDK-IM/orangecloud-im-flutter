# OrangeCloud IM SDK - Flutter

[![Platform](https://img.shields.io/badge/platform-Flutter-02569B?logo=flutter)](https://flutter.dev)
[![Version](https://img.shields.io/badge/version-2.0.0-blue)](https://github.com/OrangeCloud-SDK-IM/orangecloud-im-flutter/releases)

OrangeCloud IM Flutter SDK，为直播、社交、协作场景提供即时通信能力。

> **架构说明**：本 SDK 为 **Flutter Plugin**，是对原生 Android（AAR）/ iOS（XCFramework）核心 SDK 的桥接封装（对标腾讯云 IM Flutter SDK）。IM 核心逻辑（连接、去重、断线重连、消息补发、心跳）全部在原生二进制中实现，Dart 层仅做 MethodChannel/EventChannel 桥接。**仅支持 Android / iOS 平台**（不支持 Web/Desktop）。
>
> 集成时原生核心会自动拉取：Android 通过 Gradle 引入 `com.orangecloud.im:orangecloud-im-client`，iOS 通过 CocoaPods 引入 `OrangeCloudIMClient`。

## 安装

```yaml
dependencies:
  orangecloud_im_client:
    git:
      url: https://github.com/OrangeCloud-SDK-IM/orangecloud-im-flutter.git
      ref: v2.0.0
```

## 快速开始

```dart
import 'package:orangecloud_im_client/orangecloud_im_client.dart';

final client = OrangeCloudIMClient();

// 类型安全的消息监听
client.onTextMessageReceived.listen((msg) {
  print('${msg.senderInfo.nickName}: ${msg.content}');
});
client.onGiftMessageReceived.listen((msg) {
  print('🎁 ${msg.senderInfo.nickName} 送出 ${msg.giftName}');
});

// 登录 & 加入房间
await client.login(hubUrl, appId, userId, userSig);
await client.joinGroup('room_001');

// 类型安全的发送方法
await client.sendTextMessage('room_001', 'Hello!');
await client.sendGiftMessage('room_001', GiftInfo(giftId: '1', giftName: '火箭', giftCount: 1, giftPrice: 100));
await client.sendCustomMessage('room_001', 'barrage', {'text': '弹幕内容', 'color': '#FF0000'});
```

## API

### 连接管理
| 方法 | 说明 |
|------|------|
| `login(hubUrl, appId, userId, userSig)` | 登录连接 |
| `logout()` | 断开连接 |
| `joinGroup(groupId)` | 加入房间（支持断线重连自动恢复） |
| `quitGroup(groupId)` | 退出房间 |

### 发送消息（类型安全）
| 方法 | 说明 |
|------|------|
| `sendTextMessage(groupId, content)` | 发送文本消息 |
| `sendGiftMessage(groupId, giftInfo)` | 发送礼物消息 |
| `sendCustomMessage(groupId, type, payload)` | 发送自定义消息 |
| `sendGroupMsg(groupId, json)` | 发送原始 JSON（兼容旧版） |

### 事件流（类型安全）
| Stream | 类型 | 说明 |
|--------|------|------|
| `onTextMessageReceived` | `TextMessage` | 文本消息 |
| `onGiftMessageReceived` | `GiftMessage` | 礼物消息 |
| `onSystemNoticeReceived` | `SystemNotice` | 系统公告 |
| `onCustomMessageReceived` | `CustomMessage` | 自定义消息 |
| `onBroadcastReceived` | `IMMessage` | 全服广播 |
| `onBatchMessageReceived` | `List<IMMessage>` | 批量补发（断线恢复） |
| `onStateRestored` | `StateRestoredInfo` | 状态恢复完成 |
| `onReconnectAttempt` | `ReconnectAttemptInfo` | 重连尝试 |

### 事件流（原始）
| Stream | 说明 |
|--------|------|
| `onMessageReceived` | 原始 JSON 消息 |
| `onUserJoined` | 用户加入 |
| `onUserLeft` | 用户离开 |
| `onOnlineCountChanged` | 在线人数变化 |
| `onMuted` / `onUnmuted` | 禁言/解禁 |
| `onRoomClosed` | 房间关闭 |
| `onConnectionStateChanged` | 连接状态变化 |

## 消息模型

```dart
// 文本消息
class TextMessage extends IMMessage {
  String content;
}

// 礼物消息
class GiftMessage extends IMMessage {
  GiftInfo giftInfo; // giftId, giftName, giftCount, giftPrice, animationUrl
}

// 系统公告
class SystemNotice extends IMMessage {
  String content;
  bool isShow;
}

// 自定义消息
class CustomMessage extends IMMessage {
  String customType;
  Map<String, dynamic> payload;
}
```

## 可靠性特性

- ✅ 指数退避自动重连
- ✅ 断线重连后自动重新加入房间
- ✅ 序列号机制，断线期间消息自动补发
- ✅ 心跳保活

## Demo

完整示例请参考 [orangecloud-im-demos/flutter](https://github.com/OrangeCloud-SDK/orangecloud-im-demos/tree/main/flutter)

## License

商业授权，按月付费。
