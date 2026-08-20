import 'dart:io' show Directory;

import 'package:app_links/app_links.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';

import 'morse_audio.dart';
import 'morse_codec.dart';

import 'share_codec.dart';
import 'share_payload_stub.dart'
    if (dart.library.ui_web) 'share_payload_web.dart';
import 'updater.dart';

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
      home: MorseHomePage(
        themeMode: _themeMode,
        onThemeModeChanged: (themeMode) {
          setState(() => _themeMode = themeMode);
        },
      ),
      // 分享链接形如 https://…/c/<payload>（path 路由，配合 web/_redirects）
      onGenerateRoute: (settings) {
        final payload = shareRoutePayload(settings.name);
        if (payload == null) return null;
        return MaterialPageRoute<void>(
          builder: (_) => MorseHomePage(
            themeMode: _themeMode,
            onThemeModeChanged: (themeMode) {
              setState(() => _themeMode = themeMode);
            },
            initialPayload: payload,
          ),
        );
      },
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

class MorseHomePage extends StatefulWidget {
  const MorseHomePage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.initialPayload,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// 经 /c/<payload> 路由打开时携带的分享 payload。
  final String? initialPayload;

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

/// 网页路由 /c/<payload> → payload；其他路径返回 null。
String? shareRoutePayload(String? name) {
  if (name == null) return null;
  final match = RegExp(r'^/c/([A-Za-z0-9_-]+)$').firstMatch(name);
  return match?.group(1);
}

String shareWebUrl(String base, String payload, String preview) {
  final url = Uri.parse('$base/c/$payload');
  final text = preview.trim();
  if (text.isEmpty) return url.toString();
  return url.replace(queryParameters: {'t': text}).toString();
}

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
  // Web 端通过分享链接打开时，保存对应 morse:// 深链供「在 App 中打开」
  var _shareMorseUrl = '';
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
    if (widget.initialPayload != null) {
      _applyPayload(widget.initialPayload!);
    } else {
      _restoreFromShareUrl();
    }
    _rebuild();
    if (!kIsWeb) _listenDeepLinks();
    // 启动即聚焦输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
    // release 静默检查更新（dev/test 不查）
    if (kReleaseMode && !kIsWeb) _checkUpdate();
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

