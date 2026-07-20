# Android playback latency: best-effort 200 ms

## Summary

- Optimize every Android playback path toward tap/skip/track-boundary → first audible audio in about 200 ms.
- Treat 200 ms as a performance goal, not a guarantee for poor networks or uncached Resolver misses requiring Downloader ingestion.
- Keep standard HTTPS, byte ranges, and ETags. No custom protocol: the main delays are the explicit 500 ms Media3 startup buffer, discarded connections, and preload waiting for the remote tail. Media3 supports a configurable startup-buffer threshold, and Dart clients support persistent connection reuse. [Media3 load control](https://developer.android.com/reference/androidx/media3/exoplayer/DefaultLoadControl.Builder), [Dart HttpClient](https://api.dart.dev/dart-io/HttpClient-class.html)
- Preserve current miss behavior: Resolver returns `202` and queues downloaders while the phone’s existing online resolver continues racing; once ingested, Resolver streams the permanent stored copy.

## Harmony Music changes

- Add monotonic playback timing milestones for action, source selection, response headers, first encoded byte, player ready, and first positive playback position. Record only transition/source categories—never tokens, URLs, or user identity.
- Reduce Android `bufferForPlaybackDuration` from 500 ms to 200 ms while retaining the 2-second post-rebuffer buffer and current long-term buffer limits.
- Fix `PreloadedPrefixAudioSource` so it immediately returns and emits the local prefix. Start the remote-tail request concurrently and await it only after local bytes have been consumed; local-only ranges must never open the network.
- Replace per-operation `HttpClient` creation with one Resolver-owned connection pool shared by warm-up, prefetch, playback, `202` retries, and later ranges. Use up to four connections per authority, a five-minute idle timeout, bounded connect timeout, and close the pool only when the audio service is disposed.
- Warm the Resolver connection asynchronously during app/audio-service startup, resume, and queue prefetch. Deduplicate warm-ups and never block app startup on them.
- Keep local and Resolver candidates genuinely concurrent in “Both” mode. When local playback wins, cancel Resolver polling/response consumption while leaving the already-enqueued server ingestion running.
- Retain next-three server prefetch and next-track preparation. Avoid retaining multiple paused full-song Resolver streams, which could exhaust anonymous stream permits.

## Resolver and production edge

- Add `resolver.audio.first_byte.duration` for request-to-first-response-write, labeled only by cache status and initial/nonzero range. Keep the existing metric as full-transfer duration and correct its Grafana title.
- Send requested offsets and lengths to MinIO using its native range operation instead of downloading from byte zero and discarding data.
- In Harmony Platform, give audio requests a streaming-specific proxy path:

  - disable Nginx response buffering;
  - reuse Nginx→API connections with upstream keepalive;
  - preserve `Content-Length`, `Content-Range`, ETag, cancellation, and long read timeouts;
  - configure Caddy with a 10 ms audio flush interval, since both Caddy and Nginx otherwise buffer responses by default. [Caddy streaming](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#streaming), [Nginx proxy buffering](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)

- Disable Caddy’s HTTP/3 advertisement for now with `protocols h1 h2`, because production does not expose UDP 443 and the app’s current Dart path uses HTTP/1.1. Reconsider standard HTTP/3—not a proprietary protocol—only after the measured changes above. [Caddy protocol configuration](https://caddyserver.com/docs/caddyfile/options#protocols)
- Do not change the public API: existing audio GET, Range/ETag behavior, `POST /v1/prefetch`, and `202 Retry-After` remain compatible.

## Tests and acceptance

- Unit tests:

  - startup buffer is 200 ms while rebuffer remains 2 seconds;
  - a blocked remote tail cannot prevent immediate prefix delivery;
  - prefix/tail boundaries contain no gaps or duplicate bytes;
  - shared Resolver connections survive prefetch, token retry, playback, ranges, cancellation, and disposal.

- Resolver tests verify byte-zero and deep nonzero ranges, exact MinIO range propagation, first-byte metric recording, disconnect behavior, authentication, and quotas.
- Validate Platform configuration with Compose, Caddy, and Nginx checks, followed by deployed Range/ETag/cancellation smoke tests.
- Benchmark at least 30 physical-Android starts per case on stable Wi-Fi:

  - downloaded/local audio;
  - preloaded online audio with an intentionally delayed tail;
  - ready Resolver track on a reused connection;
  - ready Resolver track on a fresh connection;
  - manual tap, skip, and natural queue transition;
  - Resolver miss while the existing phone resolver wins.

- Acceptance target: preloaded and ready/warm cases achieve tap-or-transition → positive playback position at p95 ≤200 ms. Fresh connections and cold Downloader misses are reported separately; weak-network tests must remain functional without hangs or startup failures.
- Run Flutter analyze/tests and Resolver `scripts/agent-check.ps1`, reporting every validation command.

## Assumptions and rollout

- Android is the first milestone; desktop and Apple playback engines are out of scope.
- Preloaded mode is enabled with range 1–3. Because the persistent “cache songs while playing” setting was not confirmed, the first milestone assumes it is off; diagnostics will clearly identify the LockCaching path if that assumption is wrong.
- Preserve the current uncommitted Harmony Music durable-media/prefetch work.
- After this plan is accepted, save it verbatim and index it in Harmony Music, Harmony Resolver, and Harmony Platform before implementation.
- Roll out in order: instrumentation/baseline, Music preload and connection fixes, Resolver range/metrics, Platform streaming configuration, then physical-device benchmark.
