# Listen Together

Listen Together connects phones on a shared local network and synchronizes
queue and playback control. A normal Wi-Fi network works, and a phone hotspot
also counts as the shared network: either the host or a guest may provide it.

Party mode is for a host connected to a car or speaker. Only the host plays
audio; guests use their phones as remotes to add songs and control playback.

Bluetooth transport is not available yet. The previous nearby-connections
plugin is incompatible with current Flutter Android embedding, so the app does
not offer an offline/Bluetooth fallback. A shared LAN or hotspot is required.
