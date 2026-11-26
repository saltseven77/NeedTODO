#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <cwchar>
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 41;


}

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  platform_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.needtodo/platform",
      &flutter::StandardMethodCodec::GetInstance());
  platform_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "embed") {
      const auto* enabled = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!enabled) { result->Error("argument", "Invalid desktop state"); return; }
      if (!SetDesktopEmbedded(*enabled)) { result->Error("desktop", "Windows 桌面暂不可用"); return; }
      result->Success();
    } else if (call.method_name() == "refreshLayout") {
      RefreshContent(); result->Success();
    } else if (call.method_name() == "calendarAlive") {
      const auto* pid = call.arguments() ? std::get_if<int>(call.arguments()) : nullptr;
      if (!pid) { result->Error("argument", "Invalid calendar process"); return; }
      struct Search { DWORD pid; bool found; } search{static_cast<DWORD>(*pid), false};
      const auto inspect = [](HWND hwnd, LPARAM value) -> BOOL {
        auto* search = reinterpret_cast<Search*>(value); DWORD pid = 0; GetWindowThreadProcessId(hwnd, &pid);
        wchar_t name[128]{}; GetClassName(hwnd, name, 128);
        if (pid == search->pid && wcscmp(name, L"FLUTTER_RUNNER_WIN32_WINDOW") == 0) search->found = true;
        return TRUE;
      };
      struct Walk { Search* search; WNDENUMPROC inspect; } walk{&search, inspect};
      EnumWindows([](HWND hwnd, LPARAM value) -> BOOL {
        auto* walk = reinterpret_cast<Walk*>(value); walk->inspect(hwnd, reinterpret_cast<LPARAM>(walk->search));
        EnumChildWindows(hwnd, walk->inspect, reinterpret_cast<LPARAM>(walk->search)); return TRUE;
      }, reinterpret_cast<LPARAM>(&walk));
      result->Success(flutter::EncodableValue(search.found));
    } else if (call.method_name() == "trayEnable") {
      const auto* enabled = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!enabled || !SetTrayEnabled(*enabled)) { result->Error("tray", "系统托盘暂不可用"); return; }
      result->Success();
    } else if (call.method_name() == "trayMenu") {
      ShowTrayMenu(); result->Success();
    } else { result->NotImplemented(); }
  });
  taskbar_created_ = RegisterWindowMessage(L"TaskbarCreated");

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    first_frame_presented_ = true;
    if(GetPropW(GetHandle(),L"NeedTODO.HoverNote"))ShowWindow(GetHandle(),SW_SHOWNOACTIVATE);
    else this->Show();
    PostMessage(GetHandle(), kEmbedAfterFrame, 0, 0);
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SetTrayEnabled(false);
  SetDesktopEmbedded(false);
  platform_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::SetTrayEnabled(bool enabled) {
  NOTIFYICONDATA data{};
  data.cbSize = static_cast<DWORD>(sizeof(data));
  data.hWnd = GetHandle();
  data.uID = 1;
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"泥土豆 · NeedTODO");
  if (!enabled) {
    if (tray_enabled_) Shell_NotifyIcon(NIM_DELETE, &data);
    tray_enabled_ = false;
    return true;
  }
  if (tray_enabled_) return true;
  tray_enabled_ = Shell_NotifyIcon(NIM_ADD, &data) != FALSE;
  return tray_enabled_;
}

void FlutterWindow::ShowTrayMenu() {
  if (!tray_enabled_ || !platform_channel_) return;
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenu(menu, MF_STRING, 1, L"打开清单");
  AppendMenu(menu, MF_STRING, 2, L"桌面月历");
  AppendMenu(menu, MF_STRING, 3, L"悬浮球");
  AppendMenu(menu, MF_STRING, 5, L"关闭悬浮球");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, 4, L"退出软件");
  POINT position{};
  GetCursorPos(&position);
  SetForegroundWindow(GetHandle());
  const auto selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
      position.x, position.y, 0, GetHandle(), nullptr);
  DestroyMenu(menu);
  PostMessage(GetHandle(), WM_NULL, 0, 0);
  if (selected) platform_channel_->InvokeMethod("trayAction",
      std::make_unique<flutter::EncodableValue>(static_cast<int>(selected)));
}

