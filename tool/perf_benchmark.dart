import 'dart:convert';
import 'dart:io';

import 'package:morse/morse_audio.dart';
import 'package:morse/morse_codec.dart';
import 'package:morse/share_codec.dart';

void main(List<String> args) {
  final iterations = args.contains('--quick') ? 200 : 1000;
  final codec = const MorseCodec();
  final shareCodec = const ShareCodec();
  final text = ('HELLO WORLD THIS IS MORSE 12345 我想你 😀 ' * 8).trim();
  final morse = codec.encodeText(text).output;
  final payload = shareCodec.encode(morse);
  final results = <String, Object?>{
    'iterations': iterations,
    'cases': [
      _bench('text_to_morse', iterations, () {
        final result = codec.convert(text);
        if (result.output.isEmpty || result.hasError)
          throw StateError('bad encode');
      }),
      _bench('morse_to_text', iterations, () {
        final result = codec.convert(morse);
        if (result.output.isEmpty || result.hasError)
          throw StateError('bad decode');
      }),
      _bench('share_roundtrip', iterations, () {
        final decoded = shareCodec.decode(shareCodec.encode(text));
        if (decoded.text != text) throw StateError('bad share roundtrip');
      }),
      _bench('signal_plan', iterations, () {
        final plan = buildSignalPlan(morse);
        if (plan.isEmpty) throw StateError('bad plan');
      }),
      _bench('wav_generation', iterations ~/ 20, () {
        final wav = buildMorseWav(morse, unitMs: 1, sampleRate: 8000);
        if (wav.length <= 44) throw StateError('bad wav');
      }),
      _bench('shared_payload_decode', iterations, () {
        final decoded = shareCodec.decode(payload);
        if (decoded.text != morse) throw StateError('bad payload decode');
      }),
    ],
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(results));
}

Map<String, Object> _bench(String name, int iterations, void Function() run) {
  for (var i = 0; i < 20; i++) run();
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) run();
  sw.stop();
  final micros = sw.elapsedMicroseconds;
  return {
    'name': name,
    'iterations': iterations,
    'total_us': micros,
    'avg_us': micros / iterations,
  };
}
