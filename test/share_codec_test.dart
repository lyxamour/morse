import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse/morse_codec.dart';
import 'package:morse/main.dart';
import 'package:morse/share_codec.dart';

void main() {
  const codec = ShareCodec();

  test('中文：BCD 段打包，比原文 base64 短', () {
    const text = '我想你';
    final payload = codec.encode(text);
    // byte0 + tag + 3字×2B = 8 字节 → 11 字符（原文 UTF-8 base64 为 12）
    expect(payload, hasLength(11));
    expect(codec.decode(payload).text, text);
  });

  test('英文：6 bit 段打包，长文本比原文 base64 短', () {
    const text = 'hello world, this is morse';
    final payload = codec.encode(text);
    final raw = base64Url
        .encode(const Utf8Encoder().convert(text))
        .replaceAll('=', '');
    expect(payload.length < raw.length, isTrue);
    expect(codec.decode(payload).text, text);
  });

  test('大小写与数字保留', () {
    const text = 'Sos 2 Fast.';
    expect(codec.decode(codec.encode(text)).text, text);
  });

  test('emoji 走 UTF-8 兜底段并往返无损', () {
    const text = '你好😀❤️';
    expect(codec.decode(codec.encode(text)).text, text);
  });

  test('中文长文本跨 63 字分段往返', () {
    final text = '我想你了' * 40; // 160 字
    expect(codec.decode(codec.encode(text)).text, text);
  });

  test('英文长文本跨 63 字分段往返', () {
    final text = 'a' * 100 + ' 😀' + 'b' * 70;
    expect(codec.decode(codec.encode(text)).text, text);
  });

  test('长 emoji 串跨 63 字节分段往返（多字节 rune 不被切断）', () {
    final text = '😀' * 40; // 160 字节
    expect(codec.decode(codec.encode(text)).text, text);
  });

  test('profile 随 payload 往返', () {
    final payload = codec.encode('中文', profile: TelegraphProfile.tw);
    expect(codec.decode(payload).profile, TelegraphProfile.tw);
    expect(codec.decode(payload).text, '中文');
  });

  test('混合场景：中英数 emoji 混排往返', () {
    const text = '我想你 hello 123 😀 呜呜呜';
    final payload = codec.encode(text);
    expect(codec.decode(payload).text, text);
  });

  test('web 分享 url 带预览文本 query', () {
    expect(
      shareWebUrl('http://localhost:46315', 'AYH8wS2C-_DBLYL78MEt', '你好 Morse'),
      'http://localhost:46315/c/AYH8wS2C-_DBLYL78MEt?t=%E4%BD%A0%E5%A5%BD+Morse',
    );
    expect(
      shareWebUrl('http://localhost:46315', 'AYH8wS2C-_DBLYL78MEt', '   '),
      'http://localhost:46315/c/AYH8wS2C-_DBLYL78MEt',
    );
  });

  test('morse:// 深链解析出 payload，其他 URI 不认', () {
    const payload = 'AYKagA';
    expect(
      morseLinkPayload(Uri.parse('morse://convert?c=$payload&p=cn')),
      payload,
    );
    expect(morseLinkPayload(Uri.parse('morse://play?c=$payload')), isNull);
    expect(
      morseLinkPayload(Uri.parse('https://morse.embla.cf/#/c/$payload')),
      isNull,
    );
  });

  test('非法 payload 抛 FormatException', () {
    expect(() => codec.decode('!!!not-base64!!!'), throwsFormatException);
  });
}
