import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

const String fileTransferInit = 'FILE_TRANSFER_INIT';
const String fileTransferInitAck = 'FILE_TRANSFER_INIT_ACK';
const String fileTransferChunk = 'FILE_TRANSFER_CHUNK';
const String fileTransferChunkAck = 'FILE_TRANSFER_CHUNK_ACK';
const String fileTransferComplete = 'FILE_TRANSFER_COMPLETE';
const String fileTransferCompleteAck = 'FILE_TRANSFER_COMPLETE_ACK';
const String fileTransferError = 'FILE_TRANSFER_ERROR';
const String fileTransferCancel = 'FILE_TRANSFER_CANCEL';
const String fileTransferBrowseRequest = 'FILE_TRANSFER_BROWSE_REQUEST';
const String fileTransferBrowseResponse = 'FILE_TRANSFER_BROWSE_RESPONSE';

class FileTransferBrowserEntry {
  final String name;
  final String relativePath;
  final bool isDirectory;
  final int size;
  final int modifiedAtMs;

  const FileTransferBrowserEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    required this.size,
    required this.modifiedAtMs,
  });

  factory FileTransferBrowserEntry.fromMap(Map<String, dynamic> map) {
    return FileTransferBrowserEntry(
      name: (map['name'] ?? '').toString(),
      relativePath: (map['relativePath'] ?? '').toString(),
      isDirectory: map['isDirectory'] == true,
      size: map['size'] is num ? (map['size'] as num).toInt() : 0,
      modifiedAtMs: map['modifiedAtMs'] is num ? (map['modifiedAtMs'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'relativePath': relativePath,
      'isDirectory': isDirectory,
      'size': size,
      'modifiedAtMs': modifiedAtMs,
    };
  }
}

class FileTransferQueueItem {
  final String id;
  final String name;
  final String direction;
  final String status;
  final int bytesTotal;
  final int bytesDone;
  final double speedBytesPerSecond;
  final String sourceRelativePath;
  final String destinationRelativePath;
  final String? error;
  final bool canCancel;

  const FileTransferQueueItem({
    required this.id,
    required this.name,
    required this.direction,
    required this.status,
    required this.bytesTotal,
    required this.bytesDone,
    required this.speedBytesPerSecond,
    required this.sourceRelativePath,
    required this.destinationRelativePath,
    this.error,
    required this.canCancel,
  });

  double get progress {
    if (bytesTotal <= 0) {
      return 0;
    }
    return (bytesDone / bytesTotal).clamp(0, 1);
  }

  FileTransferQueueItem copyWith({
    String? status,
    int? bytesDone,
    double? speedBytesPerSecond,
    String? error,
    bool? canCancel,
  }) {
    return FileTransferQueueItem(
      id: id,
      name: name,
      direction: direction,
      status: status ?? this.status,
      bytesTotal: bytesTotal,
      bytesDone: bytesDone ?? this.bytesDone,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      sourceRelativePath: sourceRelativePath,
      destinationRelativePath: destinationRelativePath,
      error: error ?? this.error,
      canCancel: canCancel ?? this.canCancel,
    );
  }
}

class IncomingTransferRequest {
  final String transferId;
  final String direction;
  final String fileName;
  final int fileSize;
  final String sourceRelativePath;
  final String destinationRelativePath;

  const IncomingTransferRequest({
    required this.transferId,
    required this.direction,
    required this.fileName,
    required this.fileSize,
    required this.sourceRelativePath,
    required this.destinationRelativePath,
  });
}

typedef TransferSignalSender = bool Function(String messageType, Map<String, dynamic> payload);
typedef TransferRequestDecision = Future<bool> Function(IncomingTransferRequest request);

class FileTransferService {
  FileTransferService({
    required bool isHost,
    required TransferSignalSender sendSignal,
    required String baseDirectory,
    int maxFileSizeBytes = 1024 * 1024 * 1024,
    int chunkSizeBytes = 256 * 1024,
  })  : _isHost = isHost,
        _sendSignal = sendSignal,
        _baseDirectory = p.normalize(baseDirectory),
        _maxFileSizeBytes = maxFileSizeBytes,
        _chunkSizeBytes = chunkSizeBytes.clamp(64 * 1024, 1024 * 1024);

  final bool _isHost;
  final TransferSignalSender _sendSignal;
  final String _baseDirectory;
  final int _maxFileSizeBytes;
  final int _chunkSizeBytes;

  final ValueNotifier<List<FileTransferBrowserEntry>> localEntries = ValueNotifier<List<FileTransferBrowserEntry>>(<FileTransferBrowserEntry>[]);
  final ValueNotifier<List<FileTransferBrowserEntry>> remoteEntries = ValueNotifier<List<FileTransferBrowserEntry>>(<FileTransferBrowserEntry>[]);
  final ValueNotifier<List<FileTransferQueueItem>> queue = ValueNotifier<List<FileTransferQueueItem>>(<FileTransferQueueItem>[]);
  final ValueNotifier<String> localPath = ValueNotifier<String>('');
  final ValueNotifier<String> remotePath = ValueNotifier<String>('');

  final Map<String, _OutgoingTransferState> _outgoing = <String, _OutgoingTransferState>{};
  final Map<String, _IncomingTransferState> _incoming = <String, _IncomingTransferState>{};

  String get baseDirectory => _baseDirectory;

  Future<void> initialize() async {
    final baseDir = io.Directory(_baseDirectory);
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }
    await refreshLocal(path: '');
  }

  void dispose() {
    for (final state in _outgoing.values) {
      state.close();
    }
    for (final state in _incoming.values) {
      state.close();
    }
    _outgoing.clear();
    _incoming.clear();
    localEntries.dispose();
    remoteEntries.dispose();
    queue.dispose();
    localPath.dispose();
    remotePath.dispose();
  }

  Future<void> refreshLocal({required String path}) async {
    final safePath = _normalizeRelativePath(path);
    final target = _resolveWithinBase(safePath, mustExist: true, expectDirectory: true);
    if (target == null) {
      return;
    }
    localPath.value = safePath;
    localEntries.value = _listDirectory(target);
  }

  void requestRemoteBrowse({required String path}) {
    final safePath = _normalizeRelativePath(path);
    _sendSignal(fileTransferBrowseRequest, {'path': safePath});
  }

  Future<void> sendFilesToRemote({
    required List<String> absolutePaths,
    required String remoteDestinationPath,
  }) async {
    for (final absolutePath in absolutePaths) {
      final file = io.File(absolutePath);
      if (!file.existsSync()) {
        continue;
      }
      final stat = file.statSync();
      if (stat.size <= 0 || stat.size > _maxFileSizeBytes) {
        _pushQueue(
          FileTransferQueueItem(
            id: _newTransferId(),
            name: p.basename(absolutePath),
            direction: _isHost ? 'host->controller' : 'controller->host',
            status: 'failed',
            bytesTotal: stat.size,
            bytesDone: 0,
            speedBytesPerSecond: 0,
            sourceRelativePath: absolutePath,
            destinationRelativePath: remoteDestinationPath,
            error: stat.size > _maxFileSizeBytes ? 'File exceeds configured size limit' : 'Empty file',
            canCancel: false,
          ),
        );
        continue;
      }

      final transferId = _newTransferId();
      final digest = await sha256.bind(file.openRead()).first;
      final totalChunks = (stat.size / _chunkSizeBytes).ceil();
      final queueItem = FileTransferQueueItem(
        id: transferId,
        name: p.basename(absolutePath),
        direction: _isHost ? 'host->controller' : 'controller->host',
        status: 'pending',
        bytesTotal: stat.size,
        bytesDone: 0,
        speedBytesPerSecond: 0,
        sourceRelativePath: absolutePath,
        destinationRelativePath: _normalizeRelativePath(remoteDestinationPath),
        canCancel: true,
      );
      _pushQueue(queueItem);

      final raf = await file.open(mode: io.FileMode.read);
      _outgoing[transferId] = _OutgoingTransferState(
        transferId: transferId,
        sourceFilePath: absolutePath,
        direction: queueItem.direction,
        destinationRelativePath: queueItem.destinationRelativePath,
        totalBytes: stat.size,
        totalChunks: totalChunks,
        chunkSize: _chunkSizeBytes,
        sha256Hex: digest.toString(),
        fileName: p.basename(absolutePath),
        raf: raf,
      );

      _sendSignal(fileTransferInit, {
        'transferId': transferId,
        'direction': queueItem.direction,
        'fileName': p.basename(absolutePath),
        'fileSize': stat.size,
        'chunkSize': _chunkSizeBytes,
        'totalChunks': totalChunks,
        'sha256': digest.toString(),
        'sourcePath': p.basename(absolutePath),
        'destinationPath': queueItem.destinationRelativePath,
      });
    }
  }

  void requestReceiveFromRemote({
    required List<String> remoteFilePaths,
    required String localDestinationPath,
  }) {
    for (final remoteFilePath in remoteFilePaths) {
      final transferId = _newTransferId();
      final normalizedRemotePath = _normalizeRelativePath(remoteFilePath);
      final normalizedLocalDest = _normalizeRelativePath(localDestinationPath);
      final fileName = p.basename(normalizedRemotePath);
      final direction = _isHost ? 'controller->host' : 'host->controller';
      _pushQueue(
        FileTransferQueueItem(
          id: transferId,
          name: fileName,
          direction: direction,
          status: 'pending',
          bytesTotal: 0,
          bytesDone: 0,
          speedBytesPerSecond: 0,
          sourceRelativePath: normalizedRemotePath,
          destinationRelativePath: normalizedLocalDest,
          canCancel: true,
        ),
      );

      _sendSignal(fileTransferInit, {
        'transferId': transferId,
        'direction': direction,
        'sourcePath': normalizedRemotePath,
        'destinationPath': normalizedLocalDest,
        'requestType': 'pull',
      });
    }
  }

  Future<void> handleSignal({
    required String messageType,
    required Map<String, dynamic> payload,
    required TransferRequestDecision onIncomingRequest,
  }) async {
    switch (messageType) {
      case fileTransferBrowseRequest:
        _handleBrowseRequest(payload);
        break;
      case fileTransferBrowseResponse:
        _handleBrowseResponse(payload);
        break;
      case fileTransferInit:
        await _handleInit(payload, onIncomingRequest: onIncomingRequest);
        break;
      case fileTransferInitAck:
        await _handleInitAck(payload);
        break;
      case fileTransferChunk:
        await _handleChunk(payload);
        break;
      case fileTransferChunkAck:
        await _handleChunkAck(payload);
        break;
      case fileTransferComplete:
        await _handleComplete(payload);
        break;
      case fileTransferCompleteAck:
        _handleCompleteAck(payload);
        break;
      case fileTransferError:
        _handleError(payload);
        break;
      case fileTransferCancel:
        _handleCancel(payload);
        break;
    }
  }

  void cancelTransfer(String transferId) {
    final outgoing = _outgoing.remove(transferId);
    outgoing?.close();
    final incoming = _incoming.remove(transferId);
    incoming?.close(deleteTemp: true);
    _updateQueue(transferId, (item) => item.copyWith(status: 'canceled', canCancel: false));
    _sendSignal(fileTransferCancel, {'transferId': transferId});
  }

  Future<void> _handleInit(
    Map<String, dynamic> payload, {
    required TransferRequestDecision onIncomingRequest,
  }) async {
    final transferId = (payload['transferId'] ?? '').toString();
    final direction = (payload['direction'] ?? '').toString();
    final requestType = (payload['requestType'] ?? '').toString();
    if (transferId.isEmpty || direction.isEmpty) {
      return;
    }

    final thisSideReceives = (_isHost && direction == 'controller->host') || (!_isHost && direction == 'host->controller');
    final thisSideSends = (_isHost && direction == 'host->controller') || (!_isHost && direction == 'controller->host');

    if (requestType == 'pull' && thisSideSends) {
      final sourceRel = _normalizeRelativePath((payload['sourcePath'] ?? '').toString());
      final sourceAbs = _resolveWithinBase(sourceRel, mustExist: true, expectDirectory: false);
      if (sourceAbs == null) {
        _sendSignal(fileTransferInitAck, {
          'transferId': transferId,
          'accepted': false,
          'error': 'Invalid source path',
        });
        return;
      }
      final file = io.File(sourceAbs);
      final stat = file.statSync();
      if (stat.size <= 0 || stat.size > _maxFileSizeBytes) {
        _sendSignal(fileTransferInitAck, {
          'transferId': transferId,
          'accepted': false,
          'error': 'Source file violates size policy',
        });
        return;
      }

      final digest = await sha256.bind(file.openRead()).first;
      final totalChunks = (stat.size / _chunkSizeBytes).ceil();
      final raf = await file.open(mode: io.FileMode.read);
      _outgoing[transferId] = _OutgoingTransferState(
        transferId: transferId,
        sourceFilePath: sourceAbs,
        direction: direction,
        destinationRelativePath: _normalizeRelativePath((payload['destinationPath'] ?? '').toString()),
        totalBytes: stat.size,
        totalChunks: totalChunks,
        chunkSize: _chunkSizeBytes,
        sha256Hex: digest.toString(),
        fileName: p.basename(sourceAbs),
        raf: raf,
      );

      _pushQueue(
        FileTransferQueueItem(
          id: transferId,
          name: p.basename(sourceAbs),
          direction: direction,
          status: 'pending',
          bytesTotal: stat.size,
          bytesDone: 0,
          speedBytesPerSecond: 0,
          sourceRelativePath: sourceRel,
          destinationRelativePath: _normalizeRelativePath((payload['destinationPath'] ?? '').toString()),
          canCancel: true,
        ),
      );

      _sendSignal(fileTransferInitAck, {
        'transferId': transferId,
        'accepted': true,
        'fileName': p.basename(sourceAbs),
        'fileSize': stat.size,
        'chunkSize': _chunkSizeBytes,
        'totalChunks': totalChunks,
        'sha256': digest.toString(),
      });
      return;
    }

    if (!thisSideReceives) {
      return;
    }

    final fileName = (payload['fileName'] ?? p.basename((payload['sourcePath'] ?? '').toString())).toString();
    final fileSize = payload['fileSize'] is num ? (payload['fileSize'] as num).toInt() : 0;
    final totalChunks = payload['totalChunks'] is num ? (payload['totalChunks'] as num).toInt() : 0;
    final chunkSize = payload['chunkSize'] is num ? (payload['chunkSize'] as num).toInt() : _chunkSizeBytes;
    final sourceRel = _normalizeRelativePath((payload['sourcePath'] ?? fileName).toString());
    final destinationRel = _normalizeRelativePath((payload['destinationPath'] ?? '').toString());

    if (fileSize <= 0 || fileSize > _maxFileSizeBytes || totalChunks <= 0) {
      _sendSignal(fileTransferInitAck, {
        'transferId': transferId,
        'accepted': false,
        'error': 'Incoming file violates policy',
      });
      return;
    }

    final approved = await onIncomingRequest(
      IncomingTransferRequest(
        transferId: transferId,
        direction: direction,
        fileName: fileName,
        fileSize: fileSize,
        sourceRelativePath: sourceRel,
        destinationRelativePath: destinationRel,
      ),
    );

    if (!approved) {
      _sendSignal(fileTransferInitAck, {
        'transferId': transferId,
        'accepted': false,
        'error': 'Rejected by receiver',
      });
      return;
    }

    final destDirAbs = _resolveWithinBase(destinationRel, mustExist: true, expectDirectory: true);
    if (destDirAbs == null) {
      _sendSignal(fileTransferInitAck, {
        'transferId': transferId,
        'accepted': false,
        'error': 'Invalid destination path',
      });
      return;
    }

    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final finalFileAbs = _resolveUniqueDestination(destDirAbs, safeName);
    final tempAbs = '$finalFileAbs.part';

    final tempFile = io.File(tempAbs);
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }
    final raf = await tempFile.open(mode: io.FileMode.write);

    _incoming[transferId] = _IncomingTransferState(
      transferId: transferId,
      direction: direction,
      fileName: safeName,
      expectedBytes: fileSize,
      totalChunks: totalChunks,
      chunkSize: chunkSize,
      expectedSha256Hex: (payload['sha256'] ?? '').toString(),
      destinationRelativePath: destinationRel,
      finalFilePath: finalFileAbs,
      tempFilePath: tempAbs,
      raf: raf,
    );

    _pushQueue(
      FileTransferQueueItem(
        id: transferId,
        name: safeName,
        direction: direction,
        status: 'in-progress',
        bytesTotal: fileSize,
        bytesDone: 0,
        speedBytesPerSecond: 0,
        sourceRelativePath: sourceRel,
        destinationRelativePath: destinationRel,
        canCancel: true,
      ),
    );

    _sendSignal(fileTransferInitAck, {
      'transferId': transferId,
      'accepted': true,
      'destinationPath': destinationRel,
    });
  }

  Future<void> _handleInitAck(Map<String, dynamic> payload) async {
    final transferId = (payload['transferId'] ?? '').toString();
    if (transferId.isEmpty) {
      return;
    }
    final accepted = payload['accepted'] == true;
    final outgoing = _outgoing[transferId];
    if (outgoing == null) {
      return;
    }
    if (!accepted) {
      outgoing.close();
      _outgoing.remove(transferId);
      _updateQueue(transferId, (item) => item.copyWith(status: 'failed', error: (payload['error'] ?? 'Rejected').toString(), canCancel: false));
      return;
    }

    final remoteFileSize = payload['fileSize'] is num ? (payload['fileSize'] as num).toInt() : 0;
    if (remoteFileSize > 0) {
      _updateQueue(transferId, (item) => FileTransferQueueItem(
            id: item.id,
            name: (payload['fileName'] ?? item.name).toString(),
            direction: item.direction,
            status: 'in-progress',
            bytesTotal: remoteFileSize,
            bytesDone: item.bytesDone,
            speedBytesPerSecond: item.speedBytesPerSecond,
            sourceRelativePath: item.sourceRelativePath,
            destinationRelativePath: item.destinationRelativePath,
            error: item.error,
            canCancel: true,
          ));
      outgoing.totalBytes = remoteFileSize;
      outgoing.totalChunks = (payload['totalChunks'] is num ? (payload['totalChunks'] as num).toInt() : outgoing.totalChunks);
      outgoing.sha256Hex = (payload['sha256'] ?? outgoing.sha256Hex).toString();
    }
    await _sendNextChunk(outgoing);
  }

  Future<void> _sendNextChunk(_OutgoingTransferState state) async {
    if (state.nextChunkIndex >= state.totalChunks) {
      _sendSignal(fileTransferComplete, {
        'transferId': state.transferId,
        'bytesTotal': state.totalBytes,
        'sha256': state.sha256Hex,
      });
      return;
    }

    final offset = state.nextChunkIndex * state.chunkSize;
    await state.raf.setPosition(offset);
    final bytes = await state.raf.read(state.chunkSize);
    if (bytes.isEmpty) {
      _sendSignal(fileTransferError, {
        'transferId': state.transferId,
        'error': 'Unable to read next chunk',
      });
      _updateQueue(state.transferId, (item) => item.copyWith(status: 'failed', error: 'Read error', canCancel: false));
      return;
    }

    state.lastChunkSentAtMs = DateTime.now().millisecondsSinceEpoch;
    _sendSignal(fileTransferChunk, {
      'transferId': state.transferId,
      'chunkIndex': state.nextChunkIndex,
      'chunkData': base64Encode(bytes),
      'chunkSize': bytes.length,
      'bytesTotal': state.totalBytes,
    });
  }

  Future<void> _handleChunkAck(Map<String, dynamic> payload) async {
    final transferId = (payload['transferId'] ?? '').toString();
    final chunkIndex = payload['chunkIndex'] is num ? (payload['chunkIndex'] as num).toInt() : -1;
    final outgoing = _outgoing[transferId];
    if (outgoing == null || chunkIndex < 0 || chunkIndex != outgoing.nextChunkIndex) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dtMs = max(1, nowMs - outgoing.lastChunkSentAtMs);
    final bytesDone = min(outgoing.totalBytes, (chunkIndex + 1) * outgoing.chunkSize);
    final speed = (min(outgoing.chunkSize, outgoing.totalBytes - (chunkIndex * outgoing.chunkSize)) * 1000) / dtMs;

    outgoing.nextChunkIndex += 1;
    _updateQueue(
      transferId,
      (item) => item.copyWith(
        status: 'in-progress',
        bytesDone: bytesDone,
        speedBytesPerSecond: speed,
        canCancel: true,
      ),
    );

    await _sendNextChunk(outgoing);
  }

  Future<void> _handleChunk(Map<String, dynamic> payload) async {
    final transferId = (payload['transferId'] ?? '').toString();
    final incoming = _incoming[transferId];
    if (incoming == null) {
      return;
    }

    final chunkIndex = payload['chunkIndex'] is num ? (payload['chunkIndex'] as num).toInt() : -1;
    final chunkData = (payload['chunkData'] ?? '').toString();
    if (chunkIndex != incoming.nextChunkIndex || chunkData.isEmpty) {
      _sendSignal(fileTransferError, {
        'transferId': transferId,
        'error': 'Chunk sequence mismatch',
      });
      _updateQueue(transferId, (item) => item.copyWith(status: 'failed', error: 'Chunk mismatch', canCancel: false));
      return;
    }

    final bytes = base64Decode(chunkData);
    await incoming.raf.writeFrom(bytes);
    incoming.bytesReceived += bytes.length;
    incoming.nextChunkIndex += 1;

    _updateQueue(
      transferId,
      (item) => item.copyWith(
        status: 'in-progress',
        bytesDone: incoming.bytesReceived,
        speedBytesPerSecond: 0,
        canCancel: true,
      ),
    );

    _sendSignal(fileTransferChunkAck, {
      'transferId': transferId,
      'chunkIndex': chunkIndex,
      'bytesReceived': incoming.bytesReceived,
    });
  }

  Future<void> _handleComplete(Map<String, dynamic> payload) async {
    final transferId = (payload['transferId'] ?? '').toString();
    final incoming = _incoming.remove(transferId);
    if (incoming == null) {
      return;
    }

    await incoming.raf.flush();
    await incoming.raf.close();

    final tempFile = io.File(incoming.tempFilePath);
    if (!tempFile.existsSync()) {
      _sendSignal(fileTransferCompleteAck, {
        'transferId': transferId,
        'success': false,
        'error': 'Temporary file missing',
      });
      _updateQueue(transferId, (item) => item.copyWith(status: 'failed', error: 'Temp file missing', canCancel: false));
      return;
    }

    final actualDigest = await sha256.bind(tempFile.openRead()).first;
    final expectedDigest = (payload['sha256'] ?? incoming.expectedSha256Hex).toString();
    if (expectedDigest.isNotEmpty && actualDigest.toString() != expectedDigest) {
      tempFile.deleteSync();
      _sendSignal(fileTransferCompleteAck, {
        'transferId': transferId,
        'success': false,
        'error': 'SHA-256 mismatch',
      });
      _updateQueue(transferId, (item) => item.copyWith(status: 'failed', error: 'SHA-256 mismatch', canCancel: false));
      return;
    }

    final finalFile = io.File(incoming.finalFilePath);
    if (finalFile.existsSync()) {
      finalFile.deleteSync();
    }
    tempFile.renameSync(incoming.finalFilePath);

    _sendSignal(fileTransferCompleteAck, {
      'transferId': transferId,
      'success': true,
      'sha256': actualDigest.toString(),
    });

    _updateQueue(
      transferId,
      (item) => item.copyWith(
        status: 'completed',
        bytesDone: item.bytesTotal > 0 ? item.bytesTotal : incoming.bytesReceived,
        canCancel: false,
      ),
    );

    await refreshLocal(path: localPath.value);
  }

  void _handleCompleteAck(Map<String, dynamic> payload) {
    final transferId = (payload['transferId'] ?? '').toString();
    final outgoing = _outgoing.remove(transferId);
    outgoing?.close();

    final success = payload['success'] == true;
    _updateQueue(
      transferId,
      (item) => item.copyWith(
        status: success ? 'completed' : 'failed',
        bytesDone: success ? item.bytesTotal : item.bytesDone,
        error: success ? null : (payload['error'] ?? 'Remote failed').toString(),
        canCancel: false,
      ),
    );
  }

  void _handleError(Map<String, dynamic> payload) {
    final transferId = (payload['transferId'] ?? '').toString();
    final error = (payload['error'] ?? 'Transfer error').toString();

    final outgoing = _outgoing.remove(transferId);
    outgoing?.close();

    final incoming = _incoming.remove(transferId);
    incoming?.close(deleteTemp: true);

    _updateQueue(transferId, (item) => item.copyWith(status: 'failed', error: error, canCancel: false));
  }

  void _handleCancel(Map<String, dynamic> payload) {
    final transferId = (payload['transferId'] ?? '').toString();
    final outgoing = _outgoing.remove(transferId);
    outgoing?.close();

    final incoming = _incoming.remove(transferId);
    incoming?.close(deleteTemp: true);

    _updateQueue(transferId, (item) => item.copyWith(status: 'canceled', canCancel: false));
  }

  void _handleBrowseRequest(Map<String, dynamic> payload) {
    final path = _normalizeRelativePath((payload['path'] ?? '').toString());
    final target = _resolveWithinBase(path, mustExist: true, expectDirectory: true);
    if (target == null) {
      _sendSignal(fileTransferBrowseResponse, {
        'path': '',
        'entries': <Map<String, dynamic>>[],
        'error': 'Invalid path',
      });
      return;
    }

    final entries = _listDirectory(target);
    _sendSignal(fileTransferBrowseResponse, {
      'path': path,
      'entries': entries.map((entry) => entry.toMap()).toList(growable: false),
    });
  }

  void _handleBrowseResponse(Map<String, dynamic> payload) {
    remotePath.value = _normalizeRelativePath((payload['path'] ?? '').toString());
    final rawEntries = payload['entries'];
    if (rawEntries is! List) {
      remoteEntries.value = <FileTransferBrowserEntry>[];
      return;
    }

    final parsed = <FileTransferBrowserEntry>[];
    for (final raw in rawEntries) {
      if (raw is Map) {
        parsed.add(FileTransferBrowserEntry.fromMap(Map<String, dynamic>.from(raw)));
      }
    }
    remoteEntries.value = parsed;
  }

  List<FileTransferBrowserEntry> _listDirectory(String absoluteDirectoryPath) {
    final dir = io.Directory(absoluteDirectoryPath);
    if (!dir.existsSync()) {
      return <FileTransferBrowserEntry>[];
    }

    final entities = dir.listSync(followLinks: false);
    final result = <FileTransferBrowserEntry>[];
    for (final entity in entities) {
      final stat = entity.statSync();
      final rel = _toRelativeWithinBase(entity.path);
      if (rel == null) {
        continue;
      }
      result.add(
        FileTransferBrowserEntry(
          name: p.basename(entity.path),
          relativePath: rel,
          isDirectory: stat.type == io.FileSystemEntityType.directory,
          size: stat.type == io.FileSystemEntityType.file ? stat.size : 0,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
        ),
      );
    }

    result.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  String _newTransferId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(1 << 30);
    return 'ft-$now-$random';
  }

  String _normalizeRelativePath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '.') {
      return '';
    }
    final normalized = p.normalize(trimmed.replaceAll('\\', '/'));
    if (normalized == '.' || normalized == p.separator) {
      return '';
    }
    if (p.isAbsolute(normalized)) {
      final rel = _toRelativeWithinBase(normalized);
      return rel ?? '';
    }
    if (normalized.startsWith('..')) {
      return '';
    }
    return normalized;
  }

  String? _resolveWithinBase(String relativePath, {required bool mustExist, required bool expectDirectory}) {
    final base = p.normalize(_baseDirectory);
    final candidate = p.normalize(p.join(base, relativePath));
    if (!_isWithinBase(candidate)) {
      return null;
    }

    if (!mustExist) {
      return candidate;
    }

    final entity = io.FileSystemEntity.typeSync(candidate, followLinks: false);
    if (expectDirectory && entity != io.FileSystemEntityType.directory) {
      return null;
    }
    if (!expectDirectory && entity != io.FileSystemEntityType.file) {
      return null;
    }
    return candidate;
  }

  bool _isWithinBase(String absolutePath) {
    final base = p.normalize(_baseDirectory).toLowerCase();
    final target = p.normalize(absolutePath).toLowerCase();
    return target == base || target.startsWith('$base${p.separator}');
  }

  String? _toRelativeWithinBase(String absolutePath) {
    final normalized = p.normalize(absolutePath);
    if (!_isWithinBase(normalized)) {
      return null;
    }
    final rel = p.relative(normalized, from: _baseDirectory);
    return rel == '.' ? '' : rel;
  }

  String _resolveUniqueDestination(String dirAbs, String fileName) {
    var finalPath = p.join(dirAbs, fileName);
    if (!io.File(finalPath).existsSync()) {
      return finalPath;
    }

    final stem = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var counter = 1;
    while (true) {
      finalPath = p.join(dirAbs, '$stem($counter)$ext');
      if (!io.File(finalPath).existsSync()) {
        return finalPath;
      }
      counter += 1;
    }
  }

  void _pushQueue(FileTransferQueueItem item) {
    final next = List<FileTransferQueueItem>.from(queue.value);
    final index = next.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      next[index] = item;
    } else {
      next.insert(0, item);
    }
    queue.value = next;
  }

  void _updateQueue(String transferId, FileTransferQueueItem Function(FileTransferQueueItem item) updater) {
    final next = List<FileTransferQueueItem>.from(queue.value);
    final index = next.indexWhere((item) => item.id == transferId);
    if (index < 0) {
      return;
    }
    next[index] = updater(next[index]);
    queue.value = next;
  }
}

