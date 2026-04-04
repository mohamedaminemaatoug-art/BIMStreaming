# Keyboard System Integration Checklist

**Estimated Integration Time:** 4-6 hours  
**Complexity:** Medium (straightforward refactoring)  
**Risk Level:** Low (modular, non-breaking)

---

## ✅ Phase 1: Module Setup (30 min)

### 1.1 Import Modules

Add to top of `lib/screens/remote_support_page.dart`:

```dart
import '../services/keyboard/keyboard_services.dart';
```

This single import provides access to all 7 modules via the barrel export.

**Status:** ☐ Done

### 1.2 Add Field Declarations

In `_RemoteSupportPageState` class, add these field declarations:

```dart
// ===== NEW KEYBOARD SYSTEM (v2) =====
late KeyboardLayoutTranslator _keyboardLayoutTranslator;
late KeyboardStateManager _keyboardStateManager;
late KeyboardRepeatController _keyboardRepeatController;
late KeyboardTransportLayer _keyboardTransportLayer;
late KeyboardHostInjectionEngine _keyboardInjectionEngine;
// ===== END KEYBOARD SYSTEM =====
```

**Where to add:** Near other late final declarations (line ~127+)

**Status:** ☐ Done

---

## ✅ Phase 2: Module Initialization (1 hour)

### 2.1 Create Initialization Method

Add new method to `_RemoteSupportPageState`:

```dart
void _initializeKeyboardSystemV2() {
  // === Layout Translator ===
  _keyboardLayoutTranslator = KeyboardLayoutTranslator(
    onClientLayoutChanged: (old, newLayout) {
      if (old?.layoutId != newLayout?.layoutId) {
        print('[Keyboard] Client layout changed from ${old?.displayName} to ${newLayout?.displayName}');
        _sendInputEvent('layout_sync', extra: {
          'layout': newLayout?.layoutId ?? 'unknown',
          'layoutFamily': newLayout?.family ?? 'unknown',
        });
      }
    },
    onHostLayoutChanged: (old, newLayout) {
      print('[Keyboard] Host layout updated to ${newLayout?.displayName}');
    },
  );

  // === State Manager ===
  _keyboardStateManager = KeyboardStateManager(
    onKeyStateChanged: (key) {
      // Optional: log state changes for diagnostics
      // print('[Keyboard] State change: $key');
    },
    onStuckKeyForceReleased: (code, reason) {
      print('[Keyboard] WARNING: Stuck key 0x${code.toRadixString(16)} released due to: $reason');
      // Could show user notification here if needed
    },
  );

  // === Repeat Controller ===
  _keyboardRepeatController = KeyboardRepeatController(
    initialDelayMs: 320,
    repeatIntervalMs: 42,
    onRepeat: (physicalCode, payload) {
      // Re-send repeat key-down event
      _keyboardTransportLayer.enqueueEvent(
        KeyboardKeyEvent.fromJson(payload),
      );
    },
    onRepeatStop: (physicalCode) {
      // Optional: cleanup if needed
    },
  );

  // === Transport Layer ===
  _keyboardTransportLayer = KeyboardTransportLayer(
    onSendEvent: (event) {
      // Send to remote
      _sendInputEvent('key_event', extra: event.toJson());
      return true;
    },
    onAckReceived: (sequenceNumber) {
      // Optional: track acknowledged events
    },
    onPacketLost: (lostSequence) {
      print('[Keyboard] Packet loss detected at sequence: $lostSequence');
      // Trigger state sync recovery
    },
    onRequestStateSync: () {
      _syncKeyboardState();
    },
  );

  // === Injection Engine ===
  _keyboardInjectionEngine = KeyboardHostInjectionEngine(
    layoutTranslator: _keyboardLayoutTranslator,
    stateManager: _keyboardStateManager,
    executePowerShell: _runPowerShell,
    onInjectionOccurred: (code, strategy) {
      // Optional: log successful injections
      // print('[Keyboard] Injected 0x${code.toRadixString(16)} via $strategy');
    },
    onInjectionFailed: (code, reason) {
      print('[Keyboard] Injection FAILED for 0x${code.toRadixString(16)}: $reason');
    },
  );

  // === Startup Routines ===
  // Detect local keyboard layout
  unawaited(_keyboardLayoutTranslator.detectClientLayout());

  // Start keyboard layout sync timer
  _startKeyboardLayoutSyncV2();

  print('[Keyboard] System V2 initialized successfully');
}
```

**Status:** ☐ Done

### 2.2 Add Initialization Call

In `initState()`, call the initialization method:

```dart
@override
void initState() {
  super.initState();
  
  // ... existing init code ...
  
  // Initialize keyboard system v2
  _initializeKeyboardSystemV2();
  
  // ... rest of init ...
}
```

