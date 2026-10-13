# AGENTS.md — AOTR Hub repo

Rules for changing this repo (humans + AI).

## Layout

- `src/AOTR-Hub.luau` — the script, single file. Edit in place; no splits.
- `docs/REMOTE_MAP.md` — remote contracts. Every `InvokeServer`/`FireServer`
  shape in `src/` must be traceable here (module, func, args, source).
- `docs/` audits — third-party analysis, one file per script.
- `CHANGELOG.md` — newest entry on top, `## vX.Y — date` + what/why.

## Rules

1. **No deletions without explicit approval** (files, functions, sections).
   Unsure → stub + ask.
2. **No guessed remotes.** New endpoint = decompiled or live-spied first,
   documented in `REMOTE_MAP.md`, then used. Never the reverse.
3. **GET_2 is banned.** Suspected honeypot, zero references in game code.
4. **No economy exploits.** Currency/dupe/gifting endpoints stay disabled.
   Shop *purchases* with earned currency are fine; free generation is not.
5. **Bell-curve timing, not uniform.** Noise uses Irwin-Hall sums, never
   `math.random` ranges. Speeds stay under verified ODM caps.
6. **Health/wounds are server-owned.** Never write `Humanoid.Health`, never
   `Destroy()` injuries — zone interaction only.
7. **Logic changes need a live reason** (error log, decompile, observed
   behavior). Strings-only changes say so in the changelog.

## Release checklist

1. Static check clean (Luau analyzer, zero errors).
2. Loads live with no fatal errors.
3. Effect verified in a real session (kill / refill / buy observed).
4. CHANGELOG entry + version bump in README status line.
5. Economy/damage toggles re-audited (rule 4).

## UI

- Library: Obsidian (`deividcomsono/Obsidian`). No other lib without approval.
- Tabs: Farm / Combat / Session / Presets / Upgrades / Waves / Visuals /
  Account / Stats / Settings / Theme. New tabs need approval.
- Every toggle/dropdown confirms via `uiFeedback()`; sliders exempt.
  Bulk-apply code (presets) silences with `_silentUI` + one summary notify.
- Display strings in English. No emojis in code unless asked.

## Commits

Conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`). One change per
commit, no AI attribution lines.
