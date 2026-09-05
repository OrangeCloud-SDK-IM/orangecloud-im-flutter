import 'package:signalr_netcore/signalr_client.dart';

/// SignalR 连接的最小抽象。
///
/// 存在的唯一目的是给 [V2OCIMManager] 留一个**测试接缝** —— 重连退避、序列号去重与
/// 间隙补发、自发消息过滤、事件分发这些真正容易出错的逻辑，因此可以脱离真实网络做
/// 确定性单测。生产走 [SignalRConnection]。
abstract class V2OCIMConnection {
  Future<void> start();

  Future<void> stop();

  /// fire-and-forget 调用（不关心返回值）
  Future<void> send(String method, List<Object> args);

  /// 需要返回值的调用（发消息拿 `SendMessageResult` 用这个）
  Future<Object?> invoke(String method, List<Object> args);

  /// 注册服务端推送。[handler] 收到的是 Hub 方法的实参列表。
  void on(String method, void Function(List<Object?>? args) handler);

  /// 连接关闭回调（含服务端 Abort 与网络断开）
  void onClose(void Function() handler);
}

/// 按 URL 造一个连接。测试可替换成假实现。
typedef V2OCIMConnectionFactory = V2OCIMConnection Function(String url);

/// 基于 `signalr_netcore` 的真实实现。
///
/// ⚠ **刻意不开 `withAutomaticReconnect`**：SDK 自己做重连（退避序列 0/2/10/30 秒 +
/// 鉴权失败永久停止），四端口径一致。开了会与自研重连打架 —— 两套机制各自计时，
/// 表现为连接抖动与退避节奏被打乱。
class SignalRConnection implements V2OCIMConnection {
  SignalRConnection(String url)
      : _hub = HubConnectionBuilder().withUrl(url).build();

  final HubConnection _hub;

  @override
  Future<void> start() async {
    // start() 声明为 Future<void>?，null 时表示同步完成
    final future = _hub.start();
    if (future != null) {
      await future;
    }
  }

  @override
  Future<void> stop() => _hub.stop();

  @override
  Future<void> send(String method, List<Object> args) =>
      _hub.send(method, args: args);

  @override
  Future<Object?> invoke(String method, List<Object> args) =>
      _hub.invoke(method, args: args);

  @override
  void on(String method, void Function(List<Object?>? args) handler) =>
      _hub.on(method, handler);

  @override
  void onClose(void Function() handler) =>
      _hub.onclose(({Exception? error}) => handler());
}

/// 生产用的连接工厂
V2OCIMConnection createSignalRConnection(String url) => SignalRConnection(url);
