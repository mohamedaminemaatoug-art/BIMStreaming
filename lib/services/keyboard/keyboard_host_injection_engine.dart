/// Keyboard Host Injection Engine.
///
/// Handles remote keyboard input injection on the host machine.
/// Provides multiple injection strategies (SendInput, Unicode, text) with fallback logic.

import 'dart:async';
import 'dart:io' as io;
import 'keyboard_protocol.dart';
import 'keyboard_layout_translator.dart';
import 'keyboard_state_manager.dart';

/// Responsible for injecting keyboard input into the host system.
class KeyboardHostInjectionEngine {
  /// Layout translator for character mapping.
  final KeyboardLayoutTranslator layoutTranslator;

  /// Key state manager for lifecycle tracking.
  final KeyboardStateManager stateManager;

  /// Callback to execute PowerShell commands.
  final Future<String> Function(
    List<String> args, {
    Duration? timeout,
  }) executePowerShell;

  /// Callback when injection occurs.
  final void Function(int physicalCode, String strategy)? onInjectionOccurred;

  /// Callback when injection fails.
  final void Function(int physicalCode, String reason)? onInjectionFailed;

  /// Timeout for injection operations.
  static const Duration _injectionTimeout = Duration(seconds: 2);

  /// Virtual key code mappings (Windows-specific).
  static const Map<String, int> _specialKeyVkMap = {
    'enter': 0x0D,
    'tab': 0x09,
    'escape': 0x1B,
    'backspace': 0x08,
    'delete': 0x2E,
    'insert': 0x2D,
    'home': 0x24,
    'end': 0x23,
    'page up': 0x21,
    'page down': 0x22,
    'arrow left': 0x25,
    'arrow up': 0x26,
    'arrow right': 0x27,
    'arrow down': 0x28,
    'f1': 0x70,
    'f2': 0x71,
    'f3': 0x72,
    'f4': 0x73,
    'f5': 0x74,
    'f6': 0x75,
    'f7': 0x76,
    'f8': 0x77,
    'f9': 0x78,
    'f10': 0x79,
    'f11': 0x7A,
    'f12': 0x7B,
    'space': 0x20,
    'caps lock': 0x14,
    'shift left': 0xA0,
    'shift right': 0xA1,
    'control left': 0xA2,
    'control right': 0xA3,
    'alt left': 0xA4,
    'alt right': 0xA5,
    'meta left': 0x5B,
    'meta right': 0x5C,
  };

  KeyboardHostInjectionEngine({
    required this.layoutTranslator,
    required this.stateManager,
    required this.executePowerShell,
    this.onInjectionOccurred,
    this.onInjectionFailed,
  });

  /// Inject a keyboard event from remote.
  ///
  /// Handles strategy selection:
  /// 1. Unicode injection (for printable characters)
  /// 2. Virtual key injection (for control/navigation keys)
  /// 3. SendKeys fallback (for text with modifiers)
  Future<bool> injectKeyboardEvent(
    KeyboardKeyEvent event, {
    required String hostLayout,
    required String hostLayoutFamily,
  }) async {
    if (!io.Platform.isWindows) return false;

    try {
      // Translate character if needed.
      String translatedCharacter = event.keyLabel;
      if (translatedCharacter.isNotEmpty &&
          KeyboardInputAbstraction.isPrintableCharacter(translatedCharacter)) {
        translatedCharacter = layoutTranslator.translateCharacter(translatedCharacter);
      }

      // Choose injection strategy.
      final strategy = _selectInjectionStrategy(event, translatedCharacter);

      switch (strategy) {
        case InjectionStrategy.unicode:
          return await _injectUnicode(event, translatedCharacter);
        case InjectionStrategy.virtualKey:
          return await _injectVirtualKey(event);
        case InjectionStrategy.sendKeys:
          return await _injectSendKeys(event, translatedCharacter);
        case InjectionStrategy.modifierOnly:
          return await _injectModifier(event);
      }
    } catch (e) {
      onInjectionFailed?.call(event.physicalCode, e.toString());
      return false;
    }
  }

