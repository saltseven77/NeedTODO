#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

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

  // The calendar is a child process; repeated launches of the primary app must
  // not create competing writers for the same local document.
  const bool calendar = !command_line_arguments.empty() && command_line_arguments[0] == "--calendar";
  HANDLE singleton = nullptr;
  if (!calendar) {
    singleton = CreateMutexW(nullptr, FALSE, L"Local\\NeedTODO.Flutter.Main");
    if (singleton && GetLastError() == ERROR_ALREADY_EXISTS) {
      HWND existing = nullptr;
      for (int retry = 0; retry < 30 && !existing; ++retry) {
        EnumWindows([](HWND hwnd, LPARAM value) -> BOOL {
          if (GetPropW(hwnd, L"NeedTODO.Primary")) { *reinterpret_cast<HWND*>(value)=hwnd; return FALSE; }
          return TRUE;
        }, reinterpret_cast<LPARAM>(&existing));
        if (!existing) Sleep(100);
      }
      if (existing) {
        DWORD owner=0; GetWindowThreadProcessId(existing, &owner); AllowSetForegroundWindow(owner);
        ShowWindowAsync(existing, IsIconic(existing) ? SW_RESTORE : SW_SHOW);
        SetForegroundWindow(existing);
        PostMessage(existing, FlutterWindow::kRestoreMessage, 0, 0);
        DWORD_PTR response=0;
        if (!SendMessageTimeout(existing,WM_NULL,0,0,SMTO_ABORTIFHUNG,1500,&response)) {
          MessageBox(nullptr,L"泥土豆当前暂未响应。请稍候；若持续如此，可在任务管理器中结束泥土豆后重新打开。",L"泥土豆",MB_OK|MB_ICONINFORMATION);
        }
      } else {
        MessageBox(nullptr,L"检测到泥土豆正在启动或已有进程失去窗口。请稍候重试；若持续如此，可在任务管理器中结束泥土豆后重新打开。",L"泥土豆",MB_OK|MB_ICONINFORMATION);
      }
      CloseHandle(singleton);
      CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"NeedTODO", origin, size)) {
    if (singleton) CloseHandle(singleton);
    CoUninitialize();
    return EXIT_FAILURE;
  }
  if (!calendar) SetPropW(window.GetHandle(), L"NeedTODO.Primary", reinterpret_cast<HANDLE>(1));
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0) > 0) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (singleton) CloseHandle(singleton);
  return EXIT_SUCCESS;
}
