# CDHW External Script — Audit vs Live Game (2026-10-12, PV5710)

> Source: script pasted in chat ("Created By CDHW"). Not stored in `versions/`
> (external authorship). Verdict per section below.

## Validated ✅ (matches decompiled/live)

- **Nape path** `Hitboxes/Hit/Nape`: confirmed live (`Part` exists on real titans).
- **Alive check** `Humanoid.Health > 0`: confirmed live (titans are Models with
  Humanoid @ 100 HP, GUID names, `State` Walk/Idle, `Dead/Killed` nil while alive).
  Equivalent to our attribute check.
- **Refill sequence** (TP → `Attacks/Reload` → `Blades/Reload`): matches game flow.
  **Adopted**: return-to-position after server teleport (`refillAtStation`, v8.2).

## Rejected ❌ (detection vectors — do NOT adopt)

- **`Register(nape, 50, 0)`**: flat velocity 50 + `timeDiff = 0`, every hit.
  Constant authoritatives + zero delta are textbook flags. Ours (real velocity
  magnitude + measured delta + jitter) is strictly better.
- **0.4s attack cycle** (`0.25` tween + `0.05` + `0.15`): ~2.5 hits/s — spam rage
  vs our 1.6s heuristic floor. Would trip the server-side silent reject.
- **Tween-to-nape movement** (0.25s to 5 studs): inhuman snap speed.
- **`needReload` semantics wrong**: reloads when ANY blade is `Broken`; the game's
  `Blade_Check` (decompiled `Core.ODMG`) only reloads when NO unbroken pair
  remains (7→1 scan). CDHW over-reloads → wasted remotes + traffic anomaly.
- **Full-workspace `GetDescendants` scans** per refill + per blade check: CPU waste;
  no caching. Ours caches (`getCachedRefillPart`, 0.1s nape cache).
- **Zero guards**: no pcall, no nil checks, no lobby/mission gating, no Waves support.

## Net

One idea adopted (refill return-to-position, hardened). Attack core rejected.
CDHW is a minimal lobby-farm toy; our core stays authoritative.
