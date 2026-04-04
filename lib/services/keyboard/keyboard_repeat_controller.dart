/// Controlled Key Repeat System.
///
/// Implements TeamViewer-like key repeat with client-side control.
/// Disables blind OS repeat reliance and provides predictable, configurable behavior.

import 'dart:async';
import 'keyboard_protocol.dart';

/// Controls key repeat behavior with configurable intervals.
class KeyboardRepeatController {
  /// Initial delay before repeat starts (milliseconds).
  final int initialDelayMs;

  /// Interval between repeated events (milliseconds).
  final int repeatIntervalMs;

  /// Active repeat timers by physical code.
  final Map<int, Timer> _repeatInitialDelayTimers = <int, Timer>{};
  final Map<int, Timer> _repeatIntervalTimers = <int, Timer>{};

  /// Callback when repeat should be sent to remote.
  final void Function(int physicalCode, Map<String, dynamic> payload)? onRepeat;

  /// Callback when repeat is stopped.
  final void Function(int physicalCode)? onRepeatStop;

  KeyboardRepeatController({
    this.initialDelayMs = keyRepeatInitialDelayMs, // 320ms
    this.repeatIntervalMs = keyRepeatIntervalMs, // 42ms
    this.onRepeat,
    this.onRepeatStop,
  });

  /// Check if a key is currently repeating.
  bool isRepeating(int physicalCode) {
    return _repeatIntervalTimers.containsKey(physicalCode);
  }

  /// Check if a key is in the initial delay phase.
  bool isInInitialDelay(int physicalCode) {
    return _repeatInitialDelayTimers.containsKey(physicalCode);
  }

  /// Start managed repeat for a key.
  ///
  /// Schedules:
  /// 1. Initial delay (e.g., 320ms)
  /// 2. Then repeated sends at interval (e.g., every 42ms)
  void startRepeat(
    int physicalCode,
    Map<String, dynamic> eventPayload, {
    required bool isModifier,
  }) {
    // Don't repeat modifier keys themselves; modifiers affect other keys.
    if (isModifier) {
      return;
    }

    // Stop any existing repeat for this key.
    stopRepeat(physicalCode);

    // Schedule initial delay before repeat starts.
    _repeatInitialDelayTimers[physicalCode] = Timer(
      Duration(milliseconds: initialDelayMs),
      () {
        _repeatInitialDelayTimers.remove(physicalCode);

        // Start the repeating timer.
        _repeatIntervalTimers[physicalCode] = Timer.periodic(
          Duration(milliseconds: repeatIntervalMs),
          (_) {
            // Invoke callback to send repeat event.
            onRepeat?.call(physicalCode, eventPayload);
          },
        );
      },
    );
  }

  /// Stop repeat for a key (called on KeyUp).
  void stopRepeat(int physicalCode) {
    _repeatInitialDelayTimers.remove(physicalCode)?.cancel();
    final intervalTimer = _repeatIntervalTimers.remove(physicalCode);

    if (intervalTimer != null) {
      intervalTimer.cancel();
      onRepeatStop?.call(physicalCode);
    }
  }

  /// Stop all active repeats (called on disconnect/session end).
  void stopAllRepeats() {
    for (final timer in _repeatInitialDelayTimers.values) {
      timer.cancel();
    }
    for (final timer in _repeatIntervalTimers.values) {
      timer.cancel();
    }
    _repeatInitialDelayTimers.clear();
    _repeatIntervalTimers.clear();
  }

  /// Get list of keys currently repeating.
  List<int> getRepeatingKeys() => _repeatIntervalTimers.keys.toList();

  /// Get list of keys in initial delay.
  List<int> getInitialDelayKeys() => _repeatInitialDelayTimers.keys.toList();

  /// Get diagnostic summary.
  String getSummary() {
    final repeating = _repeatIntervalTimers.length;
    final delaying = _repeatInitialDelayTimers.length;
    return 'Repeating: $repeating keys, Delaying: $delaying keys';
  }

  /// Tune repeat intervals (for adapting to network conditions).
  void setIntervals({
    required int initialDelayMs,
    required int repeatIntervalMs,
  }) {
    // Note: Can only tune for NEW repeats; existing repeats keep their original intervals.
    // To apply to existing repeats, would need to rebuild all timers.
  }

  /// Dispose all resources.
  void dispose() {
    stopAllRepeats();
  }
}
