#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <dwmapi.h>

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
    } else { result->NotImplemented(); }
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SetDesktopEmbedded(false);
  platform_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::SetDesktopEmbedded(bool enabled) {
  HWND hwnd = GetHandle();
  if (!hwnd || !IsWindow(hwnd)) return !enabled;
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
    if (flutter_controller_) flutter_controller_->ForceRedraw();
  };
  if (!enabled) {
    if (desktop_parent_) restore();
    embedding_transition_ = false;
    return true;
  }
  HWND host = FindWindow(L"Progman", nullptr);
  if (!host) { embedding_transition_ = false; return false; }
  if (!FindWindowEx(host, nullptr, L"SHELLDLL_DefView", nullptr)) {
    HWND worker = nullptr; host = nullptr;
    while ((worker = FindWindowEx(nullptr, worker, L"WorkerW", nullptr))) {
      if (FindWindowEx(worker, nullptr, L"SHELLDLL_DefView", nullptr)) { host = worker; break; }
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
  if (flutter_controller_) flutter_controller_->ForceRedraw();
  embedding_transition_ = false;
  return true;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    if (result) {
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