**Status:** ☐ Done

---

## ✅ Phase 3: Client Input Capture (1 hour)

### 3.1 Replace KeyboardListener Callback

Find the existing `KeyboardListener` widget in `_buildRemoteCanvas()` method.

**Current code location:** Around line 3356-3370

**Replace the entire `onKeyEvent` callback with:**

```dart
onKeyEvent: (event) {
  // Check permissions
  if (!_canSendRemoteInput || _isDeviceLocked || _isSessionPaused) {
    return;
  }
  if (!_keyboardInputEnabledForUser2) {
    return;
  }

  // Handle KeyDownEvent
  if (event is KeyDownEvent) {
    try {
      // Abstract the Flutter event into structured format
      final abstractedEvent = KeyboardInputAbstraction().abstractKeyEvent(
        event,
        clientLayout: _keyboardLayoutTranslator.clientLayout?.layoutId ?? 'unknown',
        clientLayoutFamily: _keyboardLayoutTranslator.clientLayoutFamily,
      );

      // Register key downstate
      final activeKey = _keyboardStateManager.registerKeyDown(
        abstractedEvent.physicalCode,
        abstractedEvent.toJson(),
        sequenceNumber: abstractedEvent.sequenceNumber,
      );

      if (activeKey != null) {
        // Check if this is a managed repeat key
        final isManaged = _isManagedRepeatKeyV2(event.logicalKey);
        if (!abstractedEvent.isModifier && isManaged) {
          _keyboardRepeatController.startRepeat(
            abstractedEvent.physicalCode,
            abstractedEvent.toJson(),
            isModifier: false,
          );
        }

        // Enqueue for transport & sending
        _keyboardTransportLayer.enqueueEvent(abstractedEvent);
      }
    } catch (e) {
      print('[Keyboard] Error handling KeyDown: $e');
    }
  }

  // Handle KeyUpEvent
  if (event is KeyUpEvent) {
    try {
      final abstractedEvent = KeyboardInputAbstraction().abstractKeyEvent(
        event,
        clientLayout: _keyboardLayoutTranslator.clientLayout?.layoutId ?? 'unknown',
        clientLayoutFamily: _keyboardLayoutTranslator.clientLayoutFamily,
      );

      final physicalCode = abstractedEvent.physicalCode;

      // Stop any active repeat for this key
      _keyboardRepeatController.stopRepeat(physicalCode);

      // Update state to UP
      _keyboardStateManager.registerKeyUp(physicalCode);

      // Enqueue for transport & sending
      _keyboardTransportLayer.enqueueEvent(abstractedEvent);
    } catch (e) {
      print('[Keyboard] Error handling KeyUp: $e');
    }
  }
},
```

**Status:** ☐ Done

### 3.2 Add Helper Method

Add this helper method to determine which keys should have managed repeat:

```dart
/// Check if a key should have client-side managed repeat.
bool _isManagedRepeatKeyV2(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.backspace ||
      key == LogicalKeyboardKey.delete;
}
```

**Where to add:** Near other `_isManagedRepeatKey` family methods (around line 1584)

**Status:** ☐ Done

---

## ✅ Phase 4: Host Input Reception (1.5 hours)

### 4.1 Replace Remote Keyboard Event Handler

Find method `_applyRemoteKeyboardEvent()` (around line 2237).

**Replace the entire method body with:**

```dart
Future<void> _applyRemoteKeyboardEvent(Map<String, dynamic> payload) async {
  if (!io.Platform.isWindows) return;

  try {
    // Deserialize the keyboard event
    final event = KeyboardKeyEvent.fromJson(payload);

    // Update host layout info from remote
    if (event.clientLayout.isNotEmpty && event.clientLayout != 'unknown') {
      _keyboardLayoutTranslator.setHostLayout(
        event.clientLayout,
        event.clientLayoutFamily,
      );
    }

    // Inject the keyboard event
    final success = await _keyboardInjectionEngine.injectKeyboardEvent(
      event,
      hostLayout: _keyboardLayoutTranslator.hostLayout?.layoutId ?? 'unknown',
      hostLayoutFamily: _keyboardLayoutTranslator.hostLayoutFamily,
    );

    if (!success) {
      print('[Keyboard] Failed to inject key event: ${event.keyName} (phase=${event.phase})');
    }
  } catch (e) {
    print('[Keyboard] Error applying remote keyboard event: $e');
  }
}
```

**Status:** ☐ Done

### 4.2 Handle Reset Key Command

Add this new method to handle forced key reset:

