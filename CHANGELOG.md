# Changelog

本包遵循语义化版本。`V2OCIM` 前缀的公开 API 变更一律在此登记。

## 3.1.0

**改为纯 Dart 实现，不再是 Flutter Plugin。公开 API 与 3.0.0 逐字一致，升级无需改业务代码。**

### 变更

- **移除 Android AAR / iOS XCFramework 依赖** —— 本包不再给宿主工程引入任何原生库
- 传输层改用 [`signalr_netcore`](https://pub.dev/packages/signalr_netcore)；IM 逻辑（连接与鉴权、
  退避重连、心跳、序列号去重与间隙补发、自发消息过滤、事件分发）全部在 Dart 侧实现
- `pubspec.yaml` 移除 `flutter.plugin` 段；删除 `android/` 与 `ios/` 目录

### 新增（自研扩展，腾讯 V2TIM 无对应项）

- **`notifyNetworkAvailable()`** —— 宿主在「网络恢复 / 前台唤醒」时调用，立即重连不等退避计时。
  **直播类应用请务必接上**（见下方"行为差异"）
- `reconnectDelaysMs` —— 可整体替换退避序列
- `maxReconnectAttempts` —— 默认 `-1`（无限重连）

### 行为差异

| 项 | 说明 |
|---|---|
| 退避序列 | 默认 **`0 / 1s / 2s / 5s / 10s`**（末位无限复用）。原生端是 `0/2s/10s/30s` —— 那两端有系统级网络监听（Android `ConnectivityManager`、iOS `NWPathMonitor`），30 秒尾巴基本碰不到；纯 Dart 侧没有，所以尾巴缩短，保证不接 `notifyNetworkAvailable()` 也能在 10 秒内自愈 |
| 网络监听 | 本包**不引入** `connectivity_plus` 之类的插件依赖（否则所有接入方被迫带上原生代码）。请由宿主调用 `notifyNetworkAvailable()` |
| `getGroupMemberList` | 新增 **10 秒超时**。原生版是回调式、服务端不响应就永不回调；Dart 版返回 `Future`，悬挂会让调用方永久 `await` |

### 迁移

从 3.0.0 升级：**改依赖版本号即可**，代码零改动。

---

## 3.0.0

**破坏性重写：API 完全对齐腾讯云 IM（V2TIM）。**

- 从腾讯迁移三步：①全局替换 `V2TIM` / `V2Tim` → `V2OCIM`；②在 `initSDK` 之前插一行
  `setServerConfig(hubUrl:, appId:)`；③UserSig 改为向你的业务服务端签发接口获取
- **删除** 2.x 的 `OrangeCloudIMClient`，以及 `TextMessage` / `GiftMessage` / `SystemNotice` /
  `CustomMessage` 四个结构化模型 —— 礼物等业务消息统一用 custom 消息承载
- `elemType` 只有 `text` 与 `custom` 两种（与腾讯生态一致）
- **群消息不再回显给发送者**（对齐腾讯）；自己那条由 `sendXxx` 的返回值给
- 错误码沿用腾讯 V2TIM 数值，迁移方原有的错误码判断逻辑可直接复用
- 新增 `onKickedOffline`（单点登录互踢）、`onUserSigExpired`、`onServerConfigUpdated`
- 新增 `msgID`（服务端生成的 32 位 GUID hex），与 `sequenceNumber` 并存
- 鉴权类失败（UserSig 过期 / 应用禁用 / 超限 / 被踢下线）**停止自动重连**

### 不支持

群管理、历史消息、会话列表与未读计数、消息撤回与已读回执、富媒体消息、资料与关系链。
其中相当一部分腾讯 AVChatRoom 本身也不支持。C2C 消息**仅在线投递、不存离线**。

---

## 2.0.0

首个对外版本（已被 3.x 取代）。Flutter 侧为桥接插件，核心逻辑在 Android AAR / iOS XCFramework 中。
