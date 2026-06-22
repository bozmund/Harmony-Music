import 'package:meta/meta.dart';

import '../reverse_engineering/player/player_source_dart.dart'
    if (dart.library.ui) '../reverse_engineering/player/player_source_flutter.dart';
import '../../youtube_explode_dart.dart';
import '../reverse_engineering/pages/watch_page.dart';
import '../reverse_engineering/player/player_response.dart';

@internal
class VideoController {
  @protected
  final YoutubeHttpClient httpClient;

  VideoController(this.httpClient);

  Future<PlayerResponse> getPlayerResponse(
      VideoId videoId, YoutubeApiClient client,
      {WatchPage? watchPage}) async {
    Map<String, dynamic> payload = client.payload;
    assert(payload['context'] != null, 'client must contain a context');
    assert(payload['context']!['client'] != null,
        'client must contain a context.client');
    String? visitorData;

    try {
      if (payload['context']['client']['clientName'] != 'TVHTML5') {
        visitorData = await getVisitorData();
        if (visitorData != null) {
          final clientData =
              Map<String, dynamic>.from(payload['context']['client']);
          clientData['visitorData'] = visitorData;
          payload = {
            "context": {"client": clientData}
          };
        }
      }
    } catch (e) {}

    final userAgent = payload['context']!['client']!['userAgent'] as String?;
    final ytCfg = watchPage?.ytCfg;

    final content = await httpClient.postString(
      client.apiUrl,
      body: {
        ...payload,
        'videoId': videoId.value,
        if (ytCfg?.containsKey('STS') ?? false)
          'playbackContext': {
            'contentPlaybackContext': {
              'html5Preference': 'HTML5_PREF_WANTS',
              'signatureTimestamp': ytCfg!['STS'].toString()
            }
          },
      },
      headers: {
        if (userAgent != null) 'User-Agent': userAgent,
        'X-Youtube-Client-Name': payload['context']!['client']!['clientName'],
        'X-Youtube-Client-Version':
            payload['context']!['client']!['clientVersion'],
        if (ytCfg != null || visitorData != null)
          'X-Goog-Visitor-Id': ytCfg?['INNERTUBE_CONTEXT']?['client']
                  ?['visitorData'] ??
              visitorData,
        "X-Goog-FieldMask":
            "playabilityStatus.status,playabilityStatus.reason,playerConfig.audioConfig,streamingData.adaptiveFormats,videoDetails.videoId",
        'Origin': 'https://www.youtube.com',
        'Sec-Fetch-Mode': 'navigate',
        'Content-Type': 'application/json',
        if (watchPage != null) 'Cookie': watchPage.cookieString,
        ...client.headers,
      },
    );
    return PlayerResponse.parse(content);
  }
}
