/// Keyboard Host Injection Engine.
///
/// Handles remote keyboard input injection on the host machine.
/// Provides multiple injection strategies (SendInput, Unicode, text) with fallback logic.

import 'dart:async';
import 'dart:ffi';
import 'dart:io' as io;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'keyboard_protocol.dart';
import 'keyboard_layout_translator.dart';
import 'keyboard_state_manager.dart';
import 'keyboard_input_abstraction.dart';

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

      // Skip key-up for printable characters to avoid duplicate text injection.
      if (event.phase == 'up' && !event.isModifier && !_isControlKey(event.keyName)) {
        return true;
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

    try {
      final inputs = calloc<INPUT>(2);
      try {
        (inputs + 0).ref = _buildUnicodeInput(codePoint, isKeyUp: false);
        (inputs + 1).ref = _buildUnicodeInput(codePoint, isKeyUp: true);
        final sent = SendInput(2, inputs, sizeOf<INPUT>());
        if (sent != 2) {
          onInjectionFailed?.call(event.physicalCode, 'unicode sendinput returned $sent');
          return false;
        }
      } finally {
        calloc.free(inputs);
      }

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

    try {
      final inputs = calloc<INPUT>(1);
      try {
        (inputs + 0).ref = _buildVirtualKeyInput(vkCode, isKeyUp: !isKeyDown);
        final sent = SendInput(1, inputs, sizeOf<INPUT>());
        if (sent != 1) {
          onInjectionFailed?.call(event.physicalCode, 'vk sendinput returned $sent');
          return false;
        }
      } finally {
        calloc.free(inputs);
      }

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
    try {
      final inputs = <INPUT>[];
      final modifierVks = <int>[];

      if (event.modifiers.control) modifierVks.add(VK_CONTROL);
      if (event.modifiers.alt && !event.modifiers.altGraph) modifierVks.add(VK_MENU);
      if (event.modifiers.shift) modifierVks.add(VK_SHIFT);
      if (event.modifiers.meta) modifierVks.add(VK_LWIN);

      for (final vk in modifierVks) {
        inputs.add(_buildVirtualKeyInput(vk, isKeyUp: false));
      }

      if (KeyboardInputAbstraction.isPrintableCharacter(character)) {
        final codePoint = character.runes.first;
        inputs.add(_buildUnicodeInput(codePoint, isKeyUp: false));
        inputs.add(_buildUnicodeInput(codePoint, isKeyUp: true));
      } else {
        final vkCode = _resolveVirtualKeyCode(event);
        if (vkCode == 0) return false;
        inputs.add(_buildVirtualKeyInput(vkCode, isKeyUp: false));
        inputs.add(_buildVirtualKeyInput(vkCode, isKeyUp: true));
      }

      for (final vk in modifierVks.reversed) {
        inputs.add(_buildVirtualKeyInput(vk, isKeyUp: true));
      }

      if (!_sendKeyboardInputs(inputs)) {
        onInjectionFailed?.call(event.physicalCode, 'sendkeys sendinput returned failure');
        return false;
      }

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

    try {
      if (!_sendKeyboardInputs([
        _buildVirtualKeyInput(vkCode, isKeyUp: event.phase != 'down'),
      ])) {
        onInjectionFailed?.call(event.physicalCode, 'modifier sendinput returned failure');
        return false;
      }

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

    // Printable text should follow controller intent, even with Shift.
    // Only avoid Unicode for control/meta/alt shortcuts.
    if (KeyboardInputAbstraction.isPrintableCharacter(character) &&
        event.phase == 'down' &&
        !event.modifiers.control &&
        !event.modifiers.meta &&
        (!event.modifiers.alt || event.modifiers.altGraph)) {
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

  bool _sendKeyboardInputs(List<INPUT> inputs) {
    if (inputs.isEmpty) return false;

    final pInputs = calloc<INPUT>(inputs.length);
    try {
      for (var i = 0; i < inputs.length; i++) {
        (pInputs + i).ref = inputs[i];
      }
      final sent = SendInput(inputs.length, pInputs, sizeOf<INPUT>());
      return sent == inputs.length;
    } finally {
      calloc.free(pInputs);
    }
  }

  INPUT _buildUnicodeInput(int codePoint, {required bool isKeyUp}) {
    final input = calloc<INPUT>();
    final key = calloc<KEYBDINPUT>();
    input.ref.type = INPUT_KEYBOARD;
    key.ref
      ..wVk = 0
      ..wScan = codePoint
      ..dwFlags = KEYEVENTF_UNICODE | (isKeyUp ? KEYEVENTF_KEYUP : 0)
      ..time = 0
      ..dwExtraInfo = 0;
    input.ref.ki = key.ref;
    final value = input.ref;
    calloc.free(key);
    calloc.free(input);
    return value;
  }

  INPUT _buildVirtualKeyInput(int vkCode, {required bool isKeyUp}) {
    final input = calloc<INPUT>();
    final key = calloc<KEYBDINPUT>();
    input.ref.type = INPUT_KEYBOARD;
    key.ref
      ..wVk = vkCode
      ..wScan = MapVirtualKey(vkCode, MAPVK_VK_TO_VSC)
      ..dwFlags = KEYEVENTF_SCANCODE | (isKeyUp ? KEYEVENTF_KEYUP : 0)
      ..time = 0
      ..dwExtraInfo = 0;
    input.ref.ki = key.ref;
    final value = input.ref;
    calloc.free(key);
    calloc.free(input);
    return value;
  }
}

enum InjectionStrategy {
  unicode,
  virtualKey,
  sendKeys,
  modifierOnly,
}
