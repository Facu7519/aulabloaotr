# AOTR Hub — Attack on Titan: Rebirth Autofarm

AFK farming hub for **Attack on Titan: Rebirth** (Roblox). Hover-combat loop with
humanized timing, mission automation, auto-upgrades, Waves support, and a premium
Obsidian UI. Targets live-verified remote contracts — no guessed payloads.

> **Status:** v8.4 — lobby load verified live. Mission effect pending final DoD.
> **Game:** Attack on Titan: Rebirth · **UI:** Obsidian · **Language:** Luau

## Features (CORE first)

| Area | What |
|------|------|
| Farm | AFK hover-combat, titan/boss priority, blades + spears, reload/refill with return-to-position |
| Maps | Auto-start (Missions/Raids/Waves), retry w/ backoff, solo-only, return-to-lobby rotation |
| Upgrades | Gear, perks, skill tree, prestige, auto-sell (Secrets/equipped never sold) |
| Survival | Titan-grab escape, zone injury heal, crash recovery, configurable failsafe |
| Safety | Humanized Irwin-Hall timing, ODM-verified speeds, rate limits, GET_2 honeypot block |
| Waves | Autofarm, vote, HQ/gear upgrades, blessings, crates, market buy/lock, medical |
| Visuals | Titan ESP (color/dist/tracers), neon Player ESP + off-screen arrows, nape visualizer |

## Install

1. Join Attack on Titan: Rebirth.
2. Open your executor and run `src/AOTR-Hub.luau`.
3. Press `RightControl` (configurable) to show/hide the menu.
4. Farm tab → **Auto-Start Missions** + **Auto Farm**. Or pick a one-click preset.

No key system. No obfuscation — read the source before running it.

## Repo layout

```
src/AOTR-Hub.luau   ← the hub (single file)
docs/REMOTE_MAP.md  ← verified remote contracts (GET/POST router)
docs/CDHW_AUDIT.md  ← third-party script audit (what we adopted/rejected)
CHANGELOG.md        ← v1 → current
AGENTS.md           ← contributor rules (humans + AI)
```

## Safety notes

- Cooldowns, speeds and payload shapes mirror decompiled game code (see `docs/`).
  Anything the game doesn't do, the hub doesn't send.
- Economy endpoints stay **disabled by design** — this ships no currency exploits.
- You still farm on your own account: use at your own risk.

## Disclaimer

Educational / personal-use project. Not affiliated with the game developers.
If the game updates its remotes, expect breakage until contracts are re-mapped.

## License

Apache-2.0 — see [LICENSE](LICENSE).

