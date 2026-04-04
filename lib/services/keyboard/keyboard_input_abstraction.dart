/// Input Abstraction Layer (Client Side).
///
/// Captures keyboard input using low-level scan codes and key codes (layout-independent).
/// Normalizes events into a structured abstraction that is transport-agnostic.

import 'package:flutter/services.dart';
import 'keyboard_protocol.dart';

/// Abstracts keyboard input capture into a structured format.
class KeyboardInputAbstraction {
  /// Sequence counter for events.
  int _eventSequence = 0;

  /// Callback when input is captured.
  final void Function(KeyboardKeyEvent event)? onInputCaptured;

  KeyboardInputAbstraction({
    this.onInputCaptured,
  });

  /// Convert a Flutter KeyEvent into structured abstraction.
  KeyboardKeyEvent abstractKeyEvent(
    KeyEvent flutterEvent, {
    required String clientLayout,
    required String clientLayoutFamily,
  }) {
    final phase = flutterEvent is KeyDownEvent
        ? 'down'
        : flutterEvent is KeyUpEvent
            ? 'up'
            : 'unknown';

    final physicalCode = flutterEvent.physicalKey.usbHidUsage;
    final logicalKeyId = flutterEvent.logicalKey.keyId;
    final character = flutterEvent.character ?? '';
    final characterCodePoint =
        character.isNotEmpty ? character.runes.first : 0;

    final keyLabel = flutterEvent.logicalKey.keyLabel.trim();
    final debugName = (flutterEvent.logicalKey.debugName ?? '').trim();
    final keyName = keyLabel.isNotEmpty ? keyLabel : debugName;

    final modifiers = _extractModifiers();
    final isModifier = _isModifierKey(keyName);
    final isNumpad = _isNumpadKey(physicalCode, keyName);

    final event = KeyboardKeyEvent(
      physicalCode: physicalCode,
      logicalKeyId: logicalKeyId,
      characterCodePoint: characterCodePoint,
      keyName: keyName,
      keyLabel: keyLabel,
      phase: phase,
      modifiers: modifiers,
      isNumpad: isNumpad,
      isModifier: isModifier,
      clientLayout: clientLayout,
      clientLayoutFamily: clientLayoutFamily,
      captureTimestampMs: DateTime.now().millisecondsSinceEpoch,
      sequenceNumber: ++_eventSequence,
    );

    onInputCaptured?.call(event);
    return event;
  }

  /// Extract current modifier state from hardware keyboard.
  static ModifierState _extractModifiers() {
    final hw = HardwareKeyboard.instance;
    return ModifierState(
      shift: hw.isShiftPressed,
      control: hw.isControlPressed,
      alt: hw.isAltPressed,
      meta: hw.isMetaPressed,
      altGraph: hw.logicalKeysPressed.contains(LogicalKeyboardKey.altGraph),
    );
  }

  /// Check if a key name represents a modifier.
  static bool _isModifierKey(String keyName) {
    final lower = keyName.toLowerCase();
    return lower.contains('shift') ||
        lower.contains('control') ||
        lower.contains('ctrl') ||
        lower.contains('alt') ||
        lower.contains('meta') ||
        lower.contains('command') ||
        lower.contains('caps lock');
  }

  /// Check if a physical code is from the numpad.
  static bool _isNumpadKey(int physicalCode, String keyName) {
    // USB HID numpad range: 0x00070059 to 0x00070063
    if (physicalCode >= 0x00070059 && physicalCode <= 0x00070063) {
      return true;
    }
    // Fallback: check key name.
    return keyName.toLowerCase().contains('numpad') ||
        keyName.toLowerCase().contains('num pad');
  }

  /// Extract a printable character from the event.
  ///
  /// Returns the character if it's printable, otherwise empty string.
  static String extractPrintableCharacter(KeyboardKeyEvent event) {
    if (event.characterCodePoint == 0) return '';
    if (event.characterCodePoint < 0x20) return ''; // Control character
    if (event.characterCodePoint == 0x7F) return ''; // DEL
    return String.fromCharCode(event.characterCodePoint);
  }

  /// Check if a character is printable.
  static bool isPrintableCharacter(String character) {
    if (character.isEmpty || character.length != 1) return false;
    final code = character.codeUnitAt(0);
    return code >= 0x20 && code != 0x7F;
  }

  /// Normalize key name to standard format.
  ///
  /// Examples: "Key A" -> "KeyA", "Arrow Left" -> "ArrowLeft".
  static String normalizeKeyName(String keyName) {
    // Flutter uses spaces, normalize to camelCase for consistency.
    return keyName.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join();
  }

  /// Format event as human-readable string (for logging).
  static String formatEvent(KeyboardKeyEvent event) {
    return '${event.phase.toUpperCase()}: ${event.keyName} '
        '(code=0x${event.physicalCode.toRadixString(16)}, '
        'modifiers=${event.modifiers}, '
        'timestamp=${event.captureTimestampMs})';
  }
}

/// Alternative: Low-level scan code capture (advanced).
///
/// This would use platform channels to intercept at a lower level,
/// but Flutter's KeyboardListener already provides enough detail for most cases.
class LowLevelScanCodeCapture {
  /// Platform channel for low-level input.
  static const platform = MethodChannel('com.bimstreaming/keyboard');

  /// Start listening to system-wide key events (requires permissions).
  /// On Windows, this could use SetWindowsHookEx(WH_KEYBOARD_LL, ...).
  /// On macOS, use CGEventTapCreate with kCGHIDEventTap.
  /// Not implemented here; platform-specific code would be needed.
  static Future<void> startSystemWideCapture() async {
    try {
      await platform.invokeMethod<void>('startLowLevelCapture');
    } catch (e) {
      print('[LowLevelScanCodeCapture] Failed to start: $e');
    }
  }

  static Future<void> stopSystemWideCapture() async {
    try {
      await platform.invokeMethod<void>('stopLowLevelCapture');
    } catch (e) {
      print('[LowLevelScanCodeCapture] Failed to stop: $e');
    }
  }
}
