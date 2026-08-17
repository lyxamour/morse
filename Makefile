.PHONY: help run build-macos build-android build-web lint test clean

help:
	@printf '%s\n' \
		'help          显示命令列表' \
		'run           启动 Flutter App' \
		'build-macos   构建 macOS DMG' \
		'build-android 构建 Android APK' \
		'build-web     构建 Web 静态站点' \
		'lint          运行 dart format 检查和 flutter analyze' \
		'test          运行 Flutter 测试' \
		'clean         清理项目产物、Gradle 项目缓存与全局依赖缓存'

run:
	flutter run

build-macos:
	flutter build macos
	hdiutil create -volname "Morse" -srcfolder build/macos/Build/Products/Release/morse.app -ov -format UDZO build/morse.dmg

build-android:
	flutter build apk

build-web:
	flutter build web

lint:
	dart format --set-exit-if-changed lib test
	flutter analyze

test:
	flutter test

clean:
	gradle --stop >/dev/null 2>&1 || true
	flutter clean
	rm -rf android/.gradle android/app/.cxx .dart_tool
	rm -rf $(HOME)/.gradle/caches/modules-2 $(HOME)/.gradle/wrapper/dists
