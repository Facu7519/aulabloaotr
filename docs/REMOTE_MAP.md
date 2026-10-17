# AOT:R Remote Map

> Investigated: 2026-07-05 via Cobalt spy + decompiled game code + live instance inspection
> Re-validated: 2026-10-12 via Real MCP localized decompile (Place 14012874501 Trost,
> PlaceVersion 5710). Router unchanged: GET + POST + GET_2. Modules.Waves.Market.Buy
> fully decompiled — corrected contract + client-side validation chain below.
> v8.1: decompiled `Core.ODMG` — speeds Default=300/Nuke=450 (script hover capped 260),
> M1 frames Floor 13/30s–Air 11/30s–Spear 35/60s. NO client-side attack-cooldown
> constant found (server-side silent reject) → 1.6s floor is conservative heuristic.
> Re-validated: 2026-10-17 via Real MCP (LOBBY Place 14916516914, PV9150): the
> player-save endpoint moved to `Functions/Keybinds`; `Equipment.Delete` contract,
> save shapes, rarity catalogs and the Secret→Mythic retier documented below.
> Game Version: Place 14012874501 (Trost), PlaceVersion 5710

## Remote Architecture

```
ReplicatedStorage
└── Assets
    └── Remotes
        ├── GET   (InvokeServer) — bidirectional, returns data
        ├── POST  (FireServer)   — fire-and-forget, server-side
        └── GET_2 (InvokeServer) — nuevo, no referenciado en scripts (⚠️ posible honeypot)
```

> ⚠️ **GET_2**: Se detectó un tercer RemoteFunction no documentado en la carpeta Remotes. No aparece en ningún script decompilado del juego. Posible trampa de anti-cheat (honeypot) o remote legacy. NO USAR sin investigación.

The Actor/Client uses a wrapper:
- `p1:Send(path1, path2, ...)` → `postRemote:FireServer(path1, path2, ...)`
- `p1:Invoke(path1, path2, ...)` → `getRemote:InvokeServer(path1, path2, ...)`

## Attack Remotes

### `POST:Attacks/Slash` — Blades attack
```
FireServer("Attacks", "Slash", true)
```
- 3rd arg: `true` (seems to request attack validation)
- Used for both normal attack and shifted punch

### `POST:Hitboxes/Register` — Register hit on titan (CRITICAL)
```
Send("Hitboxes", "Register", hitPart, velocityMagnitude, timeDifference)
```
- `hitPart`: The touched part from `Hitbox.Touched` (usually a Nape/Body part)
- `velocityMagnitude`: `BV.Velocity.Magnitude` — player's velocity at impact (damage scales with speed!)
- `timeDifference`: Internal frame delta timer from the Zones module
- ⚠ The client does NOT send a hardcoded damage value. Damage is SERVER-SIDE based on velocity.
- ⚠ Legacy scripts (Titanic Hub) send `math.random(625, 850)` as 4th arg. The server MAY accept it as velocity or fallback.

### `POST:Attacks/Slash_Escape` — Escape from titan grab
```
FireServer("Attacks", "Slash_Escape")
```

### `POST:Attacks/Reload` — Full refill (teleport)
```
FireServer("Attacks", "Reload", refillStationPart)
```
- `refillStationPart`: A BasePart inside `workspace.Unclimbable.Reloads.GasTanks.Refill` or similar
- This TELEPORTS the player to the refill station and restocks blades + gas

### `GET:Blades/Reload` — Blade reload (R key, in-field)
```
InvokeServer("Blades", "Reload")
```
- Returns `true` if reload succeeded
- Reloads the active blade pair from your remaining blade inventory (sets)
- Does NOT teleport; works anywhere as long as you have spare blade sets
- Does NOT refill gas

### `GET:Blades/Drop` — Drop current blades
```
InvokeServer("Blades", "Drop")
```

### `GET:S_Skills/Usage` — Use shifter skill
```
InvokeServer("S_Skills", "Usage", skillId, boost_arg)
```
- Used for shifter (titan) skills
- The original script wraps it as `getRemote:InvokeServer("S_Skills", "Usage", "999", false)` for mastery

