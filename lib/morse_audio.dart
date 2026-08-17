import 'dart:math' as math;
import 'dart:typed_data';

/// Morse 播放信号：一段持续 [ms] 的开/关。
class MorseSignal {
  const MorseSignal({required this.on, required this.ms});
  final bool on;
  final int ms;
}

/// 把 Morse 串解析为信号序列：dot=1u、dash=3u，符号内间隔 1u、
/// 字符间 3u、词间（`/` 或多空格）7u。
List<MorseSignal> buildSignalPlan(String morse, {int unitMs = 90}) {
  final plan = <MorseSignal>[];
  void gap(int units) => plan.add(MorseSignal(on: false, ms: units * unitMs));
  void mark(int units) => plan.add(MorseSignal(on: true, ms: units * unitMs));

  var lastWasMark = false;
  for (final token in morse.trim().split(RegExp(r'\s+'))) {
    if (token == '/') {
      gap(lastWasMark ? 7 : 2);
      lastWasMark = false;
      continue;
    }
    var tokenHasMark = false;
    for (final symbol in token.runes) {
      if (symbol != 0x2E && symbol != 0x2D) continue; // 只认 . -
      if (tokenHasMark) {
        gap(1);
      } else if (lastWasMark) {
        gap(3);
      }
      mark(symbol == 0x2E ? 1 : 3);
      tokenHasMark = true;
      lastWasMark = true;
    }
  }
  return plan;
}

/// 时长展示，动态单位：<1s 用 ms，<1min 用 s（1 位小数），再往上用 分 s。
String formatMorseDuration(int ms) {
  if (ms < 1000) return '$ms ms';
  final seconds = ms / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)} s';
  final minutes = seconds ~/ 60;
  final rest = (seconds - minutes * 60).round();
  return '$minutes 分 $rest s';
}

/// 生成 16-bit 单声道 PCM WAV：600Hz 正弦，首尾 5ms 淡入淡出防爆音。
Uint8List buildMorseWav(
  String morse, {
  int unitMs = 90,
  int sampleRate = 44100,
  int frequency = 600,
}) {
  final plan = buildSignalPlan(morse, unitMs: unitMs);
  final totalMs = plan.fold<int>(0, (sum, signal) => sum + signal.ms);
  final totalSamples = totalMs * sampleRate ~/ 1000;
  final fadeSamples = 5 * sampleRate ~/ 1000;

  final pcm = Int16List(totalSamples);
  var cursor = 0;
  for (final signal in plan) {
    final samples = signal.ms * sampleRate ~/ 1000;
    if (signal.on) {
      for (var i = 0; i < samples; i++) {
        if (cursor + i >= totalSamples) break;
        final envelope =
            math.min(math.min(i, samples - 1 - i), fadeSamples) / fadeSamples;
        final value =
            math.sin(2 * math.pi * frequency * (cursor + i) / sampleRate) *
            envelope;
        pcm[cursor + i] = (value * 32767).round();
      }
    }
    cursor += samples;
  }

  final bytes = ByteData(44 + pcm.lengthInBytes);
  void ascii(int offset, String s) =>
      s.codeUnits.forEach((c) => bytes.setUint8(offset++, c));

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + pcm.lengthInBytes, Endian.little);
  ascii(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little); // fmt chunk 大小
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // 单声道
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little); // 字节率
  bytes.setUint16(32, 2, Endian.little); // 块对齐
  bytes.setUint16(34, 16, Endian.little); // 位深
  ascii(36, 'data');
  bytes.setUint32(40, pcm.lengthInBytes, Endian.little);
  final buffer = bytes.buffer.asUint8List();
  buffer.setRange(44, buffer.length, pcm.buffer.asUint8List());
  return buffer;
}
