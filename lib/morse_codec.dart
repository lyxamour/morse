import 'generated/chinese_s2t_table.dart';
import 'generated/chinese_t2s_table.dart';
import 'generated/telegraph_cn_table.dart';
import 'generated/telegraph_tw_table.dart';

enum MorseStatus { ok, error }

enum MorseInputKind { text, morse, ambiguous }

enum TelegraphProfile { cn, tw }

class MorseUnit {
  const MorseUnit({
    required this.source,
    required this.index,
    required this.normalized,
    required this.status,
    this.telegraphCode,
    this.morse,
    this.error,
    this.candidates = const [],
    this.debug = const {},
  });

  final String source;
  final int index;
  final String normalized;
  final MorseStatus status;
  final String? telegraphCode;
  final String? morse;
  final String? error;
  final List<String> candidates;
  final Map<String, Object?> debug;
}

class MorseResult {
  const MorseResult({
    required this.input,
    required this.normalizedInput,
    required this.kind,
    required this.output,
    required this.units,
    required this.hasError,
  });

  final String input;
  final String normalizedInput;
  final MorseInputKind kind;
  final String output;
  final List<MorseUnit> units;
  final bool hasError;
}

class MorseCodec {
  const MorseCodec({this.profile = TelegraphProfile.cn});

  final TelegraphProfile profile;

  static const Map<String, String> _latinMorse = {
    'A': '.-',
    'B': '-...',
    'C': '-.-.',
    'D': '-..',
    'E': '.',
    'F': '..-.',
    'G': '--.',
    'H': '....',
    'I': '..',
    'J': '.---',
    'K': '-.-',
    'L': '.-..',
    'M': '--',
    'N': '-.',
    'O': '---',
    'P': '.--.',
    'Q': '--.-',
    'R': '.-.',
    'S': '...',
    'T': '-',
    'U': '..-',
    'V': '...-',
    'W': '.--',
    'X': '-..-',
    'Y': '-.--',
    'Z': '--..',
    '0': '-----',
    '1': '.----',
    '2': '..---',
    '3': '...--',
    '4': '....-',
    '5': '.....',
    '6': '-....',
    '7': '--...',
    '8': '---..',
    '9': '----.',
    '.': '.-.-.-',
    ',': '--..--',
    '?': '..--..',
    '!': '-.-.--',
    ':': '---...',
    ';': '-.-.-.',
    '-': '-....-',
    '/': '-..-.',
    '(': '-.--.',
    ')': '-.--.-',
    '&': '.-...',
    '@': '.--.-.',
  };

  static final Map<String, String> _morseLatin = {
    for (final entry in _latinMorse.entries) entry.value: entry.key,
  };

  /// 码点转义：((十进制))，1-7 位覆盖全部 Unicode（上限 1114111）。
  static final RegExp _codepointEscape = RegExp(r'\(\((\d{1,7})\)\)');

  static const Map<String, String> _traditionalToSimplified = chineseT2s;

  Map<String, String> get _telegraphCodes => switch (profile) {
    TelegraphProfile.cn => chineseTelegraphCn,
    TelegraphProfile.tw => chineseTelegraphTw,
  };

  Map<String, String> get _telegraphChars => switch (profile) {
    TelegraphProfile.cn => chineseTelegraphCnReverse,
    TelegraphProfile.tw => chineseTelegraphTwReverse,
  };

  MorseResult convert(String input) {
    final normalized = _normalizeInput(input);
    final kind = _detectKind(normalized);
    return switch (kind) {
      MorseInputKind.text => encodeText(input),
      MorseInputKind.morse => decodeMorse(input),
      MorseInputKind.ambiguous => _ambiguous(input),
    };
  }

