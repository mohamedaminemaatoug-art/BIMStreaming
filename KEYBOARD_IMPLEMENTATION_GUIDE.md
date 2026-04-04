# Keyboard Input Translation & Synchronization System

**TeamViewer-Grade Implementation for Remote Desktop Keyboard Control**

---

## 📋 Overview

This modular keyboard system provides **layout-independent, low-latency, and state-safe keyboard input transmission** between client and host machines. It handles the complexity of remote keyboard input with production-grade resilience and performance.

### Key Features

✅ **Layout-Independent Input Capture** - Uses USB HID scan codes, not characters  
✅ **Keyboard Layout Detection & Translation** - Automatic layout sync (QWERTY, AZERTY, QWERTZ, etc.)  
✅ **Key State Lifecycle Management** - Prevents stuck keys, ensures state consistency  
✅ **Controlled Key Repeat** - Client-side repeat with configurable intervals (320ms initial, 42ms repeat)  
✅ **Hardware Normalization** - Handles missing keys, numpad fallbacks  
✅ **Network Resilience** - Packet loss detection, state sync recovery  
✅ **Multiple Injection Strategies** - Unicode, Virtual Key, SendKeys with automatic fallback  
✅ **Performance Optimized** - Target latency < 20ms per event  
✅ **Modular Architecture** - Each component independently testable  

---

## 🏗️ Architecture

### Module Breakdown

```
keyboard_services/
├── keyboard_protocol.dart              # Shared data structures & constants
├── keyboard_input_abstraction.dart     # Client-side input capture
├── keyboard_layout_translator.dart     # Layout detection & translation
├── keyboard_state_manager.dart         # Key lifecycle management
├── keyboard_repeat_controller.dart     # Managed key repeat
├── keyboard_host_injection_engine.dart # Host-side key injection
├── keyboard_transport.dart             # Network resilience & recovery
└── keyboard_services.dart              # Barrel export
```

### Data Flow

**Client Side (Sending Input):**
```
KeyEvent (Flutter)
    ↓
KeyboardInputAbstraction
    ↓ (to structured KeyboardKeyEvent)
KeyboardStateManager (register down/up)
KeyboardRepeatController (manage repeat)
KeyboardLayoutTranslator (translate character)
KeyboardTransportLayer (queue & send)
    ↓ (to remote via signaling)
```

**Host Side (Receiving Input):**
```
KeyboardKeyEvent (from remote)
    ↓
KeyboardLayoutTranslator (translate character)
KeyboardStateManager (track active keys)
KeyboardHostInjectionEngine (select strategy)
    ↓ (PowerShell -> SendInput/Unicode)
Windows System (key injection)
```

---

## 🔧 Integration Guide

### Step 1: Initialize Modules in RemoteSupportPage

```dart
// In _RemoteSupportPageState.initState() or similar:

late KeyboardLayoutTranslator _keyboardLayoutTranslator;
late KeyboardStateManager _keyboardStateManager;
late KeyboardRepeatController _keyboardRepeatController;
late KeyboardTransportLayer _keyboardTransportLayer;
late KeyboardHostInjectionEngine _keyboardInjectionEngine;

@override
void initState() {
  super.initState();
  
  _initializeKeyboardSystem();
}

void _initializeKeyboardSystem() {
  // Translator
  _keyboardLayoutTranslator = KeyboardLayoutTranslator(
    onClientLayoutChanged: (old, newLayout) {
      print('[Keyboard] Client layout changed: $newLayout');
      _keyboardLayoutTranslator.clearCaches();
    },
    onHostLayoutChanged: (old, newLayout) {
      print('[Keyboard] Host layout changed: $newLayout');
      _keyboardLayoutTranslator.clearCaches();
    },
  );
  
  // State Manager
  _keyboardStateManager = KeyboardStateManager(
    onKeyStateChanged: (key) {
      print('[Keyboard] Key state changed: $key');
    },
    onStuckKeyForceReleased: (code, reason) {
      print('[Keyboard] WARNING: Stuck key 0x${code.toRadixString(16)} released: $reason');
    },
  );
  
  // Repeat Controller
  _keyboardRepeatController = KeyboardRepeatController(
    initialDelayMs: 320,
    repeatIntervalMs: 42,
    onRepeat: (code, payload) {
      _sendKeyboardEvent(payload, phase: 'down');
    },
    onRepeatStop: (code) {
      // Cleanup if needed
    },
  );
  
  // Transport Layer
  _keyboardTransportLayer = KeyboardTransportLayer(
    onSendEvent: (event) {
      _sendInputEvent('key_event', extra: event.toJson());
      return true;
    },
    onPacketLost: (seq) {
      print('[Keyboard] Packet loss detected at seq=$seq');
    },
    onRequestStateSync: () {
      print('[Keyboard] Requesting state sync');
      _syncKeyboardState();
    },
  );
  
  // Injection Engine
  _keyboardInjectionEngine = KeyboardHostInjectionEngine(
    layoutTranslator: _keyboardLayoutTranslator,
    stateManager: _keyboardStateManager,
    executePowerShell: _runPowerShell,
    onInjectionOccurred: (code, strategy) {
      print('[Keyboard] Injected 0x${code.toRadixString(16)} via $strategy');
    },
    onInjectionFailed: (code, reason) {
      print('[Keyboard] Injection failed for 0x${code.toRadixString(16)}: $reason');
    },
  );
  
  // Detect local keyboard layout
  unawaited(_keyboardLayoutTranslator.detectClientLayout());
  
  // Start periodic layout sync
  _startKeyboardLayoutSync();
}
```

