# AOT:R Script Changelog — Reverse Engineering T Hub.txt

## v8.5 — 2026-10-17 (Current)

> Game-update follow-up (lobby Place 14916516914, PV9150): the save endpoint
> moved and the real save shapes changed — Auto-Sell was dead (iterated
> arrays that are dicts, entries carry no Rarity) and Auto-Prestige/
> Auto-Enhance got nil data. All fixed against decompiled game code and
> verified live this session.

### Fixed (live-verified)

1. **Save endpoint**: `("Functions","Settings")` returns zero values since the
   2026-10 update — the save now lives at `("Functions","Keybinds")`
   (full Slots/Perks/Artifacts/Currency). GetPlayerData tries Keybinds first,
   Settings as legacy fallback. Restores Auto-Prestige, Auto-Enhance and
   Auto-Sell data flow.
2. **Auto-Sell rewrite** (perks + artifacts): real shapes are dicts
   (`Storage = {uuid -> {Name, Level, XP}}`), not arrays — now iterated with
   `pairs`, rarity resolved **by name** via the game catalogs
   (`Storage.Perks` / `Storage.Items`), equipped items skipped via the
   `Equipped` ID sets, sales batched (up to 10 ids per call) using the game's
   own Delete contract: `S_Equipment/Delete(Type, {id, ...})` → new full save.
   Cache invalidated after each sale; waits are bell-curved (`humanWait`),
   replacing uniform `math.random` sleeps.
3. **Artifacts `Locked` decoded**: it is the per-STAT reroll lock array
   (`Artifact_Roll`), NOT a sell lock — the only sell guard is equipped
   (decompiled `Equipment.Delete.Check_Item`: "Cannot sell an equipped item!").
   27/27 live entries audited.
4. **Secret→Mythic retier**: the game renamed the tier (same 14 names,
   14/14 live-verified). The static map keeps labeling them "Secret" on
   purpose — v8.4 intent: never sold. `GetPerkRarity` now falls back to the
   live catalog for names the static map doesn't know (future content).
5. **New helper**: `moduleLoader` — pcall-guarded dynamic require (keeps the
   Luau analyzer clean of unresolvable instance requires).

### DoD live v8.5 (lobby, gen 6)