```dart
/// Force release all injected (active) keys on the host.
/// Called when client disconnect or timeout occurs.
Future<void> _handleRemoteKeyReset() async {
  if (!io.Platform.isWindows) return;

  try {
    // Inject UP for all modifier keys as reset
    final resetEvents = [
      KeyboardKeyEvent(
        physicalCode: 0xA0,
        logicalKeyId: 0,
        characterCodePoint: 0,
        keyName: 'Shift Left',
        keyLabel: '',
        phase: 'up',
        modifiers: ModifierState(),
        isNumpad: false,
        isModifier: true,
        clientLayout: 'unknown',
        clientLayoutFamily: 'unknown',
        captureTimestampMs: DateTime.now().millisecondsSinceEpoch,
        sequenceNumber: 0,
      ),
      // Add more modifier resets as needed (Ctrl, Alt)
    ];

    for (final event in resetEvents) {
      await _keyboardInjectionEngine.injectKeyboardEvent(
        event,
        hostLayout: 'unknown',
        hostLayoutFamily: 'unknown',
      );
    }

    print('[Keyboard] Sent key reset sequence');
  } catch (e) {
    print('[Keyboard] Error sending key reset: $e');
  }
}
```

**Status:** ☐ Done

### 4.3 Update Remote Input Dispatcher

In method `_applyRemoteInput()`, update the keyboard event handlers:

Find the line:
```dart
if (action == 'key_event' || (action == 'key_press' && payload.containsKey('phase'))) {
  await _applyRemoteKeyboardEvent(payload);
  return;
}
```

Add handling for new commands:
```dart
if (action == 'key_event' || (action == 'key_press' && payload.containsKey('phase'))) {
  await _applyRemoteKeyboardEvent(payload);
  return;
}
if (action == 'reset_all_keys') {
  await _handleRemoteKeyReset();
  return;
}
if (action == 'layout_sync') {
  final layout = (payload['layout'] ?? 'unknown').toString();
  final family = (payload['layoutFamily'] ?? 'unknown').toString();
  if (layout != 'unknown') {
    _keyboardLayoutTranslator.setHostLayout(layout, family);
  }
  return;
}
```

**Status:** ☐ Done

---

## ✅ Phase 5: Connection Lifecycle (30 min)

### 5.1 On Session Connect

Find where session connection is established. Add:

```dart
void _onKeyboardSessionConnected() {
  _keyboardTransportLayer.onConnected();
  _keyboardLayoutTranslator.detectClientLayout();
  print('[Keyboard] Session connected, transport active');
}
```

Call this when session connects (in your signaling handler).

**Status:** ☐ Done

### 5.2 On Session Disconnect

Find where session disconnection is handled. Add:

```dart
void _onKeyboardSessionDisconnected() {
  print('[Keyboard] Session disconnecting, releasing all keys...');
  
  // Stop all key repeats
  _keyboardRepeatController.stopAllRepeats();

  // Mark transport as disconnected
  _keyboardTransportLayer.onDisconnected();

  // If we're the HOST, force release all injected keys
  if (widget.sendLocalScreen) {
    unawaited(_handleRemoteKeyReset());
  }

  // Force-release all active states
  final released = _keyboardStateManager.forceReleaseAll(
    reason: 'session_disconnected',
  );

  print('[Keyboard] Force-released ${released.length} keys');
}
```

Call this in your session cleanup code.

**Status:** ☐ Done

### 5.3 Periodic Maintenance

Add this method:

```dart
void _startKeyboardLayoutSyncV2() {
  _keyboardLayoutTimer?.cancel();

  // Initial layout detection
  unawaited(_keyboardLayoutTranslator.detectClientLayout());

  // Periodic sync every 2 seconds
  _keyboardLayoutTimer = Timer.periodic(const Duration(seconds: 2), (_) {
    if (!_isConnected || _isSessionPaused) return;

    unawaited(_keyboardLayoutTranslator.detectClientLayout());

    // Sync layout with remote
    _sendInputEvent('layout_sync', extra: {
      'layout': _keyboardLayoutTranslator.clientLayout?.layoutId ?? 'unknown',
      'layoutFamily': _keyboardLayoutTranslator.clientLayoutFamily,
    });
  });
}

void _stopKeyboardLayoutSyncV2() {
  _keyboardLayoutTimer?.cancel();
  _keyboardLayoutTimer = null;
}

void _syncKeyboardState() {
  // Send active key state to remote for recovery/sync
  final activeKeys = _keyboardStateManager.activeKeys;
  _sendInputEvent('key_state_sync', extra: {
    'activeKeys': activeKeys
        .map((k) => {
              'physicalCode': k.physicalCode,
              'state': k.state.name,
              'holdDurationMs': k.holdDurationMs,
            })
        .toList(),
  });
}
```

**Status:** ☐ Done

---

## ✅ Phase 6: Cleanup & Disposal (15 min)