### Step 2: Capture Client Keyboard Input

Replace existing keyboard capture in `KeyboardListener.onKeyEvent`:

```dart
onKeyEvent: (event) {
  if (!_canSendRemoteInput || _isDeviceLocked || _isSessionPaused) {
    return;
  }
  
  if (event is KeyDownEvent) {
    // Abstract the Flutter KeyEvent into our structured format
    final abstractedEvent = KeyboardInputAbstraction().abstractKeyEvent(
      event,
      clientLayout: _keyboardLayoutTranslator.clientLayout?.layoutId ?? 'unknown',
      clientLayoutFamily: _keyboardLayoutTranslator.clientLayoutFamily,
    );
    
    // Register key state
    final activeKey = _keyboardStateManager.registerKeyDown(
      abstractedEvent.physicalCode,
      abstractedEvent.toJson(),
      sequenceNumber: abstractedEvent.sequenceNumber,
    );
    
    if (activeKey != null) {
      // Start managed repeat if applicable
      final isManaged = _shouldManageRepeat(event.logicalKey);
      if (!abstractedEvent.isModifier && isManaged) {
        _keyboardRepeatController.startRepeat(
          abstractedEvent.physicalCode,
          abstractedEvent.toJson(),
          isModifier: abstractedEvent.isModifier,
        );
      }
      
      // Send event
      _keyboardTransportLayer.enqueueEvent(abstractedEvent);
    }
  } else if (event is KeyUpEvent) {
    final abstractedEvent = KeyboardInputAbstraction().abstractKeyEvent(
      event,
      clientLayout: _keyboardLayoutTranslator.clientLayout?.layoutId ?? 'unknown',
      clientLayoutFamily: _keyboardLayoutTranslator.clientLayoutFamily,
    );
    
    final physicalCode = abstractedEvent.physicalCode;
    
    // Stop managed repeat
    _keyboardRepeatController.stopRepeat(physicalCode);
    
    // Update state
    _keyboardStateManager.registerKeyUp(physicalCode);
    
    // Send event
    _keyboardTransportLayer.enqueueEvent(abstractedEvent);
  }
}
```

### Step 3: Process Remote Keyboard Input

Update `_applyRemoteKeyboardEvent()`:

```dart
Future<void> _applyRemoteKeyboardEvent(Map<String, dynamic> payload) async {
  if (!io.Platform.isWindows) return;
  
  try {
    // Deserialize event
    final event = KeyboardKeyEvent.fromJson(payload);
    
    // Update remote layout info
    _keyboardLayoutTranslator.setHostLayout(
      event.clientLayout,
      event.clientLayoutFamily,
    );
    
    // Inject keyboard input
    final success = await _keyboardInjectionEngine.injectKeyboardEvent(
      event,
      hostLayout: _keyboardLayoutTranslator.hostLayout?.layoutId ?? 'unknown',
      hostLayoutFamily: _keyboardLayoutTranslator.hostLayoutFamily,
    );
    
    if (!success) {
      print('[Keyboard] Failed to inject event: $event');
    }
  } catch (e) {
    print('[Keyboard] Error processing remote input: $e');
  }
}
```

