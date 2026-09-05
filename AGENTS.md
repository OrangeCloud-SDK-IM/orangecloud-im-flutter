# OrangeCloud IM Flutter SDK — AI 项目规则

> 本目录的 AI 工作约束与上下文。AI 协作者**进入此目录前必读**。
> 跨项目规则（发版流程的完整步骤）见 `D:/Work/OrangeCloud/trunk/.kiro/steering/sdk-distribution-protection.md`
> 与 Skill `flutter-im-sdk-release`。

---

## 1. 项目定位

- **包名**：`orangecloud_im_client`（pub.dev / GitHub 用名）
- **当前版本**：`3.1.0`（以 `pubspec.yaml` 为准，每次改动先看）
- **类型**：**纯 Dart 包**（v3.1.0 起不再是 Flutter Plugin）
- **平台**：Android / iOS（其余平台受 `signalr_netcore` 限制，未验证，**不要**声明支持）
- **服务端**：`OrangeCloud.SignalR/Hubs/LiveHub.cs`（C# SignalR Hub）
- **契约文档**：`D:/Work/OrangeCloud/trunk/clients/V2OCIM-API-契约定稿.md`
- **集成文档**：`D:/Work/OrangeCloud/trunk/clients/OrangeCloud-IM-SDK-集成文档.md`
- **GitHub 仓库**：https://github.com/OrangeCloud-SDK-IM/orangecloud-im-flutter
- **GitHub 组织**：`OrangeCloud-SDK-IM`（**不是**旧的 `OrangeCloud-SDK`，仓库已迁移过）

## 2. v3.x 版本脉络

| 版本 | 关键变化 | 公开 API 影响 |
|---|---|---|
| 2.0.0 | 首个对外版本。Flutter 侧是 **plugin**（桥接 Android AAR + iOS XCFramework） | `OrangeCloudIMClient` + 4 个结构化消息模型 |
| 3.0.0 | **破坏性重写**，API 完全对齐腾讯云 IM（V2TIM） | 删除 `OrangeCloudIMClient` / `TextMessage` / `GiftMessage` / `SystemNotice` / `CustomMessage`；新增 `V2OCIM` 前缀；所有消息统一用 text/custom |
| **3.1.0**（当前）| **改为纯 Dart**（不再带 Android AAR / iOS XCFramework），公开 API 与 3.0.0 逐字一致 | 升级无需改业务代码；移除 `flutter.plugin` 段；新增 `notifyNetworkAvailable()`（直播场景必接） |

> 改 `lib/` 下的公开 API 时，**CHANGELOG.md 必须同步登记**（语义化版本：补丁=bugfix、次版本=新功能但不破坏、主版本=破坏性变更）。

## 3. 公开 API 边界（V2OCIM 前缀）

只有这些是「公开 API」，其余 `lib/src/v2ocim/internal/*` 是**实现细节**，可自由改：

- `V2OCIMManager.instance`（进程级单例）
- `setServerConfig(hubUrl, appId)` — ⚠ 自研扩展，必须在 `initSDK` 之前调用
- `initSDK() / unInitSDK() / getVersion() / getLoginUser() / getLoginStatus()`
- `login(userID, userSig) / logout()`
- `joinGroup(groupID) / quitGroup(groupID)`
- `sendGroupTextMessage / sendGroupCustomMessage / sendC2CTextMessage / sendC2CCustomMessage`
- `addSimpleMsgListener / addAdvancedMsgListener / addGroupListener / addIMSDKListener`（及对应 remove）
- 自研扩展：`getGroupMemberList / requestBackfill / getLastSequenceNumber / getServerLimits / notifyNetworkAvailable / reconnectDelaysMs / maxReconnectAttempts`

> ❌ 严禁把这些公开 API 改成阻塞/同步风格（与腾讯 V2TIM 兼容是头等约束）。
> ❌ 严禁在公开 API 里引入平台特定类型（`dart:io` 的 `Socket` / `Platform` 等）。

## 4. 与原生实现的差异（v3.1.0 起）

- **没有系统级网络监听** —— 不引入 `connectivity_plus`。补偿措施：
  1. 退避序列默认 `0 / 1s / 2s / 5s / 10s`（原生端 30 秒尾巴，本包缩短）
  2. 提供 `notifyNetworkAvailable()`，宿主在「网络恢复 / 前台唤醒」时调一下
