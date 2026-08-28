import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String handler;

  setUpAll(() {
    handler = File('lib/services/audio_handler.dart').readAsStringSync();
  });

  group('a resolver miss asks for the track to be ingested', () {
    test('both resolver-miss paths request ingestion', () {
      // The prefetch on song change covers the next three queue entries only,
      // never the one being played (issue #81: a track the Resolver had no
      // record of). Without this the local fallback carries that one playback
      // and nothing ever tells the Resolver the track exists, so the next
      // attempt hits the same 404 forever.
      expect(
        '_requestResolverIngestion(songId)'.allMatches(handler).length,
        2,
        reason: 'the raced path and the direct path',
      );
      expect(
        handler,
        contains('void _requestResolverIngestion(String songId)'),
      );
      expect(handler, contains('_resolverPlaybackClient.prefetch([songId])'));
    });

    test('ingestion is requested only when the Resolver is in use', () {
      final index = handler.indexOf('void _requestResolverIngestion(');
      expect(index, greaterThan(-1));
      final body = handler.substring(index, index + 240);

      expect(
        body,
        contains('if (!_effectiveResolverSourceMode().usesResolver) return;'),
        reason: 'a device set to local-only must not call the Resolver',
      );
      // Fire-and-forget: it cannot help the attempt in flight, and must never
      // delay or fail the fallback that is carrying this playback.
      expect(body, contains('unawaited('));
    });

    test('the miss still falls through to local extraction', () {
      // Requesting ingestion must not replace the fallback. Issue #66 was a
      // wedged player caused by a resolver miss that stopped instead of
      // falling through.
      final index = handler.indexOf('final source = await resolver;');
      expect(index, greaterThan(-1));
      final branch = handler.substring(index, index + 600);

      expect(branch, contains('_requestResolverIngestion(songId)'));
      expect(branch, contains('unawaited(runLocalExtraction())'));
      expect(
        branch.indexOf('_requestResolverIngestion(songId)'),
        lessThan(branch.indexOf('unawaited(runLocalExtraction())')),
      );
    });
  });
}
