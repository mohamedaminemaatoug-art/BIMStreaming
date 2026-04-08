/// Keyboard Protocol: Data structures and constants for TeamsViewer-grade keyboard handling.
///
/// This module defines the shared protocol layer for keyboard events, layout detection,
/// and synchronization across client and host machines.

/// Represents a physical or logical keyboard key.
///
/// This abstraction ensures layout-independent, scan-code based key identification.
class KeyboardKeyEvent {
  /// USB HID scan code (layout-independent physical identifier).
  final int physicalCode;

  /// Flutter logical key ID.
  final int logicalKeyId;

  /// Unicode code point of the character (0 if non-printable).
  final int characterCodePoint;

  /// Key name (e.g., "Key A", "Enter", "Shift Left").
  final String keyName;

  /// Normalized key label for display.
  final String keyLabel;

  /// Key event phase: 'down', 'up'.
  final String phase;

  /// Modifier state.
  final ModifierState modifiers;

  /// Whether this key is on the numpad.
  final bool isNumpad;

  /// Whether this key is a modifier key (Shift, Ctrl, Alt, Meta).
  final bool isModifier;

  /// Keyboard layout on client at time of capture.
  final String clientLayout;

  /// Keyboard layout family on client (QWERTY, AZERTY, QWERTZ, etc.).
  final String clientLayoutFamily;

  /// Timestamp when event was captured (milliseconds since epoch).
  final int captureTimestampMs;

  /// Unique sequence number for this event.
  final int sequenceNumber;

  KeyboardKeyEvent({
    required this.physicalCode,
    required this.logicalKeyId,
    required this.characterCodePoint,
    required this.keyName,
    required this.keyLabel,
    required this.phase,
    required this.modifiers,
    required this.isNumpad,
    required this.isModifier,
    required this.clientLayout,
    required this.clientLayoutFamily,
    required this.captureTimestampMs,
    required this.sequenceNumber,
  });

  /// Convert to JSON for network transport.
  Map<String, dynamic> toJson() => {
    'physicalCode': physicalCode,
    'logicalKeyId': logicalKeyId,
    'characterCodePoint': characterCodePoint,
    'keyName': keyName,
    'keyLabel': keyLabel,
    'phase': phase,
    'modifiers': modifiers.toJson(),
    'isNumpad': isNumpad,
    'isModifier': isModifier,
    'clientLayout': clientLayout,
    'clientLayoutFamily': clientLayoutFamily,
    'captureTimestampMs': captureTimestampMs,
    'sequenceNumber': sequenceNumber,
  };

  /// Create from JSON.
  factory KeyboardKeyEvent.fromJson(Map<String, dynamic> json) => KeyboardKeyEvent(
    physicalCode: (json['physicalCode'] as num?)?.toInt() ?? 0,
    logicalKeyId: (json['logicalKeyId'] as num?)?.toInt() ?? 0,
    characterCodePoint: (json['characterCodePoint'] as num?)?.toInt() ?? 0,
    keyName: (json['keyName'] as String?) ?? 'unknown',
    keyLabel: (json['keyLabel'] as String?) ?? '',
    phase: (json['phase'] as String?) ?? 'down',
    modifiers: ModifierState.fromJson(json['modifiers'] as Map<String, dynamic>? ?? {}),
    isNumpad: (json['isNumpad'] as bool?) ?? false,
    isModifier: (json['isModifier'] as bool?) ?? false,
    clientLayout: (json['clientLayout'] as String?) ?? 'unknown',
    clientLayoutFamily: (json['clientLayoutFamily'] as String?) ?? 'unknown',
    captureTimestampMs: (json['captureTimestampMs'] as num?)?.toInt() ?? 0,
    sequenceNumber: (json['sequenceNumber'] as num?)?.toInt() ?? 0,
  );

  @override
  String toString() =>
      'KeyboardKeyEvent(phase=$phase, keyName=$keyName, modifiers=$modifiers, isNumpad=$isNumpad)';
}

/// Modifier key state.
class ModifierState {
  final bool shift;
  final bool control;
  final bool alt;
  final bool meta;
  final bool altGraph;

  ModifierState({
    this.shift = false,
    this.control = false,
    this.alt = false,
    this.meta = false,
    this.altGraph = false,
  });

  /// Check if any modifier is pressed.
  bool get isPressed => shift || control || alt || meta || altGraph;

  /// Clone with overrides.
  ModifierState copyWith({
    bool? shift,
    bool? control,
    bool? alt,
    bool? meta,
    bool? altGraph,
  }) =>
      ModifierState(
        shift: shift ?? this.shift,
        control: control ?? this.control,
        alt: alt ?? this.alt,
        meta: meta ?? this.meta,
        altGraph: altGraph ?? this.altGraph,
      );

  Map<String, dynamic> toJson() => {
    'shift': shift,
    'control': control,
    'alt': alt,
    'meta': meta,
    'altGraph': altGraph,
  };

