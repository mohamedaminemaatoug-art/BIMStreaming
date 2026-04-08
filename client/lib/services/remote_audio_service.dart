import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

typedef RemoteAudioSender = bool Function(Map<String, dynamic> payload);

typedef PingProvider = int Function();

class RemoteAudioService {
  RemoteAudioService({
    required this.isHost,
    required this.sendPayload,
    required this.pingProvider,
    this.jitterBufferMs = 80,
  });

  final bool isHost;
  final RemoteAudioSender sendPayload;
  final PingProvider pingProvider;
  final int jitterBufferMs;

  io.Process? _captureProcess;
  io.Process? _playbackProcess;
  StreamSubscription<List<int>>? _captureStdoutSub;
  StreamSubscription<List<int>>? _captureStderrSub;
  StreamSubscription<List<int>>? _playbackStderrSub;

  bool _hostRunning = false;
  bool _clientRunning = false;
  bool _disposed = false;

  int _sequence = 0;
  int _targetBitrateKbps = 96;
  DateTime _lastCaptureRestartAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<int, _AudioPacket> _packetBuffer = <int, _AudioPacket>{};
  int _expectedSequence = 1;
  DateTime? _missingSince;
  Timer? _flushTimer;
  Timer? _feedbackTimer;
  DateTime? _firstBufferedAt;
  int _receivedPackets = 0;
  int _skippedPackets = 0;
  int _lastReportedReceived = 0;
  int _lastReportedSkipped = 0;

  double _volume = 1.0;

  Future<void> startHost({
    required int bitrateKbps,
  }) async {
    if (_disposed) return;
    _targetBitrateKbps = bitrateKbps.clamp(64, 256);
    _hostRunning = true;
    await _startCaptureProcess();
    sendPayload({
      'kind': 'control',
      'action': 'start',
      'codec': 'opus',
      'frameMs': 20,
      'bitrateKbps': _targetBitrateKbps,
      'transport': 'tcp-websocket',
    });
  }

  Future<void> stopHost() async {
    _hostRunning = false;
    sendPayload({'kind': 'control', 'action': 'stop'});
    await _stopCaptureProcess();
  }

  Future<void> updateHostBitrate(int bitrateKbps) async {
    final next = bitrateKbps.clamp(64, 256);
    if (_targetBitrateKbps == next) return;
    _targetBitrateKbps = next;
    if (_hostRunning) {
      final now = DateTime.now();
      if (now.difference(_lastCaptureRestartAt).inMilliseconds > 2500) {
        await _restartCaptureProcess();
      }
    }
  }

  Future<void> startClient({
    required double volume,
  }) async {
    if (_disposed) return;
    _volume = volume.clamp(0.0, 1.0);
    _clientRunning = true;
    await _startPlaybackProcess();
    _startFlushTimer();
    _startFeedbackTimer();
  }

  Future<void> stopClient() async {
    _clientRunning = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _packetBuffer.clear();
    _firstBufferedAt = null;
    await _stopPlaybackProcess();
  }

  Future<void> setClientVolume(double volume) async {
    final next = volume.clamp(0.0, 1.0);
    if ((next - _volume).abs() < 0.01) return;
    _volume = next;
    if (_clientRunning) {
      // ffplay does not support runtime volume changes on stdin input,
      // so restart with updated volume.
      await _startPlaybackProcess();
    }
  }

