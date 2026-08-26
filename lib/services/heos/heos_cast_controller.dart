import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/repositories/settings_repository.dart';
import '../../utils/runtime_platform.dart';
import '../constant.dart';
import '../playback_command_service.dart';
import '../../utils/helper.dart';
import 'heos_client.dart';
import 'heos_discovery_service.dart';
import 'heos_local_http_server.dart';
import 'heos_models.dart';

class HeosCastController extends ChangeNotifier {
  HeosCastController({
    required AudioHandler audioHandler,
    required SettingsRepository settingsRepository,
    required PlaybackCommandService playbackCommands,
    HeosDiscoveryService? discoveryService,
    HeosClient? client,
    HeosLocalHttpServer? localHttpServer,
  }) : _audioHandler = audioHandler,
       _settingsRepository = settingsRepository,
       _playbackCommands = playbackCommands,
       _discoveryService = discoveryService ?? HeosDiscoveryService(),
       _client = client ?? HeosClient(),
       _localHttpServer = localHttpServer ?? HeosLocalHttpServer();

  final AudioHandler _audioHandler;
  final SettingsRepository _settingsRepository;
  final PlaybackCommandService _playbackCommands;
  final HeosDiscoveryService _discoveryService;
  final HeosClient _client;
  final HeosLocalHttpServer _localHttpServer;

  HeosCastStatus status = HeosCastStatus.disconnected;
  String? statusMessage;
  List<HeosDevice> devices = const [];
  List<HeosPlayer> players = const [];
  HeosDevice? selectedDevice;
  HeosPlayer? selectedPlayer;
  bool isPlaying = false;

  bool get isAvailable => RuntimePlatform.isAndroid;
  bool get isConnected =>
      selectedDevice != null &&
      selectedPlayer != null &&
      status != HeosCastStatus.disconnected;
  bool get isCasting => status == HeosCastStatus.casting;
  String get selectedSpeakerName =>
      selectedPlayer?.name ?? selectedDevice?.name ?? 'HEOS speaker';

  Future<void> init() async {
    if (!isAvailable) return;
    final ipAddress = _settingsRepository.getHeosBridgeIp();
    if (ipAddress == null || ipAddress.isEmpty) return;
    try {
      await connectToAddress(
        ipAddress,
        preferredPlayerId: _settingsRepository.getHeosPlayerId(),
        preferredPlayerName: _settingsRepository.getHeosPlayerName(),
        silent: true,
      );
    } catch (_) {
      await disconnect(clearSavedSelection: false);
    }
  }

  Future<void> discover() async {
    if (!isAvailable) return;
    await _requestNearbyWifiPermission();
    _setStatus(HeosCastStatus.discovering, null);
    try {
      devices = await _discoveryService.discover();
      _setStatus(
        selectedPlayer == null
            ? HeosCastStatus.disconnected
            : HeosCastStatus.connected,
        devices.isEmpty ? 'No HEOS speakers found' : null,
      );
    } catch (error, stackTrace) {
      printERROR(error, tag: LogTags.heos);
      printERROR(stackTrace, tag: LogTags.heos);
      _setStatus(HeosCastStatus.error, 'HEOS discovery failed');
    }
  }

  Future<void> connectToDevice(HeosDevice device) {
    return connectToAddress(device.ipAddress, device: device);
  }

  Future<void> connectToAddress(
    String ipAddress, {
    HeosDevice? device,
    String? preferredPlayerId,
    String? preferredPlayerName,
    bool silent = false,
  }) async {
    if (!isAvailable) return;
    if (!silent) _setStatus(HeosCastStatus.discovering, null);
    try {
      await _client.connect(ipAddress);
      final discoveredPlayers = await _client.getPlayers();
      if (discoveredPlayers.isEmpty) {
        throw StateError('No HEOS players are available');
      }
      devices = [
        ...devices.where((item) => item.ipAddress != ipAddress),
        device ??
            HeosDevice(
              ipAddress: ipAddress,
              name: preferredPlayerName ?? 'HEOS bridge',
            ),
      ];
      players = discoveredPlayers;
      selectedDevice = device ?? devices.last;
      selectedPlayer = _choosePlayer(
        discoveredPlayers,
        preferredPlayerId: preferredPlayerId,
      );
      await _saveSelection();
      _setStatus(HeosCastStatus.connected, null);
    } catch (error, stackTrace) {
      printERROR(error, tag: LogTags.heos);
      printERROR(stackTrace, tag: LogTags.heos);
      _setStatus(HeosCastStatus.error, 'Unable to connect to HEOS speaker');
      rethrow;
    }
  }