- **`getGroupMemberList` 有 10 秒超时**（Dart `Future` 不能让调用方永久 `await`）

> 改这两个行为前先看 §6「行为兼容性」。

## 5. 错误码

沿用腾讯 V2TIM 数值（迁移方原有的错误码判断逻辑可直接复用）。定义在
`lib/src/v2ocim/v2ocim_constants.dart`，新增错误码时**必须**保持向后兼容（不重用已发布的数值）。

## 6. 行为兼容性约束（强制）

- **不引入**任何会让宿主工程增加原生代码的依赖（`connectivity_plus` / `path_provider` / `permission_handler` 等会拖入 plugin 的都禁止）
- `signalr_netcore` 是传输层，**仅此一个**允许的第三方依赖
- 退避序列默认值改了会破坏「不接 `notifyNetworkAvailable` 也能自愈」的承诺，**禁止改动**
- 鉴权类失败（UserSig 过期 / 应用禁用 / 超限 / 被踢下线）必须停止自动重连
- 自发消息**不通过 listener 回显**（对齐腾讯），自己那条由 `sendXxx` 返回值给

## 7. 测试

- 测试位于 `test/`，共 3 个文件 `v2ocim_manager_test.dart`（820 行）/ `v2ocim_models_test.dart`（168 行）/ `v2ocim_wire_test.dart`（300 行）
- **发版前必跑**：`flutter pub get && flutter analyze && flutter test`
- `flutter test` 不需要任何原生环境（v3.1.0 起纯 Dart）
- 集成测试在 `clients/demos/` 与各端 demo 仓库，**不要**在 SDK 包内写

## 8. 依赖管理

- `pubspec.yaml` 里**只允许** `signalr_netcore`（传输）+ `flutter_test` + `lints`（dev）
- 任何新依赖**先问**：会不会给宿主引入原生代码？跨平台覆盖度？维护活跃度？

## 9. 版本号与发版

- 严格语义化版本（MAJOR.MINOR.PATCH）
- `pubspec.yaml` 的 `version` 与 Git tag `v{version}` **必须严格一致**（`v3.1.0` ↔ `3.1.0`）
- **不要在 README 安装片段里 hardcode tag**（除了主示例），改用 `latest` 或明确说「请以最新 release 为准」
- 发版前**必读**：
  - 跨项目规则 `D:/Work/OrangeCloud/trunk/.kiro/steering/sdk-distribution-protection.md`（SDK 分发与源码保护）
  - Skill `flutter-im-sdk-release`（完整发布脚本）

## 10. 与四端的对齐

四端 API 必须保持一致（命名、参数顺序、错误码、回调时机）。改本包前**先看**：

| 端 | 仓库 | 源码（SVN） |
|---|---|---|
| Web | https://github.com/OrangeCloud-SDK-IM/orangecloud-im-web | `clients/web/orangecloud-im-client/` |
| iOS | https://github.com/OrangeCloud-SDK-IM/orangecloud-im-ios | `clients/ios/OrangeCloudIMClient/` |
| Android | https://github.com/OrangeCloud-SDK-IM/orangecloud-im-android | `clients/android/orangecloud-im-client/` |
| Flutter（本包）| https://github.com/OrangeCloud-SDK-IM/orangecloud-im-flutter | `clients/flutter/orangecloud_im_client/` |

> 改消息结构/事件名/错误码/序列号语义时，**服务端 + 四端 + 集成文档**必须同步，否则会出现「跨端对不上」的灵异 bug。

## 11. 严禁清单

- ❌ 在 `lib/` 下加任何平台特定代码（`dart:io` 的 `Socket` / `File` / `Platform` 都不行，SDK 是库不是 App）
- ❌ 把用户数据、SecretKey、UserSig 写日志（即便 Debug 模式）
- ❌ 把任何对端的依赖（如 `flutter_lints` 之外的 `flutter` 子包）写进 dependencies（dev_dependencies 可以）
- ❌ 删 `lib/src/v2ocim/internal/` 外的文件而不更新 CHANGELOG
- ❌ 直接 force-push main（除非第一次清理老 v2.x 历史，按 skill 走）
- ❌ 在 GitHub commit 里出现 SecretKey / `local.properties` / 任何凭证
