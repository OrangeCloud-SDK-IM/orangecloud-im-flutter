# OrangeCloud IM SDK - Flutter

[![Platform](https://img.shields.io/badge/platform-Flutter-02569B?logo=flutter)](https://flutter.dev)
[![Version](https://img.shields.io/badge/version-3.1.0-blue)](https://github.com/OrangeCloud-SDK-IM/orangecloud-im-flutter/releases)

OrangeCloud IM Flutter SDK，为直播、社交、协作场景提供即时通信能力。

> **v3.0.0 是破坏性重构：API 已完全对齐腾讯云 IM（V2TIM）。**
> 从腾讯迁移只需三步：①全局替换 `V2TIM` / `V2Tim` → `V2OCIM`；②在 `initSDK` 之前插一行
> `setServerConfig`；③UserSig 改为向自研签发接口获取。
> v2.x 的 `OrangeCloudIMClient` 与 `TextMessage` / `GiftMessage` / `SystemNotice` / `CustomMessage`
> **已删除**，礼物等业务消息统一用 custom 消息承载。

> **v3.1.0 改为纯 Dart 实现，公开 API 与 v3.1.0 之前逐字未变，升级无需改一行业务代码。**

## 架构说明（v3.1.0 起）

本 SDK 是**纯 Dart 包**，不再是 Flutter Plugin：

- **零原生依赖** —— 不含 Android AAR / iOS XCFramework，安装后不会给你的工程增加原生库
- 传输层用 [`signalr_netcore`](https://pub.dev/packages/signalr_netcore)（只负责 SignalR 协议）
- IM 逻辑（连接与鉴权、退避重连、心跳、序列号去重与间隙补发、自发消息过滤、事件分发）
  全部在 Dart 侧实现
- 平台支持：**Android / iOS**（其余平台受 `signalr_netcore` 限制，未验证）

> 为什么从 plugin 改成纯 Dart：原来每改一次 SDK 都要重新构建两个原生二进制，
> 其中 iOS 的 XCFramework **必须在 macOS 上构建**，成了发版硬阻塞；且 Flutter 接入方
> 被迫携带两个原生库。Android AAR 与 iOS XCFramework 继续独立发布，服务**原生**接入方。

### 与原生实现的差异

1. **没有系统级网络监听 → 改为宿主传信号。** Android 原生用 `ConnectivityManager`、
   iOS 原生用 `NWPathMonitor`，网络恢复瞬间就重连。纯 Dart 侧刻意**不引入
   `connectivity_plus` 这类插件依赖**（那会让本包重新带上原生代码，并把插件的平台支持
   范围强加给所有接入方），改为两条补偿：
   - **退避序列最长间隔缩短到 10 秒**（其余三端是 30 秒），所以不做任何事也能在 10 秒内自愈
   - 提供 **`notifyNetworkAvailable()`**，宿主拿到「网络恢复」或「前台唤醒」信号时调一下即可立即重连

   > **直播类 App 请务必接上 `notifyNetworkAvailable()`** —— 不接的话断网恢复后公屏最多黑 10 秒。

2. **`getGroupMemberList` 有 10 秒超时**。原生版是回调式、服务端不响应就永远不回调；
   Dart 版返回 `Future`，悬挂会让调用方永久 `await`，所以必须有超时。

## 安装

```yaml
dependencies:
  orangecloud_im_client:
    git:
      url: https://github.com/OrangeCloud-SDK-IM/orangecloud-im-flutter.git
      ref: v3.1.0
```

## 快速开始

```dart
import 'package:orangecloud_im_client/orangecloud_im_client.dart';

final im = V2OCIMManager.instance;

// ⚠ 自研扩展，必须在 initSDK 之前调用
await im.setServerConfig(hubUrl: hubUrl, appId: imAppId);
await im.initSDK();

im.addSimpleMsgListener(listener: V2OCIMSimpleMsgListener(
  onRecvGroupTextMessage: (msgID, groupID, sender, text) {
    print('${sender.nickName}: $text');
  },
  onRecvGroupCustomMessage: (msgID, groupID, sender, customData) {
    // 礼物 / 公告 / 关播等业务消息都走 custom，自行解 JSON
  },
));

im.addIMSDKListener(listener: V2OCIMSDKListener(
  onUserSigExpired: () { /* 重新签发 UserSig 后再 login 一次 */ },
  onKickedOffline: () { /* 账号在其他设备登录，走登出流程 */ },
  onServerConfigUpdated: (limits) => setInputMaxLength(limits.maxMessageLength),
));

final r = await im.login(userID: userID, userSig: userSig);
if (!r.isSuccess) return;

await im.joinGroup(groupID: 'room_001');

final sent = await im.sendGroupTextMessage(text: 'Hello!', groupID: 'room_001');
if (sent.isSuccess) {
  render(sent.data!);                       // 自己那条由返回值给，不会再从 listener 收到
} else if (sent.code == V2OCIMErrorCode.muted) {
  toast('你已被禁言');
}
```

## API

**Dart 的形状随腾讯自己的 Flutter SDK**：方法返回 `Future<V2OCIMCallback>` /
`Future<V2OCIMValueCallback<T>>`（`code` / `desc` / `data`），listener 是「构造函数传回调」的 class。

### 初始化与登录
| 方法 | 说明 |
|------|------|
| `setServerConfig(hubUrl:, appId:)` | ⚠ 自研扩展，必须先调用 |
| `initSDK({sdkAppId})` | `sdkAppId` 收下但忽略 |
| `unInitSDK()` | |
| `getVersion()` | 返回 `3.1.0` |
| `login(userID:, userSig:)` | 内部建连 + 鉴权；断线自动重连无需重复调用 |
| `logout()` | |
| `getLoginUser()` / `getLoginStatus()` | |

### 群组与发送
| 方法 | 说明 |
|------|------|
| `joinGroup(groupID:, {message})` | 自动带 `lastSequenceNumber` 做断连补发；`message` 收下但忽略 |
| `quitGroup(groupID:)` | |
| `sendGroupTextMessage(text:, groupID:, {priority})` | 返回完整消息，`priority` 收下但不生效 |
| `sendGroupCustomMessage(customData:, groupID:, {priority})` | 礼物/公告等都走这里 |
| `sendC2CTextMessage(text:, userID:)` | ⚠ 仅在线投递，不存离线消息 |
| `sendC2CCustomMessage(customData:, userID:)` | ⚠ 仅在线投递 |

### Listener
| 注册 | listener | 回调 |
|---|---|---|
| `addSimpleMsgListener` | `V2OCIMSimpleMsgListener` | `onRecvGroupTextMessage` / `onRecvGroupCustomMessage` / `onRecvC2CTextMessage` / `onRecvC2CCustomMessage` |
| `addAdvancedMsgListener` | `V2OCIMAdvancedMsgListener` | `onRecvNewMessage(V2OCIMMessage)` |
| `addGroupListener` | `V2OCIMGroupListener` | `onMemberEnter` / `onMemberLeave` / `onGroupDismissed` / `onMemberInfoChanged`（禁言变更）/ `onGroupOnlineMemberCountChanged`（⚠ 自研扩展） |
| `addIMSDKListener` | `V2OCIMSDKListener` | `onConnecting` / `onConnectSuccess` / `onConnectFailed` / `onKickedOffline` / `onUserSigExpired` / `onServerConfigUpdated`（⚠ 自研扩展） |

> Simple 与 Advanced **会对同一条消息同时触发**，按需选一种，别两种都处理（会重复上屏）。

### 自研扩展
| 方法 | 说明 |
|------|------|
| `getGroupMemberList(groupID:)` | 返回服务端原始 JSON |
| `requestBackfill(groupID:, afterSequenceNumber:)` | 一般不用手动调，间隙检测会自动触发 |
| `getLastSequenceNumber(groupID:)` | |
| `getServerLimits()` | 服务端下发的消息长度 / 频率 / 缓冲上限 |
| `notifyNetworkAvailable()` | **网络恢复 / 前台唤醒时立即重连**，直播场景务必接（见上文差异说明） |
| `reconnectDelaysMs` | 可整体替换退避序列，默认 `[0, 1s, 2s, 5s, 10s]`，末位无限复用 |
| `maxReconnectAttempts` | 默认 `-1` 无限重连 |

```dart
// 典型接线：网络恢复 + 前台唤醒都触发
Connectivity().onConnectivityChanged.listen((r) {
  if (!r.contains(ConnectivityResult.none)) im.notifyNetworkAvailable();
});
// WidgetsBindingObserver
void didChangeAppLifecycleState(AppLifecycleState s) {
  if (s == AppLifecycleState.resumed) im.notifyNetworkAvailable();
}
```

> 已连上 / 正在连接 / 主动登出 / 鉴权失败停连时 `notifyNetworkAvailable()` 是空操作，
> 可以随便重复调用（已连上时强行重建连接反而会造成消息空洞）。

## 消息模型

只有 **text** 与 **custom** 两种 `elemType`（与腾讯生态一致）。礼物、系统通知、公告、关播等
业务消息全部走 `custom`，业务自行在 `customData` 里定 JSON。

```dart
class V2OCIMMessage {
  String msgID;            // 服务端生成，32 位 GUID hex
  int timestamp;           // Unix 秒（与腾讯一致）
  String sender, nickName, faceURL, nameCard;
  String groupID;          // 群消息才有
  String userID;           // C2C 才有
  int status, elemType;
  bool isSelf;
  V2OCIMTextElem? textElem;      // elemType == text
  V2OCIMCustomElem? customElem;  // elemType == custom，data 是 Uint8List
  int sequenceNumber;      // ⚠ 自研扩展；C2C 恒为 0
}
```

## 可靠性特性（SDK 内置）

- ✅ 指数退避自动重连（**0 / 1s / 2s / 5s / 10s**，末位无限复用）+ `notifyNetworkAvailable()` 可立即恢复
- ✅ 重连后自动带 `lastSequenceNumber` 重新入群，服务端补发断连期间消息
- ✅ 序列号去重 + 间隙检测自动补发
- ✅ 心跳保活（30s）
- ✅ **鉴权类失败停止无效重连**（UserSig 过期 / 应用禁用 / 超限 / 被踢下线）
- ✅ **不回显自己发的消息**（对齐腾讯），自己那条由 `sendXxx` 返回值给

## 不支持

群管理、历史消息、会话与未读计数、消息撤回与已读回执、富媒体消息、资料关系链 —— 详见
`clients/OrangeCloud-IM-SDK-集成文档.md` §7（其中相当一部分腾讯 AVChatRoom 本身也不支持）。
C2C 消息**仅在线投递、不存离线**。

## License

商业授权，按月付费。