  /// Inject via Unicode input method (preferred for printable characters).
  Future<bool> _injectUnicode(
    KeyboardKeyEvent event,
    String character,
  ) async {
    if (character.isEmpty || character.length != 1) return false;

    final codePoint = character.codeUnitAt(0);
    if (codePoint == 0) return false;

    final script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT {
    public uint type;
    public InputUnion U;
  }

  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion {
    [FieldOffset(0)]
    public KEYBDINPUT ki;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk;
    public ushort wScan;
    public uint dwFlags;
    public uint time;
    public UIntPtr dwExtraInfo;
  }

  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
}
"@

$unicode = __CODEPOINT__

$down = New-Object NativeInput+INPUT
$down.type = 1
$kbDown = New-Object NativeInput+KEYBDINPUT
$kbDown.wVk = 0
$kbDown.wScan = [UInt16]$unicode
$kbDown.dwFlags = 0x0004
$kbDown.time = 0
$kbDown.dwExtraInfo = [UIntPtr]::Zero
$down.U.ki = $kbDown

$up = New-Object NativeInput+INPUT
$up.type = 1
$kbUp = New-Object NativeInput+KEYBDINPUT
$kbUp.wVk = 0
$kbUp.wScan = [UInt16]$unicode
$kbUp.dwFlags = 0x0004 -bor 0x0002
$kbUp.time = 0
$kbUp.dwExtraInfo = [UIntPtr]::Zero
$up.U.ki = $kbUp

[void][NativeInput]::SendInput(2, @($down, $up), [Runtime.InteropServices.Marshal]::SizeOf([type][NativeInput+INPUT]))
'''
        .replaceAll('__CODEPOINT__', codePoint.toString());

    try {
      await executePowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        timeout: _injectionTimeout,
      );
      onInjectionOccurred?.call(event.physicalCode, 'unicode');
      return true;
    } catch (e) {
      onInjectionFailed?.call(event.physicalCode, 'unicode injection failed: $e');
      return false;
    }
  }

  /// Inject via virtual key code (for control/navigation keys).
  Future<bool> _injectVirtualKey(KeyboardKeyEvent event) async {
    final vkCode = _resolveVirtualKeyCode(event);
    if (vkCode == 0) return false;

    final isKeyDown = event.phase == 'down';

    final script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT {
    public uint type;
    public InputUnion U;
  }

  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion {
    [FieldOffset(0)]
    public KEYBDINPUT ki;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk;
    public ushort wScan;
    public uint dwFlags;
    public uint time;
    public UIntPtr dwExtraInfo;
  }

  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint MapVirtualKey(uint uCode, uint uMapType);
}
"@

$vk = __VK__
$isDown = __IS_DOWN__

$input = New-Object NativeInput+INPUT
$input.type = 1
$kb = New-Object NativeInput+KEYBDINPUT
$kb.wVk = [UInt16]$vk
$kb.wScan = [UInt16][NativeInput]::MapVirtualKey([UInt32]$vk, 0)
$flags = 0x0008
if (-not $isDown) { $flags = $flags -bor 0x0002 }
$kb.dwFlags = $flags
$kb.time = 0
$kb.dwExtraInfo = [UIntPtr]::Zero
$input.U.ki = $kb

[void][NativeInput]::SendInput(1, @($input), [Runtime.InteropServices.Marshal]::SizeOf([type][NativeInput+INPUT]))
'''
        .replaceAll('__VK__', vkCode.toString())
        .replaceAll('__IS_DOWN__', isKeyDown ? 'true' : 'false');