### Step 4: Handle Disconnection & State Recovery

```dart
void _onSessionDisconnected() {
  // Stop all repeat
  _keyboardRepeatController.stopAllRepeats();
  
  // Force release all active keys on host
  final released = _keyboardStateManager.forceReleaseAll(
    reason: 'session_disconnected',
  );
  
  print('[Keyboard] Forced release of ${released.length} keys on disconnect');
  
  // Send reset command to remote
  _sendInputEvent('reset_all_keys');
  
  // Update transport state
  _keyboardTransportLayer.onDisconnected();
}

void _onSessionConnected() {
  // Transport layer tracks connection
  _keyboardTransportLayer.onConnected();
  
  // Sync keyboard layout with remote
  _syncKeyboardLayout();
}
```

### Step 5: Periodic Maintenance

```dart
void _startKeyboardLayoutSync() {
  _keyboardLayoutTimer?.cancel();
  unawaited(_keyboardLayoutTranslator.detectClientLayout());
  
  _keyboardLayoutTimer = Timer.periodic(Duration(seconds: 2), (_) {
    unawaited(_keyboardLayoutTranslator.detectClientLayout());
    _syncKeyboardLayout();
  });
}

void _syncKeyboardLayout() {
  _sendInputEvent('layout_sync', extra: {
    'layout': _keyboardLayoutTranslator.clientLayout?.layoutId ?? 'unknown',
    'layoutFamily': _keyboardLayoutTranslator.clientLayoutFamily,
  });
}

void _syncKeyboardState() {
  // Periodically sync active key state
  _sendInputEvent('key_state_sync', extra: {
    'activeKeys': _keyboardStateManager.activeKeys
        .map((k) => {
          'physicalCode': k.physicalCode,
          'state': k.state.name,
        })
        .toList(),
  });
}
```

---

## 📊 Monitoring & Diagnostics

### Get Transport Statistics

```dart
final stats = _keyboardTransportLayer.getStats();
print('Keyboard Transport: $stats');
// Output: KeyboardTransport(sent=1234, acked=1230, pending=2, loss=0.3%, state=connected)
```

### Get Active Keys

```dart
final activeKeys = _keyboardStateManager.activeKeys;
print('Active keys: ${_keyboardStateManager.getSummary()}');
// Output: Active keys: 2 active key(s): 28, 42
```

### Get Repeat Status

```dart
print('Repeating: ${_keyboardRepeatController.getRepeatingKeys()}');
print('${_keyboardRepeatController.getSummary()}');
```

### Layout Diagnostics

```dart
print(_keyboardLayoutTranslator.formatLayoutDiagnostics());
// Output: Client: English (US) (QWERTY) | Host: French (AZERTY)
```

---

## 🎯 Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| **Event Latency** | < 20ms | Per-event capture + send + inject |
| **Key Repeat Delay** | 320ms | Initial delay before repeat starts |
| **Key Repeat Interval** | 42ms | ~24 repeats per second |
| **Layout Detection** | < 100ms | One-time cost, cached after |
| **Stuck Key Timeout** | 30s | Force-release after 30s hold |
| **Packet Loss Handling** | < 50ms | State sync + retry |

---

## 🔒 Safety Guarantees

1. **No Stuck Keys** - Every KeyDown has a corresponding KeyUp; force-release on timeout
2. **State Consistency** - Active key registry prevents duplicate downs
3. **Layout Fidelity** - Visual character correctness across layout boundaries
4. **Network Resilience** - Handles packet loss and disconnections gracefully
5. **Modifier Integrity** - Modifiers remain consistent across key combinations

---

## 🐛 Debugging Tips

### Enable Verbose Logging

Add this in the module constructors:

```dart
// In KeyboardStateManager:
onKeyStateChanged: (key) => print('[DEBUG] $key'),

// In KeyboardRepeatController:
onRepeat: (code, _) => print('[DEBUG] Repeat $code'),

// In KeyboardHostInjectionEngine:
onInjectionOccurred: (code, strategy) => 
    print('[DEBUG] Injected via $strategy'),
```

