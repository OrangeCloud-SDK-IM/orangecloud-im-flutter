/// 旧版消息类型常量（保持向后兼容）
/// 新代码请使用 IMMessageType 枚举（来自 models/im_message.dart）
class IMLegacyMessageType {
  IMLegacyMessageType._();
  static const String publicMsg = "public_msg";
  static const String sendGift = "SEND_GIFT";
  static const String sendBigGift = "SEND_BIG_GIFT";
  static const String sendBarrage = "SEND_BARRAGE";
  static const String aNotice = "ANotice";
  static const String stopLive = "stop_live";
}
