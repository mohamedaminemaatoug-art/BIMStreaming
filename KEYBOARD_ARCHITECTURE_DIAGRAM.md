# Keyboard System Architecture Visualization

## System Architecture (High Level)

```
┌─────────────────────────────────────────────────────────────────┐
│                        BIM STREAMING APP                        │
│                                                                 │
│  ┌──────────────────┐         ┌──────────────────────────────┐ │
│  │  CLIENT MACHINE  │         │     HOST/CONTROLLER MACHINE  │ │
│  │   (Keyboard      │◄───────►│   (Accepts & Injects         │ │
│  │   Controller)    │ Network │    Remote Keyboard Input)    │ │
│  └──────────────────┘  WS/TCP │                              │ │
│                         ▲     └──────────────────────────────┘ │
│                         │                                       │
│                    Signaling → KeyboardKeyEvent (JSON)         │
│                    with full layout context                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Client-Side Data Flow (Input Capture)

```
┌────────────────────────────────────────────────────────┐
│                   FLUTTER UI LAYER                    │
│         (KeyboardListener.onKeyEvent)                 │
│  Receives:                                             │
│  - KeyDownEvent / KeyUpEvent                          │
│  - Physical key USB HID code                          │
│  - Logical key ID                                     │
│  - Character (if printable)                           │
└──────────────────────┬─────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────┐
│          KeyboardInputAbstraction                      │
│  Task: Normalize Flutter event                        │
│  Output: KeyboardKeyEvent                             │
│  - Physical code (USB HID, layout-independent)        │
│  - Logical key ID                                     │
│  - Character code point                               │
│  - Modifiers (Shift, Ctrl, Alt, Meta, AltGr)         │
│  - Is modifier? Is numpad?                            │
└──────────────────────┬─────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────┐
│          KeyboardStateManager                          │
│  Task: Track key lifecycle                            │
│  Input: PhysicalCode, eventPayload                    │
│  Action: registerKeyDown()                            │
│  - Create ActiveKey(IDLE → DOWN)                      │
│  - Prevent duplicate downs                           │
│  Output: ActiveKey or null                            │
└──────────────────────┬─────────────────────────────────┘
                       │
          ┌────────────┴────────────┐
          │                         │
          ▼                         ▼
    ┌───────────────────┐   ┌───────────────────┐
    │  Is Modifier?     │   │  Is Managed Repeat│
    │  (Shift, Ctrl...)│   │  (Backspace,      │
    └─────────┬─────────┘   │   Arrows, etc.)?  │
              │             └─────────┬─────────┘
              X                       │
               (no repeat)             ▼
                            ┌──────────────────────┐
                            │ KeyboardRepeatCtrlr  │
                            │ startRepeat()        │
                            │ Timers:              │
                            │ - Initial: 320ms     │
                            │ - Repeat: every 42ms │
                            └──────────┬───────────┘
                                       │
                                       ▼
                    ┌──────────────────────────────┐
                    │  KeyboardTransportLayer      │
                    │  enqueueEvent()              │
                    │  onSendEvent() callback      │
                    │  Sends via signaling service │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │  Network (SSH/WS/TCP)       │
                    │  KeyboardKeyEvent { json }   │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                         Remote System Receives
```

## Host-Side Data Flow (Input Injection)

```
┌─────────────────────────────────────────┐
│  Network Receives KeyboardKeyEvent JSON │
│  (from client via signaling service)   │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│      KeyboardKeyEvent.fromJson(payload)             │
│      Deserialize JSON → structured object           │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│     KeyboardLayoutTranslator                        │
│     Task: Translate character if needed             │
│     Input: event.character, source layout           │
│     Output: translatedCharacter                     │
│     - AZERTY "A" → QWERTY "A" (same visual)        │
│     - Uses cached lookup table                      │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│   KeyboardHostInjectionEngine                       │
│   Task: Select injection strategy & inject          │
│   _selectInjectionStrategy():                       │
│                                                     │
│   IF printable && !modifiers:                       │
│      → Unicode injection (preferred)                │
│   ELIF control key (arrows, Enter, etc.):          │
│      → Virtual Key injection                       │
│   ELIF complex combo (Shift+key):                   │
│      → SendKeys injection                          │
│   ELSE IF modifier:                                │
│      → Modifier-only injection                     │
└────────────────┬─────────────────────────────────────┘
                 │
   ┌─────────────┼─────────────┬─────────────────┐
   │             │             │                 │
   ▼             ▼             ▼                 ▼
Unicode         VK         SendKeys         Modifier
  │              │             │              │
  │ wScan=char   │ wVk=key    │ token        │ wVk=shift
  │ dwFlags=0x04 │ dwFlags=VK │ {ENTER}      │ dwFlags=0x0008
  │              │            │ [SendWait]   │
  ▼              ▼            ▼              ▼
