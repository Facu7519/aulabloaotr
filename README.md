# AOTR Hub — Attack on Titan: Revolution Autofarm

AFK farming script for **Attack on Titan: Revolution** (Roblox). Hover-combat loop,
mission automation, auto-upgrades, Waves support, Obsidian UI. Remote calls match
contracts verified against decompiled game code.

> **Status:** v8.5 — lobby load verified live; auto-sell delete verified E2E
> (1 junk perk sold, save persisted). Mission effect pending final check.
> **Game:** Attack on Titan: Revolution · **UI:** Obsidian · **Language:** Luau

## Features

| Area | What |
|------|------|
| Farm | AFK hover-combat, titan/boss priority, blades + spears, reload/refill with return-to-position |
| Maps | Auto-start (Missions/Raids/Waves), retry w/ backoff, solo-only, return-to-lobby rotation |
| Upgrades | Gear, perks, skill tree, prestige, auto-sell (Secrets/equipped never sold) |
| Survival | Titan-grab escape, zone injury heal, crash recovery, configurable failsafe |
| Safety | Bell-curve timing, ODM-verified speeds, rate limits, GET_2 honeypot block |
| Waves | Autofarm, vote, HQ/gear upgrades, blessings, crates, market buy/lock, medical |
| Visuals | Titan ESP (color/dist/tracers), Player ESP + off-screen arrows, nape visualizer |

## Install

1. Join Attack on Titan: Revolution.
2. Open your executor and run `src/AOTR-Hub.luau`.
3. Press `RightControl` (configurable) to show/hide the menu.
4. Farm tab → **Auto-Start Missions** + **Auto Farm**. Or pick a one-click preset.

No key system. No obfuscation — read the source before running it.

## Repo layout

```
src/AOTR-Hub.luau   ← the script (single file)
docs/REMOTE_MAP.md  ← remote contracts (GET/POST router)
docs/CDHW_AUDIT.md  ← third-party script audit
CHANGELOG.md        ← v1 → current
AGENTS.md           ← contributor rules
```

## Notes

- Cooldowns, speeds and payload shapes mirror decompiled game code (see `docs/`).
- Currency/dupe endpoints stay disabled — no economy exploits shipped.
- You farm on your own account: use at your own risk.

## Disclaimer

Personal-use project. Not affiliated with the game developers.
If the game updates its remotes, expect breakage until contracts are re-mapped.

## License

Apache-2.0 — see [LICENSE](LICENSE).