### 6.1 Add Disposal

In the `dispose()` method, add:

```dart
@override
void dispose() {
  // ... existing dispose code ...

  // Keyboard system cleanup
  _keyboardRepeatController.stopAllRepeats();
  _keyboardRepeatController.dispose();
  _keyboardTransportLayer.dispose();
  _stopKeyboardLayoutSyncV2();

  // ... rest of dispose ...
  super.dispose();
}
```

**Status:** ☐ Done

---

## ✅ Phase 7: Testing (2 hours)

### 7.1 Basic Functional Tests

- [ ] **Test 1: Single Key Press**
  - Press 'A', verify event is sent with correct physical code
  - Verify character is captured
  - Result: Received on host, letter 'a' appears in app

- [ ] **Test 2: Key Repeat**
  - Hold Backspace for 2 seconds
  - Verify: initial pause (~320ms), then repeated deletions
  - Result: Characters deleted at controlled rate

- [ ] **Test 3: Modifiers**
  - Press Shift+A
  - Verify: Capital 'A' appears on host
  - Result: Uppercase received (not lowercase)

- [ ] **Test 4: Special Keys**
  - Press Arrows, Enter, Backspace
  - Verify: Each received and injected correctly
  - Result: No lag, immediate response

- [ ] **Test 5: Layout Detection**
  - Check console output for detected layout
  - Result: Should see "English (US)" or similar

- [ ] **Test 6: Disconnect Cleanup**
  - Press & hold a key
  - Disconnect session
  - Verify: No stuck keys on host
  - Result: Key releases automatically

### 7.2 Multi-Layout Tests

- [ ] **Test 7: QWERTY Client → AZERTY Host**
  - If available, test cross-layout
  - Verify: Characters match visually

- [ ] **Test 8: Rapid Typing**
  - Type full sentence rapidly
  - Verify: All characters received, correct order
  - Result: No dropped characters

**Status:** ☐ Done

---

## ✅ Phase 8: Monitoring & Diagnostics (30 min)

### 8.1 Add Diagnostics Display

Add optional UI or logging for stats:

```dart
void _printKeyboardDiagnostics() {
  print('\n=== Keyboard Diagnostics ===');
  
  print('Layout: ${_keyboardLayoutTranslator.formatLayoutDiagnostics()}');
  
  print('Active Keys: ${_keyboardStateManager.getSummary()}');
  
  print('Repeat Status: ${_keyboardRepeatController.getSummary()}');
  
  print('Transport: ${_keyboardTransportLayer.getStats()}');
  
  print('================================\n');
}
```

Call periodically (e.g., in a debug button tap).

**Status:** ☐ Done

---

## ✅ Phase 9: Code Cleanup (30 min)

### 9.1 Remove Old Keyboard Code

- [ ] Comment out or remove old `_sendKeyboardEvent()` (if replacing)
- [ ] Remove old key press handling code
- [ ] Clean up old layout sync code

### 9.2 Update Comments

- [ ] Add "// V2" markers where new code is used
- [ ] Document behavior of each new section

**Status:** ☐ Done

---

## ✅ Final Checklist

- [ ] All 7 modules imported
- [ ] Field declarations added
- [ ] Initialization method created and called
- [ ] KeyboardListener callback updated
- [ ] _applyRemoteKeyboardEvent() updated
- [ ] Connection/disconnection handlers updated
- [ ] Periodic maintenance timers added
- [ ] Disposal code added
- [ ] All 8 tests passing
- [ ] Diagnostics working
- [ ] Old code removed/deprecated
- [ ] Code reviewed by team
- [ ] Documentation updated (team wiki/docs)

---

## 📝 Integration Verification

After completing all steps, verify:

```dart
// Should see in logs:
// [Keyboard] System V2 initialized successfully
// [Keyboard] Client layout changed from ... to ...
// [Keyboard] Injected 0x1E via unicode
// [Keyboard] Transport: KeyboardTransport(sent=..., acked=..., ...)
```

If not seeing these logs, check:
1. Are modules being initialized?
2. Is KeyboardListener callback being invoked?
3. Is _applyRemoteKeyboardEvent being called on host?

---

## 🚀 Rollout Strategy

**Recommendation:** Feature flag for gradual rollout

```dart
const bool useKeyboardV2 = true; // Set to false to fall back to old system

if (useKeyboardV2) {
  // Use new system
  _initializeKeyboardSystemV2();
} else {
  // Use old system (existing code)
  _initializeKeyboardSystemV1();
}
```

This allows safe A/B testing and quick rollback if issues arise.

---

**Estimated Total Time:** 4-6 hours  
**Difficulty:** Medium  
**Risk:** Low (modular, easy to rollback)