┌──────────────────────────────────────────────────────┐
│        PowerShell SendInput API Call                 │
│  C# Interop → NativeInput.SendInput()               │
│  INPUT struct array → user32.dll                     │
└──────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────────────┐
│     Windows System (kernel, message queue)          │
│     Key injection applied to focused window         │
└──────────────────────────────────────────────────────┘
```

## Module Interactions

```
                KeyboardProtocol
                (shared structs)
                       ▲
                       │
        ┌──────────────┼──────────────┬─────────────┐
        │              │              │             │
        ▼              ▼              ▼             ▼
   InputAbstractn  LayoutTranslator  StateManager  RepeatCtrlr
        │              │              │             │
        └──────────────┼──────────────┴─────────────┘
                       │
                       ▼
              TransportLayer
              (queue & send)
                       │
                       ▼
           NetworkSignalingService
              (WS/TCP to remote)
                       │
                       ▼
           Remote Receives & Deserializes
                       │
                       ▼
              InjectionEngine
              (selects strategy)
                       │
                       ▼
            PowerShell → SendInput
```

## State Machine: Per-Key Lifecycle

```
                    ┌─────────┐
                    │  IDLE   │
                    │ (no key)│
                    └────┬────┘
                         │
                 KeyDown Event
                         │
                         ▼
                    ┌─────────┐
                    │  DOWN   │◄────────────────────┐
                    │(initial)│  Repeat occurs      │
                    └────┬────┘  (handled by        │
                         │       RepeatController) │
                         │                         │
                    [after 320ms]                   │
                         │                         │
                         ▼                         │
                    ┌─────────┐                     │
                    │  HOLD   │─────────────────────┘
                    │(repeating)
                    └────┬────┘
                         │
                  KeyUp Event
                         │
                         ▼
                    ┌─────────┐
                    │   UP    │
                    │(released)
                    └────┬────┘
                         │
                    [cleanup]
                         │
                         ▼
                    ┌─────────┐
                    │  IDLE   │
                    │ (no key)│
                    └─────────┘
```

## Active Key Registry (State Manager)

```
PhysicalCode → ActiveKey
────────────────────────────────────────
0x1E          → ActiveKey(code=0x1E, state=DOWN, held=45ms)
0x2C          → ActiveKey(code=0x2C, state=HOLD, held=1200ms)
0x38          → ActiveKey(code=0x38, state=DOWN, held=15ms)

Rules:
- One entry per unique physical code
- state ∈ {IDLE, DOWN, HOLD, UP}
- Prevent duplicate DOWN (returns null)
- Force-release if held > 30 seconds
- Cleanup all on disconnect
```

## Character Translation (Layout Translator)

```
Client (AZERTY)     Host (QWERTY)
───────────────────────────────
Press "A"      →    Result: "A"
Physical key:       Visual: same character
Shift+Q              Inject: VK(0x41)
                     [character is visual source of truth]

Press "1"      →    Result: "1"
Physical key:       Visual: same character
1 (top row)         Inject: VK(0x31)
                     [1 is 1 on all layouts]

Press "+"      →    Result: "+"
Physical key:       Visual: may differ by layout
Shift+= (AZERTY)    Inject: appropriate modifiers + key
                     for QWERTY layout
```

## Injection Strategy Selection

```
event.keyName, modifiers, character
        │
        ├─► Is printable && !modifiers?
        │       YES ──► Unicode Injection (preferred)
        │       NO
        │
        ├─► Is control key (Enter, Backspace, arrows)?
        │       YES ──► Virtual Key Injection
        │       NO
        │
        ├─► Is modifier (Shift, Ctrl, Alt)?
        │       YES ──► Modifier-Only Injection
        │       NO
        │
        └─► Complex combo (text + modifiers)
                YES ──► SendKeys Fallback
                NO  ──► Skip (no match)
```

## Network Resilience (Transport Layer)

```
Stage 1: Local Queue
┌──────────────────────────────────┐
│  _pendingEvents: List[KeyEvent]  │
│  MAX 128 events                  │
│  If full, drop oldest            │
└──────────────────────────────────┘

Stage 2: In-Flight Tracking
┌──────────────────────────────────┐
│  _unackedEvents: Map[seq, event] │
│  Tracks: sent but not ACK'd      │
│  Timeout: 30 seconds             │
└──────────────────────────────────┘

Stage 3: Loss Detection
If seq N missing:
  → Detect gap in remote seq
  → Call onPacketLost(N)
  → Request state sync
  → Recovery: periodic full sync

Stage 4: State Sync Periodic
Every 2 seconds:
  → Send key_state_sync message
  → Remote confirms active keys
  → Recover from undetected loss
```

---

**Architectural Complexity:** 7 modules, 12 data structures, 80+ methods  
**Data Flow Separation:** Client (capture) | Network | Host (inject)  
**State Machine Rigor:** IDLE→DOWN→HOLD→UP with forced reset  
**Resilience Layers:** Queue + Tracking + Loss Detection + Periodic Sync  
**Injection Flexibility:** 4 strategies with automatic selection & fallback
