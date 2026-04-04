/// Keyboard Network Transport & Resilience Layer.
///
/// Handles packet loss resilience, key state synchronization, and recovery on disconnection.

import 'dart:async';
import 'keyboard_protocol.dart';

/// Manages robust transport of keyboard events with resilience features.
class KeyboardTransportLayer {
  /// Pending events waiting to be sent.
  final List<KeyboardKeyEvent> _pendingEvents = <KeyboardKeyEvent>[];

  /// Events awaiting acknowledgment (for loss detection).
  final Map<int, KeyboardKeyEvent> _unackedEvents = <int, KeyboardKeyEvent>{};

  /// Current session state.
  KeyboardSessionState _sessionState = KeyboardSessionState.idle;

  /// Callback to send event to remote.
  final bool Function(KeyboardKeyEvent event)? onSendEvent;

  /// Callback when ack is received.
  final void Function(int sequenceNumber)? onAckReceived;

  /// Callback when packet loss detected.
  final void Function(int lostSequence)? onPacketLost;

  /// Callback to request key state sync.
  final void Function()? onRequestStateSync;

  /// Timer for periodic state sync.
  Timer? _stateSyncTimer;

  /// Stats: events sent.
  int _eventsSent = 0;

  /// Stats: events acked.
  int _eventsAcked = 0;

  /// Stats: detected losses.
  int _detectedLosses = 0;

  KeyboardTransportLayer({
    this.onSendEvent,
    this.onAckReceived,
    this.onPacketLost,
    this.onRequestStateSync,
  });

  /// Get current session state.
  KeyboardSessionState get sessionState => _sessionState;

  /// Enqueue an event for sending.
  void enqueueEvent(KeyboardKeyEvent event) {
    if (_pendingEvents.length >= maxPendingKeyboardEvents) {
      // Drop oldest if buffer full.
      _pendingEvents.removeAt(0);
    }
    _pendingEvents.add(event);
    _dispatchNextEvent();
  }

  /// Attempt to send the next pending event.
  void _dispatchNextEvent() {
    if (_pendingEvents.isEmpty) return;
    if (_sessionState != KeyboardSessionState.connected) return;

    final event = _pendingEvents.removeAt(0);
    if (onSendEvent?.call(event) ?? false) {
      _eventsSent++;

      // Track for ack timeout.
      _unackedEvents[event.sequenceNumber] = event;
    } else {
      // Re-add to pending if send failed.
      _pendingEvents.insert(0, event);
    }
  }

  /// Mark connection as established.
  void onConnected() {
    _sessionState = KeyboardSessionState.connected;
    _pendingEvents.clear(); // Clear any pending from disconnected state.
    _startPeriodicStateSync();
    // Dispatch immediately if any pending events.
    _dispatchNextEvent();
  }

  /// Mark connection as lost.
  void onDisconnected() {
    _sessionState = KeyboardSessionState.disconnected;
    _stopPeriodicStateSync();
    // Keep pending events for re-send on reconnect.
  }

  /// Handle acknowledgment from remote.
  void handleAckReceived(int sequenceNumber) {
    _unackedEvents.remove(sequenceNumber);
    _eventsAcked++;
    onAckReceived?.call(sequenceNumber);
    _dispatchNextEvent(); // Send next pending.
  }

  /// Handle packet loss detection (remote reports gap).
  void handlePacketLoss(int lostSequence) {
    _detectedLosses++;
    onPacketLost?.call(lostSequence);
    _unackedEvents.remove(lostSequence); // No point re-sending ancient event.
    // Request state sync to recover.
    _requestStateSync();
  }

  /// Request full key state synchronization from remote.
  void _requestStateSync() {
    onRequestStateSync?.call();
  }

  /// Start periodic state sync timer.
  void _startPeriodicStateSync() {
    _stopPeriodicStateSync();
    _stateSyncTimer = Timer.periodic(
      Duration(milliseconds: keyStateSyncIntervalMs),
      (_) {
        if (_sessionState == KeyboardSessionState.connected) {
          _requestStateSync();
        }
      },
    );
  }

  /// Stop periodic state sync timer.
  void _stopPeriodicStateSync() {
    _stateSyncTimer?.cancel();
    _stateSyncTimer = null;
  }

  /// Get transport statistics.
  KeyboardTransportStats getStats() {
    final lossPercent = _eventsSent > 0
        ? ((_eventsSent - _eventsAcked) / _eventsSent * 100)
        : 0.0;

    return KeyboardTransportStats(
      eventsSent: _eventsSent,
      eventsAcked: _eventsAcked,
      pendingEvents: _pendingEvents.length,
      unackedEvents: _unackedEvents.length,
      detectedLosses: _detectedLosses,
      estimatedLossPercent: lossPercent,
      sessionState: _sessionState,
    );
  }

  /// Reset stats (for new session).
  void resetStats() {
    _eventsSent = 0;
    _eventsAcked = 0;
    _detectedLosses = 0;
    _pendingEvents.clear();
    _unackedEvents.clear();
  }

  /// Dispose resources.
  void dispose() {
    _stopPeriodicStateSync();
  }
}

/// Keyboard session state.
enum KeyboardSessionState {
  idle,
  connecting,
  connected,
  disconnected,
  paused,
  error,
}

/// Transport layer statistics.
class KeyboardTransportStats {
  final int eventsSent;
  final int eventsAcked;
  final int pendingEvents;
  final int unackedEvents;
  final int detectedLosses;
  final double estimatedLossPercent;
  final KeyboardSessionState sessionState;

  KeyboardTransportStats({
    required this.eventsSent,
    required this.eventsAcked,
    required this.pendingEvents,
    required this.unackedEvents,
    required this.detectedLosses,
    required this.estimatedLossPercent,
    required this.sessionState,
  });

  @override
  String toString() {
    return 'KeyboardTransport(sent=$eventsSent, acked=$eventsAcked, '
        'pending=$pendingEvents, loss=${estimatedLossPercent.toStringAsFixed(1)}%, '
        'state=$sessionState)';
  }
}
