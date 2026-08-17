import 'package:flutter_test/flutter_test.dart';
import 'package:morse/updater.dart';

void main() {
  test('版本比较：新旧与相等', () {
    expect(compareVersions('0.0.2', '0.0.1'), 1);
    expect(compareVersions('0.1.0', '0.0.9'), 1);
    expect(compareVersions('1.0.0', '0.9.9'), 1);
    expect(compareVersions('0.0.1', '0.0.1'), 0);
    expect(compareVersions('0.0.1', '0.0.2'), -1);
    // 缺段按 0
    expect(compareVersions('0.1', '0.0.1'), 1);
  });

  test('解析 update.json', () {
    final info = parseUpdate(
      '{"version":"0.0.2","apk":"https://github.com/lyxamour/morse/releases/download/v0.0.2/morse-0.0.2-arm64.apk","page":"https://github.com/lyxamour/morse/releases/tag/v0.0.2"}',
    );
    expect(info.version, '0.0.2');
    expect(info.apk, contains('arm64.apk'));
    expect(info.page, contains('releases/tag'));
  });

  test('GitHub 链接加国内镜像前缀，非 GitHub 原样返回', () {
    expect(
      mirrorUrl('https://github.com/lyxamour/morse/releases/download/v1/a.apk'),
      'https://gh-proxy.com/https://github.com/lyxamour/morse/releases/download/v1/a.apk',
    );
    expect(
      mirrorUrl('https://morse.embla.cf/update.json'),
      'https://morse.embla.cf/update.json',
    );
  });
}
