import 'dart:ffi';
import 'dart:io' as io;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// System-level overlay window for host session indicator.
/// Rendered in a separate system window, excluded from screen capture.
/// Not visible to remote controller via SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE).
class HostSessionOverlay {
  static int? _overlayHwnd;
  static const String _windowClassName = 'BIMStreamingSessionOverlay';
  
  /// Create and show the host session overlay window.
  static bool startOverlay() {
    if (!io.Platform.isWindows) return false;
    if (_overlayHwnd != null) return true;

    try {
      _registerWindowClass();
      _overlayHwnd = _createOverlayWindow();
      if (_overlayHwnd == null || _overlayHwnd == 0) {
        return false;
      }

      // Exclude this window from screen capture
      // so it appears only on host, not in remote stream.
      _excludeFromCapture(_overlayHwnd!);

      // Show the window
      win32.ShowWindow(_overlayHwnd!, win32.SW_SHOW);
      win32.UpdateWindow(_overlayHwnd!);

      return true;
    } catch (e) {
      print('[HostSessionOverlay] Start failed: $e');
      return false;
    }
  }

  /// Destroy the overlay window.
  static bool stopOverlay() {
    if (_overlayHwnd == null || _overlayHwnd == 0) return true;

    try {
      win32.DestroyWindow(_overlayHwnd!);
      _overlayHwnd = null;
      return true;
    } catch (e) {
      print('[HostSessionOverlay] Stop failed: $e');
      return false;
    }
  }

  static void _registerWindowClass() {
    final classNamePtr = _windowClassName.toNativeUtf16();
    final wndClass = calloc<win32.WNDCLASS>();

    try {
      wndClass.ref.style = win32.CS_HREDRAW | win32.CS_VREDRAW;
      wndClass.ref.lpfnWndProc = Pointer.fromFunction<win32.WNDPROC>(
        _windowProc,
        0,
      );
      wndClass.ref.cbClsExtra = 0;
      wndClass.ref.cbWndExtra = 0;
      final hModule = win32.GetModuleHandle(nullptr);
      wndClass.ref.hInstance = hModule;
      wndClass.ref.hIcon = Pointer<Void>.fromAddress(0);
      final hCursor = win32.LoadCursor(nullptr, win32.IDC_ARROW);
      wndClass.ref.hCursor = hCursor;
      wndClass.ref.hbrBackground = win32.GetSysColorBrush(win32.COLOR_WINDOW);
      wndClass.ref.lpszMenuName = nullptr;
      wndClass.ref.lpszClassName = classNamePtr;

      win32.RegisterClass(wndClass);
    } finally {
      calloc.free(wndClass);
      calloc.free(classNamePtr);
    }
  }

  static int _createOverlayWindow() {
    final classNamePtr = _windowClassName.toNativeUtf16();
    final titlePtr = 'BIM Session'.toNativeUtf16();

    try {
      // Get screen dimensions
      final screenW = win32.GetSystemMetrics(win32.SM_CXSCREEN);
      final screenH = win32.GetSystemMetrics(win32.SM_CYSCREEN);

      // Create window with layered + transparent flags
      // so it doesn't interfere with normal interaction
      final hModule = win32.GetModuleHandle(nullptr);
      
      // Suppress nullability warnings for CreateWindowEx parameters
      // (they accept null pointers for hwndParent, hmenu, lpParam)
      final hwnd = win32.CreateWindowEx(
        win32.WS_EX_LAYERED | win32.WS_EX_TRANSPARENT | win32.WS_EX_TOPMOST,
        classNamePtr,
        titlePtr,
        win32.WS_POPUP,
        0,
        0,
        screenW,
        screenH,
        0, // no parent (HWND)
        0, // no menu (HMENU)
        hModule,
        0, // lpParam
      ) as int;

      return hwnd;
    } finally {
      calloc.free(classNamePtr);
      calloc.free(titlePtr);
    }
  }

  static void _excludeFromCapture(int hwnd) {
    try {
      // Constants for SetWindowDisplayAffinity
      const int WDA_EXCLUDEFROMCAPTURE = 17;

      // Load user32.dll and get function pointer
      final user32 = DynamicLibrary.open('user32.dll');
      final setWindowDisplayAffinity = user32.lookupFunction<
          Int32 Function(IntPtr, Uint32),
          int Function(int, int)>('SetWindowDisplayAffinity');

      // Exclude from capture (not visible in screen streaming)
      setWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE);
    } catch (e) {
      print('[HostSessionOverlay] Set exclusion failed: $e');
    }
  }

  static int _windowProc(
    int hwnd,
    int uMsg,
    int wParam,
    int lParam,
  ) {
    const int WM_PAINT = 15;
    const int WM_DESTROY = 2;

    switch (uMsg) {
      case WM_PAINT:
        _paintOverlay(hwnd);
        win32.ValidateRect(hwnd, nullptr);
        return 0;

      case WM_DESTROY:
        win32.PostQuitMessage(0);
        return 0;

      default:
        return win32.DefWindowProc(hwnd, uMsg, wParam, lParam);
    }
  }

  static void _paintOverlay(int hwnd) {
    final ps = calloc<win32.PAINTSTRUCT>();
    final rect = calloc<win32.RECT>();

    try {
      final hdc = win32.BeginPaint(hwnd, ps);
      if (hdc == 0) return;

      // Get window bounds
      win32.GetClientRect(hwnd, rect);

      final left = rect.ref.left;
      final top = rect.ref.top;
      final right = rect.ref.right;
      final bottom = rect.ref.bottom;

      // Draw red border (3 pixels thick)
      final penRed = win32.CreatePen(win32.PS_SOLID, 3, win32.RGB(255, 0, 0));
      final oldPen = win32.SelectObject(hdc, penRed);

      // Draw rectangle border
      win32.Rectangle(hdc, left, top, right, bottom);

      // Draw top-center control bar background
      const barHeight = 40;
      const barY = 5;
      const barMargin = 200;

      final barLeft = (right - left - barMargin * 2) ~/ 2;
      final barTop = barY;
      final barRight = barLeft + barMargin * 2;
      final barBottom = barY + barHeight;

      // Dark semi-transparent background for control bar
      final brushDark = win32.CreateSolidBrush(win32.RGB(50, 50, 50));
      final oldBrush = win32.SelectObject(hdc, brushDark);
      win32.Rectangle(hdc, barLeft, barTop, barRight, barBottom);
      win32.SelectObject(hdc, oldBrush);

      // Draw text "Session Active" in white
      final textColor = win32.SetTextColor(hdc, win32.RGB(255, 255, 255));
      final oldBkMode = win32.SetBkMode(hdc, win32.TRANSPARENT);

      final textRect = calloc<win32.RECT>();
      textRect.ref.left = barLeft;
      textRect.ref.top = barTop;
      textRect.ref.right = barRight;
      textRect.ref.bottom = barBottom;

      const String sessionText = 'Session Active - Press X to Disconnect';
      final textPtr = sessionText.toNativeUtf16();

      win32.DrawText(
        hdc,
        textPtr,
        -1,
        textRect,
        win32.DT_CENTER | win32.DT_VCENTER | win32.DT_SINGLELINE,
      );

      calloc.free(textPtr);
      calloc.free(textRect);

      win32.SetBkMode(hdc, oldBkMode);
      win32.SetTextColor(hdc, textColor);
      win32.SelectObject(hdc, oldPen);
      win32.DeleteObject(penRed);
      win32.DeleteObject(brushDark);
      win32.EndPaint(hwnd, ps);
    } finally {
      calloc.free(rect);
      calloc.free(ps);
    }
  }
}
