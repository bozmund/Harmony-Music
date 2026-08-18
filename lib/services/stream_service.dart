import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';


class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  StreamProvider({
    required this.playable,
    this.audioFormats,
    this.statusMSG = "",
  });

  /// Fetches the stream manifest. No JS solver is involved: the VISIONOS
  /// client returns URLs that need no signature deciphering, which is what
  /// lets this run in a background isolate.
  static Future<StreamProvider> fetch(String videoId) async {
    final yt = YoutubeExplode();

    try {
      // VISIONOS first, and in practice only. Every other client's URLs are
      // now proof-of-origin gated: they extract fine, then 403 the moment a
      // player asks for the whole file. androidSdkless stays as a fallback so
      // a VISIONOS breakage degrades to the old behaviour rather than to
      // nothing, and because the manifest dedupes by itag with the first
      // client winning, its streams never displace working ones.
      final res = await yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.visionos, YoutubeApiClient.androidSdkless],
      );
      final audio = res.audioOnly;
      if (audio.isEmpty) {
        // `playable: true` with no formats is a trap rather than a success:
        // `hmStreamingData` then serialises a null `lowQualityAudio`, and
        // `HMStreamingData.fromJson` dereferences it. Inside the resolver race
        // that surfaces as an opaque failure; in `existingOnly` mode it throws
        // straight out of `checkNGetUrl`.
        return StreamProvider(playable: false, statusMSG: "networkError");
      }
      return StreamProvider(
        playable: true,
        statusMSG: "OK",
        audioFormats: audio
            .map(
              (e) => Audio(
                itag: e.tag,
                audioCodec: e.audioCodec.contains('mp')
                    ? Codec.mp4a
                    : Codec.opus,
                bitrate: e.bitrate.bitsPerSecond,
                duration: e.duration ?? 0,
                loudnessDb: e.loudnessDb,
                url: e.url.toString(),
                size: e.size.totalBytes,
              ),
            )
            .toList(),
      );
    } catch (e) {
      if (e is SocketException) {
        return StreamProvider(playable: false, statusMSG: "networkError");
      } else if (e is VideoUnplayableException) {
        // 3.x folded the separate `reason` into the exception message.
        return StreamProvider(
          playable: false,
          statusMSG: e.message.isEmpty ? "Song is unplayable" : e.message,
        );
      } else if (e is VideoRequiresPurchaseException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song requires purchase",
        );
      } else if (e is VideoUnavailableException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song is unavailable",
        );
      } else if (e is YoutubeExplodeException) {
        return StreamProvider(playable: false, statusMSG: e.message);
      } else {
        return StreamProvider(
          playable: false,
          statusMSG: "Unknown error occurred",
        );
      }
    } finally {
      // Also disposes the JS runtime the solver holds. Previously nothing
      // closed this client; with a solver attached, leaking it leaks a native
      // QuickJS/JavaScriptCore context per resolved song.
      yt.close();
    }
  }

  /// Picks the first itag in [preference] that the manifest actually offers.
  ///
  /// These selectors used to be `lastWhere((i) => i.itag == a || i.itag == b)`,
  /// which chose by position in the manifest rather than by preference. That
  /// happened to yield mp4a while youtube_explode 2.3.7 listed formats
  /// mp4a-last; 3.1.0 lists them opus-last, so the same expression silently
  /// started returning opus for every song. Preference order makes the choice
  /// say what it means and stops a library-side reordering from changing which
  /// codec the app plays.
  Audio? _preferred(List<int> preference) {
    final formats = audioFormats;
    if (formats == null || formats.isEmpty) return null;
    for (final itag in preference) {
      for (final format in formats) {
        if (format.itag == itag) return format;
      }
    }
    return formats.first;
  }

  Audio? get highestQualityAudio => _preferred(const [140, 251]);

  Audio? get highestBitrateMp4aAudio => _preferred(const [140, 139]);

  Audio? get highestBitrateOpusAudio => _preferred(const [251, 250]);

  Audio? get lowQualityAudio => _preferred(const [139, 249]);

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable,
      "statusMSG": statusMSG,
      "lowQualityAudio": lowQualityAudio?.toJson(),
      "highQualityAudio": highestQualityAudio?.toJson(),
    };
  }
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;
  Audio({
    required this.itag,
    required this.audioCodec,
    required this.bitrate,
    required this.duration,
    required this.loudnessDb,
    required this.url,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
    "itag": itag,
    "audioCodec": audioCodec.toString(),
    "bitrate": bitrate,
    "loudnessDb": loudnessDb,
    "url": url,
    "approxDurationMs": duration,
    "size": size,
  };

  factory Audio.fromJson(json) => Audio(
    audioCodec: (json["audioCodec"] as String).contains("mp4a")
        ? Codec.mp4a
        : Codec.opus,
    itag: json['itag'],
    duration: json["approxDurationMs"] ?? 0,
    bitrate: json["bitrate"] ?? 0,
    loudnessDb: json['loudnessDb']?.toDouble() ?? 0.0,
    url: json['url'],
    size: json["size"] ?? 0,
  );
}

enum Codec { mp4a, opus }
