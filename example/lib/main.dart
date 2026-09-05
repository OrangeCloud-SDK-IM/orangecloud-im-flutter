// OrangeCloud IM Flutter SDK — 最小接入示例
//
// 覆盖：setServerConfig / initSDK / addSimpleMsgListener / addIMSDKListener /
//       login / joinGroup / sendGroupTextMessage / notifyNetworkAvailable
//
// 真实接入时请：
//  1. 把下面 4 个常量换成你的真实环境
//  2. 把 userSig 签发放到你的业务服务端（不能用本包做 SecretKey 签发）
//  3. 直播场景务必接 notifyNetworkAvailable（见 lib/orangecloud_im_client.dart 注释）

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:orangecloud_im_client/orangecloud_im_client.dart';

// ─── 必改 ──────────────────────────────────────────────────────
const _hubUrl  = 'https://signalr.your-domain.com/hubs/live';
const _imAppId = 'YOUR_IM_APP_ID';
const _userId  = 'demo_user_001';
// userSig 必须服务端签发，见集成文档。
const _userSig = 'USER_SIG_FROM_YOUR_BACKEND';
// ───────────────────────────────────────────────────────────────

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> with WidgetsBindingObserver {
  final _im = V2OCIMManager.instance;
  final _messages = <String>[];
  final _inputCtrl = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);   // 用于前台唤醒触发重连
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _im.logout();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 直播场景：前台唤醒时立即触发重连（不接也行，会在 10s 内自愈）
    if (state == AppLifecycleState.resumed) {
      _im.notifyNetworkAvailable();
    }
  }

  Future<void> _bootstrap() async {
    // ⚠ 自研扩展，必须在 initSDK 之前调用
    await _im.setServerConfig(hubUrl: _hubUrl, appId: _imAppId);
    await _im.initSDK();

    _im.addSimpleMsgListener(listener: V2OCIMSimpleMsgListener(
      onRecvGroupTextMessage: (msgID, groupID, sender, text) {
        setState(() => _messages.add('${sender.nickName}: $text'));
      },
    ));

    _im.addIMSDKListener(listener: V2OCIMSDKListener(
      onUserSigExpired: () {
        // 真实场景：调你的接口重新签发 userSig，再 login 一次
        debugPrint('[IM] userSig 过期，请重新签发');
      },
      onKickedOffline: () {
        // 账号在其它设备登录，走登出流程
        debugPrint('[IM] 被踢下线');
        setState(() => _ready = false);
      },
    ));

    final r = await _im.login(userID: _userId, userSig: _userSig);
    if (!r.isSuccess) {
      debugPrint('[IM] login 失败: ${r.code} ${r.desc}');
      return;
    }
    await _im.joinGroup(groupID: 'demo_room');
    setState(() => _ready = true);
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final r = await _im.sendGroupTextMessage(text: text, groupID: 'demo_room');
    if (r.isSuccess) {
      // 自己这条不会从 listener 收到，直接拿返回值上屏
      setState(() => _messages.add('我: ${r.data!.textElem!.text}'));
      _inputCtrl.clear();
    } else if (r.code == V2OCIMErrorCode.muted) {
      debugPrint('你已被禁言');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('OrangeCloud IM Demo')),
        body: Column(
          children: [
            if (!_ready) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (_, i) => ListTile(title: Text(_messages[i])),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      decoration: const InputDecoration(
                        hintText: '说点什么...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _ready ? _send : null, child: const Text('发送')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