  Future<void> handleIncoming(Map<String, dynamic> payload) async {
    if (_disposed) return;
    final kind = (payload['kind'] ?? '').toString();
    if (kind.isEmpty) return;

    if (isHost) {
      if (kind == 'feedback') {
        await _applyFeedback(payload);
        return;
      }
      if (kind == 'config') {
        final bitrate = payload['bitrateKbps'];
        if (bitrate is num) {
          await updateHostBitrate(bitrate.toInt());
        }
      }
      return;
    }

    if (!_clientRunning) return;

    if (kind == 'packet') {
      final seqRaw = payload['seq'];
      final tsRaw = payload['ts'];
      final dataB64 = (payload['data'] ?? '').toString();
      if (seqRaw is! num || tsRaw is! num || dataB64.isEmpty) return;
      Uint8List data;
      try {
        data = base64Decode(dataB64);
      } catch (_) {
        return;
      }
      final seq = seqRaw.toInt();
      if (seq < _expectedSequence) return;
      _packetBuffer[seq] = _AudioPacket(seq: seq, tsMs: tsRaw.toInt(), bytes: data);
      _receivedPackets++;
      _firstBufferedAt ??= DateTime.now();
      return;
    }

    if (kind == 'control') {
      final action = (payload['action'] ?? '').toString();
      if (action == 'stop') {
        _packetBuffer.clear();
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopHost();
    await stopClient();
  }

  Future<void> _startCaptureProcess() async {
    await _stopCaptureProcess();
    _lastCaptureRestartAt = DateTime.now();

    final args = _buildCaptureArgs(_targetBitrateKbps);
    io.Process process;
    try {
      process = await io.Process.start(args.$1, args.$2);
    } catch (_) {
      return;
    }

    _captureProcess = process;
    _captureStdoutSub = process.stdout.listen((chunk) {
      if (!_hostRunning || chunk.isEmpty) return;
      _sequence++;
      sendPayload({
        'kind': 'packet',
        'seq': _sequence,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'codec': 'opus',
        'frameMs': 20,
        'data': base64Encode(chunk),
      });
    });

    _captureStderrSub = process.stderr.listen((_) {
      // Keep stderr drained.
    });

    unawaited(process.exitCode.then((_) async {
      if (!_hostRunning || _disposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (_hostRunning && !_disposed) {
        await _startCaptureProcess();
      }
    }));
  }

  Future<void> _restartCaptureProcess() async {
    await _stopCaptureProcess();
    if (_hostRunning && !_disposed) {
      await _startCaptureProcess();
    }
  }

  Future<void> _stopCaptureProcess() async {
    await _captureStdoutSub?.cancel();
    await _captureStderrSub?.cancel();
    _captureStdoutSub = null;
    _captureStderrSub = null;
    _captureProcess?.kill(io.ProcessSignal.sigterm);
    _captureProcess = null;
  }

  (String, List<String>) _buildCaptureArgs(int bitrateKbps) {
    if (io.Platform.isWindows) {
      // WASAPI loopback capture of default output device.
      return (
        'ffmpeg',
        <String>[
          '-hide_banner',
          '-loglevel',
          'warning',
          '-f',
          'wasapi',
          '-i',
          'default',
          '-ac',
          '2',
          '-ar',
          '48000',
          '-c:a',
          'libopus',
          '-b:a',
          '${bitrateKbps}k',
          '-vbr',
          'constrained',
          '-application',
          'lowdelay',
          '-frame_duration',
          '20',
          '-f',
          'ogg',
          'pipe:1',
        ],
      );
    }

    // Linux PulseAudio/PipeWire monitor source.
    return (
      'ffmpeg',
      <String>[
        '-hide_banner',
        '-loglevel',
        'warning',
        '-f',
        'pulse',
        '-i',
        'default',
        '-ac',
        '2',
        '-ar',
        '48000',
        '-c:a',
        'libopus',
        '-b:a',
        '${bitrateKbps}k',
        '-vbr',
        'constrained',
        '-application',
        'lowdelay',
        '-frame_duration',
        '20',
        '-f',
        'ogg',
        'pipe:1',
      ],
    );
  }

  Future<void> _startPlaybackProcess() async {
    await _stopPlaybackProcess();

    final vol = (_volume * 100).round().clamp(0, 100);
    io.Process process;
    try {
      process = await io.Process.start(
        'ffplay',
        <String>[
          '-hide_banner',
          '-loglevel',
          'warning',
          '-nodisp',
          '-fflags',
          'nobuffer',
          '-flags',
          'low_delay',
          '-probesize',
          '32',
          '-analyzeduration',
          '0',
          '-sync',
          'ext',
          '-volume',
          '$vol',
          '-i',
          'pipe:0',
        ],
      );
    } catch (_) {
      return;
    }

    _playbackProcess = process;
    _playbackStderrSub = process.stderr.listen((_) {
      // Keep stderr drained.
    });

    unawaited(process.exitCode.then((_) async {
      if (!_clientRunning || _disposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (_clientRunning && !_disposed) {
        await _startPlaybackProcess();
      }
    }));
  }

  Future<void> _stopPlaybackProcess() async {
    await _playbackStderrSub?.cancel();
    _playbackStderrSub = null;
    _playbackProcess?.kill(io.ProcessSignal.sigterm);
    _playbackProcess = null;
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      _flushPlaybackQueue();
    });
  }

  void _flushPlaybackQueue() {
    final process = _playbackProcess;
    if (process == null) return;
    if (_packetBuffer.isEmpty) return;

    final now = DateTime.now();
    if (_firstBufferedAt != null && now.difference(_firstBufferedAt!).inMilliseconds < jitterBufferMs) {
      return;
    }

    while (true) {
      final pkt = _packetBuffer.remove(_expectedSequence);
      if (pkt != null) {
        process.stdin.add(pkt.bytes);
        _expectedSequence++;
        _missingSince = null;
        continue;
      }

      final keys = _packetBuffer.keys.toList()..sort();
      if (keys.isEmpty) break;
      final minSeq = keys.first;
      if (minSeq <= _expectedSequence) {
        _expectedSequence = minSeq;
        continue;
      }

      _missingSince ??= now;
      if (now.difference(_missingSince!).inMilliseconds >= 60) {
        _skippedPackets += max(1, minSeq - _expectedSequence);
        _expectedSequence = minSeq;
        _missingSince = null;
        continue;
      }
      break;
    }
  }

  void _startFeedbackTimer() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final recvDelta = _receivedPackets - _lastReportedReceived;
      final skipDelta = _skippedPackets - _lastReportedSkipped;
      _lastReportedReceived = _receivedPackets;
      _lastReportedSkipped = _skippedPackets;
      final total = recvDelta + skipDelta;
      final lossRate = total <= 0 ? 0.0 : (skipDelta / total).clamp(0.0, 1.0);
      sendPayload({
        'kind': 'feedback',
        'lossRate': lossRate,
        'pingMs': pingProvider(),
      });
    });
  }

  Future<void> _applyFeedback(Map<String, dynamic> payload) async {
    final loss = payload['lossRate'] is num ? (payload['lossRate'] as num).toDouble() : 0.0;
    final ping = payload['pingMs'] is num ? (payload['pingMs'] as num).toInt() : 999;

    var next = _targetBitrateKbps;
    if (loss > 0.08 || ping > 220) {
      next -= 24;
    } else if (loss > 0.03 || ping > 150) {
      next -= 12;
    } else if (loss < 0.01 && ping < 80) {
      next += 12;
    }
    next = next.clamp(64, 256);
    if (next != _targetBitrateKbps) {
      await updateHostBitrate(next);
    }
  }
}

class _AudioPacket {
  const _AudioPacket({
    required this.seq,
    required this.tsMs,
    required this.bytes,
  });

  final int seq;
  final int tsMs;
  final Uint8List bytes;
}