  /// 打开分享链接时恢复原文与码表：新式 path 链接 /c/<payload>，
  /// 旧式 hash 链接 /#/c/<payload>。直接读 Uri.base（启动时的原始
  /// URL），不依赖 Router——3.47 web 的路由行为不可控，自己读最稳。
  void _restoreFromShareUrl() {
    // index.html 在 Flutter 启动前已把 /c/<payload> 存进 JS 全局
    // （Dart 的 Uri.base 在 path 路由下不可靠）
    final payload = pageSharePayload();
    if (payload == null) return;
    _applyPayload(payload);
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
      _shareMorseUrl = 'morse://convert?c=$payload&p=${decoded.profile.name}';
      markRestored(decoded.text);
    } catch (_) {
      _snack('链接损坏，无法打开');
    }
  }

  /// 分享：弹出链接选择。手机端系统分享面板（微信等）优先，Web 端 https 优先，
  /// 桌面端 morse:// 直达优先；均展示完整链接供复制。
  Future<void> _shareUrl() {
    // 分享的内容是当前的输出：接收方打开后，输出变成其输入（互为镜像——
    // 发文本的对方收到 Morse，发 Morse 的对方收到文本）
    final shareText = _result.output.isNotEmpty
        ? _result.output
        : _inputController.text;
    final payload = const ShareCodec().encode(shareText, profile: _profile);
    final base = kIsWeb ? Uri.base.origin : 'https://morse.embla.cf';
    final httpsUrl = shareWebUrl(base, payload, shareText);
    final morseUrl = 'morse://convert?c=$payload&p=${_profile.name}';
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        // 行定义：链接 + 标题 + 环境说明 + 是否推荐；share=true 调系统分享
        Widget row(
          String? url,
          String title,
          String env,
          bool recommended, {
          bool share = false,
        }) => ListTile(
          leading: Icon(
            title.contains('微信') ? Icons.wechat_outlined : Icons.link,
            size: 20,
            color: recommended ? scheme.secondary : null,
          ),
          title: Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
              if (url != null) ...[
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
            ],
          ),
          isThreeLine: url != null,
          onTap: () async {
            if (share) {
              // iPad/macOS 需要 sharePositionOrigin，缺省会静默不弹面板
              final box = context.findRenderObject() as RenderBox;
              final result = await SharePlus.instance.share(
                ShareParams(
                  text: httpsUrl,
                  title: 'Morse',
                  sharePositionOrigin:
                      box.localToGlobal(Offset.zero) & box.size,
                ),
              );
              if (result.status == ShareResultStatus.unavailable) {
                _snack('系统分享不可用，请改用链接复制');
                return;
              }
            } else {
              await Clipboard.setData(ClipboardData(text: url!));
            }
            if (context.mounted) Navigator.of(context).pop();
            _snack(share ? '已调起系统分享' : '链接已复制');
          },
        );
        // 微信等第三方 IM 拦截自定义 scheme，只有 https 链接在聊天里可点击，
        // 故系统分享一律发 https
        final appsRow = row(
          null,
          '微信 / 系统分享',
          kIsWeb
              ? '手机浏览器调起系统分享面板 · 可直接发微信'
              : '打开系统分享面板选微信 · 聊天里发的是可点击的 https 链接',
          false,
          share: true,
        );
        final httpsRow = row(
          httpsUrl,
          'https 网页链接',
          '全平台通用 · 浏览器直接打开，未装 App 也能看',
          true,
        );
        final morseRow = row(
          morseUrl,
          'morse:// 深链',
          '已安装原生 App（iOS / Android / macOS）直达',
          false,
        );
        // share_plus 不支持 Windows / Linux 原生
        final showAppsRow =
            !(defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.linux) ||
            kIsWeb;
        return SafeArea(
          // 真机 sheet 高度受限，行数多时需滚动，否则深链/https 行被裁掉
          child: SingleChildScrollView(
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
                // https 链接默认第一（全平台可打开），系统分享次之，深链兜底
                httpsRow,
                if (showAppsRow) appsRow,
                morseRow,
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 检查更新：读 CF Pages 上的 update.json（国内可达），
  /// 有新版弹窗，Android 下载 APK 走 gh-proxy 镜像，其他平台开 Release 页。
  Future<void> _checkUpdate({bool manual = false}) async {
    try {
      final info = await fetchLatestUpdate();
      final current = await PackageInfo.fromPlatform();
      if (compareVersions(info.version, current.version) <= 0) {
        if (manual) _snack('已是最新版本');
        return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('发现新版本 v${info.version}'),
          content: Text('当前 v${current.version}，建议更新。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                final url =
                    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                    ? mirrorUrl(info.apk)
                    : info.page;
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              child: const Text('下载更新'),
            ),
          ],
        ),
      );
    } on Exception {
      if (manual) _snack('检查更新失败，请稍后重试');
    }
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
                        onCheckUpdate: () => _checkUpdate(manual: true),
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
                  _openInAppBanner(scheme),
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

  /// Web 端经分享链接打开时：尝试 morse:// 唤起本机 App。
  /// 微信内置浏览器拦截自定义 scheme（仅白名单可跳），此时按钮无效，
  /// 引导用户右上角「…」→ 在浏览器打开后再试。
  Widget _openInAppBanner(ColorScheme scheme) {
    if (!kIsWeb) return const SizedBox.shrink();
    // 常显：装了原生 App 的用户任何入口都能一键跳过去
    final morseUrl = _shareMorseUrl.isNotEmpty
        ? _shareMorseUrl
        : 'morse://convert';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await launchUrl(Uri.parse(morseUrl));
              if (!ok) _snack('无法唤起 App：请改用系统浏览器打开本页');
            },
            icon: const Icon(Icons.smartphone_outlined, size: 16),
            label: const Text('在 App 中打开'),
          ),
          const SizedBox(height: 6),
          Text(
            '微信内打开无效？点右上角「…」→ 在浏览器打开，再点此按钮',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
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
    required this.onCheckUpdate,
  });

  final PlayCount playCount;
  final ValueChanged<PlayCount> onChanged;
  final VoidCallback onCheckUpdate;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late var _playCount = widget.playCount;
  var _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

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
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('检查更新'),
              subtitle: const Text('检查 morse.embla.cf 上的最新版本'),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onCheckUpdate,
            ),
            if (_version.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  '版本 $_version',
                  style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 2.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
