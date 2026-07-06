import 'dart:io';

import 'package:flutter/services.dart';

import 'app_contracts.dart';
import 'constant.dart';

class DefaultAppPlatformService implements AppPlatformContract {
  const DefaultAppPlatformService();

  static AppPlatformInfo fallbackInfo() {
    final version = BuildInfo.version.isEmpty ? '5.9.2' : BuildInfo.version;
    final parts = version.split('+');
    return AppPlatformInfo(
      appName: 'Harmony Music',
      packageName: Platform.isAndroid
          ? 'com.anandnet.harmonymusic'
          : Platform.operatingSystem,
      version: parts.first,
      buildNumber: parts.length > 1 ? parts.last : '1',
    );
  }

  static const _channel = MethodChannel('harmonymusic/app_platform');

  @override
  Future<AppPlatformInfo> getAppInfo() async {
    if (!Platform.isAndroid) {
      return fallbackInfo();
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getAppInfo',
      );
      if (result == null) return fallbackInfo();
      final fallback = fallbackInfo();
      return AppPlatformInfo(
        appName: result['appName']?.toString() ?? fallback.appName,
        packageName: result['packageName']?.toString() ?? fallback.packageName,
        version: result['version']?.toString() ?? fallback.version,
        buildNumber: result['buildNumber']?.toString() ?? fallback.buildNumber,
      );
    } catch (_) {
      return fallbackInfo();
    }
  }

  @override
  Future<void> setKeepScreenAwake(bool enable) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setKeepScreenAwake', enable);
    } catch (_) {
      // Best effort only; playback should never fail because this call failed.
    }
  }

  @override
  Future<void> setPlaybackWakeLock(bool enable) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setPlaybackWakeLock', enable);
    } catch (_) {
      // Best effort only; playback should never fail because this call failed.
    }
  }

  @override
  Future<void> shareText(String text) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('shareText', text);
        return;
      } catch (_) {
        // Fall through to the clipboard fallback.
      }
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Future<void> openUrl(String url) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('openUrl', url);
        return;
      } catch (_) {
        // Fall through to platform-specific desktop handling.
      }
    }

    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url], runInShell: false);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
    }
  }

  @override
  Future<void> installApk(String path) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('APK installation is only supported on Android');
    }
    await _channel.invokeMethod<void>('installApk', path);
  }

  @override
  Future<void> restartApp({bool terminate = true}) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('restartApp', terminate);
        return;
      } catch (_) {
        // Fall through to the process exit fallback.
      }
    }
    exit(0);
  }
}

class AppPlatformService {
  AppPlatformService._();

  static AppPlatformContract? override;

  static AppPlatformContract get _service =>
      override ?? const DefaultAppPlatformService();

  static Future<AppPlatformInfo> getAppInfo() => _service.getAppInfo();

  static Future<void> setKeepScreenAwake(bool enable) =>
      _service.setKeepScreenAwake(enable);

  static Future<void> setPlaybackWakeLock(bool enable) =>
      _service.setPlaybackWakeLock(enable);

  static Future<void> shareText(String text) => _service.shareText(text);

  static Future<void> openUrl(String url) => _service.openUrl(url);

  static Future<void> installApk(String path) => _service.installApk(path);

  static Future<void> restartApp({bool terminate = true}) =>
      _service.restartApp(terminate: terminate);
}