    try {
      await executePowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        timeout: _injectionTimeout,
      );
      onInjectionOccurred?.call(event.physicalCode, 'vk_${vkCode.toRadixString(16).padLeft(2, '0')}');
      return true;
    } catch (e) {
      onInjectionFailed?.call(event.physicalCode, 'vk injection failed: $e');
      return false;
    }
  }

  /// Inject with SendKeys (for text with modifiers).
  Future<bool> _injectSendKeys(
    KeyboardKeyEvent event,
    String character,
  ) async {
    final stroke = _buildSendKeysStroke(event, character);
    if (stroke.isEmpty) return false;

    final script = '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('$stroke')
'''
        .replaceAll("'", "''");

    try {
      await executePowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        timeout: _injectionTimeout,
      );
      onInjectionOccurred?.call(event.physicalCode, 'sendkeys');
      return true;
    } catch (e) {
      onInjectionFailed?.call(event.physicalCode, 'sendkeys injection failed: $e');
      return false;
    }
  }

  /// Inject modifier key only (Shift, Ctrl, Alt, Meta).
  Future<bool> _injectModifier(KeyboardKeyEvent event) async {
    if (!event.isModifier) return false;

    final keyName = event.keyName.toLowerCase();
    int vkCode = 0;

    if (keyName.contains('shift')) {
      vkCode = keyName.contains('right') ? 0xA1 : 0xA0;
    } else if (keyName.contains('control') || keyName.contains('ctrl')) {
      vkCode = keyName.contains('right') ? 0xA3 : 0xA2;
    } else if (keyName.contains('alt')) {
      vkCode = keyName.contains('right') ? 0xA5 : 0xA4;
    } else if (keyName.contains('meta')) {
      vkCode = keyName.contains('right') ? 0x5C : 0x5B;
    }

    if (vkCode == 0) return false;

    final isKeyDown = event.phase == 'down';

    final script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT {
    public uint type;
    public InputUnion U;
  }

  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion {
    [FieldOffset(0)]
    public KEYBDINPUT ki;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk;
    public ushort wScan;
    public uint dwFlags;
    public uint time;
    public UIntPtr dwExtraInfo;
  }

  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint MapVirtualKey(uint uCode, uint uMapType);
}
"@

$vk = __VK__
$isDown = __IS_DOWN__

$input = New-Object NativeInput+INPUT
$input.type = 1
$kb = New-Object NativeInput+KEYBDINPUT
$kb.wVk = [UInt16]$vk
$kb.wScan = [UInt16][NativeInput]::MapVirtualKey([UInt32]$vk, 0)
$flags = 0x0008
if (-not $isDown) { $flags = $flags -bor 0x0002 }
$kb.dwFlags = $flags
$kb.time = 0
$kb.dwExtraInfo = [UIntPtr]::Zero
$input.U.ki = $kb

[void][NativeInput]::SendInput(1, @($input), [Runtime.InteropServices.Marshal]::SizeOf([type][NativeInput+INPUT]))
'''
        .replaceAll('__VK__', vkCode.toString())
        .replaceAll('__IS_DOWN__', isKeyDown ? 'true' : 'false');

    try {
      await executePowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        timeout: _injectionTimeout,
      );
      onInjectionOccurred?.call(event.physicalCode, 'modifier_0x${vkCode.toRadixString(16)}');
      return true;
    } catch (e) {
      onInjectionFailed?.call(event.physicalCode, 'modifier injection failed: $e');
      return false;
    }
  }

  // ===== Strategy Selection =====

  InjectionStrategy _selectInjectionStrategy(
    KeyboardKeyEvent event,
    String character,
  ) {
    // Modifiers: only inject if modifier key.
    if (event.isModifier) {
      return InjectionStrategy.modifierOnly;
    }

    // Printable characters (without modifier keys): use Unicode.
    if (KeyboardInputAbstraction.isPrintableCharacter(character) &&
        !event.modifiers.isPressed) {
      return InjectionStrategy.unicode;
    }

    // Control keys (Enter, Backspace, arrows, etc.): use VK.
    if (_isControlKey(event.keyName)) {
      return InjectionStrategy.virtualKey;
    }

    // Fallback: SendKeys for complex combinations.
    return InjectionStrategy.sendKeys;
  }

  bool _isControlKey(String keyName) {
    final lower = keyName.toLowerCase();
    return _specialKeyVkMap.containsKey(lower) ||
        lower.startsWith('f') && int.tryParse(lower.substring(1)) != null ||
        lower == 'printscreen' ||
        lower == 'scroll lock' ||
        lower == 'pause' ||
        lower == 'numlock';
  }

  // ===== Key Resolution =====

  int _resolveVirtualKeyCode(KeyboardKeyEvent event) {
    final keyNameLower = event.keyName.toLowerCase();

    // Direct VK mapping.
    if (_specialKeyVkMap.containsKey(keyNameLower)) {
      return _specialKeyVkMap[keyNameLower]!;
    }

    // Letter keys (A-Z).
    if (event.keyName.length == 1) {
      final char = event.keyName.toUpperCase();
      final code = char.codeUnitAt(0);
      if (code >= 0x41 && code <= 0x5A) return code; // A-Z
      if (code >= 0x30 && code <= 0x39) return code; // 0-9
    }

    // Numpad numbers.
    final numpadMatch = RegExp(r'numpad\s*(\d)').firstMatch(keyNameLower);
    if (numpadMatch != null) {
      return 0x60 + int.parse(numpadMatch.group(1)!); // NUMPAD0 - NUMPAD9
    }

    return 0;
  }

  String _buildSendKeysStroke(KeyboardKeyEvent event, String character) {
    final buffer = StringBuffer();

    // Add modifiers.
    if (event.modifiers.control) buffer.write('^');
    if (event.modifiers.alt && !event.modifiers.altGraph) buffer.write('%');
    if (event.modifiers.shift) buffer.write('+');

    // Add key token.
    if (KeyboardInputAbstraction.isPrintableCharacter(character)) {
      buffer.write(character);
    } else {
      final token = _specialKeyToSendKeysToken(event.keyName);
      buffer.write(token);
    }

    return buffer.toString();
  }

  String _specialKeyToSendKeysToken(String keyName) {
    final lower = keyName.toLowerCase();
    const map = {
      'enter': '{ENTER}',
      'tab': '{TAB}',
      'escape': '{ESC}',
      'backspace': '{BACKSPACE}',
      'delete': '{DELETE}',
      'insert': '{INSERT}',
      'home': '{HOME}',
      'end': '{END}',
      'page up': '{PGUP}',
      'page down': '{PGDN}',
      'arrow left': '{LEFT}',
      'arrow right': '{RIGHT}',
      'arrow up': '{UP}',
      'arrow down': '{DOWN}',
      'f1': '{F1}',
      'f2': '{F2}',
      'f3': '{F3}',
      'f4': '{F4}',
      'f5': '{F5}',
      'f6': '{F6}',
      'f7': '{F7}',
      'f8': '{F8}',
      'f9': '{F9}',
      'f10': '{F10}',
      'f11': '{F11}',
      'f12': '{F12}',
    };
    return map[lower] ?? '';
  }
}

enum InjectionStrategy {
  unicode,
  virtualKey,
  sendKeys,
  modifierOnly,
}

// Provide convenience helper to access the input abstraction.
import 'keyboard_input_abstraction.dart';
