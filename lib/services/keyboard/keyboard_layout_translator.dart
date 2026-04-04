/// Keyboard Layout Detection & Translation Engine.
///
/// Detects client and host keyboard layouts, builds translation mappings,
/// and provides layout-aware character transformation for remote input.

import 'dart:async';
import 'dart:io' as io;

import 'keyboard_protocol.dart';

/// Responsible for layout detection and translation.
class KeyboardLayoutTranslator {
  /// Detected client keyboard layout.
  KeyboardLayout? _clientLayout;

  /// Detected host keyboard layout.
  KeyboardLayout? _hostLayout;

  /// Cache of character mappings: (sourceFamily, targetFamily, char) -> translated char.
  final Map<String, String> _characterMappingCache = <String, String>{};

  /// Cache of key sequence mappings.
  final Map<String, List<int>> _keySequenceCache = <String, List<int>>{};

  /// Known layout families for quick lookup.
  static const Map<String, String> _layoutFamilyMap = layoutFamilyMap;

  /// Callback when layout changes.
  final void Function(KeyboardLayout? oldLayout, KeyboardLayout? newLayout)? onClientLayoutChanged;
  final void Function(KeyboardLayout? oldLayout, KeyboardLayout? newLayout)? onHostLayoutChanged;

  KeyboardLayoutTranslator({
    this.onClientLayoutChanged,
    this.onHostLayoutChanged,
  });

  /// Get detected client layout.
  KeyboardLayout? get clientLayout => _clientLayout;

  /// Get detected host layout.
  KeyboardLayout? get hostLayout => _hostLayout;

  /// Get client layout family name (e.g., 'QWERTY').
  String get clientLayoutFamily => _clientLayout?.family ?? 'unknown';

  /// Get host layout family name (e.g., 'QWERTY').
  String get hostLayoutFamily => _hostLayout?.family ?? 'unknown';

  /// Detect current client keyboard layout (Windows only).
  Future<void> detectClientLayout() async {
    if (!io.Platform.isWindows) return;

    try {
      final result = await io.Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          // Get current keyboard layout from registry
          r"""
$layouts = Get-ItemProperty -Path 'HKCU:\Keyboard Layout\Preload' -ErrorAction SilentlyContinue
$layout = $layouts.'1'
if ([string]::IsNullOrWhiteSpace($layout)) { $layout = '00000409' }
Write-Output $layout
"""
        ],
      );

