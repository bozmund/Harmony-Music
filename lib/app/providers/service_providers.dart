import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_contracts.dart';
import '../../services/app_platform_service.dart';
import '../../services/downloader.dart';
import '../../services/file_picker_service.dart';
import '../../services/music_service.dart';
import '../../services/piped_service.dart';
import '../../services/playback_command_service.dart';
import '../../utils/helper.dart';
import 'repository_providers.dart';

final audioHandlerProvider = Provider<AudioHandler>(
  (ref) => throw StateError(
    'audioHandlerProvider must be overridden at app startup.',
  ),
);

final pipedServicesProvider = Provider<PipedServices>(
  (ref) => PipedServices(ref.watch(settingsRepositoryProvider)),
);

final musicServicesProvider = Provider<MusicServices>((ref) {
  final service = MusicServices(ref.watch(settingsRepositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});

final musicServiceContractProvider = Provider<MusicServiceContract>(
  (ref) => ref.watch(musicServicesProvider),
);

final appPlatformContractProvider = Provider<AppPlatformContract>(
  (ref) => const DefaultAppPlatformService(),
);

final updateServiceContractProvider = Provider<UpdateServiceContract>(
  (ref) => const GithubUpdateService(),
);

final filePickerContractProvider = Provider<FilePickerContract>(
  (ref) => const DefaultFilePickerService(),
);

final downloaderProvider = Provider<Downloader>(
  (ref) => Downloader(
    ref.watch(downloadRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

final playbackCommandServiceProvider = Provider<PlaybackCommandService>(
  (ref) => PlaybackCommandService(
    audioHandler: ref.read(audioHandlerProvider),
    settingsRepository: ref.read(settingsRepositoryProvider),
  ),
);
