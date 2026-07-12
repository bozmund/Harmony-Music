# Connect Harmony Music Debug Builds to LAN Resolver

## Summary

Connect the Android app on a physical phone to Harmony Resolver running through Docker on the laptop. Debug builds discover or use `http://<laptop-lan-ip>:8088`; production builds use a configured HTTPS endpoint. Resolver is enabled by default in both builds but users can disable it. Downloaded/offline files remain highest priority, while Resolver races the existing local YoutubeExplode resolver for online playback.

## Backend and LAN development

- Keep Nginx bound to all host interfaces on configurable port `8088`; add an explicit LAN readiness check that tests the laptop’s actual Wi-Fi address, currently `192.168.8.22`.
- Add an opt-in administrative PowerShell firewall helper with `enable`, `status`, and `disable` operations. Rules allow TCP 8088 and mDNS UDP 5353 only on Windows Private networks.
- Add a small host-side discovery companion that advertises `_harmony-resolver._tcp` with port, API version, scheme, and environment. Start/stop it from the Windows agent scripts and a shared Rider full-stack compound configuration; Docker remains responsible only for the HTTP stack.
- Keep manual URL configuration as the fallback when mDNS is blocked, the Wi-Fi network is isolated, or the laptop changes address.
- Replace the current fake “Ogg-shaped” bytes with a deterministic, genuinely playable Ogg Opus fixture. Keep a switch for real yt-dlp/YoutubeExplode extraction when desired.
- Extend diagnostics with the advertised address, firewall/discovery state, and a phone-oriented connectivity command without exposing credentials.

## Flutter configuration and networking

- Introduce a typed Resolver configuration/service layer:
  - Debug default: `RESOLVER_DEBUG_BASE_URL`, falling back to discovered LAN service and then an editable override.
  - Production default: `RESOLVER_PRODUCTION_BASE_URL`, required to be HTTPS.
  - Persist overrides separately per environment so a debug LAN URL can never leak into production.
  - Normalize URLs, remove trailing paths, reject credentials/query fragments, and validate with `/health/ready`.
- Add ordinary Settings controls for Resolver enabled/disabled and Test Connection. Add Developer Settings controls for current environment, effective URL, editable override, Reset, Discover on LAN, discovery results, and sanitized last-check diagnostics.
- Enable Resolver by default in debug and release builds; users may opt out. Production accepts HTTPS only. Cleartext HTTP moves from the main Android manifest to debug-only network security.
- Reuse the existing `nsd` package and Android multicast permissions. Discovery runs on demand and automatically when a debug endpoint is unreachable, with bounded timeout and no port scanning.
- Add CI/build parameters for production Resolver URL and Auth0 API audience. These are non-secret GitHub variables; no client secret enters the app.

## Playback and Auth0 integration

- Preserve source precedence: downloaded file → cached offline file → online race.
- Race an already-open Resolver audio request against local YoutubeExplode resolution:
  - Accept Resolver only after a successful `200`/`206`, `audio/ogg`, and valid initial bytes.
  - Feed the winning HTTP response through a reusable `StreamAudioSource`, supporting later Range requests and ETags without issuing a duplicate first-miss request.
  - If local wins, cancel only the phone response; server ingestion continues and may finish caching.
  - If Resolver returns `202`, follow bounded `Retry-After` polling while the local candidate continues.
  - Never persist backend audio URLs as permanent upstream URLs.
- Extend Auth0 login configuration with `AUTH0_AUDIENCE`. Add a credential method that refreshes and returns a valid access token; attach it to Resolver requests when signed in and remain anonymous otherwise.
- Never attach bearer tokens to non-HTTPS production URLs. Redact tokens, raw subjects, and full exception bodies from logs and diagnostics.
- Replace raw resolver strings with typed local/backend failure categories. If both candidates fail, emit one localized actionable playback error; developer diagnostics retain sanitized categories and backend trace IDs.

## Tests and acceptance

- Backend tests cover valid playable fixture output, LAN binding, discovery metadata, firewall helper idempotency, first-miss disconnect continuation, Range playback, and diagnostics redaction.
- Flutter unit tests cover environment precedence, URL validation, separate persisted overrides, HTTPS enforcement, discovery fallback, token attachment/refresh, anonymous behavior, `202` polling, ETag/Range handling, race cancellation, and typed failure mapping.
- Widget tests cover enabled toggle, Test Connection, Discover, override/reset, both locales, and production HTTP rejection.
- Android integration test on the same Wi-Fi verifies:
  1. firewall/discovery reports the laptop;
  2. the phone resolves `http://<LAN-IP>:8088/health/ready`;
  3. an anonymous track plays;
  4. a signed-in track sends a valid Resolver-audience JWT;
  5. local resolution wins safely when Resolver is slow;
  6. Resolver wins when local resolution fails;
  7. disabling Resolver restores current local-only behavior.
- Run backend `agent-check`, Flutter analyze/tests, Docker two-replica smoke tests, and a documented physical-device checklist.

## Assumptions

- Two environments are supported initially: debug and production.
- Laptop and phone are on the same non-client-isolated Wi-Fi network.
- mDNS is convenience, not the only connection mechanism.
- Production Resolver URL is supplied by CI and uses valid HTTPS.
- No router port forwarding or public exposure is added for LAN debugging.
- Save this accepted plan in both repositories’ `plans/` indexes when implementation begins.

