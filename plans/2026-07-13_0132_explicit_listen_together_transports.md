# Explicit Bluetooth, Wi‑Fi, and Combined Listen Together Modes

## Summary

Replace the current implicit hybrid behavior with an explicit Android transport selector:

- **Bluetooth** — Google Nearby Connections restricted to low-power BLE media; Wi‑Fi may remain off.
- **Wi‑Fi** — existing mDNS/WebSocket LAN transport; devices must share a local Wi‑Fi network or hotspot, but need no internet.
- **Bluetooth + Wi‑Fi** — both transports run concurrently and duplicate sessions are merged.

The default is **Bluetooth + Wi‑Fi**, and the last user selection is persisted. Both mode starts only when both transports are available. The app will never enable Wi‑Fi automatically or open a settings panel automatically; Android 10+ does not allow ordinary apps to toggle Wi‑Fi directly. [Android WifiManager](https://developer.android.com/reference/android/net/wifi/WifiManager)

## Implementation Changes

- Extend the transport model with explicit `bluetooth`, `wifi`, and `both` choices:
  - Android exposes all three.
  - Desktop remains Wi‑Fi-only.
  - iOS remains unsupported.
  - Sync and Party modes use the selected transport identically.
- Make Nearby Bluetooth-only:
  - Set `lowPower=true` for advertising, discovery, and connection requests, restricting Nearby to low-power media such as BLE.
  - Keep `P2P_STAR`, encryption, code confirmation, chunking, stable cross-build service ID, and the foreground service.
  - Do not require Wi‑Fi state or start LAN fallback in Bluetooth mode.
- Make Wi‑Fi mode use only `LanTransport`:
  - Do not request Bluetooth/Nearby permissions or require Google Play Services.
  - Preserve same-network and hotspot discovery through mDNS.
- Make combined mode strict and atomic:
  - Validate Bluetooth and Wi‑Fi readiness before starting.
  - Start both transports; if either cannot start, stop the other and show the exact unavailable radio.
  - Merge advertisements by session ID, prefer Bluetooth when both routes exist, and fall back to the Wi‑Fi route only after a Bluetooth connection attempt fails.
  - A later route disconnect ends peers using that route without silently changing their selected transport.
- Refactor discovery startup to be awaitable so the controller knows whether every selected transport started successfully before showing “Searching”:
  - Expose a typed discovered-session stream separately from `Future<void> startDiscovery(...)`.
  - Use typed availability/failure categories for Bluetooth disabled, Wi‑Fi disabled/unavailable, missing permission, missing Play Services, radio failure, and transport startup failure.
  - Preserve Google Play Services status codes in sanitized developer diagnostics.
- Update Listen Together UI:
  - Add three localized selectable transport options with live readiness indicators.
  - Default to Both on first install and persist subsequent selection in Hive.
  - Disable Host/Join when the selected radio requirements are not satisfied and show which radio or permission is missing.
  - Refresh readiness after permission changes, app resume, and Android Bluetooth/Wi‑Fi state broadcasts.
  - Do not automatically toggle radios, open settings, or silently downgrade Both to one transport.

## Test Plan

- Dart tests for selection persistence/default, transport factory mapping, strict combined startup, atomic cleanup, deduplication, route preference/fallback, repeated discovery, and typed error presentation.
- Kotlin tests verify BLE low-power options are applied to advertising, discovery, and connection, plus Bluetooth/Wi‑Fi readiness and Google Play Services mapping.
- Widget tests cover all three options and their disabled/ready states in English and Croatian.
- Run `flutter analyze`, full `flutter test`, Android debug/release builds, and manifest validation.
- Physical Xiaomi/Samsung matrix:
  - Bluetooth selected, Bluetooth on, Wi‑Fi off: discovery, authentication, Sync, and Party work.
  - Wi‑Fi selected, Bluetooth off, same LAN/hotspot: discovery, Sync, and Party work.
  - Both selected with both radios on: one merged session appears and connects.
  - Both selected with either radio off: no discovery starts and the missing radio is identified.
  - No Bluetooth pairing, shared internet, or common Wi‑Fi is required for Bluetooth mode.
  - Large queue synchronization and locked-screen foreground sessions work over BLE.

## Assumptions

- Bluetooth mode transfers control, queue, and synchronization messages—not audio—so BLE bandwidth is sufficient; existing chunking remains in place.
- Wi‑Fi-only means local LAN or hotspot, not a new Wi‑Fi Direct implementation.
- No automatic radio switching or fallback occurs outside the explicitly selected Both mode.
- The accepted plan will be saved under `plans/` when implementation begins.
