import 'dart:io' as io;

/// Host session overlay (Planned Feature - Awaiting FFI Implementation)
///
/// This class will show a red border and control bar on the host machine only,
/// using SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE) to hide it from controller stream.
///
/// Status: Currently a stub pending FFI type compatibility fixes in win32 package.
/// Alternative approaches under consideration:
/// 1. Use simpler GDI drawing without window class complexity
/// 2. Use Flutter overlay with manual exclusion logic
/// 3. Implement via native plugin with pure C++
class HostSessionOverlay {
  /// Start the overlay (currently a no-op pending implementation)
  static bool startOverlay() {
    if (!io.Platform.isWindows) return false;
    // TODO: Implement native window overlay with SetWindowDisplayAffinity
    return true;
  }

  /// Stop the overlay
  static bool stopOverlay() {
    // TODO: Implement cleanup
    return true;
  }
}