  MorseResult encodeText(String input) {
    final normalizedInput = _normalizeInput(input);
    final units = <MorseUnit>[];
    final parts = <String>[];
    var index = 0;

    for (final rune in normalizedInput.runes) {
      final source = String.fromCharCode(rune);
      if (source.trim().isEmpty) {
        parts.add('/');
        units.add(
          MorseUnit(
            source: source,
            index: index,
            normalized: source,
            status: MorseStatus.ok,
            morse: '/',
            debug: const {'kind': 'space'},
          ),
        );
        index++;
        continue;
      }

      final latin = _latinMorse[source.toUpperCase()];
      if (latin != null) {
        parts.add(latin);
        units.add(
          MorseUnit(
            source: source,
            index: index,
            normalized: source.toUpperCase(),
            status: MorseStatus.ok,
            morse: latin,
            debug: const {'kind': 'latin'},
          ),
        );
        index++;
        continue;
      }

      final telegraph = _lookupTelegraph(source);
      if (telegraph != null) {
        final morse = telegraph
            .split('')
            .map((digit) => _latinMorse[digit]!)
            .join(' ');
        parts.add(morse);
        units.add(
          MorseUnit(
            source: source,
            index: index,
            normalized: source,
            status: MorseStatus.ok,
            telegraphCode: telegraph,
            morse: morse,
            debug: const {'kind': 'telegraph'},
          ),
        );
        index++;
        continue;
      }

      // 无标准映射（emoji 等）：双括号码点转义，((码点十进制))
      final morse = '(($rune))'.split('').map((c) => _latinMorse[c]!).join(' ');
      parts.add(morse);
      units.add(
        MorseUnit(
          source: source,
          index: index,
          normalized: source,
          status: MorseStatus.ok,
          morse: morse,
          debug: {'kind': 'unicode-escape', 'codepoint': rune},
        ),
      );
      index++;
    }

    return MorseResult(
      input: input,
      normalizedInput: normalizedInput,
      kind: MorseInputKind.text,
      output: parts.join(' '),
      units: units,
      hasError: false,
    );
  }

  MorseResult decodeMorse(String input) {
    final normalizedInput = _normalizeMorse(input);
    final tokens = normalizedInput
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    final units = <MorseUnit>[];
    final output = <String>[];
    var hasError = false;

    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      if (token == '/') {
        output.add(' ');
        units.add(
          MorseUnit(
            source: token,
            index: index,
            normalized: token,
            status: MorseStatus.ok,
            morse: token,
            debug: const {'kind': 'word-gap'},
          ),
        );
        continue;
      }

      final char = _morseLatin[token];
      if (char != null) {
        output.add(char);
        units.add(
          MorseUnit(
            source: token,
            index: index,
            normalized: token,
            status: MorseStatus.ok,
            morse: token,
            candidates: _continuousCandidates(token),
            debug: const {'kind': 'morse-token'},
          ),
        );
        continue;
      }

      final candidates = _continuousCandidates(token);
      if (candidates.isNotEmpty) {
        output.add(candidates.first);
        units.add(
          MorseUnit(
            source: token,
            index: index,
            normalized: token,
            status: MorseStatus.ok,
            morse: token,
            candidates: candidates,
            debug: const {'kind': 'continuous-candidate'},
          ),
        );
        continue;
      }

      hasError = true;
      units.add(
        MorseUnit(
          source: token,
          index: index,
          normalized: token,
          status: MorseStatus.error,
          morse: token,
          error: '无法解析 Morse 片段',
          debug: const {'kind': 'unknown-morse'},
        ),
      );
    }

