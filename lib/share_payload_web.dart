import 'dart:js_interop';

/// index.html 在 Flutter 启动前把 /c/<payload> 或 /#/c/<payload> 存到
/// window.morseSharePayload（名字不能带前导下划线——js_interop 保留语义）。
@JS('morseSharePayload')
external String? get _payloadJS;

String? pageSharePayload() {
  final payload = _payloadJS;
  if (payload == null || payload.isEmpty) return null;
  return payload;
}

/// 恢复成功后写 window.morseRestored，供外部观测/调试。
@JS('morseRestored')
external set _restoredJS(JSString? value);
void markRestored(String text) {
  _restoredJS = text.toJS;
}
