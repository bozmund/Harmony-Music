# Harmony trajna pohrana, Cloud backup i prefetch

Potpuni prihvaćeni plan identičan je canonical planu u Harmony Resolver repozitoriju:
`C:\MyRepositories\Harmony-Resolver\plans\2026-07-20_0111_harmony_cloud_durable_media.md`.

## Harmony Music scope

- Jednokratni Cloud opt-in nakon prijave i kasniji pause/resume u Settingsu.
- Trajni lokalni outbox, checkpoint i deterministički offline merge.
- Logički backup svih prenosivih korisničkih podataka bez tajni, lokalnih putanja i prolaznih URL cacheva.
- Sekvencijalni audio backup isključivo na Wi-Fi mreži i bateriji iznad 50%.
- Slanje samo lokalnih audio datoteka s valjanim YouTube ID-em koje Resolver nema.
- Lokalni privremeni prefix približno 5 sekundi za konfiguriranih 1–3 pjesme.
- Server prefetch sljedeća tri `videoId`-a preko postojećeg `harmony-resolver.duckdns.org` hosta.

## Zajedničke granice i rollout

- Resolver trajno zadržava verificirani globalni audio; Cloud nikad ne posjeduje audio.
- Capacity pragovi su 45 GiB za prefetch, 48 GiB za backup i 50 GiB za urgentni ingest.
- Rollout: Platform i hostname, Resolver, Cloud, pa Music feature flag i smoke test.
- Jednokratno se postavljaju DuckDNS, Auth0, GHCR i VPS deploy tajne; daljnji deploy obavljaju Actions workflowi.
