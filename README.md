# Morse 转换器

跨平台 Flutter App，用同一套 Dart 核心库做中英文 Morse 转换。

## 功能

- 英文、数字、常用标点与国际 Morse 双向转换
- 中文先转电报码，再转国际 Morse 数字码
- 支持中国大陆标准和台湾 / 香港标准双表 profile
- 自动识别文本或 Morse 输入
- 严格报错，逐字符展示位置、规范化值、电报码、Morse、候选和调试数据
- 输出可复制

## 中文电报码数据

离线表生成自 [`kirklin/chinese-telegraph-code`](https://github.com/kirklin/chinese-telegraph-code)。

该仓库说明：

- 数据来源：Unicode Unihan 数据库
- 大陆表字段：`kMainlandTelegraph`
- 台湾 / 香港表字段：`kTaiwanTelegraph`
- 代码许可证：MIT
- 数据许可证：Unicode License
- 数据格式：`code`、`character`、`codepoint`

当前项目把 `data/cn.json` 和 `data/tw.json` 生成成 Dart 常量，路径：

- `lib/generated/telegraph_cn_table.dart`
- `lib/generated/telegraph_tw_table.dart`

## 命令

```bash
make help
make run
make lint
make test
make build-macos
make build-android
```

## 开发

```bash
flutter pub get
flutter analyze
flutter test
```

## 已知边界

- 当前主线只支持四位中文电报码。
- 连续点划串没有可靠字符边界，解码只返回候选，不当作唯一真值。
- 五位版本先不纳入当前实现。