  Future<void> selectPlayer(HeosPlayer player) async {
    selectedPlayer = player;
    await _saveSelection();
    _setStatus(HeosCastStatus.connected, null);
  }

  Future<void> cast(MediaItem song) async {
    if (!isConnected) return;
    final player = selectedPlayer!;
    try {
      final resolved = await _resolveUrl(song);
      if (!resolved.playable || resolved.url == null) {
        throw StateError(resolved.statusMessage ?? 'Unable to resolve stream');
      }
      final url = await _speakerReachableUrl(resolved.url!);
      await _client.playStream(playerId: player.pid, url: url);
      await _client.setPlayState(playerId: player.pid, state: 'play');
      await _playbackCommands.pause();
      isPlaying = true;
      _setStatus(HeosCastStatus.casting, null);
    } catch (error, stackTrace) {
      printERROR(error, tag: LogTags.heos);
      printERROR(stackTrace, tag: LogTags.heos);
      isPlaying = false;
      _setStatus(HeosCastStatus.error, 'HEOS could not play this song');
      rethrow;
    }
  }

  Future<void> play() async {
    final player = selectedPlayer;
    if (player == null) return;
    await _client.setPlayState(playerId: player.pid, state: 'play');
    isPlaying = true;
    _setStatus(HeosCastStatus.casting, null);
  }

  Future<void> pause() async {
    final player = selectedPlayer;
    if (player == null) return;
    await _client.setPlayState(playerId: player.pid, state: 'pause');
    isPlaying = false;
    _setStatus(HeosCastStatus.connected, null);
  }

  Future<void> setVolume(int value) async {
    final player = selectedPlayer;
    if (player == null) return;
    await _client.setVolume(playerId: player.pid, level: value);
  }

  Future<void> stopCasting() async {
    final player = selectedPlayer;
    if (player != null) {
      try {
        await _client.setPlayState(playerId: player.pid, state: 'stop');
      } catch (_) {}
    }
    isPlaying = false;
    await _localHttpServer.stop();
    _setStatus(
      selectedPlayer == null
          ? HeosCastStatus.disconnected
          : HeosCastStatus.connected,
      null,
    );
  }

  Future<void> disconnect({bool clearSavedSelection = true}) async {
    await _localHttpServer.stop();
    await _client.close();
    selectedDevice = null;
    selectedPlayer = null;
    players = const [];
    isPlaying = false;
    if (clearSavedSelection) {
      await _settingsRepository.setHeosSelection(
        bridgeIp: null,
        playerId: null,
        playerName: null,
      );
    }
    _setStatus(HeosCastStatus.disconnected, null);
  }

  Future<_ResolvedHeosUrl> _resolveUrl(MediaItem song) async {
    final response = await _audioHandler.customAction('resolveHeosStreamUrl', {
      'mediaItem': song,
    });
    if (response is! Map) {
      return const _ResolvedHeosUrl(playable: false);
    }
    final data = Map<String, dynamic>.from(response);
    return _ResolvedHeosUrl(
      playable: data['playable'] == true,
      url: data['url']?.toString(),
      statusMessage: data['statusMSG']?.toString(),
    );
  }

  Future<String> _speakerReachableUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await _localHttpServer.stop();
      return url;
    }
    return _localHttpServer.serveFile(url);
  }

  HeosPlayer _choosePlayer(
    List<HeosPlayer> availablePlayers, {
    String? preferredPlayerId,
  }) {
    if (preferredPlayerId != null) {
      for (final player in availablePlayers) {
        if (player.pid == preferredPlayerId) return player;
      }
    }
    return availablePlayers.first;
  }

  Future<void> _saveSelection() async {
    await _settingsRepository.setHeosSelection(
      bridgeIp: selectedDevice?.ipAddress,
      playerId: selectedPlayer?.pid,
      playerName: selectedPlayer?.name,
    );
  }

  Future<void> _requestNearbyWifiPermission() async {
    if (!RuntimePlatform.isAndroid) return;
    final status = await Permission.nearbyWifiDevices.status;
    if (status.isDenied || status.isRestricted) {
      await Permission.nearbyWifiDevices.request();
    }
  }

  void _setStatus(HeosCastStatus nextStatus, String? message) {
    status = nextStatus;
    statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(disconnect(clearSavedSelection: false));
    super.dispose();
  }
}

class _ResolvedHeosUrl {
  const _ResolvedHeosUrl({
    required this.playable,
    this.url,
    this.statusMessage,
  });

  final bool playable;
  final String? url;
  final String? statusMessage;
}
