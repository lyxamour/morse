import 'dart:io' show Directory;

import 'package:app_links/app_links.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:torch_light/torch_light.dart';

import 'morse_audio.dart';
import 'morse_codec.dart';
import 'share_codec.dart';

void main() {
  runApp(const MorseApp());
}

// 方向 B · 静谧工具：纯白/近黑双主题，唯一琥珀强调色，排版即层级。
const _amber = Color(0xFFd97706);
const _amberDark = Color(0xFFf0a848);
const _okGreen = Color(0xFF16a34a);
const _okGreenDark = Color(0xFF4ade80);

class MorseApp extends StatefulWidget {
  const MorseApp({super.key});

  @override
  State<MorseApp> createState() => _MorseAppState();
}

class _MorseAppState extends State<MorseApp> {
  var _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Morse',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _themeMode,
      // 宽屏（Web/桌面）收成手机宽度居中，不铺满浏览器
      builder: (context, child) => _PhoneWidthFrame(child: child),
      home: MorseHomePage(
        themeMode: _themeMode,
        onThemeModeChanged: (themeMode) {
          setState(() => _themeMode = themeMode);
        },
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFe8e8e6) : const Color(0xFF1a1a1a);
    final surface = dark ? const Color(0xFF1c1e20) : Colors.white;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: ink,
        onPrimary: surface,
        secondary: dark ? _amberDark : _amber,
        onSecondary: Colors.white,
        error: dark ? _amberDark : _amber,
        onError: Colors.white,
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: dark
            ? const Color(0xFF8a8a86)
            : const Color(0xFFa0a09b),
        outline: dark ? const Color(0xFF33352f) : const Color(0xFFd9d9d5),
        outlineVariant: dark
            ? const Color(0xFF26282a)
            : const Color(0xFFf0f0ec),
      ),
      scaffoldBackgroundColor: surface,
      dividerTheme: DividerThemeData(
        color: dark ? const Color(0xFF26282a) : const Color(0xFFe4e4e0),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class CopyOutputIntent extends Intent {
  const CopyOutputIntent();
}

/// 宽屏下把 app 限制为手机宽度（430）居中，两侧留底色。
class _PhoneWidthFrame extends StatelessWidget {
  const _PhoneWidthFrame({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    if (child == null) return const SizedBox.shrink();
    // 仅 Web 收窄成手机宽度；桌面端铺满窗口
    if (!kIsWeb || MediaQuery.sizeOf(context).width <= 520) return child;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.brightness == Brightness.dark
          ? const Color(0xFF141618)
          : const Color(0xFFececea),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              left: BorderSide(color: scheme.outlineVariant),
              right: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class MorseHomePage extends StatefulWidget {
  const MorseHomePage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<MorseHomePage> createState() => _MorseHomePageState();
}

/// 播放重复次数；forever = 一直连续。
enum PlayCount { once, twice, thrice, five, forever }

const playCountLabels = {
  PlayCount.once: '1 次（默认）',
  PlayCount.twice: '2 次',
  PlayCount.thrice: '3 次',
  PlayCount.five: '5 次',
  PlayCount.forever: '一直连续',
};

/// 播放轮数上限，-1 = 不限。
int playLimit(PlayCount count) => switch (count) {
  PlayCount.once => 1,
  PlayCount.twice => 2,
  PlayCount.thrice => 3,
  PlayCount.five => 5,
  PlayCount.forever => -1,
};

/// morse://convert?c=<payload> 深链 → payload 字符串；其他 URI 返回 null。
String? morseLinkPayload(Uri uri) {
  if (uri.scheme != 'morse' || uri.host != 'convert') return null;
  return uri.queryParameters['c'];
}

class _MorseHomePageState extends State<MorseHomePage> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  final _audioPlayer = AudioPlayer();
  var _playing = false;
  var _flashing = false;
  var _torchGeneration = 0;
  var _playCount = PlayCount.once;
  var _rounds = 0;
  Uint8List? _wav;
  var _profile = TelegraphProfile.cn;
  var _result = const MorseResult(
    input: '',
    normalizedInput: '',
    kind: MorseInputKind.text,
    output: '',
    units: [],
    hasError: false,
  );

  MorseCodec get _codec => MorseCodec(profile: _profile);

  @override
  void initState() {
    super.initState();
    _restoreFromShareUrl();
    _rebuild();
    if (!kIsWeb) _listenDeepLinks();
    // 启动即聚焦输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
    _audioPlayer.onPlayerComplete.listen((_) async {
      if (!mounted || !_playing) return;
      _rounds++;
      final limit = playLimit(_playCount);
      if (limit < 0 || _rounds < limit) {
        await _startAudio();
      } else {
        setState(() => _playing = false);
      }
    });
  }

  @override
  void dispose() {
    _torchGeneration++;
    _audioPlayer.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// morse:// 深链：冷启动（getInitialLink）与运行中（uriLinkStream）均恢复。
  void _listenDeepLinks() {
    final appLinks = AppLinks();
    appLinks.uriLinkStream.listen(
      (uri) => _applyDeepLink(uri),
      onError: (Object _) {}, // 平台不支持时静默
    );
    appLinks.getInitialLink().then(
      (uri) {
        if (uri != null) _applyDeepLink(uri);
      },
      // 冷启动无链接时部分平台抛错，忽略
      onError: (Object _) {},
    );
  }

  void _applyDeepLink(Uri uri) {
    final payload = morseLinkPayload(uri);
    if (payload == null) return;
    if (!mounted) return;
    _applyPayload(payload);
  }

  /// 打开分享链接（…/#/c/<payload>）时恢复原文与码表。
  void _restoreFromShareUrl() {
    final match = RegExp(
      r'^/c/([A-Za-z0-9_-]+)$',
    ).firstMatch(Uri.base.fragment);
    if (match == null) return;
    _applyPayload(match.group(1)!);
  }

  /// 外部边界：链接可能损坏，解码失败提示而非崩溃。
  void _applyPayload(String payload) {
    try {
      final decoded = const ShareCodec().decode(payload);
      setState(() {
        _profile = decoded.profile;
        _inputController.text = decoded.text;
        _result = MorseCodec(profile: decoded.profile).convert(decoded.text);
      });
    } catch (_) {
      _snack('链接损坏，无法打开');
    }
  }

  /// 分享：弹出链接选择。原生端 morse:// 直达优先，Web 端 https 优先，
  /// 另一项标注为兼容模式，均展示完整链接供复制。
  Future<void> _shareUrl() {
    final payload = const ShareCodec().encode(
      _inputController.text,
      profile: _profile,
    );
    final base = kIsWeb ? Uri.base.origin : 'https://morse.embla.cf';
    final httpsUrl = '$base/#/c/$payload';
    final morseUrl = 'morse://convert?c=$payload&p=${_profile.name}';
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        // 行定义：链接 + 标题 + 环境说明 + 是否推荐
        Widget row(String url, String title, String env, bool recommended) =>
            ListTile(
              leading: Icon(
                recommended ? Icons.link : Icons.open_in_new_outlined,
                size: 20,
                color: recommended ? scheme.secondary : null,
              ),
              title: Row(
                children: [
                  Text(title, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: recommended ? scheme.secondary : scheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      recommended ? '推荐' : '兼容模式',
                      style: TextStyle(
                        fontSize: 10,
                        color: recommended ? scheme.secondary : null,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(env, style: const TextStyle(fontSize: 11.5)),
                  const SizedBox(height: 4),
                  SelectableText(
                    url,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              isThreeLine: true,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) Navigator.of(context).pop();
                _snack('链接已复制');
              },
            );
        final httpsRow = row(
          httpsUrl,
          'https 网页链接',
          '全平台通用 · 浏览器直接打开，未装 App 也能看',
          kIsWeb,
        );
        final morseRow = row(
          morseUrl,
          'morse:// 深链',
          '已安装原生 App（iOS / Android / macOS）直达',
          !kIsWeb,
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(32, 0, 32, 4),
                child: Text(
                  '分享',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              if (!kIsWeb) ...[morseRow, httpsRow] else ...[httpsRow, morseRow],
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _rebuild() {
    if (_playing) {
      _playing = false;
      _audioPlayer.stop();
    }
    setState(() {
      _result = _codec.convert(_inputController.text);
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _result.output));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('输出已复制')));
  }

  /// 播放对象：输出的 Morse（encode 模式），或把输出中文重新编码（decode 模式）。
  String get _playableMorse => _result.kind == MorseInputKind.morse
      ? _codec.encodeText(_result.output).output
      : _result.output;

  Future<void> _startAudio() async {
    await _audioPlayer.play(
      BytesSource(_wav!, mimeType: 'audio/wav'),
      position: Duration.zero,
    );
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    _wav = buildMorseWav(_playableMorse);
    if (!kIsWeb) {
      // audioplayers macOS/iOS/Linux 写字节前不建临时目录（sandbox 首启无 Caches 目录会崩）
      final tempDir = await getTemporaryDirectory();
      await Directory(tempDir.path).create(recursive: true);
    }
    _rounds = 1;
    await _startAudio();
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _toggleFlash() async {
    if (_flashing) {
      _torchGeneration++;
      try {
        await TorchLight.disableTorch();
      } on Exception {
        // 手电筒已不可用，忽略
      }
      if (mounted) setState(() => _flashing = false);
      return;
    }
    try {
      await TorchLight.enableTorch();
      await TorchLight.disableTorch();
    } on Exception catch (e) {
      _snack('手电筒不可用：$e');
      return;
    }
    if (mounted) setState(() => _flashing = true);
    final generation = ++_torchGeneration;
    final limit = playLimit(_playCount);
    var rounds = 0;
    while (limit < 0 || rounds < limit) {
      rounds++;
      for (final signal in buildSignalPlan(_playableMorse)) {
        if (generation != _torchGeneration) return;
        try {
          if (signal.on) {
            await TorchLight.enableTorch();
          } else {
            await TorchLight.disableTorch();
          }
          await Future.delayed(Duration(milliseconds: signal.ms));
        } on Exception {
          return;
        }
      }
      // 轮间用词间隔（7u = 630ms）分隔
      if (limit < 0 || rounds < limit) {
        await Future.delayed(const Duration(milliseconds: 630));
      }
    }
    if (generation != _torchGeneration) return;
    try {
      await TorchLight.disableTorch();
    } on Exception {
      // 忽略
    }
    if (mounted) setState(() => _flashing = false);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyC, alt: true): CopyOutputIntent(),
      },
      child: Actions(
        actions: {
          CopyOutputIntent: CallbackAction<CopyOutputIntent>(
            onInvoke: (_) {
              _copyOutput();
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text(
              'Morse 转换器',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: .5,
              ),
            ),
            actions: [
              IconButton(
                tooltip: '复制分享链接',
                onPressed: _inputController.text.isEmpty ? null : _shareUrl,
                icon: const Icon(Icons.share_outlined, size: 20),
              ),
              IconButton(
                tooltip: '设置',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(
                        playCount: _playCount,
                        onChanged: (count) =>
                            setState(() => _playCount = count),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.settings_outlined, size: 20),
              ),
              IconButton(
                tooltip: '切换黑白模式',
                onPressed: () {
                  widget.onThemeModeChanged(
                    widget.themeMode == ThemeMode.dark
                        ? ThemeMode.light
                        : ThemeMode.dark,
                  );
                },
                icon: Icon(
                  widget.themeMode == ThemeMode.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  size: 20,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _profileSwitch(scheme),
                  const SizedBox(height: 44),
                  _label('输入 · ${_result.kind.name}'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _inputController,
                    focusNode: _inputFocus,
                    maxLines: 4,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      height: 1.7,
                    ),
                    decoration: const InputDecoration(
                      border: UnderlineInputBorder(),
                      focusedBorder: UnderlineInputBorder(),
                    ),
                    onChanged: (_) => _rebuild(),
                  ),
                  const SizedBox(height: 48),
                  _label('输出'),
                  if (_result.output.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _result.output,
                            style: TextStyle(
                              fontSize: _result.output.length > 24 ? 30 : 48,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              letterSpacing: 1,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        _playbackButtons(),
                        IconButton(
                          tooltip: '复制输出',
                          onPressed: _copyOutput,
                          icon: const Icon(Icons.copy_outlined, size: 18),
                        ),
                      ],
                    ),
                    if (_telegraphLine().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        _telegraphLine(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _statsLine(),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 48),
                  _label('逐字明细 · ${_result.units.length} UNITS'),
                  const SizedBox(height: 4),
                  ..._result.units.indexed.map((entry) {
                    final (index, unit) = entry;
                    return _unitRow(scheme, index, unit);
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playbackButtons() {
    final onPhone =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _playing ? '停止播放' : '播放 Morse 音频',
          onPressed: _togglePlay,
          icon: Icon(
            _playing ? Icons.stop_outlined : Icons.volume_up_outlined,
            size: 18,
            color: _playing ? Theme.of(context).colorScheme.secondary : null,
          ),
        ),
        if (onPhone)
          IconButton(
            tooltip: _flashing ? '停止闪烁' : '手电筒闪烁 Morse',
            onPressed: _toggleFlash,
            icon: Icon(
              Icons.highlight_outlined,
              size: 18,
              color: _flashing ? Theme.of(context).colorScheme.secondary : null,
            ),
          ),
      ],
    );
  }

  Widget _profileSwitch(ColorScheme scheme) {
    return SegmentedButton<TelegraphProfile>(
      segments: const [
        ButtonSegment(
          value: TelegraphProfile.cn,
          label: Text('中国大陆标准', style: TextStyle(fontSize: 12.5)),
        ),
        ButtonSegment(
          value: TelegraphProfile.tw,
          label: Text('台湾 / 香港标准', style: TextStyle(fontSize: 12.5)),
        ),
      ],
      selected: {_profile},
      showSelectedIcon: false,
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        visualDensity: VisualDensity.compact,
      ),
      onSelectionChanged: (selection) {
        setState(() {
          _profile = selection.first;
          _result = _codec.convert(_inputController.text);
        });
      },
    );
  }

  Widget _label(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        letterSpacing: 2.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  String _telegraphLine() {
    return _result.units
        .where((unit) => unit.telegraphCode != null)
        .map((unit) => '${unit.telegraphCode}→${unit.source}')
        .join('  ');
  }

  /// 输出长度 + 单次预期发报耗时（dot 1u=90ms 标准）。
  String _statsLine() {
    final length = _result.output.runes.length;
    final totalMs = buildSignalPlan(
      _playableMorse,
    ).fold<int>(0, (sum, signal) => sum + signal.ms);
    return '长度 $length · 预期发报 ${formatMorseDuration(totalMs)}';
  }

  Widget _unitRow(ColorScheme scheme, int index, MorseUnit unit) {
    final ok = unit.status == MorseStatus.ok;
    final okColor = scheme.brightness == Brightness.dark
        ? _okGreenDark
        : _okGreen;
    final sub = [
      if (unit.telegraphCode != null) '电报码 ${unit.telegraphCode}',
      if (unit.morse != null && unit.morse!.isNotEmpty) 'Morse ${unit.morse}',
      if (unit.candidates.isNotEmpty) '候选 ${unit.candidates.join(' | ')}',
      if (unit.error != null) '${unit.error}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                index.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  unit.source,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '位置 ${unit.index}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Text(
                ok ? 'OK' : '错误',
                style: TextStyle(
                  fontSize: 12,
                  color: ok ? okColor : scheme.secondary,
                ),
              ),
            ],
          ),
          if (sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: Text(
                sub,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

// StatefulWidget：push 后父级 setState 不刷新已推入路由，本地持有选中值
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.playCount,
    required this.onChanged,
  });

  final PlayCount playCount;
  final ValueChanged<PlayCount> onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late var _playCount = widget.playCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '设置',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '播放重复次数 · 声音与闪光共用',
                style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 2.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            RadioGroup<PlayCount>(
              groupValue: _playCount,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _playCount = value);
                widget.onChanged(value);
              },
              child: Column(
                children: [
                  for (final count in PlayCount.values)
                    RadioListTile<PlayCount>(
                      value: count,
                      title: Text(playCountLabels[count]!),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
