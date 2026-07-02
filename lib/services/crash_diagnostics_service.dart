import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

class CrashDiagnosticsService {
  CrashDiagnosticsService._();

  static final instance = CrashDiagnosticsService._();

  static const _maxLineLength = 2000;
  static const _maxBufferedLines = 240;
  static const _maxLogBytes = 512 * 1024;

  final ListQueue<String> _buffer = ListQueue<String>();
  final List<String> _pendingLines = <String>[];

  File? _logFile;
  File? _sessionFile;
  Timer? _flushTimer;
  bool _initialized = false;
  bool _flushing = false;
  String? _lastLogKey;
  int _lastLogRepeatCount = 0;

  bool previousSessionCrashed = false;
  String? logPath;

  Future<void> init() async {
    if (_initialized) return;

    final supportDir = await getApplicationSupportDirectory();
    final diagnosticsDir = Directory('${supportDir.path}/diagnostics');
    await diagnosticsDir.create(recursive: true);

    _logFile = File('${diagnosticsDir.path}/latest.log');
    _sessionFile = File('${diagnosticsDir.path}/last_session.json');
    logPath = _logFile!.path;
    previousSessionCrashed = await _wasPreviousSessionCrashed();
    _initialized = true;

    await _sessionFile!.writeAsString(
      jsonEncode({
        'startedAt': DateTime.now().toIso8601String(),
        'cleanExit': false,
      }),
      flush: true,
    );

    record(
      'diagnostics',
      'session-start previousSessionCrashed=$previousSessionCrashed log=$logPath',
      includeMemory: true,
      flush: true,
    );
  }

  void recordLog(String level, String tag, Object? message) {
    if (!_initialized) return;
    final text = _truncate(message);
    final key = '$level/$tag/$text';
    if (key == _lastLogKey) {
      _lastLogRepeatCount++;
      if (_lastLogRepeatCount % 25 != 0) return;
      record('$level/$tag', '$text (repeated $_lastLogRepeatCount times)');
      return;
    }

    _lastLogKey = key;
    _lastLogRepeatCount = 1;
    record('$level/$tag', text);
  }

  void record(
    String tag,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    bool includeMemory = false,
    bool flush = false,
  }) {
    if (!_initialized) return;

    final timestamp = DateTime.now().toIso8601String();
    final memory = includeMemory ? ' ${memorySnapshot()}' : '';
    final line =
        '$timestamp [$tag] ${_truncate(message)}$memory'
        '${error == null ? '' : ' error=${_truncate(error)}'}';
    _appendLine(line);

    if (stackTrace != null) {
      final stackLines = stackTrace.toString().split('\n').take(12);
      for (final stackLine in stackLines) {
        _appendLine('$timestamp [$tag.stack] ${_truncate(stackLine)}');
      }
    }

    if (flush) {
      unawaited(flushNow());
    } else {
      _scheduleFlush();
    }
  }

  void recordFlutterError(FlutterErrorDetails details) {
    record(
      'flutter-error',
      details.context?.toDescription() ?? 'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
      includeMemory: true,
      flush: true,
    );
  }

  void recordPlatformError(Object error, StackTrace stackTrace) {
    record(
      'platform-error',
      'Uncaught platform dispatcher error',
      error: error,
      stackTrace: stackTrace,
      includeMemory: true,
      flush: true,
    );
  }

  void recordZoneError(Object error, StackTrace stackTrace) {
    record(
      'zone-error',
      'Uncaught zone error',
      error: error,
      stackTrace: stackTrace,
      includeMemory: true,
      flush: true,
    );
  }

  Future<void> markCleanShutdown() async {
    record('diagnostics', 'session-clean-shutdown', flush: true);
    final sessionFile = _sessionFile;
    if (sessionFile != null) {
      await sessionFile.writeAsString(
        jsonEncode({
          'endedAt': DateTime.now().toIso8601String(),
          'cleanExit': true,
        }),
        flush: true,
      );
    }
    await flushNow();
  }

  Future<void> flushNow() async {
    if (!_initialized) return;
    if (_flushing) {
      _scheduleFlush();
      return;
    }
    final logFile = _logFile;
    if (logFile == null || _pendingLines.isEmpty) return;

    _flushTimer?.cancel();
    _flushTimer = null;
    _flushing = true;
    try {
      final pending = _pendingLines.join();
      _pendingLines.clear();
      await logFile.writeAsString(pending, mode: FileMode.append, flush: true);
      await _trimLogFile(logFile);
    } catch (_) {
      _pendingLines.clear();
    } finally {
      _flushing = false;
    }
  }

  String memorySnapshot() {
    final rssMb = (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1);
    final cache = PaintingBinding.instance.imageCache;
    final imageCacheMb = (cache.currentSizeBytes / (1024 * 1024))
        .toStringAsFixed(1);
    return 'rss=${rssMb}MB imageCache=${imageCacheMb}MB'
        ' images=${cache.currentSize}'
        ' live=${cache.liveImageCount}'
        ' pending=${cache.pendingImageCount}';
  }

  Future<bool> _wasPreviousSessionCrashed() async {
    final sessionFile = _sessionFile;
    if (sessionFile == null || !await sessionFile.exists()) return false;
    try {
      final data =
          jsonDecode(await sessionFile.readAsString()) as Map<String, dynamic>;
      return data['cleanExit'] != true;
    } catch (_) {
      return false;
    }
  }

  void _appendLine(String line) {
    final cappedLine = '${_truncate(line)}\n';
    _buffer.add(cappedLine);
    _pendingLines.add(cappedLine);
    while (_buffer.length > _maxBufferedLines) {
      _buffer.removeFirst();
    }
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 2), () {
      _flushTimer = null;
      unawaited(flushNow());
    });
  }

  Future<void> _trimLogFile(File logFile) async {
    if (!await logFile.exists()) return;
    final length = await logFile.length();
    if (length <= _maxLogBytes) return;

    final lines = await logFile.readAsLines();
    final retained = lines.length <= _maxBufferedLines
        ? lines
        : lines.sublist(lines.length - _maxBufferedLines);
    await logFile.writeAsString('${retained.join('\n')}\n', flush: true);
  }

  String _truncate(Object? value) {
    final text = value?.toString() ?? '';
    if (text.length <= _maxLineLength) return text;
    return '${text.substring(0, _maxLineLength)}...<truncated ${text.length - _maxLineLength} chars>';
  }
}