    // 先反转义码点转义（防其数字被误当电报码），再数字段反查电报码；
    // 电报标准字间用空格，逗号（--..--）渲染为空格
    final unescaped = output.join().replaceAllMapped(_codepointEscape, (match) {
      final cp = int.parse(match.group(1)!);
      return cp >= 0 && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF)
          ? String.fromCharCode(cp)
          : match.group(0)!;
    });
    final joined = unescaped.replaceAllMapped(
      RegExp(r'\d+'),
      (match) => _decodeTelegraphDigits(match.group(0)!) ?? match.group(0)!,
    );
    final decoded = joined
        .replaceAll(',', ' ')
        .replaceAllMapped(
          RegExp(r'([一-鿿])(?=[一-鿿])'),
          (match) => '${match.group(1)} ',
        )
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
    return MorseResult(
      input: input,
      normalizedInput: normalizedInput,
      kind: MorseInputKind.morse,
      output: decoded,
      units: units,
      hasError: hasError,
    );
  }

  /// 查电报码：台湾表按繁体收录，未命中时简→繁转换再查（大陆表反向）。
  /// 显示保持用户输入字形，仅编码查询用转换字形。
  String? _lookupTelegraph(String char) {
    final direct = _telegraphCodes[char];
    if (direct != null) return direct;
    final converted = profile == TelegraphProfile.tw
        ? chineseS2t[char]
        : _traditionalToSimplified[char];
    if (converted == null) return null;
    return _telegraphCodes[converted];
  }

  /// 分享打包用的公开查询：字 → 电报码（含简繁互转）。
  String? telegraphCodeOf(String char) => _lookupTelegraph(char);

  /// 电报码 → 显示字（台湾表反查为繁体，转回简体显示）。
  String? charOfTelegraph(String code) {
    final char = _telegraphChars[code];
    if (char == null) return null;
    return _traditionalToSimplified[char] ?? char;
  }

  MorseResult _ambiguous(String input) {
    final encoded = encodeText(input);
    final decoded = decodeMorse(input);
    return MorseResult(
      input: input,
      normalizedInput: encoded.normalizedInput,
      kind: MorseInputKind.ambiguous,
      output: encoded.output,
      units: [
        ...encoded.units,
        MorseUnit(
          source: input,
          index: 0,
          normalized: encoded.normalizedInput,
          status: MorseStatus.ok,
          candidates: [encoded.output, decoded.output],
          debug: const {'kind': 'ambiguous'},
        ),
      ],
      hasError: encoded.hasError || decoded.hasError,
    );
  }

  MorseInputKind _detectKind(String input) {
    final hasMorse = RegExp(r'[.\-·—•]').hasMatch(input);
    final hasText = RegExp(r'[A-Za-z0-9一-鿿]').hasMatch(input);
    if (hasMorse && hasText) return MorseInputKind.ambiguous;
    if (hasMorse) return MorseInputKind.morse;
    return MorseInputKind.text;
  }

  String _normalizeInput(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      final simplified = _traditionalToSimplified[char];
      if (simplified != null) {
        buffer.write(simplified);
      } else if (rune >= 0xff01 && rune <= 0xff5e) {
        buffer.write(String.fromCharCode(rune - 0xfee0));
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  String _normalizeMorse(String input) {
    return input
        .replaceAll('·', '.')
        .replaceAll('•', '.')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('_', '-');
  }

  String? _decodeTelegraphDigits(String value) {
    if (!RegExp(r'^\d+$').hasMatch(value) || value.length % 4 != 0) return null;
    final chars = <String>[];
    for (var index = 0; index < value.length; index += 4) {
      final code = value.substring(index, index + 4);
      final char = _telegraphChars[code];
      if (char == null) return null;
      // 台湾表反查出繁体，显示转回简体
      chars.add(_traditionalToSimplified[char] ?? char);
    }
    return chars.join();
  }

  List<String> _continuousCandidates(String token) {
    if (token.length > 12) return const [];
    final found = <String>[];

    void walk(String rest, String current) {
      if (found.length >= 5) return;
      if (rest.isEmpty) {
        found.add(current);
        return;
      }
      for (final entry in _morseLatin.entries) {
        if (rest.startsWith(entry.key)) {
          walk(rest.substring(entry.key.length), current + entry.value);
        }
      }
    }

    walk(token, '');
    return found.where((candidate) => candidate.length > 1).toList();
  }
}
