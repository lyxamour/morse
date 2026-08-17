import 'package:flutter_test/flutter_test.dart';
import 'package:morse/generated/telegraph_cn_table.dart';
import 'package:morse/morse_codec.dart';

void main() {
  const codec = MorseCodec();

  test('英文和数字编码为国际 Morse', () {
    final result = codec.encodeText('SOS 2');

    expect(result.output, '... --- ... ..---');
    expect(result.hasError, isFalse);
  });

  test('大陆标准表将中文经电报码转换为 Morse', () {
    final result = codec.encodeText('中文');

    expect(result.output, '----- ----- ..--- ..--- ..--- ....- ..--- ----.');
    expect(result.units[0].telegraphCode, '0022');
    expect(result.units[1].telegraphCode, '2429');
  });

  test('Morse 数字序列反解为中文电报码', () {
    final result = codec.decodeMorse('----- ----- ..--- ..---');

    expect(result.output, '中');
    expect(result.hasError, isFalse);
  });

  test('逗号分段数字 Morse 反解为中文', () {
    const input =
        '..--- ----- ..... ...-- .---- ----. ..--- --... ----- .---- ...-- ..--- '
        '--..-- ----- ---.. ...-- ----. ----- ---.. ...-- ----. ----- ---.. ...-- ----. '
        '--..-- ----- .---- ...-- ..--- -.... --... ..... --... ----- ----- ----- '
        '---.. ...-- ---.. .---- ----- ..--- ----- ..... ...--';
    final result = codec.decodeMorse(input);

    const codes = [
      '2053',
      '1927',
      '0132',
      '0839',
      '0839',
      '0839',
      '0132',
      '6757',
      '0008',
      '3810',
      '2053',
    ];
    // 电报标准：每个中文字之间空格分隔（逗号也渲染为空格）
    final expected = codes
        .map((code) => chineseTelegraphCnReverse[code])
        .join(' ');
    expect(result.output, expected);
    expect(result.hasError, isFalse);
  });

  test('台湾表：简体输入经简→繁转换可查码，解码输出回简体', () {
    final codec = MorseCodec(profile: TelegraphProfile.tw);
    final encoded = codec.encodeText('中文电码');
    // 全部可查码（不出现「无码可用」），且码与繁体字直查一致
    expect(encoded.hasError, isFalse);
    for (final unit in encoded.units) {
      expect(unit.telegraphCode, isNotNull, reason: '${unit.source} 无码');
    }
    final direct = codec.encodeText('中文電碼');
    expect(
      encoded.units.map((u) => u.telegraphCode).toList(),
      direct.units.map((u) => u.telegraphCode).toList(),
    );

    // 解码：繁体反查结果以简体显示
    final decoded = codec.decodeMorse(encoded.output);
    expect(decoded.output, '中 文 电 码');
  });

  test('双表 profile 均可离线查询', () {
    for (final profile in TelegraphProfile.values) {
      final result = MorseCodec(profile: profile).encodeText('中文');
      expect(result.hasError, isFalse);
      expect(result.units.first.telegraphCode, isNotNull);
    }
  });

  test('表外字符（emoji）走码点转义并往返无损', () {
    final result = codec.encodeText('中😀');

    expect(result.hasError, isFalse);
    expect(result.units.last.status, MorseStatus.ok);
    expect(result.units.last.index, 1);
    // ((128512)) 的 Morse 化
    expect(
      result.output.endsWith(
        '-.--. -.--. .---- ..--- ---.. ..... .---- ..--- -.--.- -.--.-',
      ),
      isTrue,
    );

    final decoded = codec.decodeMorse(result.output);
    expect(decoded.output, '中😀');
    expect(decoded.hasError, isFalse);
  });

  test('连续 emoji 与 emoji+中文混排均往返无损', () {
    for (final input in ['😀😀', '你好😀WORLD', '❤️🎉']) {
      final roundTrip = codec.decodeMorse(codec.encodeText(input).output);
      // emoji 间按词间隔（/）渲染为空格
      expect(roundTrip.output.replaceAll(' ', ''), input);
      expect(roundTrip.hasError, isFalse);
    }
  });

  test('兼容 Unicode 点划字符', () {
    final result = codec.decodeMorse('··· ——— ···');

    expect(result.output, 'SOS');
  });
}