### `POST:S_Skills/Impact` — Skill impact
```
Send("S_Skills", "Impact", skillId, position)
```
- Registers a skill impact at a world position

## Utility Remotes

| Remote | Type | Args | Purpose |
|--------|------|------|---------|
| `Functions/Keybinds` | GET | none | **Full player save** (Slots/Perks/Artifacts/Currency…) — v8.5. `Functions/Settings` now returns zero values (legacy fallback only) |
| `Functions/Teleport` | GET/POST | via Send | Teleport to lobby |
| `Functions/Retry` | GET | "Add" | Retry mission |
| `Functions/Ragdoll` | POST | force | Ragdoll player |
| `Data/Copy` | GET | none | Get match data (consumed at join by `Core.Lobby.Loader`; not reliably re-callable) |
| `Stats/Get` | GET | none | Get stats |
| `Stats/Gas_Supply` | POST | gasPart | Gas supply interaction |
| `Functions/Auto_Sell` | GET | category, name, bool | Game's own auto-sell config; returns new `Auto_Sell` table |

## Lobby Save, Catalogs & Equipment (v8.5 — live audit 2026-10-17 @ Place 14916516914 PV9150)

### Save endpoint & shapes

```
GET: InvokeServer("Functions", "Keybinds")   -- no args -> full save
```

- Returns `Slots[A/B/C]` plus top-level `Current_Slot`, `Settings`, `Spins`,
  `Auto_Sell`, `Tutorial`, `T_Perks`. Table names still say "Keybinds" (game
  quirk) — verified live 4/4 with spaced calls, not a rate-limit artifact.
- `("Functions","Settings")` returns **zero values** (dead since the 2026-10
  update) — kept only as legacy fallback in the script.
- `("Data","Copy")` is consumed in a loop by `Core.Lobby.Loader` at join; do not
  rely on it being re-callable later. In the lobby, use Keybinds.

```
Slots[X].Perks       = { Storage = {uuid -> {Name, Level, XP}}, Equipped = {Slot -> uuid}, Amount, Redo }
Slots[X].Artifacts   = { Storage = {uuid -> {Name, Stats, Locked}}, Equipped = {Body/Head -> {Vanity, ID}}, Amount, Check, Redo }
Slots[X].Upgrades    = { Blades = {...}, Spears = {...} }
Slots[X].Currency    = { Gold, Gems, Canes, Shards }
Slots[X].Progression = { Prestige, Level, XP, Max_XP }
```