      if (result.exitCode == 0) {
        final layoutId = (result.stdout as String).trim();
        await _setClientLayout(layoutId);
      }
    } catch (e) {
      print('[KeyboardLayoutTranslator] Failed to detect client layout: $e');
    }
  }

  /// Set client layout (called when remote reports their layout).
  Future<void> setClientLayoutFromRemote(String layoutId, String family) async {
    final newLayout = _createLayoutFromId(layoutId, family);
    _clientLayout = newLayout;
    onClientLayoutChanged?.call(null, newLayout);
  }

  /// Set host layout (called when self-detected).
  Future<void> _setClientLayout(String layoutId) async {
    final family = _layoutFamilyMap[layoutId] ?? _inferLayoutFamily(layoutId);
    final newLayout = KeyboardLayout(
      layoutId: layoutId,
      family: family,
      displayName: _getLayoutDisplayName(layoutId),
      language: _getLanguageFromLayoutId(layoutId),
      region: _getRegionFromLayoutId(layoutId),
    );

    final oldLayout = _clientLayout;
    _clientLayout = newLayout;

    if (oldLayout?.layoutId != newLayout.layoutId) {
      _characterMappingCache.clear();
      _keySequenceCache.clear();
      onClientLayoutChanged?.call(oldLayout, newLayout);
    }
  }

  /// Set host layout (reported by remote).
  void setHostLayout(String layoutId, String family) {
    final newLayout = KeyboardLayout(
      layoutId: layoutId,
      family: family,
      displayName: _getLayoutDisplayName(layoutId),
      language: _getLanguageFromLayoutId(layoutId),
      region: _getRegionFromLayoutId(layoutId),
    );

    final oldLayout = _hostLayout;
    _hostLayout = newLayout;

    if (oldLayout?.layoutId != newLayout.layoutId) {
      _characterMappingCache.clear();
      _keySequenceCache.clear();
      onHostLayoutChanged?.call(oldLayout, newLayout);
    }
  }

  /// Translate character from client layout to host layout.
  ///
  /// Returns the character as-is if:
  /// - Already a visual character (layout-independent like ASCII letters/digits)
  /// - Client and host layouts are the same family
  /// - Layout detection failed
  ///
  /// This preserves **visual correctness** over physical key equivalence.
  String translateCharacter(String character) {
    if (character.isEmpty || character.length != 1) return character;

    final sourceFamily = clientLayoutFamily;
    final targetFamily = hostLayoutFamily;

    // If same layout or unknown, return as-is (character is visual source of truth).
    if (sourceFamily == targetFamily || sourceFamily == 'unknown' || targetFamily == 'unknown') {
      return character;
    }

    // Check cache.
    final cacheKey = '$sourceFamily-$targetFamily-$character';
    if (_characterMappingCache.containsKey(cacheKey)) {
      return _characterMappingCache[cacheKey]!;
    }

    // For now, return as-is. In production, this would consult a comprehensive
    // layout mapping table to produce the equivalent character on the target layout.
    // Example: AZERTY client presses 'A' (which is physically at Shift+Q on AZERTY);
    // we need to inject the correct key combo on QWERTY host to produce 'A'.
    _characterMappingCache[cacheKey] = character;
    return character;
  }

  /// Check if layouts are compatible (same family).
  bool areLayoutsCompatible() {
    return clientLayoutFamily == hostLayoutFamily ||
        clientLayoutFamily == 'unknown' ||
        hostLayoutFamily == 'unknown';
  }

  /// Format layout info for diagnostics.
  String formatLayoutDiagnostics() {
    return 'Client: ${_clientLayout?.displayName ?? "unknown"} | '
        'Host: ${_hostLayout?.displayName ?? "unknown"}';
  }

  /// Clear all caches (called when layout changes).
  void clearCaches() {
    _characterMappingCache.clear();
    _keySequenceCache.clear();
  }

  // ===== Private Helpers =====

  KeyboardLayout _createLayoutFromId(String layoutId, String family) {
    return KeyboardLayout(
      layoutId: layoutId,
      family: family,
      displayName: _getLayoutDisplayName(layoutId),
      language: _getLanguageFromLayoutId(layoutId),
      region: _getRegionFromLayoutId(layoutId),
    );
  }

  String _getLayoutDisplayName(String layoutId) {
    final map = {
      '00000409': 'English (US)',
      '0000040c': 'French',
      '00000407': 'German',
      '0000040a': 'Spanish',
      '00000410': 'Italian',
      '00000413': 'Dutch',
      '00000414': 'Norwegian',
      '00000415': 'Polish',
      '00000419': 'Russian',
      '0000041a': 'Serbian',
      '00000816': 'Portuguese (Brazil)',
    };
    return map[layoutId] ?? 'Layout $layoutId';
  }

  String _getLanguageFromLayoutId(String layoutId) {
    // Extract language code from layout ID (first 2-4 hex digits after 0000).
    if (layoutId.length >= 8) {
      final code = layoutId.substring(4, 8);
      if (code == '0409') return 'en';
      if (code == '040c') return 'fr';
      if (code == '0407') return 'de';
      if (code == '0a0a') return 'es';
      if (code == '0410') return 'it';
      if (code == '0413') return 'nl';
      if (code == '0414') return 'no';
      if (code == '0415') return 'pl';
      if (code == '0419') return 'ru';
      if (code == '041a') return 'sr';
    }
    return 'unknown';
  }

  String _getRegionFromLayoutId(String layoutId) {
    final map = {
      '00000409': 'US',
      '0000040c': 'FR',
      '00000407': 'DE',
      '0000040a': 'ES',
      '00000410': 'IT',
      '00000413': 'NL',
      '00000414': 'NO',
      '00000415': 'PL',
      '00000419': 'RU',
      '0000041a': 'RS',
      '00000816': 'BR',
    };
    return map[layoutId] ?? 'XX';
  }

  String _inferLayoutFamily(String layoutId) {
    // Fallback: try to infer from layout ID if not in known map.
    if (layoutId.contains('040c') || layoutId.contains('080c')) return 'AZERTY';
    if (layoutId.contains('0407') || layoutId.contains('0c07')) return 'QWERTZ';
    if (layoutId.contains('0809') || layoutId.contains('0c09')) return 'QWERTY'; // Canadian
    return 'QWERTY'; // Default to QWERTY
  }
}
