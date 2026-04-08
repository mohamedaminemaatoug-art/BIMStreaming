/// Key State Lifecycle Management.
///
/// Tracks active keys, prevents stuck keys, ensures every KeyDown has a KeyUp,
/// and manages the state machine: IDLE -> DOWN -> HOLD -> UP -> IDLE.

import 'keyboard_protocol.dart';

/// Manages the lifecycle of active keyboard keys.
class KeyboardStateManager {
  /// Active keys by physical code.
  final Map<int, ActiveKey> _activeKeys = <int, ActiveKey>{};

  /// Callback when key state changes.
  final void Function(ActiveKey key)? onKeyStateChanged;

  /// Callback when stuck key is detected and forced released.
  final void Function(int physicalCode, String reason)? onStuckKeyForceReleased;

  KeyboardStateManager({
    this.onKeyStateChanged,
    this.onStuckKeyForceReleased,
  });

  /// Get all currently active keys.
  List<ActiveKey> get activeKeys => _activeKeys.values.toList();

  /// Check if a key is currently pressed.
  bool isKeyPressed(int physicalCode) {
    final key = _activeKeys[physicalCode];
    return key != null && (key.state == KeyState.down || key.state == KeyState.hold);
  }

  /// Get active key by physical code.
  ActiveKey? getActiveKey(int physicalCode) => _activeKeys[physicalCode];

  /// Register a key-down event.
  ///
  /// Returns the active key if successful, or null if prevented (e.g., duplicate down).
  ActiveKey? registerKeyDown(
    int physicalCode,
    Map<String, dynamic> eventPayload, {
    required int sequenceNumber,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Prevent duplicate KeyDown (key already pressed).
    if (_activeKeys.containsKey(physicalCode)) {
      final existing = _activeKeys[physicalCode]!;
      if (existing.state == KeyState.down || existing.state == KeyState.hold) {
        return null; // Ignore duplicate
      }
    }

    // Create new active key.
    final activeKey = ActiveKey(
      physicalCode: physicalCode,
      state: KeyState.down,
      pressedAtMs: now,
      lastRepeatAtMs: now,
      originalEventPayload: eventPayload,
    );

    _activeKeys[physicalCode] = activeKey;
    onKeyStateChanged?.call(activeKey);

    return activeKey;
  }

  /// Transition a key to HOLD state (occurs during repeat phase).
  void transitionToHold(int physicalCode) {
    final key = _activeKeys[physicalCode];
    if (key != null && key.state == KeyState.down) {
      key.state = KeyState.hold;
      onKeyStateChanged?.call(key);
    }
  }

  /// Update last repeat timestamp (for repeat tracking).
  void updateLastRepeat(int physicalCode, int atMs) {
    final key = _activeKeys[physicalCode];
    if (key != null) {
      key.lastRepeatAtMs = atMs;
    }
  }

  /// Register a key-up event.
  ///
  /// Returns the active key if found, or null if key was not registered.
  ActiveKey? registerKeyUp(int physicalCode) {
    final key = _activeKeys.remove(physicalCode);
    if (key != null) {
      key.state = KeyState.up;
      onKeyStateChanged?.call(key);
    }
    return key;
  }

  /// Force release all active keys (called on disconnect/timeout).
  ///
  /// Returns list of keys that were forcibly released.
  List<ActiveKey> forceReleaseAll({required String reason}) {
    final released = <ActiveKey>[];

    for (final key in _activeKeys.values) {
      key.state = KeyState.up;
      released.add(key);
      onStuckKeyForceReleased?.call(key.physicalCode, reason);
    }

    _activeKeys.clear();
    return released;
  }

  /// Force release a specific key (called on timeout).
  ActiveKey? forceRelease(int physicalCode, {required String reason}) {
    final key = _activeKeys.remove(physicalCode);
    if (key != null) {
      key.state = KeyState.up;
      onStuckKeyForceReleased?.call(physicalCode, reason);
    }
    return key;
  }

  /// Get summary of active keys.
  String getSummary() {
    if (_activeKeys.isEmpty) return 'No active keys';
    final codes = _activeKeys.keys.join(', ');
    return '${_activeKeys.length} active key(s): $codes';
  }

  /// Check for stuck keys (held longer than timeout).
  ///
  /// Returns list of keys that are considered stuck.
  List<ActiveKey> checkForStuckKeys({required int maxHoldDurationMs}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stuck = <ActiveKey>[];

    for (final key in _activeKeys.values) {
      final holdDuration = now - key.pressedAtMs;
      if (holdDuration > maxHoldDurationMs) {
        stuck.add(key);
      }
    }

    return stuck;
  }

  /// Clear all state (hard reset).
  void clear() {
    _activeKeys.clear();
  }

  /// Export state as JSON (for diagnostics/debugging).
  List<Map<String, dynamic>> exportState() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _activeKeys.values
        .map((key) => {
              'physicalCode': key.physicalCode,
              'state': key.state.name,
              'holdDurationMs': now - key.pressedAtMs,
              'lastRepeatAtMs': key.lastRepeatAtMs,
            })
        .toList();
  }
}
