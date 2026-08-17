import 'dart:convert';
import 'dart:typed_data';

import 'morse_codec.dart';

/// 分享链接解码结果：原文 + 电报码表 profile。
class SharePayload {
  const SharePayload({required this.text, required this.profile});

  final String text;
  final TelegraphProfile profile;
}

/// 分享 URL payload：分层打包 + base64url（无 padding）。
///
/// 字节布局（无压缩头，字典 = app 内置电报码表）：
///   byte0: profile<<6 | 版本（低 6 位 = 1）
///   段循环：tag = 类型<<6 | 数量(≤63，超长自动分段)
///     1 = 中文：电报码 4 位 BCD，2 字节/字
///     2 = 拉丁：64 字符表 6 bit/字符
///     3 = 其他（emoji 等）：UTF-8 原文兜底
class ShareCodec {
  const ShareCodec();

  /// 64 个常用字符，正好 6 bit/字符（索引即编码值）。
  static const _latin6 =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .';

  String encode(String text, {TelegraphProfile profile = TelegraphProfile.cn}) {
    final codec = MorseCodec(profile: profile);
    final bytes = BytesBuilder();
    bytes.addByte((profile == TelegraphProfile.tw ? 1 : 0) << 6 | 1);

    void emitCjk(List<String> chars) {
      for (var i = 0; i < chars.length; i += 63) {
        final chunk = chars.skip(i).take(63).toList();
        bytes.addByte(1 << 6 | chunk.length);
        for (final char in chunk) {
          final code = codec.telegraphCodeOf(char)!;
          final d = code.codeUnits.map((c) => c - 0x30).toList();
          bytes.addByte(d[0] << 4 | d[1]);
          bytes.addByte(d[2] << 4 | d[3]);
        }
      }
    }

    void emitLatin(List<int> values) {
      for (var i = 0; i < values.length; i += 63) {
        final chunk = values.skip(i).take(63).toList();
        bytes.addByte(2 << 6 | chunk.length);
        var acc = 0;
        var n = 0;
        for (final v in chunk) {
          acc = acc << 6 | v;
          n += 6;
          while (n >= 8) {
            bytes.addByte((acc >> (n - 8)) & 0xFF);
            n -= 8;
          }
        }
        if (n > 0) bytes.addByte((acc << (8 - n)) & 0xFF);
      }
    }

    void emitUtf8(List<int> raw) {
      for (var i = 0; i < raw.length; i += 63) {
        final chunk = raw.skip(i).take(63).toList();
        bytes.addByte(3 << 6 | chunk.length);
        bytes.add(chunk);
      }
    }

    // 连续同类型聚段，类型切换时落盘
    var runType = 0;
    final cjkRun = <String>[];
    final latinRun = <int>[];
    final utf8Run = <int>[];

    void flush() {
      if (runType == 1) emitCjk(cjkRun);
      if (runType == 2) emitLatin(latinRun);
      if (runType == 3) emitUtf8(utf8Run);
      cjkRun.clear();
      latinRun.clear();
      utf8Run.clear();
    }

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final type = codec.telegraphCodeOf(char) != null
          ? 1
          : _latin6.indexOf(char) >= 0
          ? 2
          : 3;
      if (type != runType) {
        flush();
        runType = type;
      }
      switch (type) {
        case 1:
          cjkRun.add(char);
        case 2:
          latinRun.add(_latin6.indexOf(char));
        default:
          utf8Run.addAll(utf8.encode(char));
      }
    }
    flush();

    return base64Url.encode(bytes.takeBytes()).replaceAll('=', '');
  }

  SharePayload decode(String payload) {
    final data = Uint8List.fromList(
      base64Url.decode(payload + '=' * ((4 - payload.length % 4) % 4)),
    );
    if (data.isEmpty || (data[0] & 0x3F) != 1) {
      throw const FormatException('未知 payload 版本');
    }
    final profile = (data[0] >> 6 & 1) == 1
        ? TelegraphProfile.tw
        : TelegraphProfile.cn;
    final codec = MorseCodec(profile: profile);

    final text = StringBuffer();
    var utf8Pending = <int>[];
    void flushUtf8() {
      if (utf8Pending.isEmpty) return;
      text.write(utf8.decode(utf8Pending));
      utf8Pending = <int>[];
    }

    var pos = 1;
    while (pos < data.length) {
      final tag = data[pos++];
      final type = tag >> 6;
      final count = tag & 0x3F;
      switch (type) {
        case 1:
          flushUtf8();
          for (var i = 0; i < count; i++) {
            final b1 = data[pos];
            final b2 = data[pos + 1];
            pos += 2;
            final code = '${b1 >> 4}${b1 & 0xF}${b2 >> 4}${b2 & 0xF}';
            text.write(
              codec.charOfTelegraph(code) ??
                  (throw FormatException('未知电报码 $code')),
            );
          }
        case 2:
          flushUtf8();
          var acc = 0;
          var n = 0;
          for (var i = 0; i < count; i++) {
            while (n < 6) {
              acc = acc << 8 | data[pos++];
              n += 8;
            }
            text.write(_latin6[(acc >> (n - 6)) & 0x3F]);
            acc &= (1 << (n - 6)) - 1;
            n -= 6;
          }
        default:
          // 多字节 rune 可能跨 63 字节段边界，累积后再解码
          utf8Pending.addAll(data.skip(pos).take(count));
          pos += count;
      }
    }
    flushUtf8();
    return SharePayload(text: text.toString(), profile: profile);
  }
}
