#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

// 注册 morse:// URL scheme 到当前用户（HKCU，无需管理员），
// 命令行 "%1" 即深链 URL，由 app_links 插件接收。
static void RegisterUrlScheme() {
  wchar_t exe_path[MAX_PATH];
  GetModuleFileName(nullptr, exe_path, MAX_PATH);
  const std::wstring command = std::wstring(exe_path) + L" \"%1\"";

  auto set = [](HKEY key, const wchar_t* name, const wchar_t* value) {
    RegSetValueEx(key, name, 0, REG_SZ,
                  reinterpret_cast<const BYTE*>(value),
                  static_cast<DWORD>((wcslen(value) + 1) * sizeof(wchar_t)));
  };

  HKEY key;
  if (RegCreateKeyEx(HKEY_CURRENT_USER, L"Software\\Classes\\morse", 0,
                     nullptr, 0, KEY_SET_VALUE, nullptr, &key,
                     nullptr) == ERROR_SUCCESS) {
    set(key, nullptr, L"URL:morse Protocol");
    set(key, L"URL Protocol", L"");
    RegCloseKey(key);
  }
  HKEY cmd_key;
  if (RegCreateKeyEx(HKEY_CURRENT_USER,
                     L"Software\\Classes\\morse\\shell\\open\\command", 0,
                     nullptr, 0, KEY_SET_VALUE, nullptr, &cmd_key,
                     nullptr) == ERROR_SUCCESS) {
    set(cmd_key, nullptr, command.c_str());
    RegCloseKey(cmd_key);
  }
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  RegisterUrlScheme();
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"morse", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
