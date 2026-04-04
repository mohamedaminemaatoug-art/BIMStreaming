# Keyboard System Quick Reference

## 🎯 At a Glance

| Component | Purpose | Key Methods |
|-----------|---------|-------------|
| **KeyboardProtocol** | Data structures | `KeyboardKeyEvent`, `ModifierState`, `KeyboardLayout` |
| **KeyboardInputAbstraction** | Client capture | `abstractKeyEvent()`, `isPrintableCharacter()` |
| **KeyboardLayoutTranslator** | Layout mapping | `detectClientLayout()`, `translateCharacter()`, `areLayoutsCompatible()` |
| **KeyboardStateManager** | Key lifecycle | `registerKeyDown()`, `registerKeyUp()`, `checkForStuckKeys()` |
| **KeyboardRepeatController** | Managed repeat | `startRepeat()`, `stopRepeat()`, `stopAllRepeats()` |
| **KeyboardHostInjectionEngine** | Host injection | `injectKeyboardEvent()` (auto-selects strategy) |
| **KeyboardTransportLayer** | Network resilience | `enqueueEvent()`, `handleAckReceived()`, `getStats()` |

---

## 🔄 Key Lifecycle (Per Key)

```
1. KeyDown Event
   ↓
   abstractKeyEvent() → KeyboardKeyEvent
   ↓
   registerKeyDown() → ActiveKey(state=DOWN)
   ↓
   startRepeat() (if applicable)
   ↓
   enqueueEvent() → Transport → Send

2. Repeat Phase (if key held)
   ↓
   Timer fires every 42ms
   ↓
   onRepeat() callback → enqueueEvent()
   ↓
   Send repeat event

3. KeyUp Event
   ↓
   abstractKeyEvent() → KeyboardKeyEvent
   ↓
   stopRepeat()
   ↓
   registerKeyUp() → ActiveKey(state=UP)
   ↓
   enqueueEvent() → Transport → Send

4. Cleanup
   ↓
   forceReleaseAll() (on disconnect)
```

---

## 💻 Usage Snippets

### Initialize All Modules

```dart
// One-liner pattern
late final _translator = KeyboardLayoutTranslator();
late final _stateManager = KeyboardStateManager();
late final _repeatController = KeyboardRepeatController();
late final _transport = KeyboardTransportLayer();
late final _injectionEngine = KeyboardHostInjectionEngine(
  layoutTranslator: _translator,
  stateManager: _stateManager,
  executePowerShell: _runPowerShell,
);
```

### Send Key (Client)

```dart
// On KeyDown
final event = KeyboardInputAbstraction().abstractKeyEvent(
  flutterEvent,
  clientLayout: 'en-US',
  clientLayoutFamily: 'QWERTY',
);
_stateManager.registerKeyDown(event.physicalCode, event.toJson());
_transport.enqueueEvent(event);
```

### Receive Key (Host)

```dart
// On remote keyboard message
final event = KeyboardKeyEvent.fromJson(payload);
await _injectionEngine.injectKeyboardEvent(
  event,
  hostLayout: 'en-US',
  hostLayoutFamily: 'QWERTY',
);
```

### Handle Disconnect

```dart
_repeatController.stopAllRepeats();
_stateManager.forceReleaseAll(reason: 'disconnect');
_transport.onDisconnected();
```

---

## 🚨 Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| Stuck Keys | Missing KeyUp | Check `forceReleaseAll()` on disconnect |
| Repeated Events | Multiple repeat timers | Call `stopRepeat()` before `startRepeat()` |
| Wrong Characters | Layout mismatch not detected | Call `detectClientLayout()` periodically |
| High Latency | Unacked events blocking | Monitor `_unackedEvents` size |
| Modifier Stuck | Modifier KeyUp lost | Add fallback modifier release on timeout |

---

## 📈 Monitoring Commands

```dart
// Check active keys
print(_stateManager.getSummary());
// Output: "2 active key(s): 28, 42"

// Check repeating keys
print(_repeatController.getSummary());
// Output: "Repeating: 1 keys, Delaying: 0 keys"

// Get transport stats
print(_transport.getStats());
// Output: "KeyboardTransport(sent=1234, acked=1230, pending=2, loss=0.3%, state=connected)"

// Check layout compatibility
print(_translator.areLayoutsCompatible());
// Output: true (or false if AZERTY ↔ QWERTY)
```

---

## 🔌 Integration Checklist

- [ ] Create modules in `initState()`
- [ ] Call `detectClientLayout()` at startup
- [ ] Replace `KeyboardListener.onKeyEvent` with new abstraction
- [ ] Update `_applyRemoteKeyboardEvent()` to use injection engine
- [ ] Add `_onSessionDisconnected()` cleanup
- [ ] Add `_onSessionConnected()` setup
- [ ] Add periodic `_syncKeyboardLayout()`
- [ ] Monitor stuck keys periodically
- [ ] Export stats for diagnostics UI
- [ ] Test with AZERTY, QWERTY, QWERTZ keyboards

---

## 🧪 Test Cases

```dart
// Test 1: Key repeat is managed
// Send KeyDown, verify repeat events at 42ms intervals, send KeyUp

// Test 2: Layout detection works
// Expect detectClientLayout() returns non-"unknown"

// Test 3: Layout compatibility
// QWERTY ↔ AZERTY should report false (incompatible)

// Test 4: No stuck keys
// Send KeyDown + KeyUp, verify state returns to IDLE

// Test 5: Disconnect cleanup
// Send KeyDown, disconnect, verify forceReleaseAll() removes all entries

// Test 6: Character translation
// AZERTY 'A' → translate to QWERTY equivalent

// Test 7: Special keys (arrows, backspace, etc.)
// Verify injection via VK codes, not text

// Test 8: Modifiers
// Shift+A should send as modifier + letter, not as "A"
```

---

## 🎓 Learning Path

1. **Start here:** `keyboard_protocol.dart` - Understand data structures
2. **Input side:** `keyboard_input_abstraction.dart` - How to capture
3. **State:** `keyboard_state_manager.dart` - Lifecycle management
4. **Repeat:** `keyboard_repeat_controller.dart` - Managed repeat
5. **Output:** `keyboard_host_injection_engine.dart` - Injection strategies
6. **Transport:** `keyboard_transport.dart` - Network resilience
7. **Layout:** `keyboard_layout_translator.dart` - Advanced layout handling

---

## 📞 Debugging

Enable these callbacks for verbose output:

```dart
onKeyStateChanged: (key) {
  print('[KB-State] ${key.physicalCode}: ${key.state}');
},
onStuckKeyForceReleased: (code, reason) {
  print('[KB-Stuck] Released 0x$code: $reason');
},
onInjectionOccurred: (code, strategy) {
  print('[KB-Inject] Via $strategy');
},
onInjectionFailed: (code, reason) {
  print('[KB-Error] Injection failed: $reason');
},
```

---

**Version: 2.0**  
**Last Updated: 2025-04-04**
