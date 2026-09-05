/// OrangeCloud IM Flutter SDK（v3.1.0）
///
/// API 完全对齐腾讯云 IM（V2TIM）：从腾讯迁移时全局替换 `V2TIM` / `V2Tim` → `V2OCIM`，
/// 再在 `initSDK` 之前插一行 `setServerConfig(hubUrl:, appId:)` 即可。
///
/// 契约：`clients/V2OCIM-API-契约定稿.md`
///
/// ## v3.1.0：改为纯 Dart 实现（**不再是 plugin**）
///
/// 公开 API 与回调时机**逐字未变**，接入方无需改一行代码；变化只在实现层：
///
/// - 不再依赖 Android AAR / iOS XCFramework，Flutter 端**零原生依赖**
/// - 改 SDK 不再需要重新构建两个原生二进制（iOS 那半原本必须 macOS，是发版硬阻塞）
/// - 传输层用 `signalr_netcore`，IM 逻辑（重连退避 / 心跳 / 序列号去重与间隙补发 /
///   自发消息过滤 / 事件分发）在 Dart 侧实现
///
/// 与原生实现的两处已知差异见 `V2OCIMManager` 的类注释。
///
/// ⚠ v3.0.0 是**破坏性重写**：v2.x 的 `OrangeCloudIMClient` 与
/// `TextMessage` / `GiftMessage` / `SystemNotice` / `CustomMessage`
/// 四个结构化模型已删除，礼物等业务消息统一走 custom 消息承载。
library;

export 'src/v2ocim/v2ocim_constants.dart';
export 'src/v2ocim/v2ocim_listeners.dart';
export 'src/v2ocim/v2ocim_manager.dart';
export 'src/v2ocim/v2ocim_models.dart';
