#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

std::wstring GetStartupLogPath() {
  wchar_t temp_path[MAX_PATH + 1] = {};
  DWORD length = GetTempPathW(MAX_PATH, temp_path);
  if (length == 0 || length > MAX_PATH) {
    return L"bim_streaming_startup.log";
  }
  return std::wstring(temp_path) + L"bim_streaming_startup.log";
}

void WriteStartupLog(const std::string& message) {
  const std::wstring path = GetStartupLogPath();
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  std::string line = message + "\r\n";
  WriteFile(file, line.c_str(), static_cast<DWORD>(line.size()), &written,
            nullptr);
  CloseHandle(file);
}

void ShowStartupError(const wchar_t* message) {
  MessageBoxW(nullptr, message, L"BimStreaming startup error",
             MB_OK | MB_ICONERROR);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  WriteStartupLog("wWinMain: start");
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
  WriteStartupLog("wWinMain: project ready");

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"bim_streaming", origin, size)) {
    WriteStartupLog("wWinMain: window.Create failed");
    ShowStartupError(L"Failed to create the BimStreaming window.");
    return EXIT_FAILURE;
  }
  WriteStartupLog("wWinMain: window created");
  window.SetQuitOnClose(true);
  ::ShowWindow(window.GetHandle(), SW_MAXIMIZE);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  WriteStartupLog("wWinMain: exit loop");
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