  factory ModifierState.fromJson(Map<String, dynamic> json) => ModifierState(
    shift: (json['shift'] as bool?) ?? false,
    control: (json['control'] as bool?) ?? false,
    alt: (json['alt'] as bool?) ?? false,
    meta: (json['meta'] as bool?) ?? false,
    altGraph: (json['altGraph'] as bool?) ?? false,
  );

  @override
  String toString() {
    final parts = <String>[];
    if (shift) parts.add('Shift');
    if (control) parts.add('Ctrl');
    if (alt) parts.add('Alt');
    if (meta) parts.add('Meta');
    if (altGraph) parts.add('AltGr');
    return parts.isNotEmpty ? parts.join('+') : 'none';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModifierState &&
        shift == other.shift &&
        control == other.control &&
        alt == other.alt &&
        meta == other.meta &&
        altGraph == other.altGraph;
  }

  @override
  int get hashCode =>
      shift.hashCode ^
      control.hashCode ^
      alt.hashCode ^
      meta.hashCode ^
      altGraph.hashCode;
}

/// Keyboard layout descriptor.
class KeyboardLayout {
  /// Layout identifier (e.g., '00000409' for US English).
  final String layoutId;

  /// Layout family (QWERTY, AZERTY, QWERTZ, Dvorak, etc.).
  final String family;

  /// Human-readable display name.
  final String displayName;

  /// Language code (e.g., 'en', 'fr', 'de').
  final String language;

  /// Country/region code (e.g., 'US', 'FR', 'DE').
  final String region;

  KeyboardLayout({
    required this.layoutId,
    required this.family,
    required this.displayName,
    required this.language,
    required this.region,
  });

  @override
  String toString() => '$displayName ($family)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeyboardLayout && layoutId == other.layoutId;
  }

  @override
  int get hashCode => layoutId.hashCode;
}

/// Key state in the active registry.
enum KeyState {
  /// Key is not currently pressed.
  idle,

  /// Key was just pressed (initial KeyDown).
  down,

  /// Key is held (during repeat phase).
  hold,

  /// Key was released.
  up;
}

/// Tracks active key state for lifecycle management.
class ActiveKey {
  /// Physical code of the key.
  final int physicalCode;

  /// Current state of the key.
  KeyState state;

  /// When the key was first pressed (milliseconds since epoch).
  final int pressedAtMs;

  /// When the key was last repeated (for repeat tracking).
  int lastRepeatAtMs;

  /// Payload of the original KeyDown event (for repeat injection).
  Map<String, dynamic> originalEventPayload;

  ActiveKey({
    required this.physicalCode,
    required this.state,
    required this.pressedAtMs,
    required this.lastRepeatAtMs,
    required this.originalEventPayload,
  });

  /// Duration the key has been held (milliseconds).
  int get holdDurationMs => DateTime.now().millisecondsSinceEpoch - pressedAtMs;

  @override
  String toString() => 'ActiveKey(code=$physicalCode, state=$state, held=${holdDurationMs}ms)';
}

/// Protocol version constants.
const int keyboardProtocolVersion = 2;

/// Control magic values.
const int keyRepeatInitialDelayMs = 320;
const int keyRepeatIntervalMs = 42;
const int keyStateSyncIntervalMs = 2000;
const int inputTimeoutMs = 30000;

/// Maximum pending events before dropping oldest.
const int maxPendingKeyboardEvents = 128;

/// Special key name patterns.
const Set<String> specialKeyPatterns = {
  'enter',
  'tab',
  'escape',
  'backspace',
  'delete',
  'home',
  'end',
  'page up',
  'page down',
  'arrow left',
  'arrow right',
  'arrow up',
  'arrow down',
  'insert',
  'f1',
  'f2',
  'f3',
  'f4',
  'f5',
  'f6',
  'f7',
  'f8',
  'f9',
  'f10',
  'f11',
  'f12',
};

/// Known keyboard layout families.
const Map<String, String> layoutFamilyMap = {
  '00000409': 'QWERTY', // US English
  '0000040c': 'AZERTY', // French
  '00000407': 'QWERTZ', // German
  '0000040a': 'QWERTY', // Spanish
  '0000080c': 'AZERTY', // Belgian French
  '00000813': 'QWERTY', // Belgian Dutch
  '00000c0c': 'QWERTY', // Canadian French
  '00000410': 'QWERTY', // Italian
  '00000413': 'QWERTY', // Dutch
  '00000414': 'QWERTY', // Norwegian
  '00000415': 'QWERTY', // Polish
  '00000816': 'QWERTY', // Portuguese (Brazilian)
  '00000419': 'ЙЦУКЕН', // Russian
  '0000041a': 'QWERTY', // Serbian
  '0000041b': 'QWERTY', // Slovak
  '0000041c': 'QWERTY', // Albanian
  '00000c1c': 'QWERTY', // Serbian (Cyrillic)
};