void FlutterWindow::RefreshContent() {
  if (!flutter_controller_ || !GetHandle() || IsIconic(GetHandle())) return;
  RECT rect{}; GetClientRect(GetHandle(), &rect);
  const int width = rect.right - rect.left, height = rect.bottom - rect.top;
  if (width <= 0 || height <= 0) return;
  const HWND view = flutter_controller_->view()->GetNativeWindow();
  SetWindowPos(view, nullptr, 0, 0, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
  RedrawWindow(view, nullptr, nullptr, RDW_INVALIDATE | RDW_ALLCHILDREN);
  flutter_controller_->ForceRedraw();
}

bool FlutterWindow::SetDesktopEmbedded(bool enabled) {
  HWND hwnd = GetHandle();
  if (!hwnd || !IsWindow(hwnd)) return !enabled;
  if (!enabled) pending_embed_ = false;
  if (enabled && !first_frame_presented_) { pending_embed_ = true; return true; }
  if (embedding_transition_) return false;
  if (enabled && desktop_parent_ && IsWindow(desktop_parent_) && GetParent(hwnd) == desktop_parent_) return true;
  embedding_transition_ = true;
  const auto restore = [&]() {
    SetParent(hwnd, nullptr);
    SetWindowLongPtr(hwnd, GWL_STYLE, original_style_);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, original_ex_style_);
    desktop_parent_ = nullptr;
    SetWindowPos(hwnd, HWND_NOTOPMOST, desktop_bounds_.left, desktop_bounds_.top,
        desktop_bounds_.right-desktop_bounds_.left, desktop_bounds_.bottom-desktop_bounds_.top,
        SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    RefreshContent();
  };
  if (!enabled) {
    if (desktop_parent_) restore();
    embedding_transition_ = false;
    return true;
  }
  HWND shell = FindWindow(L"Progman", nullptr);
  DWORD shell_pid = 0; if (shell) GetWindowThreadProcessId(shell, &shell_pid);
  const auto valid_host = [shell_pid](HWND host) {
    DWORD pid = 0; RECT area{}; GetWindowThreadProcessId(host, &pid);
    return shell_pid && pid == shell_pid && IsWindowVisible(host) && GetClientRect(host, &area) &&
        area.right > area.left && area.bottom > area.top &&
        FindWindowEx(host, nullptr, L"SHELLDLL_DefView", nullptr);
  };
  HWND host = valid_host(shell) ? shell : nullptr;
  if (!host) { HWND worker = nullptr;
    while ((worker = FindWindowEx(nullptr, worker, L"WorkerW", nullptr))) {
      if (valid_host(worker)) { host = worker; break; }
    }
  }
  if (!host) { embedding_transition_ = false; return false; }
  GetWindowRect(hwnd, &desktop_bounds_);
  original_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
  original_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  SetWindowPos(hwnd, HWND_NOTOPMOST, 0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
  // Win32 requires WS_CHILD before SetParent; keep physical screen geometry.
  SetWindowLongPtr(hwnd, GWL_STYLE, (original_style_ & ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME)) | WS_CHILD | WS_VISIBLE);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, (original_ex_style_ & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW);
  const auto previous = SetThreadDpiAwarenessContext(GetWindowDpiAwarenessContext(host));
  SetLastError(0); SetParent(hwnd, host); const auto error = GetLastError();
  SetThreadDpiAwarenessContext(previous);
  if (error || GetParent(hwnd) != host) {
    restore(); embedding_transition_ = false; return false;
  }
  desktop_parent_ = host;
  POINT point{desktop_bounds_.left, desktop_bounds_.top};
  MapWindowPoints(HWND_DESKTOP, host, &point, 1);
  SetWindowPos(hwnd, HWND_TOP, point.x, point.y,
      desktop_bounds_.right-desktop_bounds_.left, desktop_bounds_.bottom-desktop_bounds_.top,
      SWP_FRAMECHANGED|SWP_NOACTIVATE|SWP_SHOWWINDOW);
  RefreshContent();
  embedding_transition_ = false;
  return true;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if(message==WM_MOUSEACTIVATE && GetPropW(hwnd,L"NeedTODO.HoverNote"))return MA_NOACTIVATE;
  if (message == kEmbedAfterFrame) {
    if (pending_embed_) {
      pending_embed_ = false;
      if (!SetDesktopEmbedded(true) && platform_channel_) {
        platform_channel_->InvokeMethod("desktopEmbedFailed", nullptr);
      }
    }
    RefreshContent(); return 0;
  }
  // Keep Flutter's child viewport in sync even if a plugin consumes WM_SIZE.
  if (message == WM_SIZE && wparam != SIZE_MINIMIZED) RefreshContent();
  if (message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE &&
      GetPropW(hwnd, L"NeedTODO.Primary") && platform_channel_) {
    const bool from_hover = lparam && GetPropW(reinterpret_cast<HWND>(lparam),L"NeedTODO.HoverNote");
    if (!from_hover) platform_channel_->InvokeMethod("primaryActivated", nullptr);
  }
  if (message == kRestoreMessage && platform_channel_) {
    platform_channel_->InvokeMethod("trayAction", std::make_unique<flutter::EncodableValue>(1));
    return 0;
  }
  if (taskbar_created_ && message == taskbar_created_ && tray_enabled_) {
    tray_enabled_ = false;
    SetTrayEnabled(true);
    return 0;
  }
  if (message == kTrayMessage && platform_channel_) {
    if (lparam == WM_RBUTTONUP) ShowTrayMenu();
    else if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
      platform_channel_->InvokeMethod("trayAction", std::make_unique<flutter::EncodableValue>(1));
    }
    return 0;
  }
  // Suggested DPI rectangles are screen coordinates. Applying them to an
  // Explorer child as parent-local coordinates makes the calendar jump/resize.
  if (message == WM_DPICHANGED && (embedding_transition_ || desktop_parent_)) return 0;
  if (message == WM_WINDOWPOSCHANGING && desktop_parent_ && !embedding_transition_) {
    auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
    position->flags |= SWP_NOMOVE | SWP_NOSIZE;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result && message != WM_DESTROY) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
