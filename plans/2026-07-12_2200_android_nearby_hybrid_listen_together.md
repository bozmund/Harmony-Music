# Android Nearby Hybrid Listen Together

## Summary

Replace the disabled Bluetooth stub with Android Nearby Connections using `P2P_STAR`, not a true mesh: one host remains the queue/playback authority for both Sync and Party mode, with any number of guests. Nearby uses Bluetooth/BLE discovery and may use Wi-Fi Direct internally; users need no shared Wi-Fi, internet connection, or Bluetooth pairing.

Before feature work, remove the merged quickfix worktree and its local `codex/fix-update-loop` branch, then continue in the existing `codex/connect-harmony-resolver` worktree.

## Implementation Changes

- Add `play-services-nearby:19.3.0` and an Android Kotlin Nearby Connections bridge using `ConnectionsClient`, a typed method channel for commands and an event channel for discovery, connection, code-confirmation, payload, disconnect, and error events. Devices without current Google Play services show an actionable unavailable state.
- Replace `NearbyTransport`’s stub with the bridge-backed transport. Use `P2P_STAR`, app package name as the service ID, encrypted Nearby connections, and a shared short authentication code that both host and guest must confirm before messages are accepted.
- Add a composite/hybrid transport:
  - Android hosts advertise both LAN and Nearby under the same session ID.
  - Android guests begin Nearby discovery first; after 3 seconds, also search LAN.
  - Merge LAN/Nearby advertisements for the same session into one host row; choose Nearby first and fall back to LAN if its connection attempt fails.
  - Broadcast host state to guests on either transport, deduplicate peers by session/device ID, and route direct replies to the matching transport.
  - Desktop keeps full LAN host/join support; iOS receives no new support.
- Persist an editable Listen Together device nickname, initially derived from a neutral Android device name. Show it in discovery, participant lists, and code-confirmation dialogs.
- Request Bluetooth/Nearby permissions only when Nearby is needed. Explain the requirement first, request runtime permissions, and link to Android Settings when denied, permanently denied, Bluetooth is off, or Google Play services is unavailable. The required Android permission set follows Nearby’s current guidance.
- Keep host and guests alive in background with an Android foreground connected-device service and notification while a Nearby session is active. Stopping the session stops discovery, connections, service, and notification. A dropped guest connection immediately ends that guest’s session; no automatic reconnect.
- Keep hosts discoverable to everyone in radio range by nickname, but require both sides to confirm the short code. Do not add an artificial peer cap; surface Nearby/platform capacity errors clearly.
- Fragment outgoing Nearby byte payloads transparently and reassemble them in order, so large queue syncs are sent in chunks without a fixed song-count or application-size limit. Apply bounded per-transfer timeout/cleanup to prevent stale partial payloads consuming memory.

## Test Plan

- Dart unit tests for route merging, Nearby-first/LAN-fallback selection, cross-transport broadcast, peer deduplication, chunk framing/reassembly, permission/error mapping, immediate disconnect teardown, and nickname persistence.
- Kotlin tests for bridge event translation, connection-code confirmation, payload chunk handling, and foreground-service lifecycle.
- `flutter gen-l10n`, `flutter analyze`, full `flutter test`, and Android debug/release builds.
- Physical Android tests with no shared Wi-Fi: discovery with Bluetooth enabled, code confirmation, Sync playback, Party remote behavior, locked-screen host and guest, a desktop LAN guest in the same host session, denied permissions, radio disabled, Google Play services unavailable, large queue sync, and out-of-range disconnect.
- Verify no manual Bluetooth pairing is created and no iOS Nearby UI/support is introduced.

## Assumptions

- Android Nearby uses Google Play services and `P2P_STAR`; it is a host-and-guests session, not relay-capable mesh routing.
- Nearby discovery is preferred, while LAN remains available for desktop and as Android fallback.
- Both devices must grant Nearby permissions and confirm the displayed code before joining.
