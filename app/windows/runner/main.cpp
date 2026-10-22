#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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
  // Default 1280x820 (logical), centered in the primary monitor's work area and
  // shrunk to fit small screens.
  int width = 1280;
  int height = 820;
  int left = 10;
  int top = 10;
  RECT work = {};
  if (::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0)) {
    const POINT zero = {0, 0};
    const UINT dpi = FlutterDesktopGetDpiForMonitor(
        ::MonitorFromPoint(zero, MONITOR_DEFAULTTOPRIMARY));
    const double scale = dpi > 0 ? dpi / 96.0 : 1.0;
    const int work_w = static_cast<int>((work.right - work.left) / scale);
    const int work_h = static_cast<int>((work.bottom - work.top) / scale);
    width = (std::min)(width, (std::max)(480, work_w - 40));
    height = (std::min)(height, (std::max)(560, work_h - 40));
    left = static_cast<int>(work.left / scale) + (std::max)(0, (work_w - width) / 2);
    top = static_cast<int>(work.top / scale) + (std::max)(0, (work_h - height) / 2);
  }
  Win32Window::Point origin(left, top);
  Win32Window::Size size(width, height);
  if (!window.Create(L"Nur", origin, size)) {
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