- Static check: edited blocks analyzer-clean (Luau LSP + Real lint).
- Load verified: `_G.AOTR` + Settings + Obsidian UI present; the known
  contained theme warning (saved Background Image Real can't cache) is
  unchanged — user action still pending: clear Background Image in Theme.
- Effect verified: dry-run batch selection on live save (string-id batches,
  0 equipped leaked) + E2E sell of one junk Common L0 perk
  (`_G.AOTR.deletePerk({id})`): server returned the new save, Perks
  count/Amount 1075 → 1074, refetch persisted.
- Docs: `REMOTE_MAP.md` live-audit section — Keybinds contract, save shapes,
  Delete / Perk_State / Artifact_State / Artifact_Vanity contracts, rarity
  catalogs, retier note, client architecture (nested UI modules).

## v8.4 — 2026-10-12

> Stall preset removed (approved, ban risk) + adopted external-list ideas that
> survived audit (failsafe slider, sell protection, performance combo, nape
> visualizer). Full idea-by-idea verdict in session notes.

### Removed (approved)

1. **AFK Farming (Stall) preset deleted** — Stall + Hardest + 10 mods + Teleport
   is a flag magnet. Refs removed from all 3 remaining preset cascades + summary
   labels. Use Breach/Defend/Waves.

### Adopted from external list (audited)

2. **Failsafe timeout configurable** (was hardcoded 900s): Protection slider
   5-60 min, default 15.
3. **Auto-Sell protection**: Secrets + equipped/used/active/locked items are
   NEVER sold regardless of selected rarity (shape-agnostic guard). The rarity
   dropdown even lists Secret — this was one misclick from disaster.
4. **Performance Mode** (Protection): one switch for Hide Map + Disable 3D Rendering.
5. **Nape Visualizer** (Combat): client-only green boxes on living napes
   (BoxHandleAdornment, 1s refresh). Nape *Extend* rejected (authoritative mismatch).
6. **Farm declutter**: new **Upkeep** group (reload/TP-refill/escape) under
   Auto Farm; **Safety pinned to the bottom** of Farm. Auto Farm keeps core only.

### DoD live v8.4 (lobby, gen 9)

7. Load clean: `_G.AOTR` + Settings + Obsidian UI present, no fatal errors.
   Non-fatal contained: user's saved config/theme carries a background image
   Real can't cache (`DownloadAsset` → `RecursiveCreatePath` throws inside
   Obsidian's connection). Fixed the fatal variant (ApplyToTab crash) by
   stashing `default.txt` during tab build (+`.bak` backup) and loading guarded.
   User action: clear Background Image in Theme and re-save the config.

### Audited, not built (verdict)

- Covered already: Smart Raid Engine (= TargetPriority Boss/Titans/None),
  Boosted Maps, Auto Rejoin, webhooks, slots, skill-tree paths, prestige+threshold,
  Waves HQ/crates, achievements, mastery modes.
- Needs live discovery first (endpoints unconfirmed): Auto Claim Quests
  (`Functions/Quest` never called), Auto Buy Spins/Crates/Boosts (`S_Market/Buy`
  never called — format needs decompile), bulk family spins, TS Quest
  Forest/Utgard specifics, Shadow-Ban auto-webhook (manual check exists).
- Rejected: Feedback star-rating (no backend in a personal hub).

## v8.3 — 2026-10-12

> UI/UX overhaul + verified APIs (Obsidian ThemeManager source, Real Drawing +
> queue_on_teleport support). Display-strings + moves only; no farm logic touched.

### Theme (own section)

1. New **Theme tab** below Settings (`ApplyToTab(Tabs.Theme)`); Settings keeps
   config lists only. House style: **Mint palette + BuilderSans** via
   `SetDefaultTheme`; forced Gotham post-load removed. First run snapshots
   current style as **"THub"** custom theme + defaults it; legacy
   `Predeterminado.json` migrated (copy→THub, default.txt fixed). Existing user
   defaults respected (never overwritten).

### Farm tab

2. New **Safety section**: Auto Grapple, Auto Click Attack, Auto Jump Boost moved
   out of Flight & Movement. (4th item "attack" ambiguous — left in place, TBD.)
3. **YouTube Channel** button (copies `https://www.youtube.com/@Npc_CertifiedYt`),
   replaces Join Discord.
4. **Teleport mode hides Flight Speed** (`SetVisible`, API already used in-script);
   **"Hover Height" → "Attack Height"** (applies to both modes).
5. **Startup notify**: "Press [configured hotkey] to show/hide the menu".

### ESP

6. Titan tags show **type + distance** ("Titan • 123m"), never raw GUIDs.
   New: **color picker, max-distance filter, tracer lines** (Drawing, 0.25s loop).
7. New **Player ESP** (Display group): neon-green default, AlwaysOnTop highlight,
   name/dist/HP tags, **off-screen edge arrows** (Drawing triangles). Separate
   cleanup paths; all Drawing calls pcall-guarded (degrades gracefully).

### Feedback + discoverability

8. **Quiet confirm notify (1.2s) on ~25 toggles/dropdowns** via `uiFeedback()`;
   sliders excluded (drag spam). Presets wrap bulk-apply in `_silentUI` (single
   summary notify; auto-expires in 15s so a mid-preset error never mutes UI).
9. **Auto Reload & Refill + Teleport + Escape Titan Grab moved to Farm** (were
   buried in Combat); Combat keeps advanced tuning only.
10. New **Session tab (3rd)**: Protection (failsafe/execute/chest), Boosted Map,
    Session (helpers + boosts). Combat is pure fighting now.

### Presets + AutoExecute

11. Presets labeled **"CORE only (Farm, Combat, Mission Setup)"** + per-preset
    `Affects:` tooltips. MultiHit cap 20→10 (old tooltip admitted ban risk).
12. **AutoExecute root cause: queued `ins.lua` URL is 404** (verified). Now queues
    THIS script from disk (override via `_AOTR_SOURCE_PATH`/`_AOTR_SOURCE_URL`),
    notifies which source armed, and re-arms after autoload restore.

## v8.2 — 2026-10-12

> UI overhaul + CDHW external-script audit (live-validated, PV5710).
> Merge (approved per Regla #8): duplicate Auto-Claim Achievements fused into the
> Achievement Hunter implementation (validated helper + scan slider + summary
> notify); blind 1-84 lobby loop removed. Late groups renamed (Achievement Hunter,
> Artifacts, Shifter Skills, Loadouts, Auto-Sell).

### UI (premium pass, display-strings only — zero logic touched)

1. **Tabs renamed**: Main→Farm, Utils→Combat, Configs→Presets, Central→Account.
2. **All 22 groupboxes renamed** (Quick Actions, Auto Farm, Flight & Movement,
   Mission Setup, Attack, Safety, Boosted Map, Shifter Mastery, Session Helpers,
   One-Click Presets, Gear Upgrades, Waves Autofarm, HQ Upgrades, Black Market &
   Medical, Titan ESP, Display, Family Summon, Automation, Slots & Prestige,
   Discord Alerts, Session, Rates, Crash Recovery, Auto-Sell, Achievement Hunter,
   Artifacts, Shifter Skills, Loadouts).
3. **~60 control texts made precise** (Auto Click Attack, Attack Radius, Max Titans
   per Hit, Flight Speed, Hover Height, Escape Titan Grab, HQ: Max Health/Regen/
   Restore/+Refills/Revive, Auto-Buy/Lock (Black Market), Titan Highlights…).
4. **Tooltips rewritten** on core controls, incl. guardrail notes (ODM cap 300,
   radius cap). Sliders aligned with verified values (speed default 260, height 180,
   radius max 1500→400).
5. **Branding**: `TITANIC HUB` → `AOTR Hub` (11 notifies). Bullet labels verified
   (already • U+2022).

### Adopted from CDHW (validated, hardened)

6. **Refill return-to-position** (`refillAtStation`): save CFrame → Reload →
   humanized 1.8s → restore + zero velocity. Replaces both raw refill teleports.
   Rest of CDHW **rejected** — see `data/CDHW_AUDIT.md` (flat Register(50,0),
   0.4s cycle, any-broken reload, unguarded scans).

## v8.1 — 2026-10-12

> Live verification (Real MCP, PV5710, localized only — full index stays BANNED):
> decompiled `Core.ODMG` → verified speeds Default=300 / Nuke=450, M1 anim frames
> (Floor 13/30s, Air 11/30s, Spear 35/60s), Blade_Check 7→1 loop. NO client-side
> attack-cooldown constant exists anywhere in decompiled source (spam check is
> server-side, silent reject) → 1.6s floor stays as conservative heuristic.

### Fixes (audit findings)

1. **Cooldown regression fixed** — farm loop overwrote `AttackCooldown` to 1.0-1.5s
   every iteration. Now single `attackCooldown()` (floor 1.6s + human tail).
2. **Injury Destroy-loop deleted** — unconditional client-side `Destroy()` every 2.5s
   (visible anomaly, against AGENT.md). Replaced by throttled zone-heal only when
   actually injured (`hasInjuries()` gate, 5-7s).
3. **Farm-thread nil-guards + watchdog** — guarded titan hierarchy, boss Marker/Hit
   chains, spear HUD lookups (a single throw used to kill AFK silently). Heartbeat +
   10s monitor restarts the loop if stale >15s while toggle is on.
4. **DieAtStreak passive** — `Humanoid.Health = 0` write removed (client-authoritative
   health write = detection vector). Now stands down (no attacks, zero velocity) so
   the game kills legitimately; auto-resumes on respawn.

### Humanization (ADR-002 Irwin-Hall) + credible speeds

5. New `irwinHall()/humanWait()/humanNoise()` — bell-curved timing/drift replaces
   uniform `math.random` box noise in attack timing, hover, MultiHit throttle, upgrades.
6. `MoveSpeed` 400→260 (legit ODM = 300; 400 read as exploit), `HeightOffset` 250→180.
7. Colossal `S_Skills/Impact` 30-burst now throttled (0.05s steps).

### Organization + performance

8. Header `CONTENTS` map (§BOOT/§VALID/§HUMAN/§CONFIG/§API/§FARM/§SURVIVE/§COMBAT/§UI/§MAPS/§WAVES/§EXTRAS).
9. Objective `GetDescendants` scan 1s→3s; new blocks Luau-analyzer clean.

## v8.0 — 2026-10-12

> Live re-validation via Real MCP (Trost, PlaceVersion 5710). Full script index
> NOT built (OOM risk — crashed the operator's machine); localized decompiles only:
> `ReplicatedStorage.Modules.Waves.Market` (full, 361 lines), module listings for
> Waves/Core/Skills/Physics, Remotes router check (GET + POST + GET_2 unchanged).

### Corrected contracts (decompiled proof)

1. **`Waves/Item/Buy` was malformed** — script sent `("Waves","Buy",id,qty)`. Game sends
   `a1:Invoke("Waves","Item","Buy",Category,Item.ID,qty)`. Fixed `buyWavesMarketItem`
   to `(category, id, qty)` + updated the Auto-Buy caller to pass `cat`. Old shape
   refused loudly instead of flagging the account with malformed traffic.
2. **Item.ID = `GetAttribute("ID")`**, not the instance Name. `getWavesMarketItems`
   now captures ID attribute (fallback Name) + stock/locked/price per entry.
3. **Market.Buy validation chain mirrored client-side** (`Validators.marketBuy`):
   rotation → Stock → Locked==nil → Gold → Capacity≤1000. Matches game's notify strings.

### Hardening

4. **`Validators` block**: `char/root/humanoid/nape/refillPart/marketBuy` nil-guards.
   `getHitboxArgs` returns nil for stale/dead-titan napes; MultiHit + Colossal-P2
   call sites skip them (previously: silent server rejects).
5. **MultiHit throttle**: 30-80ms `task.wait` between `Hitboxes/Register` calls
   (was: all fired in one frame — burst detection vector). Cap still ≤5.
6. **`safeInvoke`/`safeFire`**: remotes-exist guard (new round/teleport leaves stale
   refs); `safeInvoke` hard-blocks `GET_2` with warn (suspected honeypot).
7. **Single rate limiter**: `canCallRemote` now aliases `canCall` (was: two divergent impls).
8. **`getRefillPart` Waves support**: checks `Waves.Props`/`Waves.Zones`/any `Refill`
   under `workspace.Waves` before lobby paths (pending since v7.0).
9. **`tryWavesUpgrade` via `safeInvoke`** (was: raw pcall+InvokeServer).
10. **`sellItem` validated**: `S_Inventory/Sell` is UNCONFIRMED (absent from decompiled
    source) — arg-checked + nil-safe; returns nil on reject instead of throwing.
11. **`Settings` table** (ADR-005 pattern): mirrors `getgenv()` via metatable,
    exposed as `_G.AOTR.Settings`. New code uses `Settings.X`; existing refs untouched.
12. **`getWavesMarketItems` pcall-guarded `.Value`** (threw on non-StringValue entries).

## v7.0 — 2026-07-05

### New Features

1. **Market Auto Buy (Waves)** — Nueva sección Market en Waves tab. Compra automática de items (Perks, Artifacts, Memories, Shifting) via `Waves/Item/Buy`. Selección por categoría e items individuales con cantidad configurable. Incluye Auto Lock con `Waves/Item/Lock`. Formato validado contra código decompilado del juego.

2. **Auto Heal Injuries (Waves)** — Detecta injuries en el character y las cura interactuando con `workspace.Waves.Props.Injury` via firetouchinterest. Polling cada 5s con notificación de estado.

3. **ESP Titans (Visuals)** — Nueva sección Visuals/ESP en Waves tab. Crea Highlights y BillboardGui NameTags en todos los titanes vivos. Auto-refresh configurable cada 1-10s. Limpia automáticamente al desactivar.

4. **Helpdesk de Market/Waves** — Nuevas helper functions: `getWavesMarketItems()`, `buyWavesMarketItem()`, `lockWavesMarketItem()`, `healInjuries()`, `hasInjuries()`, `createESPTitan()`, `updateESPTitans()`, `clearESPTitans()`, `useInventoryItem()`.

### Robustez

5. **Validación de input en todos los nuevos módulos** — Nil checks en char, root, workspace, y todas las referencias antes de remote calls. Jitter 0.2-0.5s en todos los loops de Market/Lock.

6. **Preservación del código existente** — Todas las funciones previas (Auto Farm, Waves, Upgrades, Auto Start, etc.) intactas sin modificar.

### UI Changes

7. **2 nuevos grupos en Waves tab**: `Market & Injury` (right side, shopping-cart icon) y `Visuals/ESP` (right side, eye icon).

8. **Dropdowns para selección de Market**: Categories (multiselect), Items específicos (multiselect), Quantity slider (1-10).

### Investigation

- `Waves/Item/Buy` confirmado: `p1:Invoke("Waves", "Item", "Buy", Category, Item.ID, quantity)` en `Modules.Waves.Market.Buy()`
- `Waves/Item/Lock` confirmado: `p1:Invoke("Waves", "Item", "Lock", Category, ID, 1)` en `Modules.UserInterface.Warning`
- Waves.Items estructura: 4 carpetas (Perks, Artifacts, Memories, Shifting) con StringValue IDs
- Crates en Waves: `workspace.Waves.Crates.Crate_<Player>.Hitbox` con TouchInterest - server-side collection
- Injuries: 6 tipos (Gear, Arm, Leg, Ribcage, Eyes, Head) - server manda Injuries folder al char
- Waves.NPCs: Lulu, Orange, Youmii, Roll (vendedor spins), Cole
- Waves.Props: Blessing, Equipment, Upgrade, Dropoff, Market, Injury
- Waves.Zones: Market, Skills, Injury, Blessing, Equipment, Upgrade
- `getRefillPart()` solo busca en `Unclimbable` (lobby/missions), no en `Waves` — fix pendiente para modo Waves

## v6.1 — 2026-07-05

### Critical Fixes

1. **Wave Counter data source fixed** — Was reading `Objectives.Waves` (HQ health percentage, always 100/100) instead of `Objectives.Clearance` (actual wave progress). Changed `getWaveNumber()` to read `Clearance.Value + 1` / `Clearance.Requirement + 1`. Verified via live game inspection: HUD showed "Waves Cleared [13/14]" while `Objectives.Waves` was `{Value=100, Requirement=100}` (HQ HP).

2. **All upgrades now one-by-one, not batched** — Lobby Auto Upgrade (`S_Equipment/Upgrade`), Waves Gear Upgrade (`Equipment/Upgrade`), and Waves HQ Upgrades now send ONE upgrade per remote call with 200-500ms jitter between each. Prevents batch detection vectors.

### UI Restructure — Waves Tab

3. **HQ Upgrades separated from Gear/Blessings** — Created new `WavesHQGroup` (right side) for HQ upgrades and `WavesGearGroup` (left side) for gear/blessings. Previously all Waves features were in a single `WavesSettingsGroup`.

4. **Individual toggles for each HQ upgrade** — Replaced single `AutoWavesHQUpgrade` toggle with individual toggles: `AutoWavesMaxToggle`, `AutoWavesRegenToggle`, `AutoWavesReplenishToggle`, `AutoWavesRefillsToggle`. Each sends `Waves/Upgrade` independently with its specific upgrade name.

5. **Auto Revive moved to HQ Upgrades group** — `AutoWavesReviveToggle` now lives in `WavesHQGroup` alongside the other HQ-related features.

### New Features

6. **Target Priority dropdown** — New dropdown in Utility > Combat: "Titans", "Boss", "None". Controls Auto Farm targeting behavior:
   - **Titans**: Prioritizes regular titans over bosses (kills normal titans first, then bosses)
   - **Boss**: Prioritizes bosses over regular titans
   - **None**: Closest target (original behavior)

7. **Smooth hover movement** — Fixed player jittering/temblor when hovering over titans. Added linear deceleration: velocity scales down when < 50 studs from target, stops at 5 studs for smooth settling.

8. **Auto Collect Crates (Waves)** — New `AutoWavesCollectCratesToggle` in Waves tab. Detects `workspace.Waves.Crates` and teleports player to crate hitbox, then fires `firetouchinterest` to trigger collection via game's server-side handler. Polls every 3s.

9. **Waves Config preset updated** — Now enables all features including Auto Collect Crates.

### Investigation

- `Objectives.Waves` confirmed as HQ health percentage: `Value=100, Requirement=100` = 100% HP
- `Objectives.Clearance` confirmed as wave progress: `Value=12, Requirement=13` displayed as "Waves Cleared [13/14]" in HUD
- HQ upgrades: Max (HP), Regen (%/s), Replenish (heal), Refills (extra refills), Revive (dead teammates)
- Each HQ upgrade has independent cost scaling and Upgrade=0 (none purchased at start)
- Crate model: `workspace.Waves.Crates.Crate_<player>.Hitbox` with TouchInterest — server handles collection on touch

## v6.0 — 2026-07-05

### Live Game Analysis (2026-07-05, PlaceVersion 5628)

All changes based on decompiled Waves modules and live instance inspection via Cobalt spy.

### Critical Fixes

1. **Waves HQ Upgrade uses correct remote** — Was using `S_Equipment/Upgrade` (lobby remote). Changed to `Waves/Upgrade` with `{upgradeName}` format matching the game's decompiled `Waves.Upgrade.Use()` which calls `p1:Invoke("Waves", "Upgrade", { p3.Name })`. Valid upgrades: Max, Regen, Replenish, Refills.

2. **Waves Gear Upgrade uses correct remote** — Was using `S_Equipment/Upgrade` (lobby remote). Changed to `Equipment/Upgrade` matching the game's decompiled `Waves.Equipment` module which calls `p1:Invoke("Equipment", "Upgrade", tbl)`. Waves mode has 16 stats (full ODM + TS + Crit), unlike lobby's 8 blade stats.

3. **Gear upgrades sent in batches of 8** — Each upgrade was sent individually (`{"TS_Speed"}`, `{"Crit_Damage"}`), creating N remote calls. Now batched in groups of 8 with 200-500ms jitter between batches.

### New Features

4. **Auto Vote Waves** — Detects vote prompts via `INTERFACE.Waves.Inner.Visible` attribute and fires `Waves/Update` (POST) to auto-vote. Uses 1s polling interval.

5. **Auto HQ Upgrade** — Automatically purchases HQ upgrades (Max HP, Regen, Replenish, Refills) using the correct `Waves/Upgrade` remote. Polls every 3s.

6. **Auto Blessings** — Rolls blessings via `Waves/Blessing/Spin` (GET). Polls every 2s.

7. **Auto Revive** — In multiplayer waves (`Player_Count > 1`), auto-revives dead teammates via `Waves/Revive` (GET). Polls every 10s.

8. **Wave Counter** — Live label in Waves tab showing current wave / max wave from `ReplicatedStorage.Objectives.Waves`.

9. **Waves Config preset updated** — Now enables all Waves features: Farm + Vote + HQ Upgrade + Gear Upgrade + Blessings.

### Investigation

- `Waves/Upgrade` confirmed: `p1:Invoke("Waves", "Upgrade", { p3.Name })` in Waves.Upgrade module
- `Equipment/Upgrade` confirmed: `p1:Invoke("Equipment", "Upgrade", tbl)` in Waves.Equipment module
- `Waves/Update` confirmed: `p1:Send("Waves", "Update")` in Waves.Waves.Vote()
- `Waves/Blessing` confirmed: `p1:Invoke("Waves", "Blessing", "Spin")` in Waves.Blessing module
- `Waves/Revive` confirmed: `p1:Invoke("Waves", "Revive")` in Spectate module
- Waves Gear Upgrades: ODM_Damage, ODM_Control, ODM_Gas, ODM_Speed, Blade_Durability, ODM_Range, TS_Damage, TS_Control, TS_Range, TS_Gas, TS_Speed, Blast_Radius, Crit_Damage, Crit_Chance (14 stats, NOT 16 — TS_Gas and TS_Speed are the TS equivalents)
- HQ Upgrades: Max (max HP), Regen (HP regen %/s), Replenish (heal current HP), Refills (increase refill count), Revive (revive dead teammates on boss wave)
- `INTERFACE.Waves.Inner` is the vote UI frame — `Visible` attribute controls show/hide

## v5.1 — 2026-07-05

### Hotfixes
1. **getHitboxArgs() reverted to damage-roll format** — The v5 change to `(nape, vel, timeDiff)` broke titan kills because `AssemblyLinearVelocity` was 0 when hovering still, producing 0 damage. Reverted to the proven working format `(nape, math.random(625, 850))` used by the original script, which the server accepts as a damage override.

2. **Moved helpers before AutoFarm:Start()** — `getHitboxArgs` and `getCurrentSpearSlot` were defined AFTER `AutoFarm:Start()` (lines 1568/1573), causing `"attempt to call a nil value"` errors at line 762 (Hitboxes/Register call site) because the farm loop runs in a spawned thread that executes before those definitions are reached. Both functions are now placed immediately before the Auto Farm section header.

### Investigation
- The game's own code sends `(nape, velocity, timeDiff)` but the server ALSO accepts `(nape, damageRoll)` from the original script. The damage-roll format is the one that actually works for scripted farming.
- Library toggles require `SetValue()` method to fire OnChanged callbacks — setting `Value = true` directly bypasses the signal.

## v5 — 2026-07-05

### Changes
1. **getHitboxArgs() changed to scalar velocity** — The function was returning a Vector3 (`Vector3.new(math.random(-50,50)/10, ...)`) but the game's Zones module sends `BV.Velocity.Magnitude` (a scalar number). Changed to read `root.AssemblyLinearVelocity.Magnitude` at call time. The old code was detectable as fake traffic. **Note: reverted in v5.1** — velocity was 0 during hover, producing 0 damage.

2. **getCurrentSpearSlot() fixed to scan rig** — Was looking for `char.ThunderSpear` which doesn't exist in the current game. Changed to scan `Rig_*/*LowerArm/Spears/{1..8}` for instances where `GetAttribute("Used") == nil`, matching the game's Spears module: `S_Fire` finds the spear in `(Left|Right)LowerArm.Spears[p3]`.

3. **Attacks/Reload changed from InvokeServer to FireServer** — Confirmed the game uses `p1:Send("Attacks", "Reload", refillStation)` (FireServer). The script was using `getRemote:InvokeServer("Attacks", "Reload", refillPart, nil)` — wrong remote type + extra nil arg. Fixed both call sites.

4. **Spears/S_Explode changed from InvokeServer to FireServer + args fixed** — Was sending `(spearSlot, explodeTimeDiff)` via InvokeServer. Game sends `p1:Send("Spears", "S_Explode", v22, Modules.Zones.Time_Difference)` (FireServer, position, timeDiff). Fixed to use nape.Position.

5. **Colossal Phase 2 S_Explode now includes timeDiff** — Was missing the 4th arg. Added timeDiff tracking. Reduced burst from 8 to 5 per loop (per detection vectors guideline).

6. **Waves Upgrade remote path fixed** — Was using `"Equipment"` instead of `"S_Equipment"`.

7. **Auto Upgrade stats corrected** — Was sending 14 stats including TS/Blast_Radius which the game doesn't accept in `S_Equipment/Upgrade`. Changed to match the working script's 8 blade stats: `Crit_Chance, Blade_Durability, ODM_Damage, Crit_Damage, ODM_Speed, ODM_Control, ODM_Range, ODM_Gas`.

8. **beforeAmmo undefined bug fixed** — `beforeAmmo` was used in comparison but never declared. Added `local beforeAmmo = getAmmo()` before the S_Fire call.

9. **MultiHit throttled** — Added 30-80ms delay between each Hitboxes/Register call to prevent burst detection. MultiHit slider max reduced from 20 to 5.

10. **Spear boss loops reduced** — S_Explode per-boss loop reduced from 40 to 3 (per detection vectors: "No sobrepasar 2-3 por boss"). Added task.wait between multi-nape hitbox registers.

### Investigation
- Game's `Attacks/Reload` format confirmed via ODMG module: `p1:Send("Attacks", "Reload", Modules.Zones.Refill_Station)` — FireServer, not InvokeServer
- Game's `Spears/S_Fire` format confirmed: `p1:Invoke("Spears", "S_Fire", p4.Spear.Name)` — the name is the slot number (e.g. "1", "3", "5", "7")
- Game's `Spears/S_Explode` format confirmed: `p1:Send("Spears", "S_Explode", v22, Modules.Zones.Time_Difference)` — FireServer with position + timeDiff
- Game's `Hitboxes/Register` format confirmed: `p1:Send("Hitboxes", "Register", p13, BV.Velocity.Magnitude, t.Time_Difference)` — scalar velocity, NOT vector
- `GET_2` RemoteFunction discovered in Remotes folder — not referenced in any decompiled scripts
- Spear storage: `Rig/*LowerArm/Spears/{1..8}` with `GetAttribute("Used") == nil` = available
- `Modules.Zones.Refill_Station` = property set by Zones module (BasePart)

## v4 — 2026-07-05

### Changes
1. **Hitboxes/Register now matches real game format** — Changed from sending `damageRoll(625, 850)` as 4th arg to sending `(velocityMagnitude, timeDifference)`, matching the real game's call: `p1:Send("Hitboxes", "Register", p13, BV.Velocity.Magnitude, t.Time_Difference)`. The game server calculates damage based on velocity, not a hardcoded value. Added `getHitboxArgs()` helper that:
   - Reads `root.AssemblyLinearVelocity.Magnitude` for velocity
   - Tracks time since last hitbox call (`tick() - _lastHitboxTime`)
   - Adds subtle noise to both values
   - Clamped to 0.05–2.0s range for timeDiff

2. **Spears/S_Fire now uses spear slot from rig** — Changed from sending `tostring(currentAmmo)` (ammo count like "3") to `getCurrentSpearSlot()` which scans the character rig for un-used spear instances (`GetAttribute("Used") == nil`). The game's actual call is `InvokeServer("Spears", "S_Fire", p4.Spear.Name)` where the name is the slot number (e.g. "1", "3", "5", "7"). The old approach sent the ammo count (e.g. "3") which is a DIFFERENT value and could fire the wrong (empty) slot.

3. **Spears/S_Explode now sends timeDiff as 4th arg** — The real game sends `p1:Send("Spears", "S_Explode", v22, Modules.Zones.Time_Difference)` (position + time difference). Added time difference to both S_Explode call sites.

4. **Mastery combo tracking removed** — Removed `masteryComboIndex` counter and its nil-padding in Hitboxes/Register. The server's combo tracking is based on the time difference between hits, not a manually managed index.

### Investigation
- Game's `Hitboxes/Register` format confirmed via decompiled Zones module: `(hitPart, BV.Velocity.Magnitude, t.Time_Difference)`
- Game's `Spears/S_Explode` format confirmed via decompiled Spears module: `("Spears", "S_Explode", position, Modules.Zones.Time_Difference)`
- Game's `Spears/S_Fire` format confirmed: `("Spears", "S_Fire", spearName)` where spearName is the slot name (e.g. "1", "3", "5", "7")
- Spear storage: LeftLowerArm.Spears = slots 1,3,5,7 / RightLowerArm.Spears = slots 2,4,6,8
- Each spear instance has `Used` attribute; nil = ready, true = consumed
- `Time_Difference` in the game is set by Input module: `tick() - Slash.Last` (time between slash releases)
- Server handler for S_Fire sets `Character:SetAttribute("Current_Spear", spearName)` after successful fire

### Notes
- `damageRoll()` is preserved in `_hum` engine but no longer used for remote calls (only available for other purposes)
- `getHitboxArgs()` and `getCurrentSpearSlot()` are defined early in the script (post-V3_ZERO, pre-GetPlayerData)

## v3 — 2026-07-05 (Previous)

### Changes
1. **Fixed 4th argument to Hitboxes/Register** — The game server REQUIRES a 4th argument after `nape`. Without it, hit registration is rejected silently (no damage). Changed from 3-arg format to 4-arg with `getgenv()._hum.damageRoll(625, 850)`. Uses Gaussian distribution via `_hum.damageRoll()` instead of uniform `math.random()` for reduced detectability.

2. **Fixed blade reload detection** — Changed from `Blade_1.Transparency == 1` (unreliable) to scanning ALL blade pairs (1-7) for `GetAttribute("Broken") == nil`, matching the game's native `Blade_Check` logic. If ALL blades are broken AND spare sets exist → calls `getRemote:InvokeServer("Blades", "Reload")`.

3. **Attack cooldown raised to 1.6s minimum** — Default changed from 1s to 1.6s. All code paths that set `AttackCooldown` now enforce `math.max(1.6, ...)`. Added UI slider (`AttackCooldownSlider`, min=1.6, max=5, step=0.1).

4. **Fixed `_hum` access pattern** — Changed `_hum.xxx()` to `getgenv()._hum.xxx()` in 4 locations. The testing script and main script use different global access patterns. In many executors, `getgenv()` and bare `_G` are separate tables.

### Investigation
- Game remote map documented in `data/REMOTE_MAP.md`
- All remote call patterns verified against decompiled client scripts
- Blade inventory structure (Left_1..3, Right_1..3 with `Used` attribute) documented
- Attach remote format discovered: `("Hitboxes", "Register", nape, velocityMagnitude, timeDifference)`

### Notes
- The `_rateGate` function is defined but never called (dead code since Instance metatables can't be wrapped)
- The `_hum` engine merges safely as a `getgenv()` global table