- Storage entries carry **no Rarity** — resolve by `Name` against the catalogs.
- `Artifacts.Locked = {statLocks…}` = per-stat **reroll** locks (decompiled
  `Artifact_Roll`: `Locked[k] == false` → "Are you sure you want to roll a good
  stat?"; both true → "Artifact stats are locked!"). NOT a sell guard —
  27/27 sampled entries carry it, mostly `[false,false]`.
- The ONLY sell guard is equip state: `Equipped{Body/Head}.ID` (artifacts) /
  `Equipped[Slot]` (perks). Game UI: "Cannot sell an equipped item!".

### Rarity catalogs (client-readable, authoritative)

| Path | Shape |
|------|-------|
| `Modules.Storage.Perks` | `{Common/Rare/Epic/Legendary/Mythic -> name -> {Type, Stats{Stat={Base,Increment}}}}` |
| `Modules.Storage.Items` | `name -> {Rarity, Image, …}` — includes artifacts; rarity values seen: Common/Uncommon/Rare/Epic/Legendary/Mythic/Exclusive |
| `Modules.Storage.Artifacts` | artifact structure (`Slot/Passives/Stats`); **no rarity** — use `Storage.Items` by Name |

- **Secret→Mythic retier (2026-10)**: the old "Secret" perk tier is now
  **Mythic** — same 14 names (live-verified 14/14). The hub's static map still
  labels them "Secret" on purpose: v8.4 intent is *never sold*, opt-in only.
- Live counts 2026-10-17: Common 9 / Rare 12 / Epic 20 / Legendary 23 /
  Mythic 14 (78 unique names; all 68 perk names in the audited save resolved).

### `GET: S_Equipment/Delete` — sell perks/artifacts (decompiled)

```
InvokeServer("S_Equipment", "Delete", Type, {id1, id2, ...})
```

- `Type`: `"Perk"` | `"Artifact"` (singular).
- Payload: array of **IDs** — the `Storage` dict keys (same value as the UI
  frame's `GetAttribute("ID")`). NOT the entry tables.
- The game batches the WHOLE selection into one call (can be hundreds of ids).
- Returns the **new full save** (assign to `Cache.Data`; `Topbar.Refresh`).
- Client-side guards: empty selection + equipped items (checked at select time).
- Hub helpers `_G.AOTR.deletePerk/deleteArtifact` take that id array directly.

### `GET: S_Equipment/Perk_State` & `Artifact_State` — equip/unequip

```
InvokeServer("S_Equipment", "Perk_State", id, "Equip"|"Unequip", Category)
InvokeServer("S_Equipment", "Artifact_State", id, "Equip"|"Unequip", Category)  -- Category: Head|Body
InvokeServer("S_Equipment", "Artifact_Vanity", Category)                        -- -> save, ?, bool
```

- `Artifact_State` returns `save, rarity, image, …` (Equip appends appearance
  data: `v6 == true, v7` → add cosmetic). Assign first return to `Cache.Data`.

### Client architecture (where the game's own code lives)

- Game client tree: `Workspace.Characters.<name>.Actor.Client` (LocalScript) →
  `require(Actor.Client.Host)`. `Host:Invoke` = `GET:InvokeServer` (re-entrancy
  mutex on `.Invoked`); `Host:Send` = `POST:FireServer`. Server pushes the save
  via `Modules.Core.Update.Data`; read with `Update.Get_Data`.
- UI modules: `Modules.User Interface.*`. Machinery screens are **nested** under
  `Equipment` (child ModuleScripts): Hotbar, Perk, Enhance, Perking, Craft,
  Prestige, Artifact, Delete, Mastery, Skill, Shifter, Details, Loadouts,
  Configure, Edit, Dice. A depth-1 tree walk misses them (Host registers via
  `GetDescendants`) — decompile by full path, e.g.
  `Modules.User Interface.Equipment.Delete`.
- Game's own Auto_Sell UI: `Modules.User Interface.Auto_Sell` →
  `("Functions","Auto_Sell", category, name, bool)` → new `Auto_Sell` table →
  stored at `Cache.Data.Auto_Sell`.

## Blade System

### Rig Structure
```
Character
└── Rig_<PlayerName>
    ├── LeftHand
    │   ├── Blade_1 (MeshPart) — Blade_1 to Blade_7
    │   └── ...
    └── RightHand
        ├── Blade_1 (MeshPart)
        └── ...
```

### Blade States
- **Fresh**: No `Broken` attribute (`Broken == nil`), Transparency = 0
- **Broken**: `GetAttribute("Broken") == true`, needs reload
- **Removed**: Blade Instance is destroyed/removed when fully consumed

### Blade Inventory
```
Character
├── Left_1 (MeshPart) — Used == nil (available) or Used == true (consumed)
├── Left_2 (MeshPart)
├── Left_3 (MeshPart)
├── Right_1 (MeshPart)
├── Right_2 (MeshPart)
└── Right_3 (MeshPart)
```
- 3 blade sets total
- Each set = Left_i + Right_i pair
- `Used == nil` = fresh set available
- `Used == true` = set consumed

### HUD for Blades
```
PlayerGui.Interface.HUD.Main.Top.7
├── Hotbar (Frame)
├── Blades (Frame) — visible when blades equipped
│   ├── Outer (ImageLabel) — bg
│   ├── Inner (ImageLabel) — durability
│   │   └── Bar (CanvasGroup) — durability bar
│   └── Sets (TextLabel) — "2 / 3" (current / total sets)
├── Spears (Frame)
└── Gas (Frame)
```

### Blade Check (game's native function)
```lua
-- Returns (true, rig, leftBlade, rightBlade) if unbroken blades exist
for i = 7, 1, -1 do
    local bl = LeftHand:FindFirstChild("Blade_" .. i)
    local br = RightHand:FindFirstChild("Blade_" .. i)
    if bl and br and bl:GetAttribute("Broken") == nil then
        return true  -- Found unbroken pair
    end
end
return nil  -- All broken
```

## Spear System

### Spear Remote
```
GET:Spears/S_Fire — InvokeServer("Spears", "S_Fire", slotIndex)
POST:Spears/S_Explode — FireServer("Spears", "S_Explode", position)
```

### Spear Ammo
```
PlayerGui.Interface.HUD.Main.Top.7.Spears.Spears
```
- Text format: `"N / M"` where N = current, M = max
- Spears rotate sides; each side has specific slots

## Hitbox System
- The game uses a `Hitbox` part (CanTouch=true) connected to `Touched` events
- When `Hitbox` touches a part whose parent is named `"Hit"`, it registers the hit
- The touched part is inside `TitanModel.Hitboxes.Hit.[BodyPart]`

## Waves Remotes (Waves Mode Only)

### `POST:Waves/Update` — Vote to continue/skip
```
FireServer("Waves", "Update")
```
- Used to vote when the vote UI appears (Phase = "Skip" or "Continue")
- The Waves module calls this in `t.Vote()` when `t.Voted ~= true`

### `GET:Waves/Upgrade` — Buy HQ upgrades
```
InvokeServer("Waves", "Upgrade", { upgradeName })
```
- `upgradeName`: One of "Max", "Regen", "Replenish", "Refills"
- "Revive" is a special upgrade (revives all dead teammates on next boss wave)
- Cost is in Waves gold, deducted server-side

### `GET:Equipment/Upgrade` — Upgrade gear stats in Waves
```
InvokeServer("Equipment", "Upgrade", { statName1, statName2, ... })
```
- Can batch multiple stats in one call
- Valid stats: ODM_Damage, ODM_Control, ODM_Gas, ODM_Speed, Blade_Durability, ODM_Range, TS_Damage, TS_Control, TS_Range, TS_Gas, TS_Speed, Blast_Radius, Crit_Damage, Crit_Chance
- Different from lobby's `S_Equipment/Upgrade` (which only accepts 8 blade stats)

### `GET:Waves/Blessing` — Roll or lock blessings
```
InvokeServer("Waves", "Blessing", "Spin")      -- Roll new blessings
InvokeServer("Waves", "Blessing", "Lock", category)  -- Lock a blessing category
```

### `GET:Waves/Item` — Buy items from market
```
InvokeServer("Waves", "Item", "Buy", category, itemID, quantity)
InvokeServer("Waves", "Item", "Lock", category, itemID, 1)
```
- Categories: Perks, Artifacts, Memories, Shifting, Blessings, Skills

### `GET:Waves/Revive` — Revive dead teammates
```
InvokeServer("Waves", "Revive")
```
- Only useful in multiplayer waves

### Waves Crates — Supply crates on map
```
workspace.Waves.Crates.Crate_<PlayerName>.Hitbox
```
- Each player gets a personal crate in the Waves zone
- Crate model has `Beam`, `Box`, `Hitbox` (with TouchInterest), `Floor`, `Spot` parts
- **Server-side collection**: When player's character touches `Hitbox`, server handles collection automatically via Touched event — no remote needed
- For script auto-collect: teleport to `Hitbox.Position + Vector3(0, 5, 0)` and use `firetouchinterest(root, hitbox, 0/1)` to simulate touch

### `GET:Waves/Item` — Buy/Lock market items (v8 CORRECTED)
```
InvokeServer("Waves", "Item", "Buy", Category, Item.ID, quantity)
InvokeServer("Waves", "Item", "Lock", Category, ID, 1)
```
- **v8 correction**: the old script sent `("Waves", "Buy", itemId, qty)` — wrong module
  AND wrong shape. Decompiled `Market.Buy` (line ~246): `a1:Invoke("Waves", "Item",
  "Buy", Category, Item.ID, v6)`. Module is `"Waves"`, func is `"Item"`, then
  `"Buy"` as 3rd arg.
- **Item.ID is the entry's `ID` attribute** (`GetAttribute("ID")`), NOT the instance Name.
- **Game's client-side validation chain** (mirror before sending — server rejects otherwise):
  1. Entry exists in current rotation (`Get_Item` by ID; else "not in rotation")
  2. `Stock > 0` (else "No stock left!" / "Not enough stock!")
  3. `Locked == nil` (locked items can't be bought — buy the unlock instead)
  4. Template not already Sold (`Sold.Visible == false`)
  5. `Price * qty <= Loadout.Gold` (else "You do not have enough Gold!")
  6. `Loadout.Capacity + qty <= 1000` (else "Your inventory is full!")
- Lock costs 20% of item price. Categories: Perks, Artifacts, Memories, Shifting.
- Item abbreviations for notify: Perks→"perk", Artifacts→"artifact", Memories→"memory", Shifting→"item".

### Waves Items Structure (v7.0 Discovery)
```
workspace.Waves.Items
├── Perks/
│   ├── 1="Experimental Shells", 2="Mangle", 3="Flawed Release", ...
│   └── 8="perk Crate"
├── Artifacts/
│   ├── 1="Ring", 2="Lantern", 3/4/7="Glasses", ...
│   └── 8="artifact Crate"
├── Memories/
│   ├── 1..6 = skill memory IDs (e.g. "9", "1", "13")
│   └── 7="memory Crate"
└── Shifting/
    ├── 1="Attack Serum", 2="Attack Shard", 3="Armored Serum", ...
    └── 8="Colossal Shard"
```

### Waves Injury System (v7.0 Discovery)
- Injuries folder (`char.Injuries`) has 6 types: Gear, Arm, Leg, Ribcage, Eyes, Head
- Server adds injuries to the char; `Modules.Core.Injuries` handles debuffs client-side
- Removal happens via `ChildRemoved` → `Remove()` in Injuries module, OR when `Active` attribute goes false
- `workspace.Waves.Props.Injury` zone exists for healing (touch-based interaction)
- Game has no dedicated heal remote — injuries are healed via zone interaction or naturally

### Waves NPCs (v7.0 Discovery)
```
workspace.Waves.NPCs
├── Lulu    (Market vendor?)
├── Orange  (Utility vendor?)
├── Youmii  (Equipment vendor?)
├── Roll    (Spin/Crate vendor)
└── Cole    (Unknown vendor)
```

## Notes for Script Implementation
1. `Hitboxes/Register` requires velocity for damage calculation — using `root.AssemblyLinearVelocity.Magnitude` is acceptable. When hovering (velocity ~0), floor to 55-80 minimum so damage still registers.
2. Blade reload (`Blades/Reload`) must be called when ALL 7 Blade_N pairs have `Broken == true`, matching the game's `Blade_Check` which iterates 7→1.
3. Full refill (`Attacks/Reload`) teleports to the nearest refill station via FireServer (POST), NOT InvokeServer (GET).
4. The attack cooldown should never go below 1.6s to avoid spam detection. With jitter: 0.45-0.70s for blades, 1.0-1.25s for spears.
5. Blade detection via `Broken` attribute is more reliable than Transparency checks.
6. **Rig structure**: `Rig_<playerName>` model has `LeftHand`, `RightHand`, `LowerTorso`(x2) — `LeftLowerArm`/`RightLowerArm` are in the **character root**, NOT inside Rig_. The game's `S_Fire` searches Rig_ but the arms only exist there when spears are equipped. Script must fallback to `char:FindFirstChild()`.
7. **Blade inventory**: `Rig_<name>.LowerTorso.{Left_1..3, Right_1..3}` with `Used` attribute (nil=available, true=consumed).
8. **Waves mode**: Uses `Equipment/Upgrade` (NOT `S_Equipment/Upgrade`) for gear stats. Uses `Waves/Upgrade` for HQ upgrades. All Waves remotes are in the same GET/POST architecture.
9. **Wave Counter**: `Objectives.Waves` is HQ health percentage (always shows 100/100). The actual wave progress is in `Objectives.Clearance` where `Value+1` = current wave, `Requirement+1` = total waves. HUD displays as "Waves Cleared [X/Y]".
