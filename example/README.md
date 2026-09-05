# OrangeCloud IM Flutter SDK — Example

最小可运行示例。展示：
- 初始化（`setServerConfig` + `initSDK`）
- 登录（`login` + 监听 `onUserSigExpired`）
- 加入群（`joinGroup`）
- 收发消息（`sendGroupTextMessage` + `addSimpleMsgListener`）
- 自研扩展：网络恢复时 `notifyNetworkAvailable()`

## 运行

```bash
flutter pub get
flutter run
```

## 必改的两行

进入 `lib/main.dart`，把这两个占位值换成你的真实环境：

```dart
const _hubUrl = 'https://signalr.your-domain.com/hubs/live';   // SignalR Hub
const _imAppId = 'YOUR_IM_APP_ID';                              // t_Live_IMApp.IMAppId
const _userSig = 'USER_SIG_FROM_YOUR_BACKEND';                  // 必须服务端签发
const _userId  = 'demo_user_001';
```

`userSig` 必须在你的业务服务端用 IMApp 的 SecretKey 签发，
参考 [`UserSigGenerator`](https://github.com/OrangeCloud-SDK-IM/orangecloud-im-flutter)
的服务端对照实现（`OrangeCloud.CoreBusiness.Live/Auth/UserSigGenerator.cs`）。

## 集成文档

完整接入说明：https://github.com/OrangeCloud-SDK-IM/orangecloud-im-flutter#readme