### Test Layout Detection

```dart
await _keyboardLayoutTranslator.detectClientLayout();
print('Detected: ${_keyboardLayoutTranslator.clientLayout}');
```

### Test Key Injection

```bash
# Manually inject a key via PowerShell (Windows):
powershell -Command @"
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
"@
```

### Export State Snapshot

```dart
print('Active keys state:');
print(_keyboardStateManager.exportState());

print('Transport stats:');
print(_keyboardTransportLayer.getStats());
```

---

## 🚀 Advanced Configuration

### Customize Repeat Intervals

```dart
_keyboardRepeatController = KeyboardRepeatController(
  initialDelayMs: 300,  // Apple-like: slightly faster
  repeatIntervalMs: 30, // Faster repeat (33ms per char)
  onRepeat: (code, payload) => _sendKeyboardEvent(payload),
);
```

### Change Layout Detection Interval

```dart
_keyboardLayoutTimer = Timer.periodic(Duration(seconds: 5), (_) {
  // Check less frequently on higher-latency networks
  unawaited(_keyboardLayoutTranslator.detectClientLayout());
});
```

### Monitor Stuck Key Timeout

```dart
Timer.periodic(Duration(seconds: 5), (_) {
  final stuck = _keyboardStateManager.checkForStuckKeys(
    maxHoldDurationMs: 30000, // 30 seconds
  );
  if (stuck.isNotEmpty) {
    print('WARNING: ${stuck.length} stuck keys detected');
    for (final key in stuck) {
      _keyboardStateManager.forceRelease(
        key.physicalCode,
        reason: 'timeout',
      );
    }
  }
});
```

---

## 📝 Protocol Messages

### Key Event (v2)

```json
{
  "action": "key_event",
  "payload": {
    "physicalCode": 65,
    "logicalKeyId": 4294967305,
    "characterCodePoint": 97,
    "keyName": "Key A",
    "keyLabel": "a",
    "phase": "down",
    "modifiers": {
      "shift": false,
      "control": false,
      "alt": false,
      "meta": false,
      "altGraph": false
    },
    "isNumpad": false,
    "isModifier": false,
    "clientLayout": "00000409",
    "clientLayoutFamily": "QWERTY",
    "captureTimestampMs": 1704067200000,
    "sequenceNumber": 1234
  }
}
```

### Layout Sync

```json
{
  "action": "layout_sync",
  "payload": {
    "layout": "0000040c",
    "layoutFamily": "AZERTY"
  }
}
```

### Key State Sync

```json
{
  "action": "key_state_sync",
  "payload": {
    "activeKeys": [
      { "physicalCode": 28, "state": "hold" },
      { "physicalCode": 42, "state": "hold" }
    ]
  }
}
```

### Reset All Keys

```json
{
  "action": "reset_all_keys"
}
```

---

## 📚 See Also

- `keyboard_protocol.dart` - Protocol & data structures
- `keyboard_input_abstraction.dart` - Client-side capture
- `keyboard_layout_translator.dart` - Layout handling
- `keyboard_state_manager.dart` - Key lifecycle
- `keyboard_repeat_controller.dart` - Managed repeat
- `keyboard_host_injection_engine.dart` - Host injection
- `keyboard_transport.dart` - Network resilience

---

## 🎓 Best Practices

1. **Always register KeyDown/KeyUp pairs** - Use the state manager to prevent orphaned states
2. **Let the system manage repeat** - Don't rely on OS repeat; use the repeat controller
3. **Check layout compatibility** - Call `areLayoutsCompatible()` for warnings
4. **Monitor stuck keys** - Periodically check for and force-release stuck keys
5. **Handle disconnections gracefully** - Always call `onSessionDisconnected()` and reset state
6. **Cache layout info** - Minimize layout detection calls; sync every 2-5 seconds
7. **Log injection failures** - Track failed injections to diagnose input delivery issues
8. **Test with real keyboards** - Test with multiple layouts (QWERTY, AZERTY, QWERTZ, Dvorak, etc.)

---

**Last Updated: 2025-04-04**  
**Version: 2.0 (TeamViewer-Grade Implementation)**
