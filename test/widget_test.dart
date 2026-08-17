import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse/main.dart';

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
    await tester.enterText(find.byType(TextField), 'sos');
    await tester.pump();
    expect(find.textContaining('预期发报'), findsOneWidget);
    // sos: 信号 15u + 间隔 12u = 27u × 90ms = 2430ms
    expect(find.textContaining('长度 11'), findsOneWidget); // '... --- ...'
    expect(find.textContaining('2.4 s'), findsOneWidget);
  });

  testWidgets('设置页可切换播放次数且默认 1 次', (tester) async {
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
  });
}
