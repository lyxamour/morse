import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse/morse_audio.dart';

void main() {
  group('buildSignalPlan', () {
    test('SOS = 3 dot + 3 dash + 3 dot，符号内 1u 字符间 3u', () {
      final plan = buildSignalPlan('... --- ...', unitMs: 100);
      final marks = plan.where((s) => s.on).map((s) => s.ms).toList();
      final gaps = plan.where((s) => !s.on).map((s) => s.ms).toList();
      expect(marks, [100, 100, 100, 300, 300, 300, 100, 100, 100]);
      expect(
        gaps,
        [100, 100, 300, 100, 100, 300, 100, 100].map((ms) => ms).toList(),
      );
    });

    test('/ 词间隔 7u', () {
      final plan = buildSignalPlan('. / .', unitMs: 10);
      expect(plan.map((s) => '${s.on ? s.ms : -s.ms}').join(','), '10,-70,10');
    });

    test('忽略非 Morse 符号', () {
      expect(buildSignalPlan('hi -!'), hasLength(1));
    });
  });

  group('formatMorseDuration', () {
    test('动态单位', () {
      expect(formatMorseDuration(500), '500 ms');
      expect(formatMorseDuration(999), '999 ms');
      expect(formatMorseDuration(1500), '1.5 s');
      expect(formatMorseDuration(59000), '59.0 s');
      expect(formatMorseDuration(90000), '1 分 30 s');
      expect(formatMorseDuration(125000), '2 分 5 s');
    });
  });

  group('buildMorseWav', () {
    test('WAV 头合法且长度 = 44 + 采样数×2', () {
      final wav = buildMorseWav('. .', unitMs: 100, sampleRate: 8000);
      final header = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
      expect(header.getUint16(20, Endian.little), 1); // PCM
      expect(header.getUint16(22, Endian.little), 1); // 单声道
      expect(header.getUint32(24, Endian.little), 8000);
      expect(header.getUint16(34, Endian.little), 16); // 位深
      // (100+300+100)ms × 8000Hz = 4000 采样
      expect(wav.length, 44 + 4000 * 2);
    });

    test('静默段全零，发声段有能量', () {
      final wav = buildMorseWav('. .', unitMs: 100, sampleRate: 8000);
      final samples = Int16List.view(
        wav.buffer.asUint8List().sublist(44).buffer,
      );
      final mark0 = samples.sublist(0, 800); // 第一个 dot
      final gap = samples.sublist(900, 2300); // 中间 3u 间隔（留淡出余量）
      expect(gap.every((s) => s == 0), isTrue);
      expect(mark0.any((s) => s.abs() > 30000), isTrue);
    });
  });
}
