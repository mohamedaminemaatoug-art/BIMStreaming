import 'dart:async';
import 'dart:ffi';
import 'dart:io' as io;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// Host session overlay - GDI-based implementation
/// Draws a red border and control bar directly on desktop DC
/// Note: Uses desktop drawing that may be visible in capture (WDA_EXCLUDEFROMCAPTURE not yet integrated)
class HostSessionOverlay {
  static Timer? _drawTimer;
  static bool _overlayActive = false;
  static const int _redrawIntervalMs = 100;

  /// Start drawing overlay on desktop
  static bool startOverlay() {
    if (!io.Platform.isWindows) return false;
    if (_overlayActive) return true;

    try {
      _overlayActive = true;

      // Draw immediately
      _drawOverlayFrame();

      // Redraw periodically to maintain visibility
      _drawTimer = Timer.periodic(
        const Duration(milliseconds: _redrawIntervalMs),
        (_) {
          if (_overlayActive) {
            _drawOverlayFrame();
          }
        },
      );

      print('[HostSessionOverlay] Started - red border and control bar visible');
      return true;
    } catch (e) {
      print('[HostSessionOverlay] Start failed: $e');
      _overlayActive = false;
      return false;
    }
  }

  /// Stop drawing overlay
  static bool stopOverlay() {
    if (!_overlayActive) return true;

    try {
      _drawTimer?.cancel();
      _drawTimer = null;
      _overlayActive = false;
      print('[HostSessionOverlay] Stopped');
      return true;
    } catch (e) {
      print('[HostSessionOverlay] Stop failed: $e');
      return false;
    }
  }

  static void _drawOverlayFrame() {
    try {
      // Get desktop window DC (NULL = entire screen) 
      // Zero address represents NULL handle
      final screenDC = win32.GetDC(0) as int;
      if (screenDC == 0) return;

      try {
        // Get screen dimensions
        final screenWidth = win32.GetSystemMetrics(win32.SM_CXSCREEN);
        final screenHeight = win32.GetSystemMetrics(win32.SM_CYSCREEN);

        // Draw red border around entire screen
        _drawRedBorder(screenDC, screenWidth, screenHeight);

        // Draw control bar at top-center
        _drawControlBar(screenDC, screenWidth);
      } finally {
        try {
          win32.ReleaseDC(0, screenDC);
        } catch (_) {}
      }
    } catch (_) {
      // Silently ignore drawing errors
    }
  }

  static void _drawRedBorder(int hDC, int screenW, int screenH) {
    try {
      // Create red pen (3 pixels thick)
      final penRed = win32.CreatePen(win32.PS_SOLID, 3, win32.RGB(255, 0, 0));
      if (penRed == 0) return;

      try {
        final oldPen = win32.SelectObject(hDC, penRed);

        // Draw rectangle border around entire screen
        win32.Rectangle(hDC, 0, 20, screenW, screenH);

        win32.SelectObject(hDC, oldPen);
      } finally {
        win32.DeleteObject(penRed);
      }
    } catch (_) {}
  }

  static void _drawControlBar(int hDC, int screenW) {
    try {
      const barHeight = 35;
      const barWidth = 380;
      const barY = 25;

      // Calculate center position
      final barLeft = (screenW - barWidth) ~/ 2;
      final barTop = barY;
      final barRight = barLeft + barWidth;
      final barBottom = barY + barHeight;

      // Draw dark background for control bar
      final brushDark = win32.CreateSolidBrush(win32.RGB(40, 40, 40));
      if (brushDark == 0) return;

      try {
        final oldBrush = win32.SelectObject(hDC, brushDark);
        win32.Rectangle(hDC, barLeft, barTop, barRight, barBottom);
        win32.SelectObject(hDC, oldBrush);
      } finally {
        win32.DeleteObject(brushDark);
      }

      // Draw text on control bar
      _drawControlBarText(hDC, barLeft, barTop, barRight, barBottom);
    } catch (_) {}
  }

  static void _drawControlBarText(
    int hDC,
    int left,
    int top,
    int right,
    int bottom,
  ) {
    try {
      final oldTextColor = win32.SetTextColor(hDC, win32.RGB(255, 255, 255));
      final oldBkMode = win32.SetBkMode(hDC, win32.TRANSPARENT);

      final textRect = calloc<win32.RECT>();
      try {
        textRect.ref.left = left + 10;
        textRect.ref.top = top;
        textRect.ref.right = right - 10;
        textRect.ref.bottom = bottom;

        const String sessionText = 'Session Active • Press X to Disconnect';
        final textPtr = sessionText.toNativeUtf16();

        try {
          win32.DrawText(
            hDC,
            textPtr,
            -1,
            textRect,
            win32.DT_LEFT | win32.DT_VCENTER | win32.DT_SINGLELINE,
          );
        } finally {
          calloc.free(textPtr);
        }
      } finally {
        calloc.free(textRect);
      }

      win32.SetBkMode(hDC, oldBkMode);
      win32.SetTextColor(hDC, oldTextColor);
    } catch (_) {}
  }
}

