import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse/main.dart';
import 'package:morse/share_codec.dart';

void main() {
  testWidgets('空输入启动并允许切换电报码表和黑白模式', (tester) async {
    await tester.pumpWidget(const MorseApp());

    expect(find.text('Morse 转换器'), findsOneWidget);
    expect(find.text('中国大陆标准'), findsOneWidget);
    expect(find.text('台湾 / 香港标准'), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    await tester.tap(find.text('台湾 / 香港标准'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换黑白模式'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });

  testWidgets('有输出时展示长度与预期发报耗时', (tester) async {
    await tester.pumpWidget(const MorseApp());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    await tester.enterText(find.byType(TextField), 'sos');
    await tester.pump();
    expect(find.textContaining('预期发报'), findsOneWidget);
    // sos: 信号 15u + 间隔 12u = 27u × 90ms = 2430ms
    expect(find.textContaining('长度 11'), findsOneWidget); // '... --- ...'
    expect(find.textContaining('2.4 s'), findsOneWidget);
  });

  testWidgets('分享面板：手机端系统分享优先并标注推荐/兼容', (tester) async {
    await tester.pumpWidget(const MorseApp());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    await tester.enterText(find.byType(TextField), 'sos');
    await tester.pump();
    await tester.tap(find.byTooltip('复制分享链接'));
    await tester.pumpAndSettle();

    // 测试环境为 Android：微信/系统分享行排最前
    final appsTop = tester.getTopLeft(find.text('微信 / 系统分享')).dy;
    final morseTop = tester.getTopLeft(find.text('morse:// 深链')).dy;
    final httpsTop = tester.getTopLeft(find.text('https 网页链接')).dy;
    expect(httpsTop < appsTop && appsTop < morseTop, isTrue);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('兼容模式'), findsNWidgets(2));
    expect(
      find.textContaining(RegExp(r'morse://convert\?c=[A-Za-z0-9_-]+&p=cn')),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'morse.embla.cf/c/')), findsOneWidget);

    await tester.tap(find.text('morse:// 深链'));
    await tester.pumpAndSettle();
    expect(find.text('链接已复制'), findsOneWidget);
  });

  testWidgets('分享内容是当前输出：发文本收到 Morse，发 Morse 收到文本', (tester) async {
    String payloadOf() {
      final url = tester
          .widget<SelectableText>(find.byType(SelectableText).first)
          .data!;
      // morse:// 链接是 c=<payload>，https 链接是 #/c/<payload>
      return RegExp(r'c[=/]([A-Za-z0-9_-]+)').firstMatch(url)![1]!;
    }

    await tester.pumpWidget(const MorseApp());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );

    // 文本输入：分享的是 Morse 输出
    await tester.enterText(find.byType(TextField), 'sos');
    await tester.pump();
    await tester.tap(find.byTooltip('复制分享链接'));
    await tester.pumpAndSettle();
    expect(const ShareCodec().decode(payloadOf()).text, '... --- ...');
    await tester.tap(find.text('https 网页链接'));
    await tester.pumpAndSettle();

    // Morse 输入：分享的是解码文本
    await tester.enterText(find.byType(TextField), '... --- ...');
    await tester.pump();
    await tester.tap(find.byTooltip('复制分享链接'));
    await tester.pumpAndSettle();
    expect(const ShareCodec().decode(payloadOf()).text, 'SOS');
  });

  testWidgets('设置页可切换播放次数且默认 1 次，显示版本号', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'morse',
      packageName: 'com.example.morse',
      version: '0.0.1',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(const MorseApp());
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    RadioGroup<PlayCount> groupOf() =>
        tester.widget(find.byType(RadioGroup<PlayCount>));
    expect(groupOf().groupValue, PlayCount.once);
    await tester.tap(find.text('一直连续'));
    await tester.pumpAndSettle();
    expect(groupOf().groupValue, PlayCount.forever);
    await tester.pump();
    expect(find.text('版本 0.0.1'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('分享路由打开后恢复 payload 内容', (tester) async {
    final payload = const ShareCodec().encode('sos');
    await tester.pumpWidget(const MorseApp());

    Navigator.of(
      tester.element(find.byType(MorseHomePage)),
    ).pushNamed('/c/$payload');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'sos'), findsOneWidget);
    expect(find.text('... --- ...'), findsOneWidget);
  });

  testWidgets('损坏分享路由显示错误提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MorseHomePage(
          themeMode: ThemeMode.dark,
          onThemeModeChanged: _noopThemeMode,
          initialPayload: 'bad',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('链接损坏，无法打开'), findsOneWidget);
  });

  testWidgets('复制输出按钮写入剪贴板并提示', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );

    await tester.pumpWidget(const MorseApp());
    await tester.enterText(find.byType(TextField), 'sos');
    await tester.pump();
    await tester.tap(find.byTooltip('复制输出'));
    await tester.pump();

    expect(calls.any((call) => call.method == 'Clipboard.setData'), isTrue);
    expect(find.text('输出已复制'), findsOneWidget);
  });

  testWidgets('设置页检查更新触发回调', (tester) async {
    var checked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          playCount: PlayCount.once,
          onChanged: (_) {},
          onCheckUpdate: () => checked = true,
        ),
      ),
    );

    await tester.tap(find.text('检查更新'));
    await tester.pump();

    expect(checked, isTrue);
  });
}

void _noopThemeMode(ThemeMode _) {}
