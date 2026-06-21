import Flutter
import Foundation
import Combine
import OrangeCloudIMClient

/// OrangeCloud IM Flutter 插件（iOS 侧）
///
/// 桥接 Dart 层与原生核心 SDK（OCIMClient，XCFramework 二进制）：
/// - MethodChannel `com.orangecloud.im/methods`：接收 Dart 命令
/// - EventChannel  `com.orangecloud.im/events`：把核心 SDK 事件推给 Dart
///
/// IM 核心逻辑全部在 XCFramework 中，本类不含业务逻辑。
public class OrangecloudImClientPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let client = OCIMClient()
    private var eventSink: FlutterEventSink?
    private var bag = Set<AnyCancellable>()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = OrangecloudImClientPlugin()
        let methodChannel = FlutterMethodChannel(
            name: "com.orangecloud.im/methods", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(
            name: "com.orangecloud.im/events", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - EventChannel

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        subscribeClientEvents()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        bag.removeAll()
        eventSink = nil
        return nil
    }

    private func emit(_ event: String, _ data: Any?) {
        eventSink?(["event": event, "data": data as Any])
    }

    /// 把核心 SDK 的 Codable 消息编码为 JSON 字符串（与 data 下扁平字段契约一致）
    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func subscribeClientEvents() {
        bag.removeAll()

        client.onConnectionStateChanged.sink { [weak self] in
            self?.emit("connectionStateChanged", $0.rawValue)
        }.store(in: &bag)

        client.onTextMessage.sink { [weak self] in self?.emit("messageReceived", Self.encode($0)) }.store(in: &bag)
        client.onGiftMessage.sink { [weak self] in self?.emit("messageReceived", Self.encode($0)) }.store(in: &bag)
        client.onSystemNotice.sink { [weak self] in self?.emit("messageReceived", Self.encode($0)) }.store(in: &bag)
        client.onCustomMessage.sink { [weak self] in self?.emit("messageReceived", Self.encode($0)) }.store(in: &bag)

        client.onBroadcastReceived.sink { [weak self] in self?.emit("broadcastReceived", Self.encode($0)) }.store(in: &bag)
        client.onBatchMessageReceived.sink { [weak self] msgs in
            self?.emit("batchMessageReceived", msgs.compactMap { Self.encode($0) })
        }.store(in: &bag)
        client.onStateRestored.sink { [weak self] info in
            self?.emit("stateRestored", [
                "restoredGroupIds": info.groupIds,
                "backfilledMessageCount": info.backfilledCount
            ])
        }.store(in: &bag)
        client.onReconnectAttempt.sink { [weak self] info in
            self?.emit("reconnectAttempt", [
                "attemptNumber": info.attemptNumber,
                "nextDelayMs": info.delayMs
            ])
        }.store(in: &bag)
        client.onReconnectFailed.sink { [weak self] in self?.emit("reconnectFailed", nil) }.store(in: &bag)
        client.onGroupMemberList.sink { [weak self] in self?.emit("groupMemberList", $0) }.store(in: &bag)
    }

    // MARK: - MethodChannel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "login":
            client.maxReconnectAttempts = args["maxReconnectAttempts"] as? Int ?? -1
            client.login(
                hubUrl: args["hubUrl"] as? String ?? "",
                appId: args["appId"] as? String ?? "",
                userId: args["userId"] as? String ?? "",
                userSig: args["userSig"] as? String ?? ""
            )
            result(nil)
        case "logout":
            client.logout(); result(nil)
        case "joinGroup":
            client.joinGroup(args["groupId"] as? String ?? ""); result(nil)
        case "quitGroup":
            client.quitGroup(args["groupId"] as? String ?? ""); result(nil)
        case "sendGroupMsg":
            client.sendGroupMsg(
                groupId: args["groupId"] as? String ?? "",
                messageJson: args["messageJson"] as? String ?? "")
            result(nil)
        case "sendTextMessage":
            client.sendTextMessage(
                groupId: args["groupId"] as? String ?? "",
                content: args["content"] as? String ?? "")
            result(nil)
        case "sendGiftMessage":
            let g = args["giftInfo"] as? [String: Any] ?? [:]
            client.sendGiftMessage(
                groupId: args["groupId"] as? String ?? "",
                giftInfo: GiftInfo(
                    giftId: g["giftId"] as? String ?? "",
                    giftName: g["giftName"] as? String ?? "",
                    giftCount: g["giftCount"] as? Int ?? 1,
                    giftPrice: g["giftPrice"] as? Int ?? 0,
                    animationUrl: g["animationUrl"] as? String ?? ""))
            result(nil)
        case "sendCustomMessage":
            client.sendCustomMessage(
                groupId: args["groupId"] as? String ?? "",
                customType: args["customType"] as? String ?? "",
                payload: args["payload"] as? [String: Any] ?? [:])
            result(nil)
        case "getGroupMemberList":
            client.getGroupMemberList(args["groupId"] as? String ?? ""); result(nil)
        case "getLastSequenceNumber":
            result(client.getLastSequenceNumber(groupId: args["groupId"] as? String ?? ""))
        case "dispose":
            client.logout(); result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