class _OutgoingTransferState {
  _OutgoingTransferState({
    required this.transferId,
    required this.sourceFilePath,
    required this.direction,
    required this.destinationRelativePath,
    required this.totalBytes,
    required this.totalChunks,
    required this.chunkSize,
    required this.sha256Hex,
    required this.fileName,
    required this.raf,
  });

  final String transferId;
  final String sourceFilePath;
  final String direction;
  final String destinationRelativePath;
  final String fileName;
  io.RandomAccessFile raf;
  int totalBytes;
  int totalChunks;
  final int chunkSize;
  String sha256Hex;
  int nextChunkIndex = 0;
  int lastChunkSentAtMs = 0;

  void close() {
    unawaited(raf.close());
  }
}

class _IncomingTransferState {
  _IncomingTransferState({
    required this.transferId,
    required this.direction,
    required this.fileName,
    required this.expectedBytes,
    required this.totalChunks,
    required this.chunkSize,
    required this.expectedSha256Hex,
    required this.destinationRelativePath,
    required this.finalFilePath,
    required this.tempFilePath,
    required this.raf,
  });

  final String transferId;
  final String direction;
  final String fileName;
  final int expectedBytes;
  final int totalChunks;
  final int chunkSize;
  final String expectedSha256Hex;
  final String destinationRelativePath;
  final String finalFilePath;
  final String tempFilePath;
  io.RandomAccessFile raf;
  int nextChunkIndex = 0;
  int bytesReceived = 0;

  void close({bool deleteTemp = false}) {
    unawaited(raf.close());
    if (deleteTemp) {
      final file = io.File(tempFilePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }
}
