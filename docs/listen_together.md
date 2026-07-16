# Listen Together

Listen Together synchronizes queue and playback control between one host and
multiple guests. Android users explicitly choose Bluetooth, Wi-Fi, or both.
The selection is remembered and defaults to both on a fresh installation.

Party mode is for a host connected to a car or speaker. Only the host plays
audio; guests use their phones as remotes to add songs and control playback.

Bluetooth uses Google Nearby Connections in BLE low-power mode. It requires
Bluetooth and Google Play services, but not pairing, Wi-Fi, or internet. Both
devices approve the same short authentication code before connecting.
Advertising and connection requests use Nearby's non-disruptive policy, so the
SDK must not enable Wi-Fi or change the user's existing radio connections.

Wi-Fi uses mDNS and WebSockets. Devices must share a local Wi-Fi network or
phone hotspot, but that network does not need internet access. Desktop hosts and
guests use this mode. Android readiness also recognizes the local Wi-Fi
interface exposed while the phone itself is hosting a hotspot.

Combined mode starts Bluetooth and Wi-Fi together and merges duplicate routes
for the same session. It starts only when both transports are available and
does not silently downgrade. The app never enables a radio or opens Android
settings automatically; users control their selected radios.

An active Android Nearby session runs a connected-device foreground service so
it can survive the screen being locked. Leaving the session stops discovery,
connections, and the notification. A dropped guest connection ends that guest's
session immediately; it is not reconnected automatically.
