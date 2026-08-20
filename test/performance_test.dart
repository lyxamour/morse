import 'package:flutter_test/flutter_test.dart';
import 'package:morse/morse_audio.dart';
import 'package:morse/morse_codec.dart';
import 'package:morse/share_codec.dart';

void main() {
  test('核心流程性能预算', () {
    const codec = MorseCodec();
    const shareCodec = ShareCodec();
    final text = ('HELLO WORLD THIS IS MORSE 12345 我想你 😀 ' * 8).trim();
    final morse = codec.encodeText(text).output;

    final encodeUs = _avgMicros(200, () {
      final result = codec.convert(text);
      expect(result.hasError, isFalse);
    });
    final decodeUs = _avgMicros(200, () {
      final result = codec.convert(morse);
      expect(result.hasError, isFalse);
    });
    final shareUs = _avgMicros(200, () {
      expect(shareCodec.decode(shareCodec.encode(text)).text, text);
    });
    final planUs = _avgMicros(200, () {
      expect(buildSignalPlan(morse), isNotEmpty);
    });
    final wavUs = _avgMicros(10, () {
      expect(
        buildMorseWav(morse, unitMs: 1, sampleRate: 8000),
        hasLength(greaterThan(44)),
      );
    });

    expect(encodeUs, lessThan(1000));
    expect(decodeUs, lessThan(1000));
    expect(shareUs, lessThan(1000));
    expect(planUs, lessThan(1000));
    expect(wavUs, lessThan(5000));
  });
}

double _avgMicros(int iterations, void Function() run) {
  for (var i = 0; i < 20; i++) run();
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) run();
  sw.stop();
  return sw.elapsedMicroseconds / iterations;
}
