# Resolver physical-phone test

1. Put the Windows laptop and Android phone on the same non-isolated Wi-Fi network.
2. In an elevated PowerShell, run `scripts/lan-firewall.ps1 enable` from Harmony Resolver once.
3. Start `Harmony Resolver Phone Stack` in Rider, or run `scripts/agent-up.ps1`.
4. Run `scripts/phone-check.ps1`; open its reported `/health/ready` URL in the phone browser.
5. Build Harmony Music debug with `--dart-define=RESOLVER_DEBUG_BASE_URL=http://<LAN-IP>:8088` when the default is not correct.
6. In Settings → Harmony Resolver, keep Resolver enabled and run Test connection.
7. In Developer settings, use Discover on LAN or enter a manual address if mDNS is blocked.
8. Play a track anonymously, then sign in and repeat to exercise Auth0 quotas.
9. Disable Resolver and confirm playback returns to the existing local-only path.

No router port forwarding is required or recommended for this workflow.
