#include "host_session_overlay.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <windowsx.h>

#include <memory>
#include <string>

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x11
#endif

namespace host_session_overlay {
namespace {

constexpr wchar_t kOverlayClassName[] = L"BimStreamingHostOverlayWindow";
constexpr COLORREF kTransparentKey = RGB(0, 0, 0);
constexpr COLORREF kBorderColor = RGB(255, 0, 0);
constexpr COLORREF kBarColor = RGB(34, 34, 34);
constexpr COLORREF kButtonColor = RGB(214, 65, 65);
constexpr COLORREF kTextColor = RGB(255, 255, 255);

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
HWND g_window = nullptr;
bool g_class_registered = false;
HHOOK g_mouse_hook = nullptr;
std::wstring g_label = L"Session Active";
bool g_privacy_mode = false;

RECT GetVirtualScreenRect() {
  RECT rect;
  rect.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  rect.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  rect.right = rect.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
  rect.bottom = rect.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
  return rect;
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) {
    return L"";
  }

  const int required = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (required <= 0) {
    return L"";
  }

  std::wstring result(required - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, result.data(), required);
  return result;
}

void NotifyDisconnectRequested() {
  if (!g_channel) {
    return;
  }

  g_channel->InvokeMethod(
      "disconnectRequested",
      std::make_unique<flutter::EncodableValue>(flutter::EncodableValue(true)));
}

void PaintOverlay(HWND hwnd, HDC hdc) {
  RECT client{};
  GetClientRect(hwnd, &client);

  HBRUSH background = CreateSolidBrush(kTransparentKey);
  FillRect(hdc, &client, background);
  DeleteObject(background);

  if (g_privacy_mode) {
    HBRUSH blackout_brush = CreateSolidBrush(RGB(0, 0, 0));
    FillRect(hdc, &client, blackout_brush);
    DeleteObject(blackout_brush);

    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, kTextColor);

    HFONT privacy_font = CreateFontW(34, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE,
                                     FALSE, DEFAULT_CHARSET,
                                     OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     CLEARTYPE_QUALITY,
                                     DEFAULT_PITCH | FF_DONTCARE,
                                     L"Segoe UI");
    HFONT old_font = static_cast<HFONT>(SelectObject(hdc, privacy_font));

    RECT text_rect = client;
    DrawTextW(hdc, L"Privacy Mode Active", -1, &text_rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    SelectObject(hdc, old_font);
    DeleteObject(privacy_font);
    return;
  }

  SetBkMode(hdc, TRANSPARENT);

  const int width = client.right - client.left;
  const int height = client.bottom - client.top;

  const int barWidth = 460;
  const int barHeight = 38;
  const int barTop = 16;
  const int barLeft = (width - barWidth) / 2;
  const int barRight = barLeft + barWidth;
  const int barBottom = barTop + barHeight;

  const int buttonWidth = 122;
  const int buttonHeight = 28;
  const int buttonRight = barRight - 10;
  const int buttonLeft = buttonRight - buttonWidth;
  const int buttonTop = barTop + 5;
  const int buttonBottom = buttonTop + buttonHeight;

  HFONT font = CreateFontW(18, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  HFONT oldFont = static_cast<HFONT>(SelectObject(hdc, font));

  HPEN borderPen = CreatePen(PS_SOLID, 3, kBorderColor);
  HGDIOBJ oldPen = SelectObject(hdc, borderPen);
  HGDIOBJ oldBrush = SelectObject(hdc, GetStockObject(NULL_BRUSH));

  MoveToEx(hdc, 0, 0, nullptr);
  LineTo(hdc, width - 1, 0);
  LineTo(hdc, width - 1, height - 1);
  LineTo(hdc, 0, height - 1);
  LineTo(hdc, 0, 0);

  SelectObject(hdc, oldBrush);
  SelectObject(hdc, oldPen);
  DeleteObject(borderPen);

  HBRUSH barBrush = CreateSolidBrush(kBarColor);
  RECT barRect{barLeft, barTop, barRight, barBottom};
  FillRect(hdc, &barRect, barBrush);
  DeleteObject(barBrush);

  HBRUSH buttonBrush = CreateSolidBrush(kButtonColor);
  RECT buttonRect{buttonLeft, buttonTop, buttonRight, buttonBottom};
  FillRect(hdc, &buttonRect, buttonBrush);
  DeleteObject(buttonBrush);

  SetTextColor(hdc, kTextColor);

  RECT labelRect{barLeft + 14, barTop + 2, buttonLeft - 14, barBottom};
  DrawTextW(hdc, g_label.c_str(), -1, &labelRect,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

  RECT buttonTextRect{buttonLeft, buttonTop + 1, buttonRight, buttonBottom};
  DrawTextW(hdc, L"Disconnect X", -1, &buttonTextRect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  SelectObject(hdc, oldFont);
  DeleteObject(font);
}

RECT GetButtonRect(HWND hwnd) {
  RECT client{};
  GetClientRect(hwnd, &client);

  const int width = client.right - client.left;
  const int barWidth = 460;
  const int barTop = 16;
  const int barLeft = (width - barWidth) / 2;
  const int buttonWidth = 122;
  const int buttonHeight = 28;
  const int buttonRight = barLeft + barWidth - 10;
  const int buttonLeft = buttonRight - buttonWidth;
  const int buttonTop = barTop + 5;
  const int buttonBottom = buttonTop + buttonHeight;
  return RECT{buttonLeft, buttonTop, buttonRight, buttonBottom};
}

bool IsInjectedMouseEvent(const MSLLHOOKSTRUCT& info) {
  return (info.flags & LLMHF_INJECTED) != 0 ||
         (info.flags & LLMHF_LOWER_IL_INJECTED) != 0;
}

LRESULT CALLBACK LowLevelMouseProc(int nCode, WPARAM wparam, LPARAM lparam) {
  if (g_privacy_mode) {
    return CallNextHookEx(g_mouse_hook, nCode, wparam, lparam);
  }

  if (nCode == HC_ACTION && g_window != nullptr) {
    const auto* info = reinterpret_cast<MSLLHOOKSTRUCT*>(lparam);
    if (info != nullptr && !IsInjectedMouseEvent(*info)) {
      if (wparam == WM_LBUTTONUP) {
        RECT buttonRect = GetButtonRect(g_window);
        if (PtInRect(&buttonRect, info->pt)) {
          NotifyDisconnectRequested();
        }
      }
    }
  }

  return CallNextHookEx(g_mouse_hook, nCode, wparam, lparam);
}

void UpdateOverlayBounds(HWND hwnd) {
  const RECT rect = GetVirtualScreenRect();
  SetWindowPos(hwnd, HWND_TOPMOST, rect.left, rect.top,
               rect.right - rect.left, rect.bottom - rect.top,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void ApplyOverlayTransparencyMode(HWND hwnd) {
  if (!hwnd) {
    return;
  }

  if (g_privacy_mode) {
    // In privacy mode the overlay must be fully opaque, otherwise desktop is visible.
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
  } else {
    // In normal mode we keep color-key transparency and only paint the session bar.
    SetLayeredWindowAttributes(hwnd, kTransparentKey, 0, LWA_COLORKEY);
  }
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_CREATE: {
      ApplyOverlayTransparencyMode(hwnd);
      SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE);
      UpdateOverlayBounds(hwnd);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
      UpdateOverlayBounds(hwnd);
      InvalidateRect(hwnd, nullptr, TRUE);
      return 0;
    case WM_NCHITTEST: {
      if (g_privacy_mode) {
        return HTCLIENT;
      }
      POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(hwnd, &pt);
      RECT buttonRect = GetButtonRect(hwnd);
      if (PtInRect(&buttonRect, pt)) {
        return HTCLIENT;
      }
      return HTTRANSPARENT;
    }
    case WM_LBUTTONUP: {
      POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      RECT buttonRect = GetButtonRect(hwnd);
      if (PtInRect(&buttonRect, pt)) {
        NotifyDisconnectRequested();
        return 0;
      }
      return HTTRANSPARENT;
    }
    case WM_PAINT: {
      PAINTSTRUCT ps{};
      HDC hdc = BeginPaint(hwnd, &ps);
      PaintOverlay(hwnd, hdc);
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_CLOSE:
      DestroyWindow(hwnd);
      return 0;
    case WM_DESTROY:
      g_window = nullptr;
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

void RegisterOverlayClass() {
  if (g_class_registered) {
    return;
  }

  WNDCLASSW window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kOverlayClassName;
  window_class.lpfnWndProc = WndProc;
  window_class.hbrBackground = nullptr;
  RegisterClassW(&window_class);
  g_class_registered = true;
}

void EnsureMouseHook() {
  if (g_mouse_hook != nullptr) {
    return;
  }

  g_mouse_hook = SetWindowsHookExW(WH_MOUSE_LL, LowLevelMouseProc,
                                   GetModuleHandle(nullptr), 0);
}

void RemoveMouseHook() {
  if (g_mouse_hook == nullptr) {
    return;
  }

  UnhookWindowsHookEx(g_mouse_hook);
  g_mouse_hook = nullptr;
}

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  if (method == "start") {
    if (const auto* arguments = method_call.arguments()) {
      if (std::holds_alternative<flutter::EncodableMap>(*arguments)) {
        const auto& map = std::get<flutter::EncodableMap>(*arguments);
        const auto it = map.find(flutter::EncodableValue("label"));
        if (it != map.end() && std::holds_alternative<std::string>(it->second)) {
          g_label = Utf8ToWide(std::get<std::string>(it->second));
          if (g_label.empty()) {
            g_label = L"Session Active";
          }
        }
      }
    }

    result->Success(flutter::EncodableValue(Start(g_label)));
    return;
  }

  if (method == "stop") {
    result->Success(flutter::EncodableValue(Stop()));
    return;
  }

  if (method == "startPrivacy") {
    result->Success(flutter::EncodableValue(StartPrivacyMode()));
    return;
  }

  if (method == "stopPrivacy") {
    result->Success(flutter::EncodableValue(StopPrivacyMode()));
    return;
  }

  result->NotImplemented();
}

}  // namespace

void Initialize(flutter::BinaryMessenger* messenger) {
  if (g_channel) {
    return;
  }

  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "host_session_overlay",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(HandleMethodCall);
}

bool Start(const std::wstring& label) {
  RegisterOverlayClass();
  g_label = label.empty() ? L"Session Active" : label;
  g_privacy_mode = false;

  if (!g_window) {
    const RECT rect = GetVirtualScreenRect();
    g_window = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE,
        kOverlayClassName, L"", WS_POPUP, rect.left, rect.top,
        rect.right - rect.left, rect.bottom - rect.top, nullptr, nullptr,
        GetModuleHandle(nullptr), nullptr);

    if (!g_window) {
      return false;
    }
  }

  UpdateOverlayBounds(g_window);
  ApplyOverlayTransparencyMode(g_window);
  SetWindowDisplayAffinity(g_window, WDA_EXCLUDEFROMCAPTURE);
  EnsureMouseHook();
  ShowWindow(g_window, SW_SHOWNOACTIVATE);
  UpdateWindow(g_window);
  InvalidateRect(g_window, nullptr, TRUE);
  return true;
}

bool StartPrivacyMode() {
  if (!Start(g_label)) {
    return false;
  }

  g_privacy_mode = true;
  UpdateOverlayBounds(g_window);
  ApplyOverlayTransparencyMode(g_window);
  ShowWindow(g_window, SW_SHOWNOACTIVATE);
  UpdateWindow(g_window);
  InvalidateRect(g_window, nullptr, TRUE);
  return true;
}

bool StopPrivacyMode() {
  if (!g_window) {
    g_privacy_mode = false;
    return true;
  }

  g_privacy_mode = false;
  ApplyOverlayTransparencyMode(g_window);
  InvalidateRect(g_window, nullptr, TRUE);
  return true;
}

bool Stop() {
  if (!g_window) {
    g_privacy_mode = false;
    RemoveMouseHook();
    return true;
  }

  g_privacy_mode = false;
  DestroyWindow(g_window);
  g_window = nullptr;
  RemoveMouseHook();
  return true;
}

void Shutdown() {
  Stop();
  g_channel = nullptr;
}

}  // namespace host_session_overlay