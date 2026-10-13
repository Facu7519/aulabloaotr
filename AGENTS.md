# AGENTS.md — AOTR Hub repo

> Rules for anyone (human or AI) changing this repo. Short, binding, no filler.

## What goes where

- `src/AOTR-Hub.luau` — the entire hub, single file. Edit in place; no splits.
- `docs/REMOTE_MAP.md` — remote contracts. Every `InvokeServer`/`FireServer`
  shape in `src/` must be traceable here (module, func, args, source).
- `docs/` audits — third-party analysis. One file per script audited.
- `CHANGELOG.md` — newest entry on top, `## vX.Y — date` + what/why.

## Hard rules

1. **No deletions without explicit approval** (files, functions, sections).
   Unsure → stub + ask. State file + what + why → wait for "yes".
2. **No guessed remotes.** New endpoint = decompiled or live-spied first,
   then documented in `REMOTE_MAP.md`, then used. Never the reverse.
3. **GET_2 is banned.** Suspected honeypot, zero references in game code.
4. **No economy exploits.** Currency/dupe/gifting endpoints stay disabled.
   Shop *purchases* with earned currency are fine; free generation is not.
5. **Humanize, don't randomize.** Timing/noise uses bell-curve (Irwin-Hall),
   never uniform `math.random` boxes. Speeds stay under verified ODM caps.
6. **Health/wounds are server-owned.** Never write `Humanoid.Health`, never
   `Destroy()` injuries — zone interaction only.
7. **UI strings only?** Say so in the changelog. Logic changes need a live
   reason (error log, decompile, or observed behavior).

## Definition of Done (per release)

1. Static check clean (Luau analyzer, zero errors).
2. Loads live with no fatal errors (contained third-party warnings OK if noted).
3. Effect verified in a real session (farm kill / refill / buy observed).
4. CHANGELOG entry + version bump in README status line.
5. Economy/damage toggles re-audited (rule 4).

## UI conventions

- Library: Obsidian (`deividcomsono/Obsidian`). No other UI lib without approval.
- Tabs: Farm / Combat / Session / Presets / Upgrades / Waves / Visuals /
  Account / Stats / Settings / Theme. New top-level groups need approval.
- Every toggle/dropdown gets a one-line confirm via `uiFeedback()`; sliders
  are exempt (drag spam). Bulk-apply code (presets) silences with `_silentUI`
  + a single summary notify, auto-expiring.
- Display strings in English. No emojis in code unless the user asks.

## Commit style

Conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`). No AI attribution
lines. One logical change per commit.
