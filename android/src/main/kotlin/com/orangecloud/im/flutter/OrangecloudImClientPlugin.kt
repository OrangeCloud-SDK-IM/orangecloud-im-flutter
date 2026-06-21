package com.orangecloud.im.flutter

import android.content.Context
import com.google.gson.Gson
import com.orangecloud.im.IMConnectionState
import com.orangecloud.im.OrangeCloudIMClient
import com.orangecloud.im.models.GiftInfo
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * OrangeCloud IM Flutter 插件（Android 侧）
 *
 * 桥接 Dart 层与原生核心 SDK（com.orangecloud.im.OrangeCloudIMClient，AAR 二进制）：
 * - MethodChannel `com.orangecloud.im/methods`：接收 Dart 下发的命令
 * - EventChannel  `com.orangecloud.im/events`：把核心 SDK 的事件推送给 Dart
 *
 * 所有 IM 核心逻辑（连接/去重/补发/重连/心跳）均在 AAR 中，本类不含业务逻辑。
 */
class OrangecloudImClientPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var appContext: Context? = null

    private val gson = Gson()
    private val client = OrangeCloudIMClient()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val collectJobs = mutableListOf<Job>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "com.orangecloud.im/methods")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "com.orangecloud.im/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        cancelCollectors()
        client.dispose()
        scope.cancel()
        appContext = null
    }

    // === EventChannel ===

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        subscribeClientEvents()
    }

    override fun onCancel(arguments: Any?) {
        cancelCollectors()
        eventSink = null
    }

    private fun emit(event: String, data: Any?) {
        scope.launch {
            eventSink?.success(mapOf("event" to event, "data" to data))
        }
    }

    private fun subscribeClientEvents() {
        cancelCollectors()
        collectJobs += scope.launch {
            client.onConnectionStateChanged.collect { emit("connectionStateChanged", it.toWire()) }
        }
        collectJobs += scope.launch {
            client.onTextMessage.collect { emit("messageReceived", it.toJson()) }
        }
        collectJobs += scope.launch {
            client.onGiftMessage.collect { emit("messageReceived", it.toJson()) }
        }
        collectJobs += scope.launch {
            client.onSystemNotice.collect { emit("messageReceived", it.toJson()) }
        }
        collectJobs += scope.launch {
            client.onCustomMessage.collect { emit("messageReceived", it.toJson()) }
        }
        collectJobs += scope.launch {
            client.onBroadcastReceived.collect { emit("broadcastReceived", it.toJson()) }
        }
        collectJobs += scope.launch {
            client.onBatchMessageReceived.collect { list ->
                emit("batchMessageReceived", list.map { it.toJson() })
            }
        }
        collectJobs += scope.launch {
            client.onStateRestored.collect {
                emit("stateRestored", mapOf(
                    "restoredGroupIds" to it.restoredGroupIds,
                    "backfilledMessageCount" to it.backfilledMessageCount
                ))
            }
        }
        collectJobs += scope.launch {
            client.onReconnectAttempt.collect {
                emit("reconnectAttempt", mapOf(
                    "attemptNumber" to it.attemptNumber,
                    "nextDelayMs" to it.nextDelayMs
                ))
            }
        }
        collectJobs += scope.launch {
            client.onReconnectFailed.collect { emit("reconnectFailed", null) }
        }
        collectJobs += scope.launch {
            client.onGroupMemberList.collect { emit("groupMemberList", it) }
        }
    }

    private fun cancelCollectors() {
        collectJobs.forEach { it.cancel() }
        collectJobs.clear()
    }

    // === MethodChannel ===

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "login" -> {
                    client.maxReconnectAttempts = call.argument<Int>("maxReconnectAttempts") ?: -1
                    appContext?.let { client.registerNetworkCallback(it) }
                    client.login(
                        call.argument<String>("hubUrl") ?: "",
                        call.argument<String>("appId") ?: "",
                        call.argument<String>("userId") ?: "",
                        call.argument<String>("userSig") ?: ""
                    )
                    result.success(null)
                }
                "logout" -> { client.logout(); result.success(null) }
                "joinGroup" -> {
                    client.joinGroup(call.argument<String>("groupId") ?: "")
                    result.success(null)
                }
                "quitGroup" -> {
                    client.quitGroup(call.argument<String>("groupId") ?: "")
                    result.success(null)
                }
                "sendGroupMsg" -> {
                    client.sendGroupMsg(
                        call.argument<String>("groupId") ?: "",
                        call.argument<String>("messageJson") ?: ""
                    )
                    result.success(null)
                }
                "sendTextMessage" -> {
                    client.sendTextMessage(
                        call.argument<String>("groupId") ?: "",
                        call.argument<String>("content") ?: ""
                    )
                    result.success(null)
                }
                "sendGiftMessage" -> {
                    @Suppress("UNCHECKED_CAST")
                    val g = call.argument<Map<String, Any?>>("giftInfo") ?: emptyMap()
                    client.sendGiftMessage(
                        call.argument<String>("groupId") ?: "",
                        GiftInfo(
                            giftId = g["giftId"]?.toString() ?: "",
                            giftName = g["giftName"]?.toString() ?: "",
                            giftCount = (g["giftCount"] as? Number)?.toInt() ?: 1,
                            giftPrice = (g["giftPrice"] as? Number)?.toInt() ?: 0,
                            animationUrl = g["animationUrl"]?.toString() ?: ""
                        )
                    )
                    result.success(null)
                }
                "sendCustomMessage" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payload = call.argument<Map<String, Any>>("payload") ?: emptyMap()
                    client.sendCustomMessage(
                        call.argument<String>("groupId") ?: "",
                        call.argument<String>("customType") ?: "",
                        payload
                    )
                    result.success(null)
                }
                "getGroupMemberList" -> {
                    client.getGroupMemberList(call.argument<String>("groupId") ?: "")
                    result.success(null)
                }
                "getLastSequenceNumber" -> {
                    result.success(
                        client.getLastSequenceNumber(call.argument<String>("groupId") ?: "")
                    )
                }
                "dispose" -> { client.dispose(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("IM_ERROR", e.message, null)
        }
    }

    private fun com.orangecloud.im.models.IMMessage.toJson(): String = gson.toJson(this)

    private fun IMConnectionState.toWire(): String = when (this) {
        IMConnectionState.DISCONNECTED -> "disconnected"
        IMConnectionState.CONNECTING -> "connecting"
        IMConnectionState.CONNECTED -> "connected"
        IMConnectionState.RECONNECTING -> "reconnecting"
        IMConnectionState.RESTORING -> "restoring"
    }
}
