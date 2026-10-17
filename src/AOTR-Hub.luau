-- aotr — Reverse Engineering T Hub (v8.5)
-- CONTENTS (search these anchors):
--   §BOOT      services/remotes/Endpoints catalog/safeInvoke+safeFire/probe
--   §VALID     Validators (char/root/humanoid/nape/refillPart/marketBuy)
--   §HUMAN     Irwin-Hall humanization + verified game speeds + cooldown policy
--   §CONFIG    Settings/getgenv flags + persistent dropdown config + session stats
--   §API       _G.AOTR helpers (market/equipment/inventory/mission/sell/trade)
--   §FARM      AutoFarm:Start (checkReady/updateCharState/targeting/movement/attack) + watchdog
--   §SURVIVE   healInjuries/hasInjuries (zone-only), AutoEscape, crash detection, rejoin
--   §COMBAT    reload/refill (getRefillPart+Waves), blades/spears, noclip
--   §UI        Obsidian tabs (Farm/Utils/Configs/Upgrades/Waves/Visuals/Global/Stats/Settings)
--   §MAPS      AutoStart/Create/Leave, boosts, modifiers, retry, return-lobby
--   §WAVES     vote/HQ/gear/blessings/revive/crates/market-buy/market-lock/ESP
--   §EXTRAS    sell/achievements/artifacts/shifters/loadouts (background-only per Foco)
-- Foco: CORE = farm→mapas→mejoras→supervivencia→antidetección (ver AGENT.md).
repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local lp = Players.LocalPlayer 

-- In lobby, character may not exist - wait max 10s then continue
local charWaitStart = os.clock()
repeat task.wait(0.5) until (lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")) or os.clock() - charWaitStart > 10

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local remotesFolder = game:GetService("ReplicatedStorage"):WaitForChild("Assets"):WaitForChild("Remotes")
local getRemote = remotesFolder:WaitForChild("GET")
local postRemote = remotesFolder:WaitForChild("POST")
local vim = game:GetService("VirtualInputManager")
local INTERFACE = PlayerGui:WaitForChild("Interface")
local rewards = INTERFACE:FindFirstChild("Rewards")
local statsFrame = rewards and rewards.Main.Info.Main.Stats or nil
local itemsFrame = rewards and rewards.Main.Info.Main.Items or nil
local customisation = INTERFACE:FindFirstChild("Customisation") or nil
local familyFrame = customisation and customisation:FindFirstChild("Family") or nil
local rollButton = familyFrame and familyFrame.Buttons_2.Roll or nil

local V3_ZERO = Vector3.new(0, 0, 0)

-- ==========================================
-- REMOTE ENDPOINT CATALOG (runtime reference)
-- ==========================================
local Endpoints = {
	GET = {
		Functions = {"Settings","Keybinds","Layout","Quest","Join","Tier","Tutorial","Battlepass","Active_Server","Rejoin","Select","Finished","Auto_Sell","Get"},
		Data = {"Copy","Reset"},
		S_Equipment = {"Upgrade","Enhance","Weapon","Forge","Buy","Skill_State","Perk_State"},
		S_Inventory = {"Item","Equip","Unequip"},
		S_Missions = {"Kick","Start","Create","Leave","Join","Modify"},
		Regiments = {"CreateRegiment","EditRegiment","DonateSilver","LeaveRegiment","ResetUpgrades","GetLeaderboardCache","SwitchOwnership"},
		Leaderboards = {"Get"},
		S_Market = {"Get","Buy","Gift"},
		S_Achievements = {"Claim","State","Category"},
		S_Trade = {"Info","Item","State","End"},
		S_Rewards = {"Get"},
		S_Skills = {"Usage"},
		Waves = {"Item","Buy","Lock","Upgrade","Blessing","Spin","Revive"},
		Cannon = {"State","Shoot"},
		Spears = {"S_Fire"},
		Blades = {"Reload"},
	},
	POST = {
		Functions = {"Teleport","Rejoin","Switch"},
		S_Equipment = {"Is_Rolling"},
		Invites = {"State","Invite"},
		S_Trade = {"Review"},
		Attacks = {"Slash","Reload","Slash_Escape"},
		Hitboxes = {"Register"},
		Spears = {"S_Explode"},
		S_Skills = {"Impact"},
		Waves = {"Update"},
	}
}

local function listEndpoints(direction)
	local ep = Endpoints[direction or "GET"]
	local lines = {}
	for module, funcs in pairs(ep) do
		table.insert(lines, module .. ": " .. table.concat(funcs, ", "))
	end
	return table.concat(lines, "\n")
end

-- Safe remote call wrappers (v8 hardened: remotes-exist guard + GET_2 block)
-- GET_2 is a suspected honeypot (not referenced in any decompiled game script).
-- NOTHING in this script may touch it; safeInvoke refuses it loudly.
local function remotesReady()
	return getRemote ~= nil and getRemote.Parent ~= nil
		and postRemote ~= nil and postRemote.Parent ~= nil
end
local remoteCallCache = {}
local function canCall(key, cooldown)
	cooldown = cooldown or 0.05
	local now = tick()
	local last = remoteCallCache[key] or 0
	if now - last >= cooldown then
		remoteCallCache[key] = now
		return true
	end
	return false
end

local function safeInvoke(module, func, ...)
	if module == "GET_2" then
		warn("[AOTR] blocked call to suspected honeypot GET_2 (" .. tostring(func) .. ")")
		return nil
	end
	if not remotesReady() then return nil end
	local args = { ... }
	if not canCall(module .. "." .. func, 0.1) then return nil end
	local ok, result = pcall(function()
		return getRemote:InvokeServer(module, func, unpack(args))
	end)
	return ok and result or nil
end

local function safeFire(module, func, ...)
	if not remotesReady() then return end
	local args = { ... }
	if not canCall(module .. "." .. func .. "_fire", 0.05) then return end
	pcall(function()
		postRemote:FireServer(module, func, unpack(args))
	end)
end

-- Quick endpoint probe (test if a remote responds)
local function probeEndpoint(module, func, ...)
	local args = { ... }
	local ok, result = pcall(function()
		return getRemote:InvokeServer(module, func, unpack(args))
	end)
	return ok, result
end

-- Probe all GET endpoints in a module (returns list of working funcs)
local function probeModule(module, args)
	args = args or {}
	local working = {}
	for _, func in ipairs(Endpoints.GET[module] or {}) do
		local ok, res = probeEndpoint(module, func, unpack(args))
		if ok then
			table.insert(working, func .. (res ~= nil and " (ok)" or " (nil)"))
		else
			table.insert(working, func .. " (error)")
		end
		task.wait(0.2)
	end
	return working
end

-- ==========================================
-- VALIDATORS (v8) — every remote call site must pass these first.
-- Nil-guards for char/root/humanoid/parts; decompiled-contract checks
-- for Market.Buy (Modules.Waves.Market.Buy, PlaceVersion 5710).
-- ==========================================
local Validators = {}

function Validators.char()
	local c = lp.Character
	if not c or not c.Parent then return nil end
	return c
end

function Validators.root()
	local c = Validators.char()
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if not r or not r.Parent then return nil end
	return r
end

function Validators.humanoid()
	local c = Validators.char()
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if not h or not h.Parent then return nil end
	return h
end

-- Nape must still be in the world and belong to a living titan.
function Validators.nape(nape)
	if typeof(nape) ~= "Instance" or not nape:IsA("BasePart") then return nil end
	if not nape.Parent then return nil end
	local titan = nape.Parent.Parent and nape.Parent.Parent.Parent
	if titan and titan:IsA("Model") then
		if titan:GetAttribute("Dead") or titan:GetAttribute("Killed") then return nil end
	end
	return nape
end

function Validators.refillPart(part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return nil end
	if not part.Parent then return nil end -- stale cache (teleported map / new round)
	return part
end

-- Market.Buy client-side pre-validation, mirroring the game's own checks
-- (Market.Buy: Stock>0, Locked==nil, Gold>=Price*qty, Capacity+qty<=1000,
--  template not Sold). Returns (true) or (false, reason).
function Validators.marketBuy(category, itemId, qty)
	qty = tonumber(qty) or 1
	if qty < 1 then return false, "Invalid quantity" end
	if type(category) ~= "string" or type(itemId) ~= "string" then
		return false, "Category/ID must be strings (ID = GetAttribute('ID'))"
	end
	local waves = workspace:FindFirstChild("Waves")
	local items = waves and waves:FindFirstChild("Items")
	local folder = items and items:FindFirstChild(category)
	if not folder then return false, "Not in Waves market context" end
	local entry = nil
	for _, sv in ipairs(folder:GetChildren()) do
		if sv:GetAttribute("ID") == itemId then entry = sv break end
	end
	if not entry then return false, "Item not in rotation" end
	local stock = entry:GetAttribute("Stock") or 0
	if qty > stock then
		return false, (qty > 1 and "Not enough stock!" or "No stock left!")
	end
	if entry:GetAttribute("Locked") ~= nil then
		return false, "Item is locked (buy the unlock, not the item)"
	end
	return true, entry
end

-- ==========================================
-- HUMANIZATION (v8.1, ADR-002) — Irwin-Hall, NOT uniform math.random.
-- Uniform timing/speeds are the #1 farm-pattern tell: humans cluster around
-- a mean with bell-curve tails. irwinHall() ~ N(0,1) via 12x random.
-- Verified game speeds (decompiled Core.ODMG @ PV5710): Default=300,
-- Nuke=450. Script hover must live UNDER 300 to read as legit ODM play.
-- No client-side attack-cooldown constant exists in decompiled source
-- (spam check is server-side, silent reject): 1.6s floor stays as
-- conservative heuristic from the original author's live testing.
-- ==========================================
local function irwinHall()
	local s = 0
	for _ = 1, 12 do s += math.random() end
	return s - 6
end

-- Bell-curved wait around `mean` with ±`spread` covering ~±3 sigma.
local function humanWait(mean, spread)
	return math.max(0.01, mean + irwinHall() * (spread / 3))
end

-- Attack cooldown: heuristic floor 1.6s + human tail (never below floor).
local function attackCooldown()
	return 1.6 + math.max(0, irwinHall() * 0.15) + math.random() * 0.2
end

-- Human 3D drift noise (replaces uniform Vector3 noise in hot paths).
local function humanNoise(scale)
	scale = scale or 0.05
	return Vector3.new(irwinHall() * scale, irwinHall() * scale * 0.6, irwinHall() * scale)
end

local lastPlayerData, lastPlayerDataTime = nil, 0
local function GetPlayerData()
	if os.clock() - lastPlayerDataTime < 0.5 and lastPlayerData then return lastPlayerData end
	-- v8.5: the save moved to ("Functions","Keybinds") (live-verified 2026-10-17,
	-- place 14916516914 PV9150): full Slots/Perks/Artifacts/Currency. The old
	-- ("Functions","Settings") returns zero values now — kept as legacy fallback.
	lastPlayerData = safeInvoke("Functions", "Keybinds") or safeInvoke("Functions", "Settings")
	lastPlayerDataTime = os.clock()
	return lastPlayerData
end

local mapData = nil

local startLoadTime = os.clock()
local isLobby = game.PlaceId == 14916516914

if not isLobby then
	repeat
	    task.wait(1)
	    mapData = safeInvoke("Data", "Copy")
	    if not mapData then
	        lastPlayerData = nil
	        GetPlayerData()
	    end
	until mapData ~= nil or os.clock() - startLoadTime > 15
end

if mapData then
	if mapData.Map.Type == "Raids" then
		repeat task.wait() until workspace:GetAttribute("Finalised")
	end
end

local function checkMission()
	local activeType = workspace:GetAttribute("Type")
	if activeType then return true end
	mapData = getRemote:InvokeServer("Data", "Copy")
	return mapData ~= nil and mapData.Map ~= nil and mapData.Slots ~= nil
end

local familyRaritiesOptions = {
	"Rare",
	"Epic",
	"Legendary",
	"Mythical"
}

-- Config system for persistent dropdown state
if not isfolder("./THUB1") then makefolder("./THUB1") end
if not isfolder("./THUB1/aotr") then makefolder("./THUB1/aotr") end

local ConfigFile = "./THUB1/aotr/dropdown_config.json"
local returnCounterPath = "./THUB1/aotr/return_lobby_counter.txt"
local HttpService = game:GetService("HttpService")

local function LoadConfig()
	if not isfile(ConfigFile) then
		return { Missions = {}, Raids = {}, DeleteMap = false }
	end
	local success, config = pcall(HttpService.JSONDecode, HttpService, readfile(ConfigFile))
	return success and config or { Missions = {}, Raids = {}, DeleteMap = false }
end

local function SaveConfig(config)
	pcall(writefile, ConfigFile, HttpService:JSONEncode(config))
end

local DropdownConfig = LoadConfig()
getgenv().AutoExec = false
getgenv().AutoRoll = false
getgenv().AutoSlot = false
getgenv().AutoUpgrade = false
getgenv().AutoPerk = false
getgenv().AutoSkillTree = false
getgenv().AutoStart = false
getgenv().AutoChest = false
getgenv().AutoRetry = false
getgenv().AutoSkip = false
getgenv().AutoPrestige = false
getgenv().AutoFailsafe = false
getgenv().FailsafeMins = 15 -- v8.4: configurable failsafe timeout
getgenv().AutoExecute = false
getgenv().RewardWebhook = false
getgenv().MythicalFamilyWebhook = false
getgenv().AutoReturnLobby = false
getgenv().ReturnAfterGames = 10
getgenv().WaitBeforeStart = false
getgenv().WaitBeforeStartSecs = 0
getgenv().MultiHit = false
getgenv().MultiHitCount = 3
getgenv().LastTitanWait = false
getgenv().LastTitanWaitSecs = 60
getgenv().OpenSecondChest = false
getgenv().DeleteMap = false -- default OFF: never delete map on script execution
getgenv().AdminConfig = false
getgenv().HideDamageText = false
getgenv().TargetPriority = "Titans" -- Titans, Boss, None
if not isfile(returnCounterPath) then writefile(returnCounterPath, "0") end

-- v8: Settings table (ADR-005 pattern). Single entry point for config;
-- mirrors getgenv() so all existing references keep working. New code
-- should read/write Settings.X instead of scattering getgenv() flags.
local Settings = setmetatable({}, {
	__index = function(_, k) return getgenv()[k] end,
	__newindex = function(_, k, v) getgenv()[k] = v end,
})
-- NOTE: published as _G.AOTR.Settings where _G.AOTR is created (§API) —
-- _G.AOTR does not exist yet at this point, so do NOT index it here.

getgenv().CurrentStatusLabel = nil
function UpdateStatus(text)
	if getgenv().CurrentStatusLabel then 
		getgenv().CurrentStatusLabel:SetText("Status: " .. text) 
	end
end

-- ==========================================
-- SESSION STATS (defined first so everything can use it)
-- ==========================================

local function SaveSessionStats()
	writefile("./THUB1/aotr/s_games.txt",     tostring(sessionStats.gamesPlayed))
	writefile("./THUB1/aotr/s_gold.txt",      tostring(sessionStats.totalGold))
	writefile("./THUB1/aotr/s_gems.txt",      tostring(sessionStats.totalGems))
	writefile("./THUB1/aotr/s_xp.txt",        tostring(sessionStats.totalXP))
	writefile("./THUB1/aotr/s_mythicals.txt", tostring(sessionStats.mythicalDrops))
	writefile("./THUB1/aotr/s_crashes.txt",   tostring(sessionStats.crashes))
	-- Save elapsed time so timer pauses when script is off
	local elapsed = os.time() - sessionStats.startTime
	writefile("./THUB1/aotr/s_elapsed.txt",   tostring(elapsed))
end

local function LoadSessionStats()
	local function rf(path, default)
		if isfile(path) then
			return tonumber(readfile(path)) or default
		end
		return default
	end
	-- Resume timer from saved elapsed so time doesnt count when script is off
	local savedElapsed = rf("./THUB1/aotr/s_elapsed.txt", 0)
	return {
		startTime     = os.time() - savedElapsed,
		gamesPlayed   = rf("./THUB1/aotr/s_games.txt",     0),
		totalGold     = rf("./THUB1/aotr/s_gold.txt",      0),
		totalGems     = rf("./THUB1/aotr/s_gems.txt",      0),
		totalXP       = rf("./THUB1/aotr/s_xp.txt",        0),
		totalKills    = 0,
		mythicalDrops = rf("./THUB1/aotr/s_mythicals.txt", 0),
		crashes       = rf("./THUB1/aotr/s_crashes.txt",   0),
	}
end

sessionStats = LoadSessionStats()

-- Rate Limiter — flood control (v8: single implementation; canCallRemote
-- kept as alias so older call sites don't break)
getgenv()._lastHitboxTime = 0
getgenv()._lastFireTime = 0
getgenv()._lastRemoteCall = {}
local function canCallRemote(key, cooldown)
    return canCall(key, cooldown or 0.05)
end

-- Fatigue randomization — jitter for mimetic timing
local function getFatigue()
    return math.random(10, 50) / 1000  -- 10-50ms jitter
end


local function getSessionTime()
	local elapsed = os.time() - sessionStats.startTime
	local hours = math.floor(elapsed / 3600)
	local mins = math.floor((elapsed % 3600) / 60)
	local secs = math.floor(elapsed % 60)
	return string.format("%02d:%02d:%02d", hours, mins, secs)
end

local function getGoldPerHour()
	local elapsed = (os.time() - sessionStats.startTime) / 3600
	if elapsed < 0.01 then return 0 end
	return math.floor(sessionStats.totalGold / elapsed)
end

local function getGamesPerHour()
	local elapsed = (os.time() - sessionStats.startTime) / 3600
	if elapsed < 0.01 then return 0 end
	return math.floor(sessionStats.gamesPlayed / elapsed)
end

-- Helper: generate hitbox args matching game's format (velocity + timeDiff)
-- v8: validates nape (stale/dead-titan parts are rejected before sending,
-- which previously produced silent server rejects). Velocity floor 55-80
-- kept: hovering gives ~0 velocity which the server reads as 0 damage.
local function getHitboxArgs(nape)
    nape = Validators.nape(nape)
    if not nape then return nil end
    local hrp = Validators.root()
    local vel = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0
    vel = math.max(vel, math.random(55, 80))
    local timeDiff = tick() - (getgenv()._lastHitboxTime or tick())
    if timeDiff < 0.01 then timeDiff = 0.01 end
    if timeDiff > 2.0 then timeDiff = 1.5 + math.random() * 0.5 end
    getgenv()._lastHitboxTime = tick()
    local jitter = 1 + (math.random(-30, 30) / 1000)
    return nape, vel * jitter, timeDiff
end

-- Helper: get current spear slot name from rig (checks rig + char root)
local function getCurrentSpearSlot()
    local char = lp.Character
    if not char then return nil end
    local rig = char:FindFirstChild("Rig_" .. lp.Name)
    local searchRoots = {rig, char}
    for _, root in ipairs(searchRoots) do
        if not root then continue end
        for _, armName in ipairs({"LeftLowerArm", "RightLowerArm"}) do
            local arm = root:FindFirstChild(armName)
            if arm then
                local spears = arm:FindFirstChild("Spears")
                if spears then
                    for _, spear in ipairs(spears:GetChildren()) do
                        if spear:GetAttribute("Used") == nil then
                            return spear.Name
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- ==========================================
-- MARKET / WAVES / EQUIPMENT / INVENTORY HELPERS
-- Assigned to _G.AOTR to avoid exceeding Luau's 200-local limit at chunk scope
-- ==========================================

_G.AOTR = _G.AOTR or {}
_G.AOTR.Settings = Settings -- v8: single config entry point (see §CONFIG)

-- Waves market helpers (v8: contract confirmed vs decompiled
-- Modules.Waves.Market.Buy @ PlaceVersion 5710:
--   a1:Invoke("Waves", "Item", "Buy", Category, Item.ID, qty)
-- Item.ID is the entry's ID *attribute* (NOT the instance Name).
-- Client-side pre-checks mirror the game: Stock, Locked, Gold, Capacity.)
_G.AOTR.getWavesMarketItems = function()
    local waves = workspace:FindFirstChild("Waves")
    local items = waves and waves:FindFirstChild("Items")
    if not items then return {} end
    local result = {}
    for _, cat in ipairs(items:GetChildren()) do
        local catName = cat.Name
        result[catName] = {}
        for _, sv in ipairs(cat:GetChildren()) do
            -- v8: entries are usually StringValues but guard anyway (.Value
            -- throws on instances without that property)
            local val = nil
            pcall(function() val = sv.Value end)
            table.insert(result[catName], {
                id = sv:GetAttribute("ID") or sv.Name,
                name = (type(val) == "string" and val) or sv.Name,
                stock = sv:GetAttribute("Stock"),
                locked = sv:GetAttribute("Locked") ~= nil,
                price = sv:GetAttribute("Price"),
            })
        end
    end
    return result
end

_G.AOTR.buyWavesMarketItem = function(category, itemId, quantity)
    quantity = tonumber(quantity) or 1
    -- Backward compat: old callers passed (itemId, qty). Category required
    -- by the server; without it we refuse loudly instead of sending a
    -- malformed remote that flags the account.
    if type(itemId) == "number" or (type(category) ~= "string") or (type(itemId) ~= "string" and type(itemId) ~= "number") then
        warn("[AOTR] buyWavesMarketItem needs (category, id, qty)")
        return false, "Bad args: need (category, id, qty)"
    end
    if type(itemId) == "number" then itemId = tostring(itemId) end
    local ok, entryOrReason = Validators.marketBuy(category, itemId, quantity)
    if not ok then return false, entryOrReason end
    return safeInvoke("Waves", "Item", "Buy", category, itemId, quantity)
end

_G.AOTR.lockWavesSlot = function(slotId)
    return safeInvoke("Waves", "Lock", slotId) == true
end

_G.AOTR.upgradeWavesSlot = function(slotId, upgradeData)
    return safeInvoke("Waves", "Upgrade", slotId, upgradeData)
end

_G.AOTR.blessWavesItem = function(blessingData)
    return safeInvoke("Waves", "Blessing", blessingData)
end

_G.AOTR.spinWavesSlot = function(slotId)
    return safeInvoke("Waves", "Spin", slotId)
end

-- Equipment helpers (confirmed endpoints)
_G.AOTR.upgradeEquipment = function(equipmentId)
    return safeInvoke("S_Equipment", "Upgrade", equipmentId)
end

_G.AOTR.enhanceEquipment = function(id, materialIds)
    return safeInvoke("S_Equipment", "Enhance", id, materialIds)
end

_G.AOTR.forgeEquipment = function(tag, material)
    return safeInvoke("S_Equipment", "Forge", tag, material)
end

_G.AOTR.setWeapon = function(weaponData)
    return safeInvoke("S_Equipment", "Weapon", weaponData)
end

_G.AOTR.equipPerk = function(itemId, category)
    return safeInvoke("S_Equipment", "Perk_State", itemId, "Equip", category)
end

_G.AOTR.unequipPerk = function(itemId, category)
    return safeInvoke("S_Equipment", "Perk_State", itemId, "Unequip", category)
end

-- Additional equipment/automation helpers (confirmed endpoints)
_G.AOTR.deletePerk = function(items)
    return safeInvoke("S_Equipment", "Delete", "Perk", items)
end

_G.AOTR.deleteArtifact = function(items)
    return safeInvoke("S_Equipment", "Delete", "Artifact", items)
end

_G.AOTR.unlockSkill = function(skillId)
    return safeInvoke("S_Equipment", "Unlock", { skillId })
end

_G.AOTR.rerollPerk = function(itemId, mode)
    return safeInvoke("S_Equipment", "Replacing", mode, itemId)
end

_G.AOTR.equipArtifact = function(itemId, category)
    return safeInvoke("S_Equipment", "Artifact_State", itemId, "Equip", category)
end

_G.AOTR.unequipArtifact = function(itemId, category)
    return safeInvoke("S_Equipment", "Artifact_State", itemId, "Unequip", category)
end

_G.AOTR.rollArtifact = function(itemId, using)
    return safeInvoke("S_Equipment", "Artifact_Roll", itemId, using)
end

_G.AOTR.configureLoadout = function(category, name, name2)
    return safeInvoke("S_Equipment", "Loadout", "Configure", tonumber(category), name, name2)
end

_G.AOTR.updateLoadout = function(category)
    return safeInvoke("S_Equipment", "Loadout", "Update", tonumber(category))
end

-- Inventory helpers (confirmed endpoints)
_G.AOTR.useInventoryItem = function(itemName)
    return safeInvoke("S_Inventory", "Item", itemName)
end

_G.AOTR.equipItem = function(slot, itemId)
    return safeInvoke("S_Inventory", "Equip", slot, itemId)
end

_G.AOTR.unequipItem = function(slot)
    return safeInvoke("S_Inventory", "Unequip", slot)
end

-- Mission helpers (confirmed endpoints)
_G.AOTR.startMission = function()
    return safeInvoke("S_Missions", "Start")
end

_G.AOTR.kickFromMission = function(playerName)
    return safeInvoke("S_Missions", "Kick", playerName)
end

-- Sell / Market / Achievements / Trade helpers (confirmed endpoints)
-- Sell helper (v8: S_Inventory/Sell is UNCONFIRMED — never seen in decompiled
-- game source, only in prior analysis notes. Validated + rate-limited; if the
-- server rejects it, this returns nil instead of throwing into the UI loop.)
_G.AOTR.sellItem = function(tag, quantity)
    quantity = tonumber(quantity) or 1
    if type(tag) ~= "string" or tag == "" or quantity < 1 then
        return nil
    end
    return safeInvoke("S_Inventory", "Sell", tag, quantity)
end

_G.AOTR.claimAchievement = function(id)
    return safeInvoke("S_Achievements", "Claim", id)
end

_G.AOTR.getAchievementState = function(id)
    return safeInvoke("S_Achievements", "State", id)
end

_G.AOTR.tradeInfo = function(userId, kind)
    return safeInvoke("S_Trade", "Info", userId, kind)
end

_G.AOTR.tradeItem = function(typeName, id, listCategory, extra)
    return safeInvoke("S_Trade", "Item", typeName, id, listCategory, extra)
end

_G.AOTR.tradeState = function(typeName, extra)
    return safeInvoke("S_Trade", "State", typeName, extra)
end

_G.AOTR.tradeEnd = function()
    return safeInvoke("S_Trade", "End")
end

_G.AOTR.tradeReview = function(tradeId, accepted)
    return safeInvoke("S_Trade", "Review", tradeId, accepted)
end

_G.AOTR.sendInvite = function(playerName)
    return safeFire("Invites", "Invite", playerName)
end

_G.AOTR.inviteState = function(state)
    return safeFire("Invites", "State", state)
end

-- ==========================================
-- INJURY HEAL HELPER
-- ==========================================

local function healInjuries()
    local injuryProps = workspace:FindFirstChild("Waves") and workspace.Waves:FindFirstChild("Props") and workspace.Waves.Props:FindFirstChild("Injury")
    if not injuryProps then return false end
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    -- Touch all parts in Injury prop that have TouchInterest or are named heal-related
    for _, part in ipairs(injuryProps:GetDescendants()) do
        if part:IsA("BasePart") and (part:FindFirstChildOfClass("TouchTransmitter") or part.Name:lower():find("heal")) then
            firetouchinterest(root, part, 0)
            task.wait(0.1)
            firetouchinterest(root, part, 1)
            task.wait(0.2)
        end
    end
    return true
end

local function hasInjuries()
    local injuries = lp.Character and lp.Character:FindFirstChild("Injuries")
    if not injuries then return false end
    local count = 0
    for _ in ipairs(injuries:GetChildren()) do count = count + 1 end
    return count > 0, count
end

-- ==========================================
-- VISUALS / ESP HELPERS
-- ==========================================

-- ==========================================
-- VISUALS / ESP HELPERS (v8.3)
-- Reads config ONLY via getgenv (these helpers are defined before the UI
-- chunk, so they must not upvalue Options/Library). UI pickers sync into
-- getgenv on change; sane defaults set here.
-- ==========================================

getgenv().ESPTitanColor = getgenv().ESPTitanColor or Color3.fromRGB(255, 80, 80)
getgenv().ESPTitanMaxDist = getgenv().ESPTitanMaxDist or 2000
getgenv().ESPTitanTracers = getgenv().ESPTitanTracers or false
getgenv().ESPPlayerColor = getgenv().ESPPlayerColor or Color3.fromRGB(57, 255, 20)
getgenv().ESPPlayerMaxDist = getgenv().ESPPlayerMaxDist or 5000
getgenv().ESPPlayerMarkers = getgenv().ESPPlayerMarkers or true

local ESP_BOSS_NAMES = { Attack_Titan = true, Armored_Titan = true, Female_Titan = true, Colossal_Titan = true, Warhammer_Titan = true }

local espHighlights = {}
local espNameTags = {}
local espLines = {} -- { line = Drawing, part = BasePart }

local function espTitanColor()
	local c = getgenv().ESPTitanColor
	return typeof(c) == "Color3" and c or Color3.fromRGB(255, 80, 80)
end

local function clearESPTitans()
    for _, h in pairs(espHighlights) do
        if h and h.Parent then h:Destroy() end
    end
    table.clear(espHighlights)
    for _, n in pairs(espNameTags) do
        if n and n.Parent then n:Destroy() end
    end
    table.clear(espNameTags)
    for _, e in pairs(espLines) do
        pcall(function() e.line:Remove() end)
    end
    table.clear(espLines)
end

-- v8.3: label shows type + distance ("Titan • 123m", "Armored_Titan • 45m"),
-- never the raw GUID model name (was unaesthetic noise).
local function createESPTitan(titanModel, dist)
    if not titanModel then return end
    local nape = titanModel:FindFirstChild("Hitboxes") and titanModel.Hitboxes:FindFirstChild("Hit") and titanModel.Hitboxes.Hit:FindFirstChild("Nape")
    local hrp = titanModel:FindFirstChild("HumanoidRootPart")
    local fake = titanModel:FindFirstChild("Fake")
    local head = fake and fake:FindFirstChild("Head")
    local targetPart = nape or hrp or head
    if not targetPart then return end
    local col = espTitanColor()

    -- Highlight
    local highlight = Instance.new("Highlight")
    highlight.Name = "AOTR_ESP_Highlight"
    highlight.FillTransparency = 0.65
    highlight.OutlineTransparency = 0
    highlight.FillColor = col
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.Adornee = titanModel
    highlight.Parent = targetPart
    table.insert(espHighlights, highlight)

    -- NameTag (BillboardGui)
    local tag = ESP_BOSS_NAMES[titanModel.Name] and titanModel.Name or "Titan"
    if dist then tag ..= " • " .. math.floor(dist) .. "m" end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "AOTR_ESP_NameTag"
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 15, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = targetPart
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = tag
    label.TextColor3 = col
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard
    billboard.Parent = targetPart
    table.insert(espNameTags, billboard)
end

local function playerRoot()
	local c = lp.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function updateESPTitans()
    clearESPTitans()
    local titansFolder = workspace:FindFirstChild("Titans")
    if not titansFolder then return end
    local root = playerRoot()
    local rootPos = root and root.Position
    local maxDist = tonumber(getgenv().ESPTitanMaxDist) or 2000
    for _, titan in ipairs(titansFolder:GetChildren()) do
        if not titan:GetAttribute("Dead") and not titan:GetAttribute("Killed") then
            local hit = titan:FindFirstChild("Hitboxes") and titan.Hitboxes:FindFirstChild("Hit")
            local nape = hit and hit:FindFirstChild("Nape")
            if nape then
                local dist = rootPos and (rootPos - nape.Position).Magnitude or nil
                if not dist or dist <= maxDist then
                    createESPTitan(titan, dist)
                end
            end
        end
    end
end

-- Tracer lines (Drawing): bottom-center of screen → each living nape.
-- Separate 0.25s loop (billboards refresh slower); all calls pcall-guarded
-- so a missing Drawing lib degrades to no-lines instead of errors.
local function refreshTitanTracers()
	if not getgenv().ESPTitanTracers then return end
	local ok, cam = pcall(function() return workspace.CurrentCamera end)
	if not ok or not cam then return end
	local vs = cam.ViewportSize
	local from = Vector2.new(vs.X / 2, vs.Y)
	-- drop dead entries
	for i = #espLines, 1, -1 do
		local e = espLines[i]
		if not e.part or not e.part.Parent then
			pcall(function() e.line:Remove() end)
			table.remove(espLines, i)
		end
	end
	-- map existing by part
	local byPart = {}
	for _, e in ipairs(espLines) do byPart[e.part] = e end
	local maxDist = tonumber(getgenv().ESPTitanMaxDist) or 2000
	local root = playerRoot()
	local rootPos = root and root.Position
	local folder = workspace:FindFirstChild("Titans")
	if not folder then return end
	for _, titan in ipairs(folder:GetChildren()) do
		if titan:GetAttribute("Dead") or titan:GetAttribute("Killed") then continue end
		local hit = titan:FindFirstChild("Hitboxes") and titan.Hitboxes:FindFirstChild("Hit")
		local nape = hit and hit:FindFirstChild("Nape")
		if nape and (not rootPos or (rootPos - nape.Position).Magnitude <= maxDist) then
			if not byPart[nape] then
				local ok2, line = pcall(function() return Drawing.new("Line") end)
				if ok2 and line then
					line.Visible = true
					line.Thickness = 1
					line.Transparency = 0.7
					table.insert(espLines, { line = line, part = nape })
					byPart[nape] = espLines[#espLines]
				end
			end
		end
	end
	local col = espTitanColor()
	for _, e in ipairs(espLines) do
		pcall(function()
			local sp, onScreen = cam:WorldToViewportPoint(e.part.Position)
			e.line.Color = col
			e.line.From = from
			e.line.To = Vector2.new(sp.X, sp.Y)
			e.line.Visible = onScreen
		end)
	end
end

-- ============ PLAYER ESP (v8.3) ============
-- Deliberately louder than titan ESP: AlwaysOnTop highlight in neon color +
-- name/dist billboard + edge arrows for off-screen players.

local espPlayerHl = {}
local espPlayerTags = {}
local espPlayerArrows = {} -- { tri = Drawing, plr = Player }

local function espPlayerColor()
	local c = getgenv().ESPPlayerColor
	return typeof(c) == "Color3" and c or Color3.fromRGB(57, 255, 20)
end

local function clearESPPlayers()
	for _, h in pairs(espPlayerHl) do
		if h and h.Parent then h:Destroy() end
	end
	table.clear(espPlayerHl)
	for _, b in pairs(espPlayerTags) do
		if b and b.Parent then b:Destroy() end
	end
	table.clear(espPlayerTags)
	for _, e in pairs(espPlayerArrows) do
		pcall(function() e.tri:Remove() end)
	end
	table.clear(espPlayerArrows)
end

local function updateESPPlayers()
	clearESPPlayers()
	if not getgenv().ESPPlayers then return end
	local col = espPlayerColor()
	local root = playerRoot()
	local rootPos = root and root.Position
	local maxDist = tonumber(getgenv().ESPPlayerMaxDist) or 5000
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == lp then continue end
		local c = plr.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end
		local dist = rootPos and (rootPos - hrp.Position).Magnitude or nil
		if dist and dist > maxDist then continue end
		local hum = c:FindFirstChildOfClass("Humanoid")
		local tag = plr.DisplayName .. " • " .. (dist and (math.floor(dist) .. "m") or "?")
		if hum then tag ..= " • " .. math.floor(hum.Health) .. "hp" end
		local hl = Instance.new("Highlight")
		hl.Name = "AOTR_ESP_Player"
		hl.FillTransparency = 0.5
		hl.OutlineTransparency = 0
		hl.FillColor = col
		hl.OutlineColor = col
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = c
		hl.Parent = hrp
		table.insert(espPlayerHl, hl)
		local bb = Instance.new("BillboardGui")
		bb.Name = "AOTR_ESP_PlayerTag"
		bb.Size = UDim2.new(0, 220, 0, 40)
		bb.StudsOffset = Vector3.new(0, 8, 0)
		bb.AlwaysOnTop = true
		bb.Adornee = hrp
		local lb = Instance.new("TextLabel")
		lb.Size = UDim2.new(1, 0, 1, 0)
		lb.BackgroundTransparency = 0.4
		lb.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		lb.Text = tag
		lb.TextColor3 = col
		lb.TextStrokeTransparency = 0
		lb.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		lb.TextScaled = true
		lb.Font = Enum.Font.GothamBold
		lb.Parent = bb
		bb.Parent = hrp
		table.insert(espPlayerTags, bb)
	end
end

-- Edge arrows for off-screen players (same 0.25s cadence as tracers).
local function refreshPlayerArrows()
	if not getgenv().ESPPlayers or not getgenv().ESPPlayerMarkers then return end
	local ok, cam = pcall(function() return workspace.CurrentCamera end)
	if not ok or not cam then return end
	local vs = cam.ViewportSize
	local cx, cy = vs.X / 2, vs.Y / 2
	for i = #espPlayerArrows, 1, -1 do
		local e = espPlayerArrows[i]
		local c = e.plr.Character
		if not c or not c.Parent then
			pcall(function() e.tri:Remove() end)
			table.remove(espPlayerArrows, i)
		end
	end
	local byPlr = {}
	for _, e in ipairs(espPlayerArrows) do byPlr[e.plr] = e end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == lp then continue end
		local c = plr.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end
		if not byPlr[plr] then
			local ok2, tri = pcall(function() return Drawing.new("Triangle") end)
			if ok2 and tri then
				tri.Visible = false
				tri.Filled = true
				tri.Thickness = 1
				table.insert(espPlayerArrows, { tri = tri, plr = plr })
				byPlr[plr] = espPlayerArrows[#espPlayerArrows]
			end
		end
	end
	local col = espPlayerColor()
	local margin = 40
	for _, e in ipairs(espPlayerArrows) do
		pcall(function()
			local c = e.plr.Character
			local hrp = c and c:FindFirstChild("HumanoidRootPart")
			if not hrp then e.tri.Visible = false return end
			local sp, onScreen = cam:WorldToViewportPoint(hrp.Position)
			if onScreen and sp.Z > 0 then e.tri.Visible = false return end
			-- clamp to screen edge, point the triangle outward
			local dx, dy = sp.X - cx, sp.Y - cy
			if dx == 0 and dy == 0 then e.tri.Visible = false return end
			local t = math.min(
				(cx - margin) / math.abs(dx),
				(cy - margin) / math.abs(dy)
			)
			t = math.min(t, 1)
			local ex, ey = cx + dx * t, cy + dy * t
			local ang = math.atan2(dy, dx)
			local s, sz = math.sin(ang), 14
			local cs = math.cos(ang)
			-- nose points outward, base perpendicular
			e.tri.PointA = Vector2.new(ex + cs * sz, ey + s * sz)
			e.tri.PointB = Vector2.new(ex - cs * sz * 0.6 - s * sz * 0.6, ey - s * sz * 0.6 + cs * sz * 0.6)
			e.tri.PointC = Vector2.new(ex - cs * sz * 0.6 + s * sz * 0.6, ey - s * sz * 0.6 - cs * sz * 0.6)
			e.tri.Color = col
			e.tri.Visible = true
		end)
	end
end

-- Shared fast visual loop (0.25s): tracers + player arrows.
task.spawn(function()
	while true do
		pcall(refreshTitanTracers)
		pcall(refreshPlayerArrows)
		task.wait(0.25)
	end
end)

-- ==========================================
-- UPGRADE TOUCH HELPER (for HQ Upgrades)
-- ==========================================

local function getWavesUpgradeZone()
    -- Directly target the Hitbox in Zones.Upgrade (has TouchInterest)
    local zones = workspace:FindFirstChild("Waves") and workspace.Waves:FindFirstChild("Zones")
    local upgradeZone = zones and zones:FindFirstChild("Upgrade")
    if upgradeZone then
        local hitbox = upgradeZone:FindFirstChild("Hitbox")
        if hitbox and hitbox:IsA("BasePart") then
            return hitbox
        end
    end
    return nil
end

local function touchWavesUpgrade()
    local touchPart = getWavesUpgradeZone()
    if not touchPart then return false end
    
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    
    -- Teleport to upgrade zone and touch the hitbox
    root.CFrame = CFrame.new(touchPart.Position + Vector3.new(0, 5, 0))
    task.wait(0.2)
    touchPart.CanTouch = true
    firetouchinterest(root, touchPart, 0)
    task.wait(0.1)
    firetouchinterest(root, touchPart, 1)
    task.wait(0.5)
    return true
end

local function getMarketCategories()
    return { "Perks", "Artifacts", "Memories", "Shifting" }
end

-- ==========================================
-- AUTO FARM
-- ==========================================

local AutoFarm = {}
AutoFarm._running = false

lp.CharacterAdded:Connect(function()
	task.wait(3)
	if Toggles and Toggles.AutoKillToggle and Toggles.AutoKillToggle.Value then
		AutoFarm:Stop()
		task.wait(0.5)
		AutoFarm:Start()
	end
end)

getgenv().AutoFarmConfig = {
	AttackCooldown = 1.6, -- heuristic floor (server check is silent; never below)
	ReloadCooldown = 1.6,
	AttackRange = 150,
	MoveSpeed = 260, -- v8.1: was 400 (above legit ODM Default=300, reads as exploit)
	HeightOffset = 180, -- v8.1: was 250 (sky); titans are 15-60 tall, ODM plays mid-air
	MovementMode = "Hover",
	TargetPriority = "Titans", -- Titans, Boss, None
}

getgenv().MasteryFarmConfig = {
	Enabled = false,
	Mode = "Both",
}

-- v8.1: injury healing is ZONE interaction only (healInjuries). The old loop
-- Destroy()ed injuries client-side every 2.5s — visible server-side anomaly
-- and against AGENT.md. Deleted with cause; healInjuries() covers it.
task.spawn(function()
	while true do
		pcall(function()
			-- Only touch the zone when actually injured (no blind touch spam)
			if hasInjuries() then healInjuries() end
		end)
		task.wait(5 + math.random() * 2)
	end
end)

function AutoFarm:Start()
	if self._running then return end
	if isLobby then return end

	self._running = true
	getgenv()._farmWantOn = true
	getgenv()._farmHeartbeat = os.clock()
	-- v8.1 watchdog: the farm thread dying silently was the #1 AFK killer.
	-- If the heartbeat goes stale while the toggle is on, restart the loop.
	if not getgenv()._watchdogOn then
		getgenv()._watchdogOn = true
		task.spawn(function()
			while getgenv()._watchdogOn do
				task.wait(10)
				if not getgenv()._farmWantOn then
					getgenv()._watchdogOn = false
					break
				end
				if AutoFarm._running and os.clock() - (getgenv()._farmHeartbeat or 0) > 15 then
					pcall(function()
						AutoFarm._running = false
						task.wait(2)
						if getgenv()._farmWantOn then AutoFarm:Start() end
					end)
				end
			end
		end)
	end
	task.spawn(function()
		UpdateStatus("Waiting for mission...")
		
		local function checkReady()
			local char = lp.Character
			local playerReady = char and (char:GetAttribute("Shifter") or (char:FindFirstChild("Main") and char.Main:FindFirstChild("W")))
			local mapReady = workspace:FindFirstChild("Unclimbable") ~= nil
			local titans = workspace:FindFirstChild("Titans")
			local titansReady = false
			if titans then
				for _, v in ipairs(titans:GetChildren()) do
					if v:FindFirstChild("Fake") and v.Fake:FindFirstChild("Head") and v.Fake.Head:FindFirstChild("Header") then
						titansReady = true
						break
					end
				end
			end
			return playerReady and mapReady and titansReady
		end

		local startTime = os.clock()
		while self._running and not checkReady() do
			if os.clock() - startTime > 10 then
				Library:Notify({
					Title = "AOTR Hub",
					Description = "Still waiting for mission assets to load...",
					Time = 5
				})
				startTime = os.clock()
			end
			task.wait(1)
		end

		if not self._running then return end
		UpdateStatus("Farming")

		local titansFolder = workspace:FindFirstChild("Titans")
		local lastAttack = 0
		local currentChar, root, charParts = nil, nil, {}

		local bossNames = {Attack_Titan = true, Armored_Titan = true, Female_Titan = true, Colossal_Titan = true}
		local attackTitanSpawnTime = nil
		local AttackRangeSq = getgenv().AutoFarmConfig.AttackRange * getgenv().AutoFarmConfig.AttackRange

		local function updateCharState()
			local char = lp.Character
			if not char then return false end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then return false end
			if char ~= currentChar then
				currentChar = char
				root = hrp
				charParts = {}
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA("BasePart") then
						p.CanCollide = false
						table.insert(charParts, p)
					end
				end
			end
			return true
		end

		local validNapes = {}
		local nextTitanCacheUpdate = 0
		local nextObjectiveCacheUpdate = 0
		local cachedObjectivePart = nil
		local lastMasteryPunch = 0

		while self._running do
			getgenv()._farmHeartbeat = os.clock() -- watchdog feed
			AttackRangeSq = getgenv().AutoFarmConfig.AttackRange * getgenv().AutoFarmConfig.AttackRange

			if lp:GetAttribute("Cutscene") then
				task.wait(0.05)
				continue
			end

			if not checkMission() then
				UpdateStatus("Waiting for mission...")
				task.wait(1)
				continue
			end

			local slotIndex = lp:GetAttribute("Slot")
			local slotData = slotIndex and mapData and mapData.Slots and mapData.Slots[slotIndex]

			if not slotData then
				UpdateStatus("Waiting for data...")
				task.wait(1)
				continue
			end

		-- Die at Streak check (v8.1 passive: NEVER write Humanoid.Health —
		-- client-authoritative health writes are a detection vector and against
		-- AGENTS.md. Instead stop attacking and drift at the nearest titan so
		-- the game kills you legitimately.)
		if getgenv().DieAtStreak then
			local streak = lp:GetAttribute("Streak") or 0
			if streak >= (getgenv().DieAtStreakCount or 10000) then
				getgenv()._dieAtStreakActive = true
				UpdateStatus("Streak reached — standing down...")
			else
				getgenv()._dieAtStreakActive = false -- died/respawned: resume farm
			end
		end
		if getgenv()._dieAtStreakActive then
			-- Stand down: no attacks, gentle drift (titans finish the job)
			if root then root.AssemblyLinearVelocity = V3_ZERO end
			task.wait(0.5)
			continue
		end

		-- v8.1: single heuristic cooldown (floor 1.6s, human tail). The old code
		-- overwrote this every iteration to 1.0-1.5s, violating the 1.6s minimum.
		getgenv().AutoFarmConfig.AttackCooldown = attackCooldown()

			if getgenv().AutoFailsafe then
				if not self.missionStartTime then
					self.missionStartTime = os.clock()
				end
				local missionElapsedTime = os.clock() - self.missionStartTime
				-- v8.4: configurable (was hardcoded 900s)
				if missionElapsedTime >= (tonumber(getgenv().FailsafeMins) or 15) * 60 then
					self:Stop()
					task.spawn(function() getRemote:InvokeServer("Functions", "Teleport", "Lobby") end)
					task.wait(0.5)
					TeleportService:Teleport(14916516914, lp)
					break
				end
			end

			local playerCount = workspace:GetAttribute("Player_Count") or #Players:GetPlayers()
			if getgenv().SoloOnly and playerCount > 1 then
				self:Stop()
				task.spawn(function() getRemote:InvokeServer("Functions", "Teleport", "Lobby") end)
				task.wait(0.5)
				TeleportService:Teleport(14916516914, lp)
				break
			end
			
			if not updateCharState() then task.wait(0.05) continue end

			titansFolder = workspace:FindFirstChild("Titans") or titansFolder

			local ws_ObjectiveFolder = workspace:FindFirstChild("Unclimbable") and workspace.Unclimbable:FindFirstChild("Objective")
			local rs_ObjectiveFolder = ReplicatedStorage:FindFirstChild("Objectives")
			local mapType = workspace:GetAttribute("Type") or (mapData and mapData.Map and mapData.Map.Type)

			local isArmoredRaid = ws_ObjectiveFolder:FindFirstChild("Armored_Boss")
			local isFemaleRaid = rs_ObjectiveFolder:FindFirstChild("Defeat_Annie")
			local femaleExists = ws_ObjectiveFolder:FindFirstChild("Female_Boss")
			local attackExists = ws_ObjectiveFolder:FindFirstChild("Attack_Boss")
			local armoredTitan = titansFolder and titansFolder:FindFirstChild("Armored_Titan")
			local hasReinerObjective = armoredTitan and armoredTitan:GetAttribute("State")
			local isColossalRaid = rs_ObjectiveFolder:FindFirstChild("Defeat_Bertholdt") or ws_ObjectiveFolder:FindFirstChild("Colossal_Boss")

			if isFemaleRaid and not femaleExists and not attackExists then
				task.wait(0.05)
				continue
			end

			-- COLOSSAL RAID: Phase 1
			if isColossalRaid then
				local stallObjective = rs_ObjectiveFolder:FindFirstChild("Stall_Colossal_Titan")
				local stallDone = stallObjective and stallObjective.Value >= (stallObjective:GetAttribute("Requirement") or 1)

				if not stallDone then
					UpdateStatus("Colossal Raid - Phase 1: Cannon Stalling...")

					local walls = workspace:FindFirstChild("Climbable") and workspace.Climbable:FindFirstChild("Walls")
					local cannonModel = walls and walls:FindFirstChild("Wall") and
						walls.Wall:FindFirstChild("Cannons") and
						walls.Wall.Cannons:FindFirstChild("1")

					if not cannonModel and walls then
						for _, wall in ipairs(walls:GetChildren()) do
							local c = wall:FindFirstChild("Cannons") and wall.Cannons:FindFirstChild("1")
							if c then cannonModel = c break end
						end
					end

					if cannonModel and not getgenv()._colossalCannonRunning then
						getgenv()._colossalCannonRunning = true
						task.spawn(function()
							local function getLiveNapePos()
								local ct = titansFolder:FindFirstChild("Colossal_Titan")
								if not ct then return nil end
								local hit = ct:FindFirstChild("Hitboxes") and ct.Hitboxes:FindFirstChild("Hit")
								if hit and hit:FindFirstChild("Nape") then return hit.Nape.Position end
								local fake = ct:FindFirstChild("Fake")
								local head = fake and fake:FindFirstChild("Head")
								return head and head.Position or nil
							end

							local function isStallDone()
								local so = ReplicatedStorage:FindFirstChild("Objectives") and ReplicatedStorage.Objectives:FindFirstChild("Stall_Colossal_Titan")
								return so and so.Value >= (so:GetAttribute("Requirement") or 1)
							end

							local impactConn = postRemote.OnClientEvent:Connect(function(a1, a2, cannonObj, hitbox, ...)
								if a1 ~= "Skills" or a2 ~= "Impact" then return end
								if not getgenv()._colossalCannonRunning then return end
								local ref = cannonObj or workspace:FindFirstChild("Cannon")
								if not ref then return end
								for i = 1, 30 do
									local napePos = getLiveNapePos()
									if napePos then
										postRemote:FireServer("S_Skills", "Impact", ref, napePos)
										-- v8.1: was an instant 30-impact burst (blatant); throttle it
										task.wait(0.05)
									end
								end
							end)

							while self._running and not isStallDone() do
								getRemote:InvokeServer("Cannon", "State", cannonModel, true)
								task.wait(0.1)
								getRemote:InvokeServer("Cannon", "Shoot", {BarrelWood = 40, Base = 0})
								task.wait(2)
							end

							impactConn:Disconnect()
							pcall(function() getRemote:InvokeServer("Cannon", "State", cannonModel, false) end)
							getgenv()._colossalCannonRunning = false
							UpdateStatus("Colossal Raid - Phase 1 Complete!")
						end)
					end
				else
					getgenv()._colossalCannonRunning = false

					if not getgenv()._colossalPhase2Running then
						getgenv()._colossalPhase2Running = true
						task.spawn(function()
							UpdateStatus("Colossal Raid - Phase 2: Kill Colossal!")

							local function getNapeTarget()
								local ct = titansFolder:FindFirstChild("Colossal_Titan")
								if not ct then return nil, nil end
								local hit = ct:FindFirstChild("Hitboxes") and ct.Hitboxes:FindFirstChild("Hit")
								local nape = hit and hit:FindFirstChild("Nape")
								if nape then return nape, nape.Position + Vector3.new(0, 4, 0) end
								return nil, nil
							end

							while self._running do
								local napePart, napePos = getNapeTarget()
								if not napePart or not napePos then task.wait() continue end
								for i = 1, 5 do
									local explodeTimeDiff = tick() - (getgenv()._lastExplodeTime or 0)
									if explodeTimeDiff < 0.01 then explodeTimeDiff = 0.01 end
									getgenv()._lastExplodeTime = tick()
									postRemote:FireServer("Spears", "S_Explode", napePos, explodeTimeDiff)
								end
								-- Add jitter to position for Colossal Phase 2
								local jitter = CFrame.new(
								    math.random(-5, 5) / 10,
								    math.random(-3, 3) / 10,
								    math.random(-5, 5) / 10
								)
							napePos = (CFrame.new(napePos) * jitter).Position
							-- v8: getHitboxArgs returns nil for stale/dead napes — skip
							local a, v, td = getHitboxArgs(napePart)
							if a then
								postRemote:FireServer("Hitboxes", "Register", a, v, td)
							end
							task.wait()
							end

							getgenv()._colossalPhase2Running = false
						end)
					end
				end
			end

			if math.fmod(os.clock(), 0.5) < 0.05 then
				for i = 1, #charParts do
					local p = charParts[i]
					if p and p.Parent then p.CanCollide = false end
				end
			end

			local now = os.clock()
			local isShifted = currentChar and currentChar:GetAttribute("Shifter") or false
			
			if getgenv().MasteryFarmConfig.Enabled then
				local shiftReady = lp:GetAttribute("Bar") and lp:GetAttribute("Bar") == 100
				if not isShifted and shiftReady then
					repeat 
						getRemote:InvokeServer("S_Skills", "Usage", "999", false) 
						task.wait(1) 
					until not self._running or (lp.Character and lp.Character:GetAttribute("Shifter"))
					continue
				end
			end

			if now >= nextTitanCacheUpdate then
				nextTitanCacheUpdate = now + 0.1
				table.clear(validNapes)
				for _, v in ipairs(titansFolder:GetChildren()) do
					if v:GetAttribute("Killed") then continue end
					local hit = v:FindFirstChild("Hitboxes") and v.Hitboxes:FindFirstChild("Hit")
					if hit then
						local fake = v:FindFirstChild("Fake")
						if fake and fake:FindFirstChild("Collision") and not fake.Collision.CanCollide then continue end
						local nape = hit:FindFirstChild("Nape")
						if nape then table.insert(validNapes, nape) end
					end
				end
			end

			local rootPos = root.Position
			local referencePos = rootPos
			local objectiveFound = false

			if now >= nextObjectiveCacheUpdate then
				nextObjectiveCacheUpdate = now + 3 -- v8.1: was 1s (GetDescendants scan each second is wasted CPU)
				cachedObjectivePart = nil
				if ws_ObjectiveFolder then
					for _, desc in ipairs(ws_ObjectiveFolder:GetDescendants()) do
						if desc:IsA("BillboardGui") and desc.Parent and desc.Parent:IsA("BasePart") then
							cachedObjectivePart = desc.Parent
							break
						end
					end
				end
			end

			if cachedObjectivePart and cachedObjectivePart.Parent then
				referencePos = cachedObjectivePart.Position
				objectiveFound = true
			end

			local useRangeLimit = objectiveFound and isArmoredRaid and not hasReinerObjective
			local closestDist, closestNape = math.huge, nil
			local closestIsBoss = false
			local bossDist, bossHitPoint = math.huge, nil
			local attackTitanFound = false
			local highestZ = -math.huge
			local isStall = mapData and mapData.Map and mapData.Map.Objective == "Stall"
			local bossIsRoaring = false

			local priority = getgenv().AutoFarmConfig.TargetPriority or "Titans"

			for i = 1, #validNapes do
				local nape = validNapes[i]
				if not nape.Parent then continue end

				local titanModel = nape.Parent.Parent.Parent
				local fake = titanModel:FindFirstChild("Fake")
				if (fake and fake:FindFirstChild("Collision") and not fake.Collision.CanCollide) or (titanModel:GetAttribute("Dead")) then continue end

				local tName = titanModel.Name
				local isBoss = bossNames[tName]

				if isArmoredRaid and not hasReinerObjective and tName == "Armored_Titan" then continue end

				if isColossalRaid then
					if tName == "Colossal_Titan" then continue end
				end
		
				if isBoss and not titanModel:GetAttribute("State") then continue end
			
				local isRoaring = isBoss and (titanModel:GetAttribute("Attack") == "Roar" or titanModel:GetAttribute("Attack") == "Berserk_Mode")

				if tName == "Attack_Titan" then attackTitanFound = true end

				local dx = referencePos.X - nape.Position.X
				local dz = referencePos.Z - nape.Position.Z
				local d = dx*dx + dz*dz
				
				local adjustedDist = d
				if getgenv()._currentTargetNape == nape then
					adjustedDist = adjustedDist - 15000
				end

				if useRangeLimit then
					if d > 90000 then continue end
				end

				if isBoss then
					local marker = titanModel:FindFirstChild("Marker")
					local hitFolder = titanModel:FindFirstChild("Hitboxes")
					local hit = hitFolder and hitFolder:FindFirstChild("Hit")
					local hitPart = (marker and marker.Adornee) or (hit and hit:FindFirstChild("Nape"))
					if hitPart and adjustedDist < bossDist then
						bossDist = adjustedDist
						bossHitPoint = hitPart
						bossIsRoaring = isRoaring
					end
				end

				if isStall then
					if nape.Position.Z > highestZ then
						highestZ = nape.Position.Z
						closestNape = nape
					end
				else
					-- Target priority logic
					local shouldPreferBoss = priority == "Boss"
					local shouldPreferTitans = priority == "Titans"
					
					if isBoss and shouldPreferBoss then
						-- Boss priority: track boss separately with higher preference
						if adjustedDist < bossDist * 0.5 then -- give boss preference
							closestDist = adjustedDist
							closestNape = nape
							closestIsBoss = true
						elseif bossHitPoint == nil and adjustedDist < closestDist then
							closestDist = adjustedDist
							closestNape = nape
							closestIsBoss = true
						end
					elseif not isBoss and shouldPreferTitans then
						-- Titans priority: prefer regular titans
						if adjustedDist < closestDist then
							closestDist = adjustedDist
							closestNape = nape
							closestIsBoss = false
						end
					else
						-- None: closest target (original behavior)
						if adjustedDist < closestDist then
							closestDist = adjustedDist
							closestNape = nape
							closestIsBoss = isBoss
						end
					end
				end
			end

			local targetPart = bossHitPoint or closestNape
			local targetIsRoaring = (targetPart ~= nil and targetPart == bossHitPoint) and bossIsRoaring or false
			
			if useRangeLimit and closestNape then
				targetPart = closestNape
				targetIsRoaring = false
			end

			if not getgenv()._missionStartTime then
				getgenv()._missionStartTime = os.clock()
			end

			if targetPart and #validNapes == 1 and mapType == "Missions" then
				local elapsed = os.clock() - getgenv()._missionStartTime
				local requiredWait = getgenv().LastTitanWait and getgenv().LastTitanWaitSecs or 10
				if elapsed < requiredWait then
					UpdateStatus("Waiting... " .. math.floor(requiredWait - elapsed) .. "s left")
					targetPart = nil
				end
			end

			getgenv()._currentTargetNape = targetPart

			if attackTitanFound then
				attackTitanSpawnTime = attackTitanSpawnTime or now
			else
				attackTitanSpawnTime = nil
			end

			local attackTitanReady = not attackTitanFound or (attackTitanSpawnTime and (now - attackTitanSpawnTime) >= 5)

			if targetPart then
				UpdateStatus(closestIsBoss and "Attacking Boss..." or "Farming Titans...")
				local currentTitanModel = targetPart
				while currentTitanModel and currentTitanModel.Parent ~= titansFolder do
					currentTitanModel = currentTitanModel.Parent
				end

				if isShifted then
					local targetHRP = currentTitanModel:FindFirstChild("HumanoidRootPart")
					local targetCFrame = targetHRP and targetHRP.CFrame or targetPart.CFrame
					
					root.AssemblyLinearVelocity = V3_ZERO
					root.CFrame = targetCFrame * CFrame.new(0, 0, 80)
					local mode = getgenv().MasteryFarmConfig.Mode
					local doPunch = mode == "Punching" or mode == "Both"
					local doSkills = mode == "Skill Usage" or mode == "Both"

					if not targetIsRoaring then
						if doPunch and (now - lastMasteryPunch) >= 1 then
							lastMasteryPunch = now
							postRemote:FireServer("Attacks", "Slash", true)
							postRemote:FireServer("Hitboxes", "Register", getHitboxArgs(targetPart))
						end

						if doSkills and slotData and slotData.Skills and slotData.Skills.Shifter and not getgenv().ShifterSkillsRunning then
							getgenv().ShifterSkillsRunning = true
							task.spawn(function()
								for _, skillId in ipairs(slotData.Skills.Shifter) do
									local idNum = tonumber(skillId)
									if idNum and idNum ~= 200 and idNum ~= 300 and idNum ~= 400 and idNum ~= 210 and idNum ~= 211 and idNum ~= 306 and idNum ~= 308 and idNum ~= 402 and idNum ~= 403 and idNum ~= 407 then
										getRemote:InvokeServer("S_Skills", "Usage", tostring(skillId), false)
									end
									task.wait(1)
								end
								getgenv().ShifterSkillsRunning = false
							end)
						end
					end
					task.wait(0.05)
					continue
				end

local titanHRP = currentTitanModel:FindFirstChild("HumanoidRootPart")
			local targetHeightPos
			if titanHRP then
				targetHeightPos = (titanHRP.CFrame * CFrame.new(0, getgenv().AutoFarmConfig.HeightOffset, 30)).Position
			else
				targetHeightPos = targetPart.Position + Vector3.new(0, getgenv().AutoFarmConfig.HeightOffset, 0)
			end
			
			-- Movement: Teleport mode teleports when far; Hover mode always glides
			local distToTarget = (targetHeightPos - rootPos).Magnitude
			local moveMode = getgenv().AutoFarmConfig.MovementMode or "Hover"
			
			if distToTarget > 15 and moveMode == "Teleport" then
				root.AssemblyLinearVelocity = V3_ZERO
				root.CFrame = CFrame.new(targetHeightPos)
			else
				-- Smooth hover tracking with quadratic deceleration
				local dir = targetHeightPos - rootPos
				local dist = dir.Magnitude
				local moveSpeed = getgenv().AutoFarmConfig.MoveSpeed
				
				if dist < 30 then
					local t = dist / 30
					moveSpeed = moveSpeed * (t * t)
				end
				if dist < 5 then
					moveSpeed = 0
				end
				
				if moveSpeed > 0 then
					-- v8.1: bell-curved drift (was uniform box noise — a pattern tell)
					root.AssemblyLinearVelocity = dir.Unit * moveSpeed + humanNoise(0.05)
				else
					root.AssemblyLinearVelocity = V3_ZERO
				end
			end

				if not attackTitanReady then task.wait(0.05) continue end

				local dx = root.Position.X - targetPart.Position.X
				local dz = root.Position.Z - targetPart.Position.Z

			if not targetIsRoaring and (dx*dx + dz*dz) <= AttackRangeSq and (now - lastAttack) >= getgenv().AutoFarmConfig.AttackCooldown then
				lastAttack = now + irwinHall() * 0.043 -- v8.1: bell-curved, was uniform -80/+50ms

					local hitTargets = { targetPart }
					if getgenv().MultiHit then
						local sortedNapes = {}
						for i = 1, #validNapes do
							local n = validNapes[i]
							-- v8.1: full hierarchy guard (a half-despawned titan
							-- previously threw here and silently killed the farm thread)
							local titanM = n.Parent and n.Parent.Parent and n.Parent.Parent.Parent
							if n ~= targetPart and n.Parent and titanM and not titanM:GetAttribute("Dead") then
								local ndx = root.Position.X - n.Position.X
								local ndz = root.Position.Z - n.Position.Z
								sortedNapes[#sortedNapes + 1] = { nape = n, distSq = ndx*ndx + ndz*ndz }
							end
						end
						table.sort(sortedNapes, function(a, b) return a.distSq < b.distSq end)

						local count = 1
						for i = 1, #sortedNapes do
							if count >= getgenv().MultiHitCount then break end
							local entry = sortedNapes[i]
							if entry.distSq <= AttackRangeSq then
								table.insert(hitTargets, entry.nape)
								count = count + 1
							end
						end
					end

					if slotData.Weapon == "Blades" then
					-- MultiHit: fire all hits instantly in one frame
					local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
					local baseVel = hrp and hrp.AssemblyLinearVelocity.Magnitude or 75
					baseVel = math.max(baseVel, math.random(60, 85))
					local baseTimeDiff = tick() - (getgenv()._lastHitboxTime or tick())
					if baseTimeDiff < 0.01 then baseTimeDiff = 0.01 end
					if baseTimeDiff > 2.0 then baseTimeDiff = 1.5 + math.random() * 0.5 end
					
					postRemote:FireServer("Attacks", "Slash", true)
					for _, nape in ipairs(hitTargets) do
						-- v8: skip stale/dead napes (getHitboxArgs returns nil) +
						-- v8.1 bell-curved throttle (was uniform — a pattern tell)
						local a, v, td = getHitboxArgs(nape)
						if a then
							postRemote:FireServer("Hitboxes", "Register", a, v, td)
							task.wait(humanWait(0.055, 0.05))
						end
					end
					getgenv()._lastHitboxTime = tick()
					if #hitTargets > 1 then
						print("[MultiHit] Blades hit", #hitTargets, "targets")
					end
			else
				-- Spears: MultiHit - fire S_Fire + S_Explode per target
				-- v8.1: guarded hierarchy + HUD lookups (a missing HUD or a
				-- Marker-adornee target previously threw and killed the farm)
				local titanM = targetPart.Parent and targetPart.Parent.Parent and targetPart.Parent.Parent.Parent
				local isBoss = titanM and bossNames[titanM.Name] or false
				local top = PlayerGui:FindFirstChild("Interface")
				local hud = top and top:FindFirstChild("HUD")
				local main = hud and hud:FindFirstChild("Main")
				local top7 = main and main:FindFirstChild("Top")
				local f7 = top7 and top7:FindFirstChild("7")
				local spearsF = f7 and f7:FindFirstChild("Spears")
				local spearsLabel = spearsF and spearsF:FindFirstChild("Spears")
				if not spearsLabel then task.wait(0.2) continue end
				local text = spearsLabel.Text
					local currentAmmo, maxAmmo = string.match(text, "(%d+)%s*/%s*(%d+)")
					currentAmmo, maxAmmo = tonumber(currentAmmo), tonumber(maxAmmo)

					if currentAmmo and currentAmmo > 0 and maxAmmo and maxAmmo > 0 then
						task.spawn(function()
							local function getAmmo()
								return tonumber(string.match(spearsLabel.Text, "(%d+)"))
							end

							for _, nape in ipairs(hitTargets) do
								local spearSlot = getCurrentSpearSlot() or "A"
								pcall(function()
									getRemote:InvokeServer("Spears", "S_Fire", spearSlot)
								end)
								task.wait(0.05)
								local loops = isBoss and 3 or 1
								for j = 1, loops do
									local explodeTimeDiff = tick() - (getgenv()._lastExplodeTime or 0)
									if explodeTimeDiff < 0.01 then explodeTimeDiff = 0.01 end
									getgenv()._lastExplodeTime = tick()
									postRemote:FireServer("Spears", "S_Explode", nape.Position, explodeTimeDiff)
								end
								task.wait(math.random(3, 8) / 100)
							end
						end)
					end
				end
				end
			else
				root.AssemblyLinearVelocity = V3_ZERO
			end

			task.wait(0.05)
		end
	end)
end

function AutoFarm:Stop()
	self._running = false
	getgenv()._farmWantOn = false
	getgenv()._colossalCannonRunning = false
	getgenv()._colossalPhase2Running = false
end

-- ==========================================
-- NOCLIP
-- ==========================================

local noclipConn = nil
-- Cached noclip — avoids repeated character lookups
local noclipCache = {character = nil, humanoid = nil}
local function setNoclip(state)
    local char = lp.Character
    if char ~= noclipCache.character then
        noclipCache.character = char
        noclipCache.humanoid = char and char:FindFirstChildOfClass("Humanoid")
    end
    if noclipCache.humanoid then
        noclipCache.humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, not state)
    end
end

-- ==========================================
-- AUTO REJOIN ON CRASH
-- ==========================================

local lastMissionState = false
local crashCheckRunning = false

local function startCrashDetection()
	if crashCheckRunning then return end
	crashCheckRunning = true
	task.spawn(function()
		while crashCheckRunning do
			task.wait(10)
			if not getgenv().AutoRejoin then continue end
			if isLobby then continue end
			if not AutoFarm._running then continue end

			local titans = workspace:FindFirstChild("Titans")
			local unclimbable = workspace:FindFirstChild("Unclimbable")

			if not titans and not unclimbable then
				task.wait(10)
				titans = workspace:FindFirstChild("Titans")
				unclimbable = workspace:FindFirstChild("Unclimbable")

				if not titans and not unclimbable then
					sessionStats.crashes = sessionStats.crashes + 1
					SaveSessionStats()
					Library:Notify({
						Title = "Auto Rejoin",
						Description = "Crash detected! Rejoining... (" .. sessionStats.crashes .. " total)",
						Time = 5
					})

					AutoFarm:Stop()
					task.wait(0.5)
					pcall(function() getRemote:InvokeServer("Functions", "Teleport", "Lobby") end)
					task.wait(0.5)
					pcall(function() TeleportService:Teleport(14916516914, lp) end)
				end
			end
		end
	end)
end

local function stopCrashDetection()
	crashCheckRunning = false
end

-- ==========================================
-- HELPERS
-- ==========================================

local function formatTable(tbl)
	local str = ""
	for k, v in pairs(tbl) do
		str ..= string.format("%s: %s\n", k, tostring(v))
	end
	return str ~= "" and str or "None"
end

local function formatItems(tbl)
	local str = ""
	for name, qty in pairs(tbl) do
		name = string.gsub(name, "_", " ")
		str ..= string.format("[+] %s (x%s)\n", name, qty)
	end
	return str ~= "" and str or "None"
end

local data = {
	Stats = {},
	Total = {},
	Items = {},
	Special = {}
}

local path = "./THUB1/aotr/games_played.txt"
if not isfile(path) then writefile(path, "0") end
local gamesPlayed = tonumber(readfile(path))

local webhook



-- ==========================================
-- REWARDS LISTENER
-- ==========================================

if rewards then
	rewards:GetPropertyChangedSignal("Visible"):Connect(function()
		if not rewards.Visible then return end

		-- Reset mission start timer
		getgenv()._missionStartTime = nil

		gamesPlayed = gamesPlayed + 1
		writefile("./THUB1/aotr/games_played.txt", tostring(gamesPlayed))

		-- Update session stats
		sessionStats.gamesPlayed = sessionStats.gamesPlayed + 1
		pcall(function()
			local res = getRemote:InvokeServer("S_Rewards", "Get", true)
			if res and res.Obtained then
				sessionStats.totalGold = sessionStats.totalGold + (res.Obtained.Gold or 0)
				sessionStats.totalGems = sessionStats.totalGems + (res.Obtained.Gems or 0)
				sessionStats.totalXP = sessionStats.totalXP + (res.Obtained.XP or 0)
			end
		end)
		if data.Special and next(data.Special) then
			sessionStats.mythicalDrops = sessionStats.mythicalDrops + 1
		end
		SaveSessionStats()

		local gamesUntilReturn = tonumber(readfile(returnCounterPath)) or 0
		local willReturn = false

		if getgenv().AutoReturnLobby then
			gamesUntilReturn = gamesUntilReturn + 1

			if gamesUntilReturn >= getgenv().ReturnAfterGames then
				gamesUntilReturn = 0
				willReturn = true
			end
			
			writefile(returnCounterPath, tostring(gamesUntilReturn))
			
			if willReturn then
				task.spawn(function()
					getRemote:InvokeServer("Functions", "Teleport", "Lobby")
				end)
				task.wait(0.5)
				TeleportService:Teleport(14916516914, lp)
				return
			end
		elseif gamesUntilReturn >= getgenv().ReturnAfterGames then
			gamesUntilReturn = 0
			writefile(returnCounterPath, "0")
		end
		
		if not getgenv().RewardWebhook then return end
		
		local start = os.clock()
		local hasData
		repeat 
			task.wait(0.1)
			hasData = false
			for _, v in ipairs(statsFrame:GetChildren()) do
				if v:IsA("Frame") and v:FindFirstChild("Amount") and v.Amount.Text ~= "0" and v.Amount.Text ~= "" then
					hasData = true
					break
				end
			end
		until hasData or (os.clock() - start) > 2

		data.Stats = {}
		data.Total = {}
		data.Items = {}
		data.Special = {}
		local dropsData = {} -- itemId -> itemName mapping for Special lookup

		for i, v in ipairs(statsFrame:GetChildren()) do
			if v:IsA("Frame") and v:FindFirstChild("Stat") and v:FindFirstChild("Amount") then
				data.Stats[string.gsub(v.Name, "_", " ")] = v.Amount.Text
			end
		end

		pcall(function()
			local res = getRemote:InvokeServer("S_Rewards", "Get", true)
			if res and res.Obtained then
				local ob = res.Obtained
				if ob.Gold   and ob.Gold   > 0 then data.Items["Gold"]   = tostring(ob.Gold)   end
				if ob.XP     and ob.XP     > 0 then data.Items["XP"]     = tostring(ob.XP)     end
				if ob.Gems   and ob.Gems   > 0 then data.Items["Gems"]   = tostring(ob.Gems)   end
				if ob.Canes  and ob.Canes  > 0 then data.Items["Canes"]  = tostring(ob.Canes)  end
				if ob.Shards and ob.Shards > 0 then data.Items["Shards"] = tostring(ob.Shards) end
				if ob.Silver and ob.Silver > 0 then data.Items["Silver"] = tostring(ob.Silver) end
				if ob.BP_XP  and ob.BP_XP  > 0 then data.Items["BP XP"]  = tostring(ob.BP_XP)  end
				if ob.Perks then
					for _, perkName in ipairs(ob.Perks) do
						data.Items["Perk: " .. perkName] = "1"
					end
				end
				if ob.Drops then
					for itemId, itemName in pairs(ob.Drops) do
						local name = tostring(itemName)
						dropsData[tostring(itemId)] = name
						local existing = tonumber(data.Items[name]) or 0
						data.Items[name] = tostring(existing + 1)
					end
				end
				if ob.Chests then
					for chestName, qty in pairs(ob.Chests) do
						if qty and qty > 0 then
							data.Items["Chest: " .. chestName] = tostring(qty)
						end
					end
				end
			end
		end)

		-- SECRET PERK DETECTION (server-side, reliable)
		pcall(function()
			local res2 = getRemote:InvokeServer("S_Rewards", "Get", true)
			if res2 and res2.Obtained and res2.Obtained.Perks then
				for _, perkName in ipairs(res2.Obtained.Perks) do
					if GetPerkRarity(perkName) == "Secret" then
						data.Special["Perk: " .. perkName] = "1"
					end
				end
			end
		end)

		-- MYTHICAL ITEM DROPS (non-perk, GUI scan)
		if itemsFrame then
			for _, v in ipairs(itemsFrame:GetChildren()) do
				if v:IsA("Frame") and v:FindFirstChild("Main") then
					local inner = v.Main:FindFirstChild("Inner")
					if inner and inner:FindFirstChild("Rarity")
					   and inner.Rarity.BackgroundColor3 == Color3.fromRGB(255, 0, 0) then
						local qty = inner:FindFirstChild("Quantity")
						local itemId = string.match(tostring(v.Name), "(%d+)$")
						local displayName = (itemId and dropsData[itemId]) or v.Name
						if not data.Special[displayName] then
							data.Special[displayName] = qty and qty.Text or "1"
						end
					end
				end
			end
		end

		local currentSlot = lp:GetAttribute("Slot") or "A"
		local slotData = mapData and mapData.Slots and mapData.Slots[currentSlot]
		local executor = identifyexecutor and identifyexecutor() or "Unknown"

		if slotData then
			if slotData.Currency then
				for i, v in pairs(slotData.Currency) do
					if i == "Gems" or i == "Gold" then data.Total[i] = v end
				end
			end
			if slotData.Progression then
				for i, v in pairs(slotData.Progression) do
					if i == "Prestige" or i == "Level" or i == "Streak" then data.Total[i] = v end
				end
			end
		end

		local hasSpecial = data.Special and next(data.Special) ~= nil

		if webhook and webhook ~= "" then
			local payload = {
				content = hasSpecial and "MYTHICAL DROP! @everyone" or nil,
				embeds = {{
					title = "TH Rewards",
					color = hasSpecial and 16711680 or 2829617,
					fields = {
						{
							name = "Information",
							value = "```\n" ..
								"User: " .. lp.Name .. "\n" ..
								"Games Played: " .. tostring(gamesPlayed) .. "\n" ..
								"Executor: " .. executor .. "\n" ..
								"\n```",
							inline = true
						},
						{
							name = "Total Stats",
							value = "```\n" ..
								"Prestige : " .. tostring(data.Total.Prestige or "0") .. "\n" ..
								"Level : " .. tostring(data.Total.Level or "1") .. "\n" ..
								"Gold  : " .. tostring(data.Total.Gold or "0") .. "\n" ..
								"Gems  : " .. tostring(data.Total.Gems or "0") ..
								"\n```",
							inline = true
						},
						{
							name = "Combat",
							value = "```\n" .. formatTable(data.Stats) .. "\n```",
							inline = true
						},
						{
							name = "Rewards",
							value = "```\n" .. formatItems(data.Items) .. "\n```",
							inline = true
						},
						{
							name = "Special",
							value = "```\n" .. (hasSpecial and formatItems(data.Special) or "None") .. "\n```",
							inline = true
						}
					},
					footer = {
						text = "AOTR Hub • " .. DateTime.now():FormatLocalTime("LTS", "en-us")
					},
					timestamp = DateTime.now():ToIsoDate()
				}}
			}

			request({
				Url = webhook,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(payload)
			})
		end
	end)
end


-- ==========================================
-- PERKS & TALENTS DATA
-- ==========================================

local Perks = {
	Legendary = {
		"Peerless Commander","Indefatigable","Tyrant's Stare","Invincible","Eviscerate",
		"Font of Vitality","Flame Rhapsody","Robust","Sixth Sense","Gear Master",
		"Carnifex","Munitions Master","Sanctified","Wind Rhapsody","Peerless Constitution",
		"Exhumation","Warchief","Peerless Focus","Perfect Form","Courage Catalyst",
		"Aegis","Unparalleled Strength","Perfect Soul"
	},
	Common = {
		"Cripple","Lucky","Enhanced Metabolism","First Aid","Mighty",
		"Fortitude","Hollow","Gear Beginner","Enduring"
	},
	Epic = {
		"Munitions Expert","Gear Expert","Butcher","Resilient","Speedy",
		"Reckless Abandon","Focus","Stalwart Durability","Adrenaline","Safeguard",
		"Warrior","Solo","Mutilate","Trauma Battery","Hardy",
		"Unbreakable","Siphoning","Flawed Release","Luminous","Peerless Strength"
	},
	Rare = {
		"Blessed","Gear Intermediate","Unyielding","Fully Stocked","Forceful",
		"Lightweight","Protection","Mangle","Experimental Shells","Critical Hunter",
		"Tough","Heightened Vitality"
	},
	Secret = {
		"Everlasting Flame","Heavenly Restriction","Adaptation","Maximum Firepower",
		"Soulfeed","Kengo","Black Flash","Font of Inspiration","Explosive Fortune",
		"Immortal","Art of War","Tatsujin","Founder's Blessing","Unwavering Belief"
	}
}

local PerkRarityMap = {}
for rarity, names in pairs(Perks) do
	for _, name in pairs(names) do PerkRarityMap[name] = rarity end
end

local Talents = {
	"Blitzblade","Crescendo","Swiftshot","Surgeshot","Guardian","Deflectra",
	"Mendmaster","Cooldown Blitz","Stalwart","Stormcharged","Aegisurge","Riposte",
	"Lifefeed","Vitalize","Gem Fiend","Luck Boost","EXP Boost","Gold Boost",
	"Furyforge","Quakestrike","Assassin","Amputation","Steel Frame","Resilience",
	"Vengeflare","Flashstep","Omnirange","Tactician","Gambler","Overslash",
	"Afterimages","Necromantic","Thanatophobia","Apotheosis","Bloodthief"
}

local Perk_Level_XP = {
	Common    = {50, 100, 150, 200, 250, 300, 350, 400, 450, 500},
	Rare      = {125, 250, 375, 500, 625, 750, 875, 1000, 1125, 1250},
	Epic      = {250, 500, 750, 1000, 1250, 1500, 1750, 2000, 2250, 2500},
	Legendary = {500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000},
	Secret    = {2000, 4000, 6000, 8000, 10000, 12000, 14000, 16000, 18000, 20000},
}

local Perk_Base_XP = {
	Common    = 100,
	Rare      = 250,
	Epic      = 625,
	Legendary = 2500,
	Secret    = 10000,
}

local Blades_Critical = {
	"1","2","3","4","5","6","7","8","9","10","11","12","13",
	"14","15","16","17","18","19","20","21","22","23","24","25"
}

local Blades_Damage = {
	"1","2","3","4","5","6","7","8","9","10","11","12","13",
	"26","27","28","29","30","31","32","33","34","35","36","37"
}

local Spears_Critical = {
	"113","114","115","116","117","118","119","120",
	"121","122","123","124","125",
	"126","127","128","129","130","131","132",
	"133","134","135","136","137"
}

local Spears_Damage = {
	"113","114","115","116","117","118","119","120",
	"121","122","123","124","125",
	"138","139","140","141","142","143","144",
	"145","146","147","148","149"
}

local Defense_Health = {
	"38","39","40","41","42","43","44","45",
	"46","47","48","49","50","51","52","53","54","55","56","57"
}

local Defense_Damage_Reduction = {
	"38","39","40","41","42","43","44","45",
	"58","59","60","61","62","63","64","65","66","67","68","69"
}

local Support_Regen = {
	"70","71","72","73","74","75","76","77","78","79","80",
	"81","82","83","84","85","86","87","88","89"
}

local Support_Cooldown_Reduction = {
	"70","71","72","73","74","75","76","77","78","79","80",
	"90","91","92","93","94","95","96","97","98"
}

local Missions = {
	["Shiganshina"] = { "Skirmish", "Breach", "Random" },
	["Trost"] = { "Skirmish", "Protect", "Random" },
	["Outskirts"] = { "Skirmish", "Escort", "Random" },
	["Forest"] = { "Skirmish", "Guard", "Random" },
	["Utgard"] = { "Skirmish", "Defend", "Random" },
	["Docks"] = { "Skirmish", "Stall", "Random" },
	["Stohess"] = { "Skirmish", "Random" },
	["Chapel"] = {"Skirmish", "Random"},
	["Colossal"] = { "Random" },
	["Waves"] = { "Waves" }
}

local RaidObjectives = {
	["Trost"]       = "Attack Titan",
	["Shiganshina"] = "Armored Titan",
	["Stohess"]     = "Female Titan",
	["Colossal"]    = "Colossal Titan",
}

local RaidMapNames = {
	["Trost"]       = "Trost",
	["Shiganshina"] = "Shiganshina",
	["Stohess"]     = "Stohess",
	["Colossal"]    = "Shiganshina",
}

local SkillPaths = {
	Blades = { Damage = Blades_Damage, Critical = Blades_Critical },
	Spears = { Damage = Spears_Damage, Critical = Spears_Critical },
	Defense = { Health = Defense_Health, ["Damage Reduction"] = Defense_Damage_Reduction },
	Support = { Regen = Support_Regen, ["Cooldown Reduction"] = Support_Cooldown_Reduction }
}

-- v8.5: dynamic module lookup + indirect require (pcall-guarded; keeps the
-- analyzer clean of unresolvable instance requires). Path = segments under
-- ReplicatedStorage, e.g. {"Modules","Storage","Perks"}.
local moduleLoader = function(path)
	local current = game:GetService("ReplicatedStorage")
	for _, segment in ipairs(path) do
		current = current:FindFirstChild(segment)
		if current == nil then return nil end
	end
	local ok, result = pcall(require, current)
	return (ok and type(result) == "table") and result or nil
end

-- v8.5: static map first (preserves v8.4 semantics: the legacy "Secret" tier —
-- now the game's Mythic tier, same 14 names, verified live 2026-10-17 — keeps its
-- never-sell behavior), then the live game catalog for names the static map
-- doesn't know (post-renovation additions: Modules.Storage.Perks tiers
-- Common/Rare/Epic/Legendary/Mythic -> name -> {Type, Stats}).
local _runtimePerkRarity = nil
local function GetPerkRarity(perkName)
	local known = PerkRarityMap[perkName]
	if known then return known end
	if _runtimePerkRarity == nil then
		_runtimePerkRarity = {}
		local catalog = moduleLoader({ "Modules", "Storage", "Perks" })
		if catalog then
			for rarity, names in pairs(catalog) do
				if type(names) == "table" then
					for name in pairs(names) do _runtimePerkRarity[name] = rarity end
				end
			end
		end
	end
	return _runtimePerkRarity[perkName]
end

local function GetPerkXP(rarity, level)
	local base = Perk_Base_XP[rarity] or 0
	return base * math.max(level, 1)
end

local function UseButton(button)
	if not button or not button.Parent then return false end
	if not button.Visible then return false end
	if GuiService.MenuIsOpen then
		vim:SendKeyEvent(true, Enum.KeyCode.Escape, false, game) 
		vim:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
		task.wait(0.1)
	end
	GuiService.SelectedObject = button
	task.wait(0.05)
	vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
	vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
	return true
end

local _deleteMapRunning = false
local function isRefillPart(part)
	-- Never delete refill stations: match by name or descendant named Refill
	if not part then return false end
	if part.Name == "Refill" or part.Name:lower():find("refill") then return true end
	if part:FindFirstChild("Refill", true) then return true end
	return false
end

local function DeleteMap()
	if _deleteMapRunning or not getgenv().DeleteMap or not workspace:FindFirstChild("Climbable") or (mapData and mapData.Map and mapData.Map.Type == "Raids") then return end
	task.spawn(function()
		_deleteMapRunning = true
		while getgenv().DeleteMap do
			if not workspace:FindFirstChild("Climbable") or (mapData and mapData.Map and mapData.Map.Type == "Raids") then break end
			-- Climbable: skip any part that is (or contains) a refill station
			for i, v in workspace.Climbable:GetChildren() do
				if not isRefillPart(v) then v:Destroy() end
			end
			-- Unclimbable: preserve Reloads, Objective, Cutscene AND any Refill station
			for i, v in workspace.Unclimbable:GetChildren() do
				if v.Name ~= "Reloads" and v.Name ~= "Objective" and v.Name ~= "Cutscene" and not isRefillPart(v) then
					v:Destroy()
				end
			end
			task.wait(3)
		end
		_deleteMapRunning = false
	end)
end

-- v8.3: the old queued URL (THUB ins.lua) is DEAD (404) — that is why
-- AutoExecute silently did nothing. Now it queues THIS script: override the
-- source with getgenv()._AOTR_SOURCE_PATH (or _AOTR_SOURCE_URL) if you run
-- from another copy. Disk candidates are tried in order.
local function setupAutoExecute()
	if getgenv().AutoExecute and not getgenv().AutoExec then
		if not queue_on_teleport then
			Library:Notify({ Title = "Auto Execute", Description = "Your executor doesn't support Auto Execute!", Time = 5 })
			return
		end
		local queued, how = false, nil
		pcall(function()
			-- 1) explicit URL override
			if type(getgenv()._AOTR_SOURCE_URL) == "string" and getgenv()._AOTR_SOURCE_URL ~= "" then
				queue_on_teleport("loadstring(game:HttpGet(" .. string.format("%q", getgenv()._AOTR_SOURCE_URL) .. "))()")
				queued, how = true, "URL override"
				return
			end
			-- 2) disk candidates
			local candidates = {}
			if type(getgenv()._AOTR_SOURCE_PATH) == "string" then
				table.insert(candidates, getgenv()._AOTR_SOURCE_PATH)
			end
			table.insert(candidates, "C:/Users/Aldor/Desktop/bovedas/Bovedas Delicadas/Scripts/05_Raw_Scripts/3_Products/Aotr/versions/Reverse Engineering T Hub.lua")
			for _, path in ipairs(candidates) do
				local ok, src = pcall(readfile, path)
				if ok and type(src) == "string" and #src > 10000 then
					queue_on_teleport(src)
					queued, how = true, "disk"
					break
				end
			end
		end)
		if queued then
			getgenv().AutoExec = true
			Library:Notify({ Title = "Auto Execute", Description = "Armed (" .. tostring(how) .. ") — script re-runs after teleport. Save a config + autoload to keep it persistent.", Time = 6 })
		else
			Library:Notify({ Title = "Auto Execute", Description = "No script source found! Set getgenv()._AOTR_SOURCE_PATH or _AOTR_SOURCE_URL.", Time = 8 })
		end
	end
end

local function ExecuteImmediateAutomation()
	
-- Auto Skip Cutscenes + Always TP to Refill
if getgenv().AutoSkip then
    -- Remote method: Functions/Finished (v4)
    pcall(function()
        getRemote:InvokeServer("Functions", "Finished")
    end)
    
    local skip = INTERFACE:FindFirstChild("Skip")
    
    if skip and skip.Visible then
        -- Click skip multiple times
        for i = 1, 5 do
            local interact = skip:FindFirstChild("Interact")
            if interact then
                UseButton(interact)
            end
            task.wait(0.3)
            if not skip.Visible then break end
        end
    end
    
    -- ✅ ALWAYS TP to refill (chahe skip tha ya nahi)
    task.wait(0.5)
    pcall(function()
        local refillPart = getCachedRefillPart()
        if refillPart and refillPart.Parent then
            local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = refillPart.CFrame * CFrame.new(0, 5, 10)
            end
        end
    end)
end
	-- Auto Open Chests (US Suite logic — polling based, works even if event missed)
	-- Auto Open Chests (ULTRA FIX - forces both chests to open)
if getgenv().AutoChest then
    local chests = INTERFACE:FindFirstChild("Chests")
    if chests and chests.Visible then
        local free = chests:FindFirstChild("Free")
        local premium = chests:FindFirstChild("Premium")
        local finish = chests:FindFirstChild("Finish")

        -- Step 1: Open Free Chest + WAIT
        if free and free.Visible then
            UseButton(free)
            repeat task.wait(0.5) until not free.Visible or not chests.Visible
        end

        -- Step 2: Open Premium Chest + WAIT (if enabled)
        if premium and premium.Visible and getgenv().OpenSecondChest then
            -- Small delay to ensure free chest animation completes
            task.wait(0.5)
            
            if premium.Visible then
                UseButton(premium)
                repeat task.wait(0.5) until not premium.Visible or not chests.Visible
            end
        end

        -- Step 3: Finish button (ONLY after both done)
        if finish and finish.Visible then
            task.wait(0.3)
            UseButton(finish)
        end
    end
end

if getgenv().AutoRetry then
        local rewardsGui = INTERFACE:FindFirstChild("Rewards")
        if rewardsGui and rewardsGui.Visible then
            -- Method 1: Direct button path
            local retryBtn = rewardsGui:FindFirstChild("Main")
                and rewardsGui.Main:FindFirstChild("Info")
                and rewardsGui.Main.Info:FindFirstChild("Main")
                and rewardsGui.Main.Info.Main:FindFirstChild("Buttons")
                and rewardsGui.Main.Info.Main.Buttons:FindFirstChild("Retry")
            
            -- Method 2: Search all descendants for "Retry" button
            if not retryBtn or not retryBtn.Visible then
                for _, btn in ipairs(rewardsGui:GetDescendants()) do
                    if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible and btn.Active then
                        if btn.Name == "Retry" or (btn:IsA("TextButton") and btn.Text:find("Retry")) then
                            retryBtn = btn
                            break
                        end
                    end
                end
            end
            
            -- Method 3: Click via VirtualInputManager directly
            if retryBtn and retryBtn.Visible and retryBtn.Active then
                -- Wait a bit for UI to fully load
                task.wait(0.5)
                
                -- Try multiple click methods
                local clicked = false
                
                -- Try 1: UseButton function
                clicked = UseButton(retryBtn)
                
                -- Try 2: Direct VIM click
                if not clicked then
                    GuiService.SelectedObject = retryBtn
                    task.wait(0.1)
                    vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
                    vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                    clicked = true
                end
                
                -- Try 3: Mouse click simulation
                if not clicked then
                    local pos = retryBtn.AbsolutePosition + retryBtn.AbsoluteSize / 2
                    vim:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
                    task.wait(0.1)
                    vim:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
                    clicked = true
                end
                
                if clicked then
                    print("Retry button clicked!")
                end
            else
                -- Button not found or not active, force refresh
                print("Retry button not ready, waiting...")
                task.wait(0.5)
            end
        end
    end
end

local function roll(targets, rarities)
	if not PlayerGui.Interface.Customisation.Visible then return end

	local familyString = PlayerGui.Interface.Customisation.Family.Family.Title.Text
	local familyName = targets and string.lower(string.split(familyString, " ")[1]) or nil
	local familyRarity = string.lower(string.match(familyString, "%((.-)%)") or "")

	local stopRolling = false
	if targets and familyName and table.find(targets, familyName) then stopRolling = true end
	if rarities and table.find(rarities, familyRarity) then stopRolling = true end
	if familyRarity == "mythical" then stopRolling = true end

	if stopRolling then
		getgenv().AutoRoll = false
		pcall(function()
			if Library and Library.Toggles and Library.Toggles.AutoRollToggle then
				Library.Toggles.AutoRollToggle:SetValue(false)
			end
		end)

		if familyRarity == "mythical" and webhook and webhook ~= "" then
			local rareMythicals = {"helos", "fritz", "reiss", "tybur"}
			local isRareMythical = false
			for _, name in ipairs(rareMythicals) do
				if string.find(string.lower(familyString), name) then
					isRareMythical = true
					break
				end
			end

			local payload = {
				content = isRareMythical and "🔥 RARE MYTHICAL! @everyone" or "✨ MYTHICAL FAMILY! @everyone",
				embeds = {{
					title = "Family Roll",
					color = isRareMythical and 16711680 or 16750848,
					fields = {
						{
							name = "Information",
							value = "```\n" ..
								"User: " .. lp.Name .. "\n" ..
								"Family: " .. tostring(familyString) .. "\n" ..
								"Rare Mythical: " .. (isRareMythical and "YES 🔥" or "No") .. "\n" ..
								"\n```",
							inline = true
						}
					},
					footer = { text = "AOTR Hub • " .. DateTime.now():FormatLocalTime("LTS", "en-us") },
					timestamp = DateTime.now():ToIsoDate()
				}}
			}

			request({
				Url = webhook,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(payload)
			})
		end

		pcall(function()
			Library:Notify({
				Title = "AOTR Hub",
				Description = "Target family rolled: " .. familyString,
				Time = 5,
			})
		end)
		return
	end

	if PlayerGui.Interface.Warning.Prompt.Visible then
		UseButton(PlayerGui.Interface.Warning.Prompt.Main.Yes)
		task.wait(0.5)
	end

	if familyFrame and not familyFrame.Visible then
		UseButton(PlayerGui.Interface.Customisation.Categories.Family.Interact)
		task.wait(1)
	end

	if rollButton then
		UseButton(rollButton)
	end
end

-- ==========================================
-- WEAPON RELOAD
-- ==========================================

local lastReloadTime = 0
local autoReloadEnabled = false
local autoRefillEnabled = false
local isReloading = false

local function getWeaponHUDFrame()
	local HUD = INTERFACE:FindFirstChild("HUD")
	if not HUD then return nil end
	local top = HUD:FindFirstChild("Main") and HUD.Main:FindFirstChild("Top")
	if not top then return nil end
	return top:FindFirstChild("7")
end

local function getBladeCount()
	local frame7 = getWeaponHUDFrame()
	if not frame7 then return nil end
	local blades = frame7:FindFirstChild("Blades")
	if not blades then return nil end
	local sets = blades:FindFirstChild("Sets")
	if not sets then return nil end
	return tonumber(sets.Text:match("(%d+)"))
end

local function getRefillPart()
	-- v8: Waves mode keeps its own refill props (workspace.Waves.Props /
	-- Zones), NOT Unclimbable. Check Waves first so AutoRefill works there.
	local waves = workspace:FindFirstChild("Waves")
	if waves then
		local props = waves:FindFirstChild("Props")
		local refillProp = props and (props:FindFirstChild("Refill") or props:FindFirstChild("Gas"))
		if refillProp then
			if refillProp:IsA("BasePart") then return refillProp end
			local inner = refillProp:FindFirstChild("Refill", true)
			if inner and inner:IsA("BasePart") then return inner end
		end
		local zones = waves:FindFirstChild("Zones")
		local refillZone = zones and (zones:FindFirstChild("Refill") or zones:FindFirstChild("Gas"))
		if refillZone then
			local hb = refillZone:IsA("BasePart") and refillZone or refillZone:FindFirstChild("Hitbox", true)
			if hb and hb:IsA("BasePart") then return hb end
		end
		local anyRefill = waves:FindFirstChild("Refill", true)
		if anyRefill and anyRefill:IsA("BasePart") then return anyRefill end
	end

	local climbable = workspace:FindFirstChild("Climbable")
	if not climbable then return nil end

	local refill = climbable:FindFirstChild("Refill", true)
	if refill then return refill end

	local unclimbable = workspace:FindFirstChild("Unclimbable")
	if unclimbable then
		local reloads = unclimbable:FindFirstChild("Reloads")
		if reloads then
			local gasTanks = reloads:FindFirstChild("GasTanks")
			if gasTanks then
				local r = gasTanks:FindFirstChild("Refill")
				if r then return r end
			end
		end

		local props = unclimbable:FindFirstChild("Props")
		if props then
			local hq = props:FindFirstChild("HQ")
			if hq then
				local gasTank = hq:FindFirstChild("GasTanks")
				if gasTank then
					local r = gasTank:FindFirstChild("Refill")
					if r then return r end
				end
				for _, child in ipairs(hq:GetChildren()) do
					local r = child:FindFirstChild("Refill")
					if r then return r end
				end
			end
		end

		return unclimbable:FindFirstChild("Refill", true)
	end

	return nil
end

local function getWeaponType()
	local frame7 = getWeaponHUDFrame()
	if not frame7 then return nil end
	local bladesFrame = frame7:FindFirstChild("Blades")
	local spearsFrame = frame7:FindFirstChild("Spears")
	if bladesFrame and bladesFrame.Visible then return "Blades" end
	if spearsFrame and spearsFrame.Visible then return "Spears" end
	return nil
end

local lastBladeReloadTime = 0
local lastRefillTime = 0
local cachedRefillPart = nil

local function getCachedRefillPart()
	if cachedRefillPart and cachedRefillPart.Parent then return cachedRefillPart end
	cachedRefillPart = getRefillPart()
	return cachedRefillPart
end

-- v8.2 (idea validada de script externo CDHW): the server teleports you to the
-- station on Attacks/Reload. Save position and fly back afterwards so the farm
-- resumes where it left off instead of re-hovering across the map. Humanized
-- wait (server needs a moment to restock); all refs re-validated (respawn safe).
local function refillAtStation()
	local part = Validators.refillPart(getCachedRefillPart())
	local root = Validators.root()
	if not part or not root then return false end
	local backTo = root.CFrame
	safeFire("Attacks", "Reload", part)
	task.wait(humanWait(1.8, 0.6))
	local fresh = Validators.root()
	if fresh and backTo then
		fresh.CFrame = backTo
		fresh.AssemblyLinearVelocity = V3_ZERO
	end
	return true
end

local function handleWeaponReload()
	if not autoReloadEnabled then return end
	if isReloading then return end
	if isLobby then return end
	if os.clock() - lastReloadTime < getgenv().AutoFarmConfig.ReloadCooldown then return end

	local HUD = INTERFACE:FindFirstChild("HUD")
	if not HUD then return end

	local weaponType = getWeaponType()
	if not weaponType then return end

	local refillPart = getCachedRefillPart()

	if weaponType == "Blades" then
		local current = getBladeCount() or 0

		if current == 0 and autoRefillEnabled then
			if os.clock() - lastRefillTime < 1.5 then return end
			isReloading = true
			lastReloadTime = os.clock()
			lastRefillTime = os.clock()
			pcall(refillAtStation)
			task.delay(1.5, function() isReloading = false end)
			return
		end

		local char = lp.Character
		local rig = char and char:FindFirstChild("Rig_" .. lp.Name)
		local allBroken = false
		if rig then
			local leftHand = rig:FindFirstChild("LeftHand")
			local rightHand = rig:FindFirstChild("RightHand")
			if leftHand and rightHand then
				allBroken = true
				for i = 1, 7 do
					local lb = leftHand:FindFirstChild("Blade_" .. i)
					local rb = rightHand:FindFirstChild("Blade_" .. i)
					if lb and rb and lb:GetAttribute("Broken") == nil then
						allBroken = false
						break
					end
				end
			end
		end
		if allBroken and current > 0 then
			isReloading = true
			lastReloadTime = os.clock()
			lastBladeReloadTime = os.clock()
			pcall(function() getRemote:InvokeServer("Blades", "Reload") end)
			task.delay(0.5, function() isReloading = false end)
			return
		end

	elseif weaponType == "Spears" then
		local frame7 = getWeaponHUDFrame()
		if not frame7 then return end
		local spearsFrame = frame7:FindFirstChild("Spears")
		local spearsLabel = spearsFrame and spearsFrame:FindFirstChild("Spears")
		if not spearsLabel then return end
		local spearCount = tonumber(spearsLabel.Text:match("(%d+)")) or 0
		if spearCount == 0 and autoRefillEnabled then
			if os.clock() - lastRefillTime < 1.5 then return end
			isReloading = true
			lastReloadTime = os.clock()
			lastRefillTime = os.clock()
			pcall(refillAtStation)
			task.delay(1.5, function() isReloading = false end)
		end
	end
end

task.spawn(function()
	while true do
		pcall(handleWeaponReload)
		task.wait(0.5)
	end
end)

getgenv().AutoEscape = false
postRemote.OnClientEvent:Connect(function(...)
	local args = {...}
	if getgenv().AutoEscape and args[1] == "Titans" and args[2] == "Grab_Event" then
		game:GetService("Players").LocalPlayer.PlayerGui.Interface.Buttons.Visible = not getgenv().AutoEscape
		postRemote:FireServer("Attacks", "Slash_Escape")
	end
end)

-- ==========================================
-- OBSIDIAN UI LIBRARY LOAD
-- ==========================================

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

-- v8.3 UI feedback: quiet confirm when the user flips anything (presets set
-- _silentUI while applying bulk changes so they stay a single notify).
local function uiFeedback(text)
	-- Silence auto-expires (a preset dying mid-apply must never mute feedback forever)
	if getgenv()._silentUI and os.clock() - (getgenv()._silentSince or 0) < 15 then return end
	getgenv()._silentUI = false
	pcall(function()
		Library:Notify({ Title = "AOTR Hub", Description = text, Time = 1.2 })
	end)
end

task.spawn(function()
	task.wait(1)
	pcall(function() Library:SetFont(Enum.Font.BuilderSans) end)
end)

local Window = Library:CreateWindow({
	Title = "AOTR Hub",
	Footer = "AOT:R | FREE",
	Center = true,
	AutoShow = true,
	Resizable = true,
	ShowCustomCursor = true,
})

local Tabs = {
	Farm     = Window:AddTab("Farm",     "house"),
	Utility  = Window:AddTab("Combat",  "zap"),
	Session  = Window:AddTab("Session", "timer"),
	Configs  = Window:AddTab("Presets", "settings-2"),
	Upgrades = Window:AddTab("Upgrades", "trending-up"),
	Waves    = Window:AddTab("Waves", "waves-horizontal"),
	Visuals  = Window:AddTab("Visuals",  "eye"),
	Global   = Window:AddTab("Account",   "globe"),
	Stats    = Window:AddTab("Stats",    "activity"),
	Settings = Window:AddTab("Settings", "settings"),
	Theme    = Window:AddTab("Theme", "paintbrush"),
}

-- Farm tab (v8.4: Auto Farm keeps core only; upkeep + safety live below/around)
local MiscGroup      = Tabs.Farm:AddLeftGroupbox("Quick Actions", "compass")
local MainGroup      = Tabs.Farm:AddLeftGroupbox("Auto Farm", "tractor")
local UpkeepGroup    = Tabs.Farm:AddLeftGroupbox("Upkeep", "wrench")
local MovementGroup  = Tabs.Farm:AddRightGroupbox("Flight & Movement", "move")
local AutoStartGroup = Tabs.Farm:AddRightGroupbox("Mission Setup", "power")
local SafetyGroup    = Tabs.Farm:AddRightGroupbox("Safety", "shield-check")

-- Utility tab
local CombatGroup   = Tabs.Utility:AddLeftGroupbox("Attack", "shield")
-- Session tab (v8.3: moved here from Combat — 3rd tab, plug-and-play reachable)
local SecurityGroup = Tabs.Session:AddLeftGroupbox("Protection", "shield")
local BoostGroup    = Tabs.Session:AddLeftGroupbox("Boosted Map", "flame")
local MasteryGroup  = Tabs.Utility:AddRightGroupbox("Shifter Mastery", "award")
local FeaturesGroup = Tabs.Session:AddRightGroupbox("Session", "timer")

-- Configs tab
local ConfigsGroup = Tabs.Configs:AddLeftGroupbox("One-Click Presets", "zap")

-- Upgrades tab
local UpgradesGroup  = Tabs.Upgrades:AddLeftGroupbox("Gear Upgrades", "trending-up")
local SkillTreeGroup = Tabs.Upgrades:AddRightGroupbox("Skill Tree", "git-branch")

-- Waves tab
local WavesFarmGroup  = Tabs.Waves:AddLeftGroupbox("Waves Autofarm", "flame")
local WavesGearGroup   = Tabs.Waves:AddLeftGroupbox("Gear & Blessings", "shield")
local WavesHQGroup     = Tabs.Waves:AddRightGroupbox("HQ Upgrades", "heart")
local WavesMarketGroup = Tabs.Waves:AddRightGroupbox("Black Market & Medical", "shopping-cart")


-- Visuals tab
local VisualsESPGroup = Tabs.Visuals:AddLeftGroupbox("Titan ESP", "eye")
local VisualsSettingsGroup = Tabs.Visuals:AddRightGroupbox("Display", "settings")


-- Global tab
local FamilyRollGroup = Tabs.Global:AddLeftGroupbox("Family Summon", "shuffle")
local SettingsGroup   = Tabs.Global:AddLeftGroupbox("Automation", "settings")
local SlotGroup       = Tabs.Global:AddRightGroupbox("Slots & Prestige", "list")
local WebhookGroup    = Tabs.Global:AddRightGroupbox("Discord Alerts", "link")

-- Stats tab
local SessionGroup = Tabs.Stats:AddLeftGroupbox("Session", "clock")
local RatesGroup   = Tabs.Stats:AddRightGroupbox("Rates", "gauge")
local CrashGroup   = Tabs.Stats:AddRightGroupbox("Crash Recovery", "log-in")


-- ==========================================
-- FARM TAB : Misc
-- ==========================================

MiscGroup:AddButton({
	Text = "Return to Lobby",
	Func = function()
		getRemote:InvokeServer("Functions", "Teleport", "Lobby")
		TeleportService:Teleport(14916516914, lp)
	end,
})

MiscGroup:AddButton({
	Text = "Check Shadow Ban",
	Func = function()
		if game.PlaceId ~= 14916516914 then
			Library:Notify({ Title = "Error", Description = "Must be in lobby!", Time = 3 })
			return
		end
		local bl = lp:GetAttribute("Blacklisted") == true
		local ex = lp:GetAttribute("Exploiter") == true
		local lv = tostring(lp:GetAttribute("Level") or "N/A")
		local pr = tostring(lp:GetAttribute("Prestige") or "N/A")
		local flags = (bl and 1 or 0) + (ex and 1 or 0)
		local res = flags == 0 and "✅ Clean" or (flags == 1 and "⚠️ Flagged" or "🚫 Banned")
		Library:Notify({
			Title = "Shadow Ban Check",
			Description = 
				"Blacklisted: " .. (bl and "YES ❌" or "No ✅") ..
				"\nExploiter: " .. (ex and "YES ❌" or "No ✅") ..
				"\nLevel: " .. lv ..
				"\nPrestige: " .. pr ..
				"\n\nStatus: " .. res,
			Time = 8
		})
	end,
})

MiscGroup:AddButton({
	Text = "YouTube Channel",
	Func = function()
		setclipboard("https://www.youtube.com/@Npc_CertifiedYt")
		Library:Notify({ Title = "YouTube", Description = "Channel link copied!", Time = 5 })
	end,
	Tooltip = "Copies the creator's YouTube channel link"
})

-- ==========================================
-- FARM TAB : Farm
-- ==========================================

getgenv().CurrentStatusLabel = MainGroup:AddLabel("Status: Idle")

-- v8.3/v8.4: upkeep controls live in their own group (plug-and-play visible),
-- not buried in Combat and not crowding Auto Farm. Advanced tuning (radius,
-- multi-hit, priority) stays in Combat.
UpkeepGroup:AddToggle("AutoReloadToggle", {
	Text = "Auto Reload & Refill",
	Default = false,
	Tooltip = "Swaps blade sets in-field; teleports to a refill station when empty, then flies back"
})
Toggles.AutoReloadToggle:OnChanged(function()
	autoReloadEnabled = Toggles.AutoReloadToggle.Value
	autoRefillEnabled = Toggles.AutoReloadToggle.Value
	uiFeedback("Auto Reload & Refill " .. (Toggles.AutoReloadToggle.Value and "ON" or "OFF"))
end)

UpkeepGroup:AddButton({
	Text = "Teleport to Refill",
	Func = function()
		local refillPart = getRefillPart()
		if not refillPart then
			Library:Notify({ Title = "AOTR Hub", Description = "Refill station not found!", Time = 3 })
			return
		end
		local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			Library:Notify({ Title = "AOTR Hub", Description = "Character not loaded yet!", Time = 3 })
			return
		end
		root.CFrame = refillPart.CFrame * CFrame.new(0, 5, 10)
		Library:Notify({ Title = "AOTR Hub", Description = "Teleported to refill station!", Time = 2 })
	end,
	Tooltip = "Teleports directly to the nearest refill station"
})

UpkeepGroup:AddToggle("AutoEscapeToggle", {
	Text = "Escape Titan Grab",
	Default = false,
	Tooltip = "Automatically escapes when grabbed by a titan"
})
Toggles.AutoEscapeToggle:OnChanged(function()
	getgenv().AutoEscape = Toggles.AutoEscapeToggle.Value
	uiFeedback("Escape Titan Grab " .. (Toggles.AutoEscapeToggle.Value and "ON" or "OFF"))
end)

MainGroup:AddToggle("AutoKillToggle", {
	Text = "Auto Farm",
	Default = false,
	Tooltip = "CORE: hover-combat loop — targets, kills and loots titans unattended"
})
Toggles.AutoKillToggle:OnChanged(function()
	if Toggles.AutoKillToggle.Value then AutoFarm:Start() else AutoFarm:Stop() end
	uiFeedback("Auto Farm " .. (Toggles.AutoKillToggle.Value and "ON — good hunting" or "OFF"))
end)

MainGroup:AddToggle("LastTitanWaitToggle", {
	Text = "Delay Final Kill",
	Default = false,
	Tooltip = "Holds the last titan so teammates can catch up on rewards"
})
Toggles.LastTitanWaitToggle:OnChanged(function()
	getgenv().LastTitanWait = Toggles.LastTitanWaitToggle.Value
	uiFeedback("Delay Final Kill " .. (Toggles.LastTitanWaitToggle.Value and "ON" or "OFF"))
end)

MainGroup:AddSlider("LastTitanWaitSlider", {
	Text = "Delay (sec, from mission start)",
	Default = 60,
	Min = 10,
	Max = 300,
	Rounding = 0,
})
Options.LastTitanWaitSlider:OnChanged(function()
	getgenv().LastTitanWaitSecs = Options.LastTitanWaitSlider.Value
end)


MainGroup:AddToggle("AutoRetryToggle", {
	Text = "Auto-Retry Mission",
	Default = false,
	Tooltip = "Instantly queues the next run when the mission ends"
})
Toggles.AutoRetryToggle:OnChanged(function()
	getgenv().AutoRetry = Toggles.AutoRetryToggle.Value
	uiFeedback("Auto-Retry " .. (Toggles.AutoRetryToggle.Value and "ON" or "OFF"))
	if getgenv().AutoRetry then ExecuteImmediateAutomation() end
end)

MainGroup:AddToggle("SoloOnlyToggle", {
	Text = "Solo Missions Only",
	Default = false,
	Tooltip = "Automatically leaves if another player joins your mission"
})
Toggles.SoloOnlyToggle:OnChanged(function()
	getgenv().SoloOnly = Toggles.SoloOnlyToggle.Value
	uiFeedback("Solo Missions Only " .. (Toggles.SoloOnlyToggle.Value and "ON" or "OFF"))
end)

MainGroup:AddToggle("AutoReturnLobbyToggle", {
	Text = "Auto-Return to Lobby",
	Default = false,
	Tooltip = "Returns to lobby after completing specified number of games"
})
Toggles.AutoReturnLobbyToggle:OnChanged(function()
	getgenv().AutoReturnLobby = Toggles.AutoReturnLobbyToggle.Value
	if not getgenv().AutoReturnLobby then
		pcall(function() writefile(returnCounterPath, "0") end)
	end
	uiFeedback("Auto-Return to Lobby " .. (Toggles.AutoReturnLobbyToggle.Value and "ON" or "OFF"))
end)

MainGroup:AddSlider("ReturnAfterGamesSlider", {
	Text = "Games Before Lobby Return",
	Default = 10,
	Min = 1,
	Max = 250,
	Rounding = 0,
	Tooltip = "Number of games to complete before auto returning to lobby"
})
Options.ReturnAfterGamesSlider:OnChanged(function()
	getgenv().ReturnAfterGames = Options.ReturnAfterGamesSlider.Value
end)

-- ==========================================
-- FARM TAB : Movement
-- ==========================================

MovementGroup:AddDropdown("MovementModeDropdown", {
	Values = {"Hover", "Teleport"},
	Default = 1,
	Multi = false,
	Text = "Movement Mode",
	Tooltip = "Hover: Smooth flight | Teleport: Instant movement"
})
Options.MovementModeDropdown:OnChanged(function()
	getgenv().AutoFarmConfig.MovementMode = Options.MovementModeDropdown.Value
	-- v8.3: flight speed only applies to Hover; hide it in Teleport mode
	pcall(function()
		Options.HoverSpeedSlider:SetVisible(Options.MovementModeDropdown.Value == "Hover")
	end)
	uiFeedback("Movement: " .. tostring(Options.MovementModeDropdown.Value))
end)

MovementGroup:AddSlider("HoverSpeedSlider", {
	Text = "Flight Speed",
	Default = 260,
	Min = 100,
	Max = 700,
	Rounding = 0,
	Tooltip = "Hover velocity (studs/s). Legit ODM caps at 300 — above reads as exploit"
})
Options.HoverSpeedSlider:OnChanged(function()
	getgenv().AutoFarmConfig.MoveSpeed = Options.HoverSpeedSlider.Value
end)

MovementGroup:AddSlider("FloatHeightSlider", {
	Text = "Attack Height",
	Default = 180,
	Min = 100,
	Max = 1000,
	Rounding = 0,
	Tooltip = "Engage altitude above the target (both Hover and Teleport modes)"
})
Options.FloatHeightSlider:OnChanged(function()
	getgenv().AutoFarmConfig.HeightOffset = Options.FloatHeightSlider.Value
end)

MovementGroup:AddToggle("NoclipToggle", {
	Text = "NoClip (Fly Through Walls)",
	Default = false,
	Tooltip = "Walk through walls and objects"
})
Toggles.NoclipToggle:OnChanged(function()
	setNoclip(Toggles.NoclipToggle.Value)
	uiFeedback("NoClip " .. (Toggles.NoclipToggle.Value and "ON" or "OFF"))
end)

-- ==========================================
-- AUTO USE HOOKS
-- ==========================================

getgenv().AutoHooks = false

SafetyGroup:AddToggle("AutoHooksToggle", {
	Text = "Auto Grapple",
    Default = false,
    Tooltip = "Fires your grapple hooks on a timer (looks like active play)"
})
Toggles.AutoHooksToggle:OnChanged(function()
    getgenv().AutoHooks = Toggles.AutoHooksToggle.Value
    uiFeedback("Auto Grapple " .. (Toggles.AutoHooksToggle.Value and "ON" or "OFF"))
    
    if getgenv().AutoHooks then
        task.spawn(function()
            local vim = game:GetService("VirtualInputManager")
            
            while getgenv().AutoHooks do
                -- Press Q
                vim:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
                task.wait(2)
                vim:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
                
                task.wait(0.1)
                
                -- Press E
                vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(2)
                vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                
                -- Wait 3 seconds before next hooks
                task.wait(3)
            end
        end)
    end
end)

-- ==========================================
-- SAFE FARM (Auto Click Every 1s)
-- ==========================================

getgenv().SafeFarm = false

SafetyGroup:AddToggle("SafeFarmToggle", {
	Text = "Auto Click Attack",
    Default = false,
    Tooltip = "Clicks attack once per second (manual-play camouflage)"
})
Toggles.SafeFarmToggle:OnChanged(function()
    getgenv().SafeFarm = Toggles.SafeFarmToggle.Value
    uiFeedback("Auto Click Attack " .. (Toggles.SafeFarmToggle.Value and "ON" or "OFF"))
    
    if getgenv().SafeFarm then
        task.spawn(function()
            local vim = game:GetService("VirtualInputManager")
            
            while getgenv().SafeFarm do
                pcall(function()
                    -- Left click down
                    vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                    task.wait(0.5)
                    -- Left click up
                    vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                end)
                task.wait(1) -- Every 1 second
            end
        end)
    end
end)
-- ==========================================
-- AUTO DOUBLE JUMP BOOST (Auto Space Press)
-- ==========================================

getgenv().DoubleJumpBoost = false

SafetyGroup:AddToggle("DoubleJumpToggle", {
	Text = "Auto Jump Boost",
    Default = false,
    Tooltip = "Double-jumps every 5s so you never look idle/AFK"
})
Toggles.DoubleJumpToggle:OnChanged(function()
    getgenv().DoubleJumpBoost = Toggles.DoubleJumpToggle.Value
    uiFeedback("Auto Jump Boost " .. (Toggles.DoubleJumpToggle.Value and "ON" or "OFF"))
    
    if getgenv().DoubleJumpBoost then
        task.spawn(function()
            local vim = game:GetService("VirtualInputManager")
            
            while getgenv().DoubleJumpBoost do
                -- Press Space twice quickly
                vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.wait(0.1)
                vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                
                task.wait(0.05)
                
                vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.wait(0.1)
                vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                
                -- Wait 4 seconds before next boost
                task.wait(5)
            end
        end)
    end
end)


-- ==========================================
-- UTILITY TAB : Combat
-- ==========================================

-- UTILITY TAB : Combat (advanced tuning; core survival moved to Farm, v8.3)

CombatGroup:AddSlider("AttackRangeSlider", {
	Text = "Attack Radius",
	Default = 150,
	Min = 100,
	Max = 400,
	Rounding = 0,
	Tooltip = "Engage range in studs (capped: cross-map hits read as exploit)"
	
})
Options.AttackRangeSlider:OnChanged(function()
    getgenv().AutoFarmConfig.AttackRange = Options.AttackRangeSlider.Value
end)


CombatGroup:AddToggle("MultiHitToggle", {
	Text = "Multi-Target Hits",
	Default = false,
	Tooltip = "Hits multiple titans with a single attack"
})
Toggles.MultiHitToggle:OnChanged(function()
	getgenv().MultiHit = Toggles.MultiHitToggle.Value
	uiFeedback("Multi-Target Hits " .. (Toggles.MultiHitToggle.Value and "ON" or "OFF"))
end)

CombatGroup:AddSlider("MultiHitCountSlider", {
	Text = "Max Titans per Hit",
	Default = 3,
	Min = 2,
	Max = 10,
	Rounding = 0,
	Tooltip = "Titans hit per attack (capped at 10: above reads as exploit traffic)"
})
Options.MultiHitCountSlider:OnChanged(function()
	getgenv().MultiHitCount = Options.MultiHitCountSlider.Value
end)

-- v8.4 Nape Visualizer (client-only): green boxes on living napes so you can
-- verify targeting at a glance. Purely visual, sends nothing, touches nothing.
local napeAdorns = {}
local function clearNapeVisuals()
	for _, ad in pairs(napeAdorns) do
		pcall(function() ad:Destroy() end)
	end
	table.clear(napeAdorns)
end
CombatGroup:AddToggle("NapeVisualizerToggle", {
	Text = "Nape Visualizer",
	Default = false,
	Tooltip = "Green boxes on living napes (visual only)"
})
Toggles.NapeVisualizerToggle:OnChanged(function()
	getgenv().NapeVisualizer = Toggles.NapeVisualizerToggle.Value
	if not getgenv().NapeVisualizer then clearNapeVisuals()
	else
		task.spawn(function()
			while getgenv().NapeVisualizer do
				pcall(function()
					local folder = workspace:FindFirstChild("Titans")
					if folder then
						local seen = {}
						for _, titan in ipairs(folder:GetChildren()) do
							if titan:GetAttribute("Dead") or titan:GetAttribute("Killed") then continue end
							local hit = titan:FindFirstChild("Hitboxes") and titan.Hitboxes:FindFirstChild("Hit")
							local nape = hit and hit:FindFirstChild("Nape")
							if nape and nape:IsA("BasePart") then
								seen[nape] = true
								if not napeAdorns[nape] then
									local ad = Instance.new("BoxHandleAdornment")
									ad.Name = "AOTR_NapeViz"
									ad.Adornee = nape
									ad.Size = nape.Size + Vector3.new(0.5, 0.5, 0.5)
									ad.Color3 = Color3.fromRGB(57, 255, 20)
									ad.Transparency = 0.5
									ad.AlwaysOnTop = true
									ad.ZIndex = 5
									ad.Parent = nape
									napeAdorns[nape] = ad
								end
							end
						end
						for part in pairs(napeAdorns) do
							if not seen[part] or not part.Parent then
								pcall(function() napeAdorns[part]:Destroy() end)
								napeAdorns[part] = nil
							end
						end
					end
				end)
				task.wait(1)
			end
		end)
	end
	uiFeedback("Nape Visualizer " .. (Toggles.NapeVisualizerToggle.Value and "ON" or "OFF"))
end)

CombatGroup:AddDropdown("TargetPriorityDropdown", {
	Values = {"Titans", "Boss", "None"},
	Default = 1,
	Multi = false,
	Text = "Target Priority (Raid, etc)",
	Tooltip = "Titans: focus regular titans first | Boss: focus bosses first | None: closest target"
})
Options.TargetPriorityDropdown:OnChanged(function()
	getgenv().AutoFarmConfig.TargetPriority = Options.TargetPriorityDropdown.Value
	getgenv().TargetPriority = Options.TargetPriorityDropdown.Value
	uiFeedback("Target Priority: " .. tostring(Options.TargetPriorityDropdown.Value))
end)

-- ==========================================
-- SESSION TAB : Protection
-- ==========================================

SecurityGroup:AddDropdown("FarmOptionsDropdown", {
	Values = {"Auto Execute", "Failsafe", "Open Second Chest"},
	Default = {},
	Multi = true,
	Text = "Farm Options",
	Tooltip = "Auto Execute: Re-run script after teleport | Failsafe: Return to lobby after timeout | Open Second Chest: Open premium chests"
})
Options.FarmOptionsDropdown:OnChanged(function()
	local vals = Options.FarmOptionsDropdown.Value
	getgenv().AutoFailsafe = vals["Failsafe"] or false
	getgenv().AutoExecute = vals["Auto Execute"] or false
	getgenv().OpenSecondChest = vals["Open Second Chest"] or false
	if getgenv().AutoExecute then setupAutoExecute() end
end)

SecurityGroup:AddLabel("Returns you to the lobby\nif the mission stalls.")

SecurityGroup:AddSlider("FailsafeMinsSlider", {
	Text = "Failsafe Timeout (min)",
	Default = 15,
	Min = 5,
	Max = 60,
	Rounding = 0,
	Tooltip = "Minutes before a stalled mission auto-returns to lobby"
})
Options.FailsafeMinsSlider:OnChanged(function()
	getgenv().FailsafeMins = Options.FailsafeMinsSlider.Value
end)

SecurityGroup:AddToggle("PerformanceModeToggle", {
	Text = "Performance Mode",
	Default = false,
	Tooltip = "One switch: hides map + disables 3D rendering for max FPS"
})
Toggles.PerformanceModeToggle:OnChanged(function()
	getgenv()._silentUI = true getgenv()._silentSince = os.clock()
	pcall(function() Toggles.DeleteMapToggle:SetValue(Toggles.PerformanceModeToggle.Value) end)
	pcall(function() Toggles.Disable3DRendering:SetValue(Toggles.PerformanceModeToggle.Value) end)
	getgenv()._silentUI = false
	uiFeedback("Performance Mode " .. (Toggles.PerformanceModeToggle.Value and "ON" or "OFF"))
end)

-- ==========================================
-- SESSION TAB : Boosted Maps
-- ==========================================

BoostGroup:AddToggle("AutoJoinBoostedMapToggle", {
	Text = "Join Boosted Map",
	Default = false,
	Tooltip = "Automatically detects and joins maps with active 2x rewards boost"
})
Toggles.AutoJoinBoostedMapToggle:OnChanged(function()
	getgenv().AutoJoinBoostedMap = Toggles.AutoJoinBoostedMapToggle.Value
	if getgenv().AutoJoinBoostedMap then
		task.spawn(function()
			local lastBoostedMap = nil
			while getgenv().AutoJoinBoostedMap do
				if game.PlaceId ~= 14916516914 then
					local currentBoostedMap = workspace:GetAttribute("Boosted_Map")
					if currentBoostedMap and currentBoostedMap ~= lastBoostedMap then
						Library:Notify({ Title = "🔄 Boost Changed!", Description = "New boost: " .. currentBoostedMap .. "\nReturning to lobby...", Time = 5 })
						if AutoFarm and AutoFarm._running then AutoFarm:Stop() end
						pcall(function() getRemote:InvokeServer("Functions", "Teleport", "Lobby") end)
						task.wait(0.5)
						pcall(function() TeleportService:Teleport(14916516914, lp) end)
						lastBoostedMap = nil
						task.wait(5)
						continue
					end
					task.wait(10)
					continue
				end

				local boostedMap = workspace:GetAttribute("Boosted_Map")
				local boostedTimer = workspace:GetAttribute("Boosted_Timer")
				
				if boostedMap and boostedMap ~= "" and boostedMap ~= lastBoostedMap then
					lastBoostedMap = boostedMap
					Library:Notify({ Title = "🎯 Boost Found!", Description = "Map: " .. boostedMap .. " | Time: " .. tostring(boostedTimer or "N/A") .. "s", Time = 5 })
					
					pcall(function()
						for _, m in next, ReplicatedStorage.Missions:GetChildren() do
							if m:FindFirstChild("Leader") and m.Leader.Value == lp.Name then
								getRemote:InvokeServer("S_Missions", "Leave")
							end
						end
					end)
					task.wait(1)
					
					local created = false
					for _, diff in ipairs({"Aberrant", "Severe", "Hard", "Normal"}) do
						if created then break end
						pcall(function()
							getRemote:InvokeServer("S_Missions", "Create", {
								Difficulty = diff, Type = "Missions",
								Name = boostedMap, Objective = "Skirmish"
							})
						end)
						task.wait(0.5)
						for _, m in next, ReplicatedStorage.Missions:GetChildren() do
							if m:FindFirstChild("Leader") and m.Leader.Value == lp.Name then
								created = true; break
							end
						end
					end
					
					if created then
						task.wait(0.5)
						if getgenv().AutoModifiers then
							for _, mod in ipairs({"No Perks","No Skills","No Memories","Nightmare","Oddball","Injury Prone","Chronic Injuries","Fog","Glass Cannon"}) do
								pcall(function() getRemote:InvokeServer("S_Missions", "Modify", mod) end)
								task.wait(0.05)
							end
						end
						pcall(function() getRemote:InvokeServer("S_Missions", "Start") end)
						Library:Notify({ Title = "✅ Farming Boosted Map!", Description = "Map: " .. boostedMap, Time = 3 })
					end
				else
					task.wait(5)
				end
			end
		end)
	end
end)

BoostGroup:AddToggle("AutoModifiersToggle", {
	Text = "All Mission Modifiers",
	Default = false,
	Tooltip = "Enables all mission modifiers for maximum rewards multiplier"
})
Toggles.AutoModifiersToggle:OnChanged(function()
	getgenv().AutoModifiers = Toggles.AutoModifiersToggle.Value
end)

BoostGroup:AddButton({
	Text = "Check Boosted Map",
	Func = function()
		local boostedMap = workspace:GetAttribute("Boosted_Map")
		local boostedTimer = workspace:GetAttribute("Boosted_Timer")
		if boostedMap and boostedMap ~= "" then
			Library:Notify({ Title = "Current Boost", Description = "Map: " .. boostedMap .. "\nTime Left: " .. tostring(boostedTimer or "N/A") .. "s", Time = 8 })
		else
			Library:Notify({ Title = "No Boost", Description = "No boosted map active!", Time = 5 })
		end
	end,
	Tooltip = "Shows which map currently has active boost"
})

BoostGroup:AddLabel("Auto joins boosted map with\nall modifiers for max rewards!")

-- ==========================================
-- UTILITY TAB : Mastery Farm
-- ==========================================

MasteryGroup:AddToggle("MasteryFarmToggle", {
	Text = "Shifter Mastery Farm",
	Default = false,
	Tooltip = "Farms titan mastery by auto punch and using skills"
})
Toggles.MasteryFarmToggle:OnChanged(function()
	getgenv().MasteryFarmConfig.Enabled = Toggles.MasteryFarmToggle.Value
	if Toggles.MasteryFarmToggle.Value then
		if not Toggles.AutoKillToggle.Value then
			Toggles.AutoKillToggle:SetValue(true)
		elseif not AutoFarm._running then
			AutoFarm:Start()
		end
	end
end)

MasteryGroup:AddDropdown("MasteryModeDropdown", {
	Values = {"Punching", "Skill Usage", "Both"},
	Default = 3,
	Multi = false,
	Text = "Mastery Mode",
})
Options.MasteryModeDropdown:OnChanged(function()
	getgenv().MasteryFarmConfig.Mode = Options.MasteryModeDropdown.Value
end)

-- ==========================================
-- SESSION TAB : Session
-- ==========================================

FeaturesGroup:AddToggle("AutoSkipToggle", {
	Text = "Skip Cutscenes",
	Default = false,
	Tooltip = "Automatically skips mission cutscenes and animations"
})
Toggles.AutoSkipToggle:OnChanged(function()
	getgenv().AutoSkip = Toggles.AutoSkipToggle.Value
	uiFeedback("Skip Cutscenes " .. (Toggles.AutoSkipToggle.Value and "ON" or "OFF"))
	if getgenv().AutoSkip then ExecuteImmediateAutomation() end
end)


FeaturesGroup:AddToggle("DieAtStreakToggle", {
	Text = "Reset Run at Streak",
	Default = false,
	Tooltip = "Automatically dies when reaching specified streak count"
})
Toggles.DieAtStreakToggle:OnChanged(function()
	getgenv().DieAtStreak = Toggles.DieAtStreakToggle.Value
	uiFeedback("Reset Run at Streak " .. (Toggles.DieAtStreakToggle.Value and "ON" or "OFF"))
end)

FeaturesGroup:AddSlider("DieAtStreakSlider", {
	Text = "Streak Limit",
	Default = 10000,
	Min = 100,
	Max = 100000,
	Rounding = 0,
	Tooltip = "Streak count at which to auto die"
})
Options.DieAtStreakSlider:OnChanged(function()
	getgenv().DieAtStreakCount = Options.DieAtStreakSlider.Value
end)

FeaturesGroup:AddToggle("AutoChestToggle", {
	Text = "Auto-Open Chests",
	Default = false,
	Tooltip = "Automatically opens free and premium chests after missions"
})
Toggles.AutoChestToggle:OnChanged(function()
	getgenv().AutoChest = Toggles.AutoChestToggle.Value
	uiFeedback("Auto-Open Chests " .. (Toggles.AutoChestToggle.Value and "ON" or "OFF"))
end)

FeaturesGroup:AddToggle("DeleteMapToggle", {
	Text = "Hide Map (FPS Boost)",
	Default = DropdownConfig.DeleteMap or false,
	Tooltip = "Removes map objects for significant FPS improvement"
})
Toggles.DeleteMapToggle:OnChanged(function()
	getgenv().DeleteMap = Toggles.DeleteMapToggle.Value
	uiFeedback("Hide Map " .. (Toggles.DeleteMapToggle.Value and "ON" or "OFF"))
	DropdownConfig.DeleteMap = getgenv().DeleteMap
	SaveConfig(DropdownConfig)
	if getgenv().DeleteMap then DeleteMap() end
end)

FeaturesGroup:AddDivider()

FeaturesGroup:AddToggle("AutoBoostToggle", {
	Text = "Auto-Use Boosts",
	Default = false,
	Tooltip = "Automatically uses XP/Gold/Luck boosts from inventory when available"
})
Toggles.AutoBoostToggle:OnChanged(function()
	getgenv().AutoBoost = Toggles.AutoBoostToggle.Value
	uiFeedback("Auto-Use Boosts " .. (Toggles.AutoBoostToggle.Value and "ON" or "OFF"))
	if not getgenv().AutoBoost then return end
	task.spawn(function()
		local boostItems = {
			Gold = {"2x Gold Boost [30m]", "2x Gold Boost [15m]"},
			Luck = {"2x Luck Boost [30m]", "2x Luck Boost [15m]"},
			XP   = {"2x XP Boost [30m]",  "2x XP Boost [15m]"},
		}
		local function useBoost(boostType)
			for _, itemName in ipairs(boostItems[boostType]) do
				local ok, result = pcall(function()
					return getRemote:InvokeServer("S_Inventory", "Item", itemName)
				end)
				if ok and result ~= nil and result ~= false then
					Library:Notify({ Title = "Auto Boost", Description = "✅ " .. itemName, Time = 3 })
					return true
				end
			end
			return false
		end
		while getgenv().AutoBoost do
			local cfg = Options.BoostSelectDropdown.Value or {}
			if cfg["Gold"] then useBoost("Gold"); task.wait(0.5) end
			if cfg["Luck"] then useBoost("Luck"); task.wait(0.5) end
			if cfg["XP"]   then useBoost("XP");   task.wait(0.5) end
			task.wait(60)
		end
	end)
end)

FeaturesGroup:AddDropdown("BoostSelectDropdown", {
	Values = {"Gold", "Luck", "XP"},
	Default = {},
	Multi = true,
	Text = "Boosts to Auto Use",
	Tooltip = "Select which boost types to automatically use"
})

FeaturesGroup:AddButton({
	Text = "Use Selected Boosts",
	Func = function()
		task.spawn(function()
			local boostItems = {
				Gold = {"2x Gold Boost [2h]", "2x Gold Boost [1h]", "2x Gold Boost [30m]", "2x Gold Boost [15m]"},
	Luck = {"2x Luck Boost [2h]", "2x Luck Boost [1h]", "2x Luck Boost [30m]", "2x Luck Boost [15m]"},
	XP   = {"2x XP Boost [2h]",  "2x XP Boost [1h]", "2x XP Boost [30m]", "2x XP Boost [15m]"},
			}
			local cfg = Options.BoostSelectDropdown.Value or {}
			local used = 0
			for boostType, items in pairs(boostItems) do
				if cfg[boostType] then
					for _, itemName in ipairs(items) do
						local ok, result = pcall(function()
							return getRemote:InvokeServer("S_Inventory", "Item", itemName)
						end)
						if ok and result ~= nil and result ~= false then
							Library:Notify({ Title = "Auto Boost", Description = "✅ " .. itemName, Time = 3 })
							used += 1
							break
						end
					end
					task.wait(0.4)
				end
			end
			if used == 0 then
				Library:Notify({ Title = "Auto Boost", Description = "No items available!", Time = 3 })
			end
		end)
	end,
	Tooltip = "Immediately uses all available selected boosts"
})

-- ==========================================
-- FARM TAB : Auto Start
-- ==========================================

AutoStartGroup:AddToggle("AutoStartToggle", {
	Text = "Auto-Start Missions",
	Default = false,
	Tooltip = "Automatically creates and starts missions with selected settings"
})
Toggles.AutoStartToggle:OnChanged(function()
	getgenv().AutoStart = Toggles.AutoStartToggle.Value
	uiFeedback("Auto-Start Missions " .. (Toggles.AutoStartToggle.Value and "ON" or "OFF"))

	if getgenv().AutoStart and game.PlaceId == 14916516914 then
		task.spawn(function()
			local MAX_RETRIES = 10
			local retries = 0

			local function getMyMission()
				local start = os.clock()
				while (os.clock() - start) < 2 do
					for _, mission in next, ReplicatedStorage.Missions:GetChildren() do
						if mission:FindFirstChild("Leader") and mission.Leader.Value == lp.Name then
							return mission
						end
					end
					task.wait(0.1)
				end
				return nil
			end

			while getgenv().AutoStart do
				for _, mission in next, ReplicatedStorage.Missions:GetChildren() do
					if mission:FindFirstChild("Leader") and mission.Leader.Value == lp.Name then
						getRemote:InvokeServer("S_Missions", "Leave")
					end
				end

				local missionType = Options.StartTypeDropdown.Value
				local selectedDifficulty
				local mapName
				local objective

				if missionType == "Missions" then
					selectedDifficulty = Options.MissionDifficultyDropdown.Value
					mapName = Options.MissionMapDropdown.Value
					objective = Options.MissionObjectiveDropdown.Value
				elseif missionType == "Raids" then
    selectedDifficulty = Options.RaidDifficultyDropdown.Value
    mapName = Options.RaidMapDropdown.Value
    objective = RaidObjectives[mapName] or Options.RaidObjectiveDropdown.Value
    mapName = RaidMapNames[mapName] or mapName
elseif missionType == "Waves" then
    selectedDifficulty = "Easy"  -- Fixed Easy
    mapName = Options.WavesMapDropdown.Value or "Trost"
    objective = "Waves"
end

				local created = false

				if selectedDifficulty == "Hardest" then
					local diffOrder = missionType == "Raids"
						and {"Aberrant", "Severe", "Hard"}
						or {"Aberrant", "Severe", "Hard", "Normal", "Easy"}

					for _, diff in ipairs(diffOrder) do
						if not getgenv().AutoStart then break end
						getRemote:InvokeServer("S_Missions", "Create", {
							Difficulty = diff,
							Type = missionType,
							Name = mapName,
							Objective = objective
						})
						if getMyMission() then
							Library:Notify({ Title = "Auto Start", Description = "Selected difficulty: " .. diff, Time = 3 })
							created = true
							break
						end
					end
				else
					getRemote:InvokeServer("S_Missions", "Create", {
						Difficulty = selectedDifficulty,
						Type = missionType,
						Name = mapName,
						Objective = objective
					})
					if getMyMission() then created = true end
				end

				if not getgenv().AutoStart then break end

				if not created then
					retries = retries + 1
					local backoff = math.min(retries * 2, 20)
					if retries >= MAX_RETRIES then
						Library:Notify({ Title = "Auto Start", Description = "Failed after " .. MAX_RETRIES .. " retries. Stopping.", Time = 10 })
						getgenv().AutoStart = false
						Toggles.AutoStartToggle:SetValue(false)
						break
					end
					Library:Notify({ Title = "Auto Start", Description = "Failed to create. Retry " .. retries .. "/" .. MAX_RETRIES .. " in " .. backoff .. "s", Time = backoff })
					task.wait(backoff)
					continue
				end

				retries = 0

				local activeMods = {}
				if Options.ModifiersDropdown.Value then
					for modName, isActive in pairs(Options.ModifiersDropdown.Value) do
						if isActive then table.insert(activeMods, modName) end
					end
				end

				if #activeMods > 0 then
					for _, modifier in ipairs(activeMods) do
						getRemote:InvokeServer("S_Missions", "Modify", modifier)
					end
				end

				task.wait(0.5)

				if getgenv().WaitBeforeStart and getgenv().WaitBeforeStartSecs > 0 then
					Library:Notify({ Title = "Auto Start", Description = "Waiting " .. getgenv().WaitBeforeStartSecs .. "s before starting...", Time = getgenv().WaitBeforeStartSecs })
					task.wait(getgenv().WaitBeforeStartSecs)
				end

				getRemote:InvokeServer("S_Missions", "Start")
				task.wait(5)
			end
		end)
	end
end)

AutoStartGroup:AddToggle("WaitBeforeStartToggle", {
	Text = "Delay Start",
	Default = false,
	Tooltip = "Adds a delay before starting the mission after creation"
})
Toggles.WaitBeforeStartToggle:OnChanged(function()
	getgenv().WaitBeforeStart = Toggles.WaitBeforeStartToggle.Value
	uiFeedback("Delay Start " .. (Toggles.WaitBeforeStartToggle.Value and "ON" or "OFF"))
end)

AutoStartGroup:AddSlider("WaitBeforeStartSlider", {
	Text = "Delay (sec)",
	Default = 0,
	Min = 0,
	Max = 500,
	Rounding = 0,
	Tooltip = "Delay in seconds before mission starts"
})
Options.WaitBeforeStartSlider:OnChanged(function()
	getgenv().WaitBeforeStartSecs = Options.WaitBeforeStartSlider.Value
end)

AutoStartGroup:AddDropdown("StartTypeDropdown", {
	Values = {"Missions", "Raids", "Waves"},
	Default = DropdownConfig._lastType and table.find({"Missions", "Raids", "Waves"}, DropdownConfig._lastType) or 1,
	Multi = false,
	Text = "Type",
})
Options.StartTypeDropdown:OnChanged(function()
    local Value = Options.StartTypeDropdown.Value
    if not Value then return end
    DropdownConfig._lastType = Value
    SaveConfig(DropdownConfig)
    local isMission = Value == "Missions"
    local isRaid = Value == "Raids"
    local isWaves = Value == "Waves"
    
    -- Mission settings
    Options.MissionMapDropdown:SetVisible(isMission)
    Options.MissionObjectiveDropdown:SetVisible(isMission)
    Options.MissionDifficultyDropdown:SetVisible(isMission)
    
    -- Raid settings
    Options.RaidMapDropdown:SetVisible(isRaid)
    Options.RaidObjectiveDropdown:SetVisible(isRaid)
    Options.RaidDifficultyDropdown:SetVisible(isRaid)
    
    -- Waves settings
    Options.WavesMapDropdown:SetVisible(isWaves)
end)

AutoStartGroup:AddDropdown("MissionMapDropdown", {
	Values = {"Shiganshina","Trost","Outskirts","Forest","Utgard","Docks","Stohess","Chapel"},
	Default = DropdownConfig.Missions and table.find({"Shiganshina","Trost","Outskirts","Forest","Utgard","Docks","Stohess","Chapel"}, DropdownConfig.Missions.map) or 1,
	Multi = false,
	Text = "Mission Map",
})
Options.MissionMapDropdown:OnChanged(function()
	local Value = Options.MissionMapDropdown.Value
	if not Value then return end
	Options.MissionObjectiveDropdown:SetValues(Missions[Value] or {})
	DropdownConfig.Missions = DropdownConfig.Missions or {}
	DropdownConfig.Missions.map = Value
	SaveConfig(DropdownConfig)
end)

local initMissionMap = DropdownConfig.Missions and DropdownConfig.Missions.map or "Shiganshina"
local initMissionObjVals = Missions[initMissionMap] or {}
local initMissionObjDef = 1
if DropdownConfig.Missions and DropdownConfig.Missions.objective then
	initMissionObjDef = table.find(initMissionObjVals, DropdownConfig.Missions.objective) or 1
end

AutoStartGroup:AddDropdown("MissionObjectiveDropdown", {
	Values = initMissionObjVals,
	Default = initMissionObjDef,
	Multi = false,
	Text = "Mission Objective",
})
Options.MissionObjectiveDropdown:OnChanged(function()
	local Value = Options.MissionObjectiveDropdown.Value
	DropdownConfig.Missions = DropdownConfig.Missions or {}
	DropdownConfig.Missions.objective = Value
	SaveConfig(DropdownConfig)
end)

AutoStartGroup:AddDropdown("MissionDifficultyDropdown", {
	Values = {"Easy","Normal","Hard","Severe","Aberrant","Hardest"},
	Default = DropdownConfig.Missions and table.find({"Easy","Normal","Hard","Severe","Aberrant","Hardest"}, DropdownConfig.Missions.difficulty) or 2,
	Multi = false,
	Text = "Mission Difficulty",
})
Options.MissionDifficultyDropdown:OnChanged(function()
	local Value = Options.MissionDifficultyDropdown.Value
	DropdownConfig.Missions = DropdownConfig.Missions or {}
	DropdownConfig.Missions.difficulty = Value
	SaveConfig(DropdownConfig)
end)

AutoStartGroup:AddDivider()

AutoStartGroup:AddDropdown("RaidMapDropdown", {
	Values = {"Trost","Shiganshina","Stohess","Colossal"},
	Default = DropdownConfig.Raids and table.find({"Trost","Shiganshina","Stohess","Colossal"}, DropdownConfig.Raids.map) or 1,
	Multi = false,
	Text = "Raid Map",
})
Options.RaidMapDropdown:OnChanged(function()
	local Value = Options.RaidMapDropdown.Value
	if not Value then return end
	Options.RaidObjectiveDropdown:SetValues(Missions[Value] or {})
	DropdownConfig.Raids = DropdownConfig.Raids or {}
	DropdownConfig.Raids.map = Value
	SaveConfig(DropdownConfig)
end)

local initRaidMap = DropdownConfig.Raids and DropdownConfig.Raids.map or "Trost"
local initRaidObjVals = Missions[initRaidMap] or {}
local initRaidObjDef = 1
if DropdownConfig.Raids and DropdownConfig.Raids.objective then
	initRaidObjDef = table.find(initRaidObjVals, DropdownConfig.Raids.objective) or 1
end

AutoStartGroup:AddDropdown("RaidObjectiveDropdown", {
	Values = initRaidObjVals,
	Default = initRaidObjDef,
	Multi = false,
	Text = "Raid Objective",
})
Options.RaidObjectiveDropdown:OnChanged(function()
	local Value = Options.RaidObjectiveDropdown.Value
	DropdownConfig.Raids = DropdownConfig.Raids or {}
	DropdownConfig.Raids.objective = Value
	SaveConfig(DropdownConfig)
end)

AutoStartGroup:AddDropdown("RaidDifficultyDropdown", {
	Values = {"Hard","Severe","Aberrant","Hardest"},
	Default = DropdownConfig.Raids and table.find({"Hard","Severe","Aberrant","Hardest"}, DropdownConfig.Raids.difficulty) or 1,
	Multi = false,
	Text = "Raid Difficulty",
})
Options.RaidDifficultyDropdown:OnChanged(function()
	local Value = Options.RaidDifficultyDropdown.Value
	DropdownConfig.Raids = DropdownConfig.Raids or {}
	DropdownConfig.Raids.difficulty = Value
	SaveConfig(DropdownConfig)
end)

AutoStartGroup:AddLabel("Trost: Attack Titan\nShiganshina: Armored Titan\nStohess: Female Titan\nColossal: Colossal Titan", true)

AutoStartGroup:AddDivider()
-- Waves settings (only Easy difficulty)

AutoStartGroup:AddLabel("Waves Mode Settings:", true)

AutoStartGroup:AddDropdown("WavesMapDropdown", {
    Values = {"Trost"},
    Default = 1,
    Multi = false,
    Text = "Waves Map",
    Tooltip = "Select map for Waves mode"
})

-- Waves difficulty always Easy - no dropdown needed
AutoStartGroup:AddDivider()

AutoStartGroup:AddDropdown("ModifiersDropdown", {
	Values = {"No Perks","No Skills","No Memories","Nightmare","Oddball","Injury Prone","Chronic Injuries","Fog","Glass Cannon","Time Trial","Boring","Simple"},
	Default = {},
	Multi = true,
	Text = "Modifiers",
})

AutoStartGroup:AddToggle("AllModifiersToggle", {
	Text = "All Modifiers (Max Rewards)",
	Default = false,
	Tooltip = "Enables all 9 modifiers for maximum 3.5x reward multiplier"
})
Toggles.AllModifiersToggle:OnChanged(function()
	if Toggles.AllModifiersToggle.Value then
		Options.ModifiersDropdown:SetValue({
			["No Perks"] = true, ["No Skills"] = true, ["No Memories"] = true,
			["Nightmare"] = true, ["Oddball"] = true, ["Injury Prone"] = true,
			["Chronic Injuries"] = true, ["Fog"] = true, ["Glass Cannon"] = true,
		})
		Library:Notify({ Title = "Auto Start", Description = "All 9 modifiers enabled!", Time = 3 })
	else
		Options.ModifiersDropdown:SetValue({})
		Library:Notify({ Title = "Auto Start", Description = "Modifiers cleared!", Time = 3 })
	end
end)

task.defer(function()
	task.wait(0.2)
	local savedType = DropdownConfig._lastType or "Missions"
	Options.StartTypeDropdown:SetValue(savedType)
end)


-- ==========================================
-- CONFIGS TAB
-- ==========================================

ConfigsGroup:AddLabel("One-Click Config Presets")
ConfigsGroup:AddLabel("Presets set up CORE only (Farm, Combat, Mission Setup) — everything else stays as you left it.")

-- ==========================================
-- CONFIG 1: AFK Farming (Breach)
-- ==========================================
ConfigsGroup:AddToggle("AFKFarmingBreachToggle", {
    Text = "AFK Farming (Breach)",
    Default = false,
    Tooltip = "Plug-and-play Breach farmer. Affects: Farm, Combat, Mission Setup (Shiganshina/Hardest/10 mods), Boosts, Protection"
})
Toggles.AFKFarmingBreachToggle:OnChanged(function()
    if Toggles.AFKFarmingBreachToggle.Value then
        getgenv()._silentUI = true getgenv()._silentSince = os.clock() -- one summary notify, not 20 (see below)
        -- Turn OFF other configs
        pcall(function() Toggles.AFKFarmingDefendToggle:SetValue(false) end)
		pcall(function() Toggles.AFKFarmingWavesToggle:SetValue(false) end)
        
        -- Farm Settings
        pcall(function() Toggles.AutoKillToggle:SetValue(true) end)
        pcall(function() Toggles.AutoRetryToggle:SetValue(true) end)
        pcall(function() Toggles.SoloOnlyToggle:SetValue(true) end)
        
        -- Movement
        pcall(function() Options.MovementModeDropdown:SetValue("Teleport") end)
        pcall(function() Options.FloatHeightSlider:SetValue(170) end)
        pcall(function() Toggles.NoclipToggle:SetValue(true) end)
	    pcall(function() Toggles.AutoBoostToggle:SetValue(true) end) -- Auto boost
        
        -- Combat
        pcall(function() Toggles.AutoReloadToggle:SetValue(true) end)
        pcall(function() Toggles.AutoEscapeToggle:SetValue(true) end)
        pcall(function() Toggles.MultiHitToggle:SetValue(true) end)
        pcall(function() Options.MultiHitCountSlider:SetValue(3) end)
        
        -- Security
        pcall(function() Options.FarmOptionsDropdown:SetValue({
            ["Auto Execute"] = true, ["Failsafe"] = true
        }) end)
        
        -- Extras
        pcall(function() Toggles.DeleteMapToggle:SetValue(false) end)
        
        -- Auto Start - Breach
        pcall(function() Options.StartTypeDropdown:SetValue("Missions") end)
        pcall(function() Options.MissionMapDropdown:SetValue("Shiganshina") end)
        pcall(function() Options.MissionObjectiveDropdown:SetValue("Breach") end)
        pcall(function() Options.MissionDifficultyDropdown:SetValue("Hardest") end)
        pcall(function() Options.ModifiersDropdown:SetValue({
            ["No Perks"] = true, ["No Skills"] = true, ["No Memories"] = true,
            ["Nightmare"] = true, ["Oddball"] = true, ["Injury Prone"] = true,
            ["Chronic Injuries"] = true, ["Fog"] = true, ["Glass Cannon"] = true,
        }) end)
        pcall(function() Toggles.AutoStartToggle:SetValue(true) end)
        
        pcall(function() Toggles.AutoHideToggle:SetValue(true) end)
        getgenv()._silentUI = false -- bulk done: summary notify below is the only one
        
        Library:Notify({
            Title = "⚙️ AFK Farming (Breach) Applied!",
            Description = "Shiganshina | Breach | Hardest\nAll 10 Mods | Solo | Teleport",
            Time = 5
        })
        
        task.delay(3, function()
            if Library then Library:Toggle(false) end
        end)
    end
end)

-- ==========================================
-- CONFIG 2: AFK Farming (Defend)
-- ==========================================
ConfigsGroup:AddToggle("AFKFarmingDefendToggle", {
    Text = "AFK Farming (Defend)",
    Default = false,
    Tooltip = "Plug-and-play Defend farmer. Affects: Farm, Combat, Mission Setup (map/Hardest/10 mods), Boosts, Protection"
})
Toggles.AFKFarmingDefendToggle:OnChanged(function()
    if Toggles.AFKFarmingDefendToggle.Value then
        getgenv()._silentUI = true getgenv()._silentSince = os.clock() -- one summary notify, not 20 (see below)
        -- Turn OFF other configs
        pcall(function() Toggles.AFKFarmingBreachToggle:SetValue(false) end)
		pcall(function() Toggles.AFKFarmingWavesToggle:SetValue(false) end)
        
        -- Farm Settings
        pcall(function() Toggles.AutoKillToggle:SetValue(true) end)
        pcall(function() Toggles.AutoRetryToggle:SetValue(true) end)
        pcall(function() Toggles.SoloOnlyToggle:SetValue(true) end)
        
        -- Movement
        pcall(function() Options.MovementModeDropdown:SetValue("Teleport") end)
        pcall(function() Options.FloatHeightSlider:SetValue(170) end)
        pcall(function() Toggles.NoclipToggle:SetValue(true) end)
		pcall(function() Toggles.AutoBoostToggle:SetValue(true) end) -- Auto boost

		-- Extras
		pcall(function() Toggles.AutoSkipToggle:SetValue(true) end)
        
        -- Combat
        pcall(function() Toggles.AutoReloadToggle:SetValue(true) end)
        pcall(function() Toggles.AutoEscapeToggle:SetValue(true) end)
        pcall(function() Toggles.MultiHitToggle:SetValue(true) end)
        pcall(function() Options.MultiHitCountSlider:SetValue(3) end)
        
        -- Security
        pcall(function() Options.FarmOptionsDropdown:SetValue({
            ["Auto Execute"] = true, ["Failsafe"] = true
        }) end)
        
        -- Extras
        pcall(function() Toggles.DeleteMapToggle:SetValue(false) end)
        
        -- Auto Start - Defend
        pcall(function() Options.StartTypeDropdown:SetValue("Missions") end)
        pcall(function() Options.MissionMapDropdown:SetValue("Utgard") end)
        pcall(function() Options.MissionObjectiveDropdown:SetValue("Defend") end)
        pcall(function() Options.MissionDifficultyDropdown:SetValue("Hardest") end)
        pcall(function() Options.ModifiersDropdown:SetValue({
            ["No Perks"] = true, ["No Skills"] = true, ["No Memories"] = true,
            ["Nightmare"] = true, ["Oddball"] = true, ["Injury Prone"] = true,
            ["Chronic Injuries"] = true, ["Fog"] = true, ["Glass Cannon"] = true,
        }) end)
        pcall(function() Toggles.AutoStartToggle:SetValue(true) end)
        
        pcall(function() Toggles.AutoHideToggle:SetValue(true) end)
        getgenv()._silentUI = false -- bulk done: summary notify below is the only one
        
        Library:Notify({
            Title = "⚙️ AFK Farming (Defend) Applied!",
            Description = "Utgard | Defend | Hardest\nAll 10 Mods | Solo | Teleport",
            Time = 5
        })
        
        task.delay(3, function()
            if Library then Library:Toggle(false) end
        end)
    end
end)


-- v8.4: AFK Farming (Stall) preset REMOVED (approved — high ban risk:
-- Stall objective + Hardest + 10 mods + Teleport is a flag magnet).
-- Use Breach/Defend presets instead.

-- ==========================================
-- CONFIG 4: AFK Farming (Waves)
-- ==========================================
ConfigsGroup:AddToggle("AFKFarmingWavesToggle", {
    Text = "AFK Farming (Waves)",
    Default = false,
    Tooltip = "Plug-and-play Waves farmer. Affects: Farm, Combat, Waves (farm/vote/HQ/gear/blessings), Boosts, Protection"
})
Toggles.AFKFarmingWavesToggle:OnChanged(function()
    if Toggles.AFKFarmingWavesToggle.Value then
        getgenv()._silentUI = true getgenv()._silentSince = os.clock() -- one summary notify, not 20 (see below)
        -- Turn OFF other configs
        pcall(function() Toggles.AFKFarmingBreachToggle:SetValue(false) end)
        pcall(function() Toggles.AFKFarmingDefendToggle:SetValue(false) end)
        
        -- Farm Settings
        pcall(function() Toggles.AutoKillToggle:SetValue(true) end)
        pcall(function() Toggles.AutoRetryToggle:SetValue(true) end)
        pcall(function() Toggles.SoloOnlyToggle:SetValue(true) end)
        
        -- Movement
        pcall(function() Options.MovementModeDropdown:SetValue("Hover") end)
        pcall(function() Options.FloatHeightSlider:SetValue(250) end)
        pcall(function() Toggles.NoclipToggle:SetValue(true) end)
        pcall(function() Toggles.AutoBoostToggle:SetValue(false) end)
        
        -- Combat
        pcall(function() Toggles.AutoReloadToggle:SetValue(true) end)
        pcall(function() Toggles.AutoEscapeToggle:SetValue(true) end)
        pcall(function() Toggles.MultiHitToggle:SetValue(true) end)
        pcall(function() Options.MultiHitCountSlider:SetValue(3) end)
        
        -- Security
        pcall(function() Options.FarmOptionsDropdown:SetValue({
            ["Auto Execute"] = true, ["Failsafe"] = true
        }) end)
        
        -- Extras
        pcall(function() Toggles.AutoSkipToggle:SetValue(true) end)
        pcall(function() Toggles.DeleteMapToggle:SetValue(false) end)
        
        -- Waves Settings
        pcall(function() Toggles.AutoWavesToggle:SetValue(true) end)
        pcall(function() Toggles.AutoWavesVoteToggle:SetValue(true) end)
        pcall(function() Toggles.AutoWavesMaxToggle:SetValue(true) end)
        pcall(function() Toggles.AutoWavesRegenToggle:SetValue(true) end)
        pcall(function() Toggles.AutoWavesReplenishToggle:SetValue(true) end)
        pcall(function() Toggles.AutoWavesRefillsToggle:SetValue(true) end)
        pcall(function() Toggles.AutoWavesUpgradeToggle:SetValue(true) end)
        pcall(function() Toggles.AutoWavesBlessingToggle:SetValue(true) end)
        pcall(function() Toggles.AutoWavesCollectCratesToggle:SetValue(true) end)
        
        -- Auto Start - Waves
        pcall(function() Options.StartTypeDropdown:SetValue("Waves") end)
        pcall(function() Options.WavesMapDropdown:SetValue("Trost") end)
        pcall(function() Toggles.AutoStartToggle:SetValue(true) end)
        
        pcall(function() Toggles.AutoHideToggle:SetValue(true) end)
        getgenv()._silentUI = false -- bulk done: summary notify below is the only one
        
        Library:Notify({
            Title = "Waves Config Applied!",
            Description = "Waves | Trost | Easy\nFarm + Vote + HQ/Gear Upgrades + Blessings + Crates",
            Time = 5
        })
        
        task.delay(3, function()
            if Library then Library:Toggle(false) end
        end)
    end
end)

-- Configs Info
ConfigsGroup:AddDivider()
ConfigsGroup:AddLabel("What's included:")
ConfigsGroup:AddLabel("• Breach: AFK Farming")
ConfigsGroup:AddLabel("• Defend: AFK Farming")
ConfigsGroup:AddLabel("• Waves: Full Auto (Farm+Vote+HQ/Gear+Blessings+Crates)")
ConfigsGroup:AddLabel("• All: Hardest + 10 Mods + Solo")


-- ==========================================
-- UPGRADES TAB
-- ==========================================

UpgradesGroup:AddToggle("AutoUpgradeToggle", {
	Text = "Auto-Upgrade Gear (Lobby)",
    Default = false,
})
Toggles.AutoUpgradeToggle:OnChanged(function()
    getgenv().AutoUpgrade = Toggles.AutoUpgradeToggle.Value
    if not getgenv().AutoUpgrade then return end
    task.spawn(function()
        if game.PlaceId ~= 14916516914 then
            Library:Notify({ Title = "Auto Upgrade", Description = "Works in lobby!", Time = 3 })
            getgenv().AutoUpgrade = false
            Toggles.AutoUpgradeToggle:SetValue(false)
            return
        end

        local slot = lp:GetAttribute("Slot")
        if not slot then
            getRemote:InvokeServer("Functions", "Select", "A")
            local waited = 0
            repeat task.wait(0.5); waited += 0.5 until lp:GetAttribute("Slot") or waited >= 5
            slot = lp:GetAttribute("Slot")
        end

        if not slot then
            Library:Notify({ Title = "Auto Upgrade", Description = "Slot not selected!", Time = 3 })
            getgenv().AutoUpgrade = false
            Toggles.AutoUpgradeToggle:SetValue(false)
            return
        end

        Library:Notify({ Title = "Auto Upgrade", Description = "Slot " .. slot .. " upgrading...", Time = 2 })

        local allUpgrades = {
            "Crit_Chance", "Blade_Durability", "ODM_Damage", "Crit_Damage",
            "ODM_Speed", "ODM_Control", "ODM_Range", "ODM_Gas",
        }

        while getgenv().AutoUpgrade do
            local anyDone = false
            for _, upgradeName in ipairs(allUpgrades) do
                if not getgenv().AutoUpgrade then break end
                local ok, result = pcall(function()
                    return getRemote:InvokeServer("S_Equipment", "Upgrade", { upgradeName })
                end)
                if ok and result ~= nil and result ~= false then
                    anyDone = true
                    Library:Notify({ Title = "Upgraded!", Description = upgradeName .. " upgraded!", Time = 1.5 })
                    task.wait(humanWait(0.35, 0.3)) -- v8.1 bell-curved jitter (was uniform 0.2-0.5s)
                else
                    task.wait(0.1)
                end
            end
            if not anyDone then
                task.wait(10)
            else
                task.wait(1)
            end
        end
    end)
end)

UpgradesGroup:AddToggle("AutoEnhanceToggle", {
	Text = "Auto-Enhance Perks",
	Default = false,
})
Toggles.AutoEnhanceToggle:OnChanged(function()
	getgenv().AutoPerk = Toggles.AutoEnhanceToggle.Value
	if not getgenv().AutoPerk then return end
	task.spawn(function()
		-- Slot select pehle
		local slot = lp:GetAttribute("Slot")
		if not slot then
			getRemote:InvokeServer("Functions", "Select", "A")
			local waited = 0
			repeat task.wait(0.5); waited += 0.5 until lp:GetAttribute("Slot") or waited >= 5
			slot = lp:GetAttribute("Slot")
		end

		if not slot then
			Library:Notify({ Title = "Auto Perk", Description = "Slot select nahi hua!", Time = 3 })
			getgenv().AutoPerk = false
			Toggles.AutoEnhanceToggle:SetValue(false)
			return
		end

		-- Data fetch with retry
		local plrData = nil
		for i = 1, 5 do
			lastPlayerDataTime = 0
			lastPlayerData = nil
			local ok, result = pcall(GetPlayerData)
			if ok and type(result) == "table" and result.Slots then
				plrData = result
				break
			end
			task.wait(1)
		end

		if not plrData or not plrData.Slots then
			Library:Notify({ Title = "Auto Perk", Description = "Data fetch failed!", Time = 3 })
			getgenv().AutoPerk = false
			Toggles.AutoEnhanceToggle:SetValue(false)
			return
		end

		local slotIndex = lp:GetAttribute("Slot")
		if not slotIndex or not plrData.Slots[slotIndex] then
			getgenv().AutoPerk = false
			Toggles.AutoEnhanceToggle:SetValue(false)
			return
		end

		local slotPerkData = plrData.Slots[slotIndex]
		local storagePerks = {}
		for id, val in pairs(slotPerkData.Perks.Storage) do
			storagePerks[id] = val
		end

		local perkSlot = Options.PerkSlotDropdown.Value
		local equippedPerkId = slotPerkData.Perks.Equipped[perkSlot]
		if not equippedPerkId then
			Library:Notify({ Title = "Auto Perk", Description = "No perk in " .. tostring(perkSlot) .. " slot!", Time = 3 })
			getgenv().AutoPerk = false
			Toggles.AutoEnhanceToggle:SetValue(false)
			return
		end

		local perkData = storagePerks[equippedPerkId]
		if not perkData then
			Library:Notify({ Title = "Auto Perk", Description = "Equipped perk data not found!", Time = 3 })
			getgenv().AutoPerk = false
			Toggles.AutoEnhanceToggle:SetValue(false)
			return
		end

		local perkName = perkData.Name
		local rarity = GetPerkRarity(perkName)
		local currentLevel = perkData.Level or 0
		local currentXP = perkData.XP or 0

		while getgenv().AutoPerk do
			if currentLevel >= 10 then
				Library:Notify({ Title = "Auto Perk", Description = perkName .. " Level 10 max!", Time = 3 })
				break
			end

			local selectedRarities = Options.SelectPerksDropdown.Value
			local rarityPerks = {}
			if selectedRarities then
				for r, isActive in pairs(selectedRarities) do
					if isActive then rarityPerks[r] = true end
				end
			end

			-- Build food perks as DICT {[id] = qty} — server expects this format
			local foodPerkDict = {}
			local totalXPGain = 0
			local count = 0

			for perkId, tbl in pairs(storagePerks) do
				if count >= 5 then break end
				local r = GetPerkRarity(tbl.Name)
				if perkId ~= equippedPerkId and rarityPerks[r] then
					foodPerkDict[perkId] = 1
					totalXPGain = totalXPGain + GetPerkXP(r, math.max(tbl.Level or 0, 1))
					count = count + 1
				end
			end

			if count == 0 then
				Library:Notify({ Title = "Auto Perk", Description = "No food perks found!", Time = 3 })
				break
			end

			local ok, result = pcall(function()
				return getRemote:InvokeServer("S_Equipment", "Enhance", equippedPerkId, foodPerkDict)
			end)

			if ok and result ~= nil and result ~= false then
				-- Remove used food perks from storage
				for id in pairs(foodPerkDict) do storagePerks[id] = nil end
				currentXP = currentXP + totalXPGain
				while currentLevel < 10 do
					local thresholds = Perk_Level_XP[rarity]
					if not thresholds then break end
					local needed = thresholds[currentLevel + 1]
					if not needed or currentXP < needed then break end
					currentXP = currentXP - needed
					currentLevel = currentLevel + 1
				end
				Library:Notify({ Title = "Enhanced: " .. perkName, Description = "Lv " .. currentLevel .. " (+" .. totalXPGain .. " XP)", Time = 1 })
			else
				Library:Notify({ Title = "Auto Perk", Description = "Enhance failed, stopping.", Time = 3 })
				break
			end
			task.wait(0.5)
		end

		getgenv().AutoPerk = false
		Toggles.AutoEnhanceToggle:SetValue(false)
	end)
end)
UpgradesGroup:AddDropdown("PerkSlotDropdown", {
	Values = {"Defense", "Support", "Family", "Extra", "Offense", "Body"},
	Default = 6,
	Multi = false,
	Text = "Perk Slot",
})

UpgradesGroup:AddDropdown("SelectPerksDropdown", {
	Values = {"Common", "Rare", "Epic", "Legendary"},
	Default = {},
	Multi = true,
	Text = "Perks to use (Food)",
})

UpgradesGroup:AddLabel("Perk slot defaults to Body")

-- ==========================================
-- UPGRADES TAB : Skill Tree
-- ==========================================

SkillTreeGroup:AddToggle("AutoSkillTree", {
	Text = "Auto-Buy Skill Tree",
	Default = false,
})
Toggles.AutoSkillTree:OnChanged(function()
	getgenv().AutoSkillTree = Toggles.AutoSkillTree.Value
	if not getgenv().AutoSkillTree then return end
	if game.PlaceId ~= 14916516914 then return end

	task.spawn(function()
		local slot = lp:GetAttribute("Slot")
		if not slot then
			getRemote:InvokeServer("Functions", "Select", "A")
			local waited = 0
			repeat task.wait(0.5); waited += 0.5 until lp:GetAttribute("Slot") or waited >= 5
			slot = lp:GetAttribute("Slot")
		end

		if not slot then
			Library:Notify({ Title = "Skill Tree", Description = "Slot not Selected!", Time = 3 })
			getgenv().AutoSkillTree = false
			Toggles.AutoSkillTree:SetValue(false)
			return
		end

		local weapon = Options.MiddlePathDropdown.Value == "Damage" and "Blades" or "Blades"

		local middle = Options.MiddlePathDropdown.Value
		local left   = Options.LeftPathDropdown.Value
		local right  = Options.RightPathDropdown.Value

		local middlePath = SkillPaths[weapon] and SkillPaths[weapon][middle]
		local leftPath   = SkillPaths.Support[left]
		local rightPath  = SkillPaths.Defense[right]

		local p1 = Options.Priority1Dropdown.Value or "Middle"
		local p2 = Options.Priority2Dropdown.Value or "Left"
		local p3 = Options.Priority3Dropdown.Value or "None"

		local pathMap = { Left = leftPath, Middle = middlePath, Right = rightPath }
		local paths, used = {}, {}
		local function addPath(p)
			if not used[p] and pathMap[p] then
				table.insert(paths, pathMap[p])
				used[p] = true
			end
		end
		addPath(p1); addPath(p2); addPath(p3)

		while getgenv().AutoSkillTree do
			local anyUnlocked = false
			for _, path in ipairs(paths) do
				for _, skillId in ipairs(path) do
					if not getgenv().AutoSkillTree then break end
					local ok, result = pcall(function()
						return getRemote:InvokeServer("S_Equipment", "Unlock", {skillId})
					end)
					if ok and result ~= nil and result ~= false then
						anyUnlocked = true
						Library:Notify({ Title = "Skill Unlocked", Description = "ID: " .. skillId, Time = 1 })
						task.wait(0.5)
					end
				end
			end

			if not anyUnlocked then
				Library:Notify({ Title = "Skill Tree", Description = "All selected paths complete!", Time = 3 })
				getgenv().AutoSkillTree = false
				Toggles.AutoSkillTree:SetValue(false)
				break
			end
			task.wait(1)
		end
	end)
end)

SkillTreeGroup:AddDropdown("MiddlePathDropdown", {
	Values = {"Damage", "Critical"},
	Default = 2,
	Multi = false,
	Text = "Middle Path",
})

SkillTreeGroup:AddDropdown("LeftPathDropdown", {
	Values = {"Regen", "Cooldown Reduction"},
	Default = 2,
	Multi = false,
	Text = "Left Path",
})

SkillTreeGroup:AddDropdown("RightPathDropdown", {
	Values = {"Health", "Damage Reduction"},
	Default = 2,
	Multi = false,
	Text = "Right Path",
})

SkillTreeGroup:AddDropdown("Priority1Dropdown", {
	Values = {"Left", "Middle", "Right", "None"},
	Default = 2,
	Multi = false,
	Text = "Priority 1",
})

SkillTreeGroup:AddDropdown("Priority2Dropdown", {
	Values = {"Left", "Middle", "Right", "None"},
	Default = 1,
	Multi = false,
	Text = "Priority 2",
})

SkillTreeGroup:AddDropdown("Priority3Dropdown", {
	Values = {"Left", "Middle", "Right", "None"},
	Default = 4,
	Multi = false,
	Text = "Priority 3",
})


-- ==========================================
-- WAVES TAB
-- ==========================================

getgenv().AutoWaves = false
getgenv().AutoWavesUpgrade = false
getgenv().AutoWavesMax = false
getgenv().AutoWavesRegen = false
getgenv().AutoWavesReplenish = false
getgenv().AutoWavesRefills = false
getgenv().AutoWavesVote = false
getgenv().AutoWavesBlessing = false
getgenv().AutoWavesRevive = false

-- Market / Injury / Visuals
getgenv().AutoWavesMarketBuy = false
getgenv().AutoWavesMarketLock = false
getgenv().AutoWavesHealInjuries = false
getgenv().AutoVisualsESPTitans = false
getgenv().WavesMarketCategories = { "Perks", "Artifacts", "Memories", "Shifting" }
getgenv().WavesMarketSelectedItems = {}
getgenv().WavesMarketQuantity = 1
getgenv().VisualsESPTitanUpdateInterval = 2

-- Waves Gear Upgrade names (stats via Equipment/Upgrade remote)
local WavesGearUpgrades = {
    "ODM_Damage", "ODM_Control", "ODM_Gas", "ODM_Speed",
    "Blade_Durability", "ODM_Range",
    "TS_Damage", "TS_Control", "TS_Range", "TS_Gas", "TS_Speed",
    "Blast_Radius", "Crit_Damage", "Crit_Chance",
    "ODM_Crit_Damage", "ODM_Crit_Chance",
}

-- Helper: get Waves objectives folder
local function getWavesObjectives()
    return ReplicatedStorage:FindFirstChild("Objectives")
end

-- Helper: get current wave number from Clearance objective
-- Objectives.Waves = HQ health %, NOT wave count
-- Objectives.Clearance = actual wave progress (Value=waves cleared, Requirement=total-1)
local function getWaveNumber()
    local obj = getWavesObjectives()
    if obj then
        local c = obj:FindFirstChild("Clearance")
        if c then return c.Value + 1, c.Requirement + 1 end
    end
    return nil, nil
end

-- Helper: check if Waves vote is showing
local function isWavesVoteShowing()
    local obj = getWavesObjectives()
    if not obj then return false end
    local w = obj:FindFirstChild("Waves")
    if not w then return false end
    -- The Waves UI inner frame shows when vote is active
    local inner = INTERFACE:FindFirstChild("Waves") and INTERFACE.Waves:FindFirstChild("Inner")
    return inner and inner.Visible == true
end

WavesFarmGroup:AddToggle("AutoWavesToggle", {
	Text = "Waves Autofarm",
    Default = false,
    Tooltip = "Auto Waves Farm !"
})
Toggles.AutoWavesToggle:OnChanged(function()
    getgenv().AutoWaves = Toggles.AutoWavesToggle.Value
    uiFeedback("Waves Autofarm " .. (Toggles.AutoWavesToggle.Value and "ON" or "OFF"))
    
    if getgenv().AutoWaves then
        if not Toggles.AutoKillToggle.Value then
            Toggles.AutoKillToggle:SetValue(true)
        elseif not AutoFarm._running then
            AutoFarm:Start()
        end
    else
        if AutoFarm._running then
            AutoFarm:Stop()
        end
        if Toggles.AutoKillToggle.Value then
            Toggles.AutoKillToggle:SetValue(false)
        end
    end
end)

-- ==========================================
-- WAVES: AUTO VOTE
-- ==========================================

WavesFarmGroup:AddToggle("AutoWavesVoteToggle", {
	Text = "Auto-Vote to Continue",
    Default = false,
    Tooltip = "Automatically votes to continue/skip waves when vote prompt appears"
})
Toggles.AutoWavesVoteToggle:OnChanged(function()
    getgenv().AutoWavesVote = Toggles.AutoWavesVoteToggle.Value
    uiFeedback("Auto-Vote " .. (Toggles.AutoWavesVoteToggle.Value and "ON" or "OFF"))
    
    if getgenv().AutoWavesVote then
        task.spawn(function()
            while getgenv().AutoWavesVote do
                pcall(function()
                    if isWavesVoteShowing() then
                        postRemote:FireServer("Waves", "Update")
                    end
                end)
                task.wait(1)
            end
        end)
    end
end)

-- Target Priority for Waves
WavesFarmGroup:AddDropdown("WavesTargetPriorityDropdown", {
    Values = {"Titans", "Boss", "None"},
    Default = 1,
    Multi = false,
    Text = "Target Priority",
    Tooltip = "Titans: focus regular titans first | Boss: focus bosses first | None: closest target"
})
Options.WavesTargetPriorityDropdown:OnChanged(function()
    getgenv().AutoFarmConfig.TargetPriority = Options.WavesTargetPriorityDropdown.Value
    getgenv().TargetPriority = Options.WavesTargetPriorityDropdown.Value
end)

-- ==========================================
-- WAVES: AUTO HQ UPGRADES (individual toggles) — touch + remote
-- ==========================================

local function tryWavesUpgrade(upgradeName)
    -- First touch the upgrade zone, then call remote (v8: via safeInvoke)
    local touched = touchWavesUpgrade()
    if touched then
        return safeInvoke("Waves", "Upgrade", { upgradeName })
    end
    return false
end

WavesHQGroup:AddToggle("AutoWavesMaxToggle", {
	Text = "HQ: Max Health",
    Default = false,
    Tooltip = "Auto buy Max HP upgrade using Waves gold (touches upgrade zone)"
})
Toggles.AutoWavesMaxToggle:OnChanged(function()
    getgenv().AutoWavesMax = Toggles.AutoWavesMaxToggle.Value
    if getgenv().AutoWavesMax then
        task.spawn(function()
            while getgenv().AutoWavesMax do
                local success = tryWavesUpgrade("Max")
                if success then
                    Library:Notify({ Title = "HQ Upgrade", Description = "Max HP upgraded!", Time = 2 })
                end
                task.wait(3 + math.random() * 2)
            end
        end)
    end
end)

WavesHQGroup:AddToggle("AutoWavesRegenToggle", {
	Text = "HQ: Health Regen",
    Default = false,
    Tooltip = "Auto buy Regen upgrade using Waves gold (touches upgrade zone)"
})
Toggles.AutoWavesRegenToggle:OnChanged(function()
    getgenv().AutoWavesRegen = Toggles.AutoWavesRegenToggle.Value
    if getgenv().AutoWavesRegen then
        task.spawn(function()
            while getgenv().AutoWavesRegen do
                local success = tryWavesUpgrade("Regen")
                if success then
                    Library:Notify({ Title = "HQ Upgrade", Description = "Regen upgraded!", Time = 2 })
                end
                task.wait(3 + math.random() * 2)
            end
        end)
    end
end)

WavesHQGroup:AddToggle("AutoWavesReplenishToggle", {
	Text = "HQ: Restore Health",
    Default = false,
    Tooltip = "Auto buy Replenish upgrade (heal HQ) using Waves gold (touches upgrade zone)"
})
Toggles.AutoWavesReplenishToggle:OnChanged(function()
    getgenv().AutoWavesReplenish = Toggles.AutoWavesReplenishToggle.Value
    if getgenv().AutoWavesReplenish then
        task.spawn(function()
            while getgenv().AutoWavesReplenish do
                local success = tryWavesUpgrade("Replenish")
                if success then
                    Library:Notify({ Title = "HQ Upgrade", Description = "Replenish upgraded!", Time = 2 })
                end
                task.wait(3 + math.random() * 2)
            end
        end)
    end
end)

WavesHQGroup:AddToggle("AutoWavesRefillsToggle", {
	Text = "HQ: +Refill Capacity",
    Default = false,
    Tooltip = "Auto buy Refills upgrade using Waves gold (touches upgrade zone)"
})
Toggles.AutoWavesRefillsToggle:OnChanged(function()
    getgenv().AutoWavesRefills = Toggles.AutoWavesRefillsToggle.Value
    if getgenv().AutoWavesRefills then
        task.spawn(function()
            while getgenv().AutoWavesRefills do
                local success = tryWavesUpgrade("Refills")
                if success then
                    Library:Notify({ Title = "HQ Upgrade", Description = "Refills upgraded!", Time = 2 })
                end
                task.wait(3 + math.random() * 2)
            end
        end)
    end
end)

-- ==========================================
-- WAVES: AUTO REVIVE (HQ Upgrades group)
-- ==========================================

WavesHQGroup:AddToggle("AutoWavesReviveToggle", {
	Text = "HQ: Revive Teammates",
    Default = false,
    Tooltip = "Auto revive dead teammates in multiplayer waves"
})
Toggles.AutoWavesReviveToggle:OnChanged(function()
    getgenv().AutoWavesRevive = Toggles.AutoWavesReviveToggle.Value
    
    if getgenv().AutoWavesRevive then
        task.spawn(function()
            while getgenv().AutoWavesRevive do
                pcall(function()
                    local playerCount = workspace:GetAttribute("Player_Count") or 1
                    if playerCount > 1 then
                        getRemote:InvokeServer("Waves", "Revive")
                    end
                end)
                task.wait(10)
            end
        end)
    end
end)

-- ==========================================
-- WAVES: AUTO GEAR UPGRADE (Equipment/Upgrade) — one by one
-- ==========================================

WavesGearGroup:AddToggle("AutoWavesUpgradeToggle", {
	Text = "Auto-Upgrade Gear",
    Default = false,
    Tooltip = "Auto upgrade ODM/TS gear using Waves currency (Equipment remote) — one by one"
})
Toggles.AutoWavesUpgradeToggle:OnChanged(function()
    getgenv().AutoWavesUpgrade = Toggles.AutoWavesUpgradeToggle.Value
    
    if getgenv().AutoWavesUpgrade then
        task.spawn(function()
            while getgenv().AutoWavesUpgrade do
                local anyDone = false
                for _, upgradeName in ipairs(WavesGearUpgrades) do
                    if not getgenv().AutoWavesUpgrade then break end
                    local ok, result = pcall(function()
                        return getRemote:InvokeServer("Equipment", "Upgrade", { upgradeName })
                    end)
                    if ok and result ~= nil and result ~= false then
                        anyDone = true
                        task.wait(0.2 + math.random() * 0.3) -- jitter 0.2-0.5s
                    else
                        task.wait(0.1)
                    end
                end
                if not anyDone then
                    task.wait(5)
                end
            end
        end)
    end
end)

-- ==========================================
-- WAVES: AUTO BLESSINGS (Roll + Lock)
-- ==========================================

WavesGearGroup:AddToggle("AutoWavesBlessingToggle", {
	Text = "Auto-Roll Blessings",
    Default = false,
    Tooltip = "Auto roll blessings and lock by rarity"
})
Toggles.AutoWavesBlessingToggle:OnChanged(function()
    getgenv().AutoWavesBlessing = Toggles.AutoWavesBlessingToggle.Value
    
    if getgenv().AutoWavesBlessing then
        task.spawn(function()
            while getgenv().AutoWavesBlessing do
                pcall(function()
                    local ok, result = pcall(function()
                        return getRemote:InvokeServer("Waves", "Blessing", "Spin")
                    end)
                    if ok and result ~= nil then
                        -- result = { blessing1, blessing2, blessing3 } or similar
                        -- Auto-lock legendaries/Mythicals
                        -- The server handles the actual spin
                    end
                end)
                task.wait(2)
            end
        end)
    end
end)

-- ==========================================
-- WAVES: WAVE COUNTER LABEL
-- ==========================================

WavesFarmGroup:AddDivider()
local waveLabel = WavesFarmGroup:AddLabel("Wave: Loading...")
task.spawn(function()
    while not Library.Unloaded do
        pcall(function()
            local cur, max = getWaveNumber()
            if cur then
                waveLabel:SetText("Wave: " .. math.floor(cur) .. "/" .. tostring(max or "?"))
            else
                waveLabel:SetText("Wave: N/A")
            end
        end)
        task.wait(2)
    end
end)

local function collectAndDepositCrate()
    local wavesFolder = workspace:FindFirstChild("Waves")
    local crates = wavesFolder and wavesFolder:FindFirstChild("Crates")
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not crates or not root then return false end
    
    local crate = crates:FindFirstChild("Crate_" .. lp.Name)
    if not crate then return false end
    
    local hitbox = crate:FindFirstChild("Hitbox")
    if not hitbox or not hitbox:IsA("BasePart") then return false end
    
    -- Pause autofarm
    local wasFarming = AutoFarm._running
    if wasFarming then AutoFarm:Stop() end
    
    local success = false
    pcall(function()
        -- 1. Go to crate and pick up
        root.CFrame = CFrame.new(hitbox.Position + Vector3.new(0, 5, 0))
        task.wait(0.3)
        hitbox.CanTouch = true
        firetouchinterest(root, hitbox, 0)
        firetouchinterest(root, hitbox, 1)
        task.wait(0.8)
        
        -- 2. Go to Skills zone to deposit
        local skillsZone = wavesFolder and wavesFolder.Zones:FindFirstChild("Skills")
        local depositHitbox = skillsZone and skillsZone:FindFirstChild("Hitbox")
        if depositHitbox and depositHitbox:IsA("BasePart") then
            root.CFrame = CFrame.new(depositHitbox.Position + Vector3.new(0, 5, 0))
            task.wait(0.3)
            depositHitbox.CanTouch = true
            firetouchinterest(root, depositHitbox, 0)
            firetouchinterest(root, depositHitbox, 1)
            task.wait(0.8)
            success = true
        end
    end)
    
    -- Resume autofarm
    if wasFarming and not AutoFarm._running then
        task.wait(0.5)
        AutoFarm:Start()
    end
    
    return success
end

-- ==========================================
-- WAVES: AUTO COLLECT CRATES
-- ==========================================

getgenv().AutoWavesCollectCrates = false

WavesFarmGroup:AddToggle("AutoWavesCollectCratesToggle", {
	Text = "Auto-Collect Supply Crates",
    Default = false,
    Tooltip = "Auto collects supply crates in Waves mode and deposits at Skills zone"
})
Toggles.AutoWavesCollectCratesToggle:OnChanged(function()
    getgenv().AutoWavesCollectCrates = Toggles.AutoWavesCollectCratesToggle.Value
    
    if getgenv().AutoWavesCollectCrates then
        task.spawn(function()
            while getgenv().AutoWavesCollectCrates do
                pcall(function()
                    local wavesFolder = workspace:FindFirstChild("Waves")
                    local crates = wavesFolder and wavesFolder:FindFirstChild("Crates")
                    local crate = crates and crates:FindFirstChild("Crate_" .. lp.Name)
                    if crate and crate:FindFirstChild("Hitbox") then
                        collectAndDepositCrate()
                    end
                end)
                task.wait(5)
            end
        end)
    end
end)


-- ==========================================
-- WAVES: MARKET AUTO BUY / LOCK
-- ==========================================

WavesMarketGroup:AddDropdown("WavesMarketCategoryDropdown", {
    Values = { "Perks", "Artifacts", "Memories", "Shifting" },
    Default = 1,
    Multi = true,
    Text = "Categories to Buy",
    Tooltip = "Select which market categories to auto-buy from"
})
Options.WavesMarketCategoryDropdown:OnChanged(function()
    getgenv().WavesMarketCategories = Options.WavesMarketCategoryDropdown.Value
end)

WavesMarketGroup:AddDropdown("WavesMarketItemDropdown", {
    Values = { "All Available" },
    Default = 1,
    Multi = true,
    Text = "Items to Buy (All = everything)",
    Tooltip = "Specific items to buy. 'All Available' buys everything in selected categories"
})
Options.WavesMarketItemDropdown:OnChanged(function()
    getgenv().WavesMarketSelectedItems = Options.WavesMarketItemDropdown.Value
end)

WavesMarketGroup:AddSlider("WavesMarketQuantitySlider", {
	Text = "Buy Quantity",
    Default = 1,
    Min = 1,
    Max = 10,
    Rounding = 0,
    Tooltip = "How many of each item to buy per cycle"
})
Options.WavesMarketQuantitySlider:OnChanged(function()
    getgenv().WavesMarketQuantity = Options.WavesMarketQuantitySlider.Value
end)

getgenv().AutoWavesMarketBuy = false
WavesMarketGroup:AddToggle("AutoWavesMarketBuyToggle", {
	Text = "Auto-Buy (Black Market)",
    Default = false,
    Tooltip = "Automatically buys selected items from Waves market"
})
Toggles.AutoWavesMarketBuyToggle:OnChanged(function()
    getgenv().AutoWavesMarketBuy = Toggles.AutoWavesMarketBuyToggle.Value
    if getgenv().AutoWavesMarketBuy then
        task.spawn(function()
            while getgenv().AutoWavesMarketBuy do
                pcall(function()
                    local categories = getgenv().WavesMarketCategories or { "Perks", "Artifacts", "Memories", "Shifting" }
                    local selectedItems = getgenv().WavesMarketSelectedItems or { "All Available" }
                    local quantity = getgenv().WavesMarketQuantity or 1
                    
                    local marketItems = _G.AOTR.getWavesMarketItems()
                    for _, cat in ipairs(categories) do
                        if not getgenv().AutoWavesMarketBuy then break end
                        local items = marketItems[cat]
                        if items then
                            for _, item in ipairs(items) do
                                if not getgenv().AutoWavesMarketBuy then break end
                                local shouldBuy = false
                                if selectedItems["All Available"] then
                                    shouldBuy = true
                                else
                                    for _, sel in ipairs(selectedItems) do
                                        if sel == item.name or sel == item.id then
                                            shouldBuy = true
                                            break
                                        end
                                    end
                                end
                                if shouldBuy then
                                    local ok, result = _G.AOTR.buyWavesMarketItem(cat, item.id, quantity)
                                    if ok and result then
                                        Library:Notify({ Title = "Market Buy", Description = "Bought " .. quantity .. "x " .. item.name .. " (" .. cat .. ")", Time = 2 })
                                    end
                                    task.wait(0.3 + math.random() * 0.2)
                                end
                            end
                        end
                    end
                end)
                task.wait(10)
            end
        end)
    end
end)

getgenv().AutoWavesMarketLock = false
WavesMarketGroup:AddToggle("AutoWavesMarketLockToggle", {
	Text = "Auto-Lock (Black Market)",
    Default = false,
    Tooltip = "Automatically locks items (costs 20% of price)"
})
Toggles.AutoWavesMarketLockToggle:OnChanged(function()
    getgenv().AutoWavesMarketLock = Toggles.AutoWavesMarketLockToggle.Value
    if getgenv().AutoWavesMarketLock then
        task.spawn(function()
            while getgenv().AutoWavesMarketLock do
                pcall(function()
                    local categories = getgenv().WavesMarketCategories or { "Perks", "Artifacts", "Memories", "Shifting" }
                    local selectedItems = getgenv().WavesMarketSelectedItems or { "All Available" }
                    
                    local marketItems = _G.AOTR.getWavesMarketItems()
                    for _, cat in ipairs(categories) do
                        if not getgenv().AutoWavesMarketLock then break end
                        local items = marketItems[cat]
                        if items then
                            for _, item in ipairs(items) do
                                if not getgenv().AutoWavesMarketLock then break end
                                local shouldLock = false
                                if selectedItems["All Available"] then
                                    shouldLock = true
                                else
                                    for _, sel in ipairs(selectedItems) do
                                        if sel == item.name or sel == item.id then
                                            shouldLock = true
                                            break
                                        end
                                    end
                                end
                                if shouldLock then
                                    local ok = lockWavesMarketItem(cat, item.id)
                                    if ok then
                                        Library:Notify({ Title = "Market Lock", Description = "Locked " .. item.name .. " (" .. cat .. ")", Time = 2 })
                                    end
                                    task.wait(0.5 + math.random() * 0.3)
                                end
                            end
                        end
                    end
                end)
                task.wait(30)
            end
        end)
    end
end)


-- ==========================================
-- WAVES: AUTO HEAL INJURIES
-- ==========================================

WavesMarketGroup:AddDivider()
WavesMarketGroup:AddLabel("Injury Management", true)

getgenv().AutoWavesHealInjuries = false
WavesMarketGroup:AddToggle("AutoWavesHealInjuriesToggle", {
	Text = "Auto-Heal (Medical Tent)",
    Default = false,
    Tooltip = "Automatically heals injuries by interacting with Injury zone"
})
Toggles.AutoWavesHealInjuriesToggle:OnChanged(function()
    getgenv().AutoWavesHealInjuries = Toggles.AutoWavesHealInjuriesToggle.Value
    uiFeedback("Auto-Heal " .. (Toggles.AutoWavesHealInjuriesToggle.Value and "ON" or "OFF"))
    if getgenv().AutoWavesHealInjuries then
        task.spawn(function()
            while getgenv().AutoWavesHealInjuries do
                pcall(function()
                    local hasInj, count = hasInjuries()
                    if hasInj then
                        Library:Notify({ Title = "Injury Heal", Description = "Healing " .. count .. " injury(ies)...", Time = 2 })
                        healInjuries()
                    end
                end)
                task.wait(5)
            end
        end)
    end
end)

WavesMarketGroup:AddButton({
	Text = "Heal Now",
    Func = function()
        local hasInj, count = hasInjuries()
        if hasInj then
            healInjuries()
            Library:Notify({ Title = "Injury Heal", Description = "Attempted to heal " .. count .. " injury(ies)", Time = 3 })
        else
            Library:Notify({ Title = "Injury Heal", Description = "No injuries to heal", Time = 2 })
        end
    end,
    Tooltip = "Manually trigger injury heal"
})


-- ==========================================
-- VISUALS TAB : ESP / VISUALS
-- ==========================================

VisualsESPGroup:AddToggle("AutoVisualsESPTitansToggle", {
	Text = "Titan Highlights",
    Default = false,
    Tooltip = "Shows highlights and name tags on all living titans"
})
Toggles.AutoVisualsESPTitansToggle:OnChanged(function()
    getgenv().AutoVisualsESPTitans = Toggles.AutoVisualsESPTitansToggle.Value
    uiFeedback("Titan Highlights " .. (Toggles.AutoVisualsESPTitansToggle.Value and "ON" or "OFF"))
    if getgenv().AutoVisualsESPTitans then
        task.spawn(function()
            while getgenv().AutoVisualsESPTitans do
                pcall(updateESPTitans)
                task.wait(getgenv().VisualsESPTitanUpdateInterval or 2)
            end
        end)
    else
        clearESPTitans()
    end
end)

VisualsESPGroup:AddSlider("VisualsESPTitanUpdateSlider", {
	Text = "Refresh Every (sec)",
    Default = 2,
    Min = 1,
    Max = 10,
    Rounding = 1,
    Tooltip = "How often to refresh ESP highlights"
})
Options.VisualsESPTitanUpdateSlider:OnChanged(function()
    getgenv().VisualsESPTitanUpdateInterval = Options.VisualsESPTitanUpdateSlider.Value
end)

VisualsESPGroup:AddButton({
	Text = "Clear Highlights",
    Func = function()
        clearESPTitans()
        Library:Notify({ Title = "ESP", Description = "Cleared all titan ESP", Time = 2 })
    end,
    Tooltip = "Manually clear all ESP highlights and name tags"
})

-- v8.3 titan ESP tuning (colors sync into getgenv; labels never show GUIDs)
VisualsESPGroup:AddLabel("Highlight Color"):AddColorPicker("ESPTitanColor", {
    Default = Color3.fromRGB(255, 80, 80),
    Title = "Titan highlight color",
})
pcall(function()
    Options.ESPTitanColor:OnChanged(function()
        getgenv().ESPTitanColor = Options.ESPTitanColor.Value
    end)
end)

VisualsESPGroup:AddSlider("ESPTitanMaxDistSlider", {
	Text = "Max Distance (m)",
    Default = 2000,
    Min = 500,
    Max = 5000,
    Rounding = 0,
    Tooltip = "Ignore titans farther than this (perf + declutter)"
})
Options.ESPTitanMaxDistSlider:OnChanged(function()
    getgenv().ESPTitanMaxDist = Options.ESPTitanMaxDistSlider.Value
end)

VisualsESPGroup:AddToggle("ESPTitanTracersToggle", {
	Text = "Tracer Lines",
    Default = false,
    Tooltip = "Lines from screen bottom to each living titan"
})
Toggles.ESPTitanTracersToggle:OnChanged(function()
    getgenv().ESPTitanTracers = Toggles.ESPTitanTracersToggle.Value
    uiFeedback("Tracer Lines " .. (Toggles.ESPTitanTracersToggle.Value and "ON" or "OFF"))
end)

-- v8.3 player ESP (deliberately louder: neon + always-on-top + edge arrows)
VisualsSettingsGroup:AddToggle("ESPPlayersToggle", {
	Text = "Player Highlights",
    Default = false,
    Tooltip = "Neon highlights + name/dist/HP tags on every other player"
})
Toggles.ESPPlayersToggle:OnChanged(function()
    getgenv().ESPPlayers = Toggles.ESPPlayersToggle.Value
    if getgenv().ESPPlayers then
        task.spawn(function()
            while getgenv().ESPPlayers do
                pcall(updateESPPlayers)
                task.wait(2)
            end
        end)
    else
        clearESPPlayers()
    end
    uiFeedback("Player Highlights " .. (Toggles.ESPPlayersToggle.Value and "ON" or "OFF"))
end)

VisualsSettingsGroup:AddLabel("Player Color"):AddColorPicker("ESPPlayerColor", {
    Default = Color3.fromRGB(57, 255, 20),
    Title = "Player highlight color",
})
pcall(function()
    Options.ESPPlayerColor:OnChanged(function()
        getgenv().ESPPlayerColor = Options.ESPPlayerColor.Value
    end)
end)

VisualsSettingsGroup:AddToggle("ESPPlayerMarkersToggle", {
	Text = "Off-Screen Arrows",
    Default = true,
    Tooltip = "Edge arrows point to players behind you or far away"
})
Toggles.ESPPlayerMarkersToggle:OnChanged(function()
    getgenv().ESPPlayerMarkers = Toggles.ESPPlayerMarkersToggle.Value
    uiFeedback("Off-Screen Arrows " .. (Toggles.ESPPlayerMarkersToggle.Value and "ON" or "OFF"))
end)


-- ==========================================
-- GLOBAL TAB : Slots
-- ==========================================

SlotGroup:AddToggle("AutoSelectSlot", {
	Text = "Auto-Select Slot",
	Default = false,
})
Toggles.AutoSelectSlot:OnChanged(function()
	getgenv().AutoSlot = Toggles.AutoSelectSlot.Value
	if getgenv().AutoSlot and not lp:GetAttribute("Slot") then
		local selectedSlot = Options.SelectSlotDropdown.Value
		local args = { "Functions", "Select", string.sub(selectedSlot, -1) }
		task.spawn(function()
			repeat
				getRemote:InvokeServer(unpack(args))
				task.wait(1)
			until lp:GetAttribute("Slot") or not getgenv().AutoSlot
			getRemote:InvokeServer("Functions", "Teleport", "Lobby")
		end)
	end
end)

SlotGroup:AddDropdown("SelectSlotDropdown", {
	Values = {"Slot A", "Slot B", "Slot C"},
	Default = 1,
	Multi = false,
	Text = "Select Slot",
})

SlotGroup:AddToggle("AutoPrestigeToggle", {
	Text = "Auto-Prestige",
	Default = false,
})
Toggles.AutoPrestigeToggle:OnChanged(function()
	getgenv().AutoPrestige = Toggles.AutoPrestigeToggle.Value
	if getgenv().AutoPrestige then
		if game.PlaceId ~= 14916516914 then return end
		task.spawn(function()
			local pData = GetPlayerData()
			if not pData or not pData.Slots then return end
			local slotIdx = lp:GetAttribute("Slot")
			if not slotIdx or not pData.Slots[slotIdx] then return end
			local gold = pData.Slots[slotIdx].Currency.Gold
			local requiredGold = Options.PrestigeGoldSlider.Value * 1000000
			if gold < requiredGold then return end

			while getgenv().AutoPrestige do
				for _, Memory in ipairs(Talents) do
					if not getgenv().AutoPrestige then break end
					local success = getRemote:InvokeServer("S_Equipment", "Prestige", {Boosts = Options.SelectBoostDropdown.Value, Talents = Memory})
					if success then
						Library:Notify({ Title = "Successfully Prestiged", Description = "Prestiged with " .. Options.SelectBoostDropdown.Value .. " and " .. Memory, Time = 5 })
						break
					end
					task.wait(0.1)
				end
				task.wait(1)
			end
		end)
	end
end)

SlotGroup:AddDropdown("SelectBoostDropdown", {
	Values = {"Luck Boost", "EXP Boost", "Gold Boost"},
	Default = 1,
	Multi = false,
	Text = "Select Boost",
})

SlotGroup:AddSlider("PrestigeGoldSlider", {
	Text = "Prestige at Gold (M)",
	Default = 0,
	Min = 0,
	Max = 100,
	Rounding = 0,
})

-- ==========================================
-- GLOBAL TAB : Family Roll
-- ==========================================

FamilyRollGroup:AddToggle("AutoRollToggle", {
	Text = "Auto-Summon Family",
	Default = false,
})
Toggles.AutoRollToggle:OnChanged(function()
	getgenv().AutoRoll = Toggles.AutoRollToggle.Value
	if getgenv().AutoRoll then
		if game.PlaceId ~= 13379208636 then
			Library:Notify({ Title = "AOTR Hub", Description = "You must be in the lobby to use family roll features.", Time = 3 })
			return
		end
		task.spawn(function()
			while getgenv().AutoRoll do
				local targets, rarities
				local text = Options.SelectFamily.Value
				if text and text ~= "" then
					text = string.lower(text)
					targets = string.split(text, ",")
				end
				local raritySelected = Options.SelectFamilyRarity.Value
				if raritySelected then
					rarities = {}
					for rarityName, isEnabled in pairs(raritySelected) do
						if isEnabled then table.insert(rarities, string.lower(rarityName)) end
					end
				end
				roll(targets, rarities)
				task.wait(0.25)
			end
		end)
	end
end)

FamilyRollGroup:AddInput("SelectFamily", {
	Default = "",
	Text = "Keep These Families",
	Placeholder = "Fritz,Yeager,etc.",
})
Options.SelectFamily:OnChanged(function()
	if Options.SelectFamily.Value ~= "" then
		Library:Notify({ Title = "AOTR Hub", Description = "Families selected: " .. Options.SelectFamily.Value, Time = 2 })
	end
end)

FamilyRollGroup:AddDropdown("SelectFamilyRarity", {
	Values = familyRaritiesOptions,
	Default = {},
	Multi = true,
	Text = "Stop At",
})

FamilyRollGroup:AddLabel("Mythical families won't be rolled\nSeparate families with commas & no spaces (Fritz,Yeager)", true)

-- ==========================================
-- GLOBAL TAB : Settings
-- ==========================================

SettingsGroup:AddToggle("AutoHideToggle", {
	Text = "Auto-Hide Menu",
	Default = false,
})

-- v8.2 merge (approved): the duplicate lobby claim-loop lived here. Single
-- implementation now in Achievement Hunter (Tabs.Upgrades), which uses the
-- validated helper + scan-range slider instead of blind 1-84 claims.

SettingsGroup:AddToggle("Disable3DRendering", {
	Text = "Disable 3D Rendering",
	Default = false,
	Tooltip = "Completely disables 3D rendering for maximum FPS"
})
Toggles.Disable3DRendering:OnChanged(function()
	RunService:Set3dRenderingEnabled(not Toggles.Disable3DRendering.Value)
end)

-- ==========================================
-- GLOBAL TAB : Webhook
-- ==========================================

WebhookGroup:AddToggle("ToggleRewardWebhook", {
	Text = "Loot Alerts",
	Default = false,
})
Toggles.ToggleRewardWebhook:OnChanged(function()
	if Toggles.ToggleRewardWebhook.Value and (not webhook or webhook == "") then
		Library:Notify({ Title = "Webhook", Description = "Set webhook URL first!", Time = 3 })
		Toggles.ToggleRewardWebhook:SetValue(false)
		return
	end
	getgenv().RewardWebhook = Toggles.ToggleRewardWebhook.Value
end)

WebhookGroup:AddToggle("ToggleMythicalFamilyWebhook", {
	Text = "Mythical Alerts",
	Default = false,
})
Toggles.ToggleMythicalFamilyWebhook:OnChanged(function()
	getgenv().MythicalFamilyWebhook = Toggles.ToggleMythicalFamilyWebhook.Value
end)

WebhookGroup:AddInput("WebhookUrl", {
	Default = "",
	Text = "Discord Webhook URL",
	Placeholder = "https://discord.com/api/webhooks/...",
})
Options.WebhookUrl:OnChanged(function()
	webhook = Options.WebhookUrl.Value
end)

-- ==========================================
-- STATS TAB
-- ==========================================

local labelSessionTime = SessionGroup:AddLabel("Session Time: 00:00:00")
local labelGames       = SessionGroup:AddLabel("Games Played: 0")
local labelGold        = SessionGroup:AddLabel("Total Gold: 0")
local labelGems        = SessionGroup:AddLabel("Total Gems: 0")
local labelXP          = SessionGroup:AddLabel("Total XP: 0")
local labelMythicals   = SessionGroup:AddLabel("Mythical Drops: 0")
local labelCrashes     = SessionGroup:AddLabel("Crashes Detected: 0")

local labelGoldHour  = RatesGroup:AddLabel("Gold / Hour: 0")
local labelGamesHour = RatesGroup:AddLabel("Games / Hour: 0")
local labelAvgGold   = RatesGroup:AddLabel("Avg Gold / Game: 0")

SessionGroup:AddButton({
	Text = "Reset Session",
	Func = function()
		sessionStats.startTime    = os.time()
		sessionStats.gamesPlayed  = 0
		sessionStats.totalGold    = 0
		sessionStats.totalGems    = 0
		sessionStats.totalXP      = 0
		sessionStats.totalKills   = 0
		sessionStats.mythicalDrops = 0
		sessionStats.crashes      = 0
		writefile("./THUB1/aotr/s_elapsed.txt", "0") -- reset elapsed too
		SaveSessionStats()
		Library:Notify({ Title = "Stats", Description = "Session reset!", Time = 2 })
	end,
})

CrashGroup:AddToggle("AutoRejoinToggle", {
	Text = "Auto-Rejoin on Crash",
	Default = false,
	Tooltip = "Detects crashed/stuck missions and automatically returns to lobby"
})
Toggles.AutoRejoinToggle:OnChanged(function()
	getgenv().AutoRejoin = Toggles.AutoRejoinToggle.Value
	if getgenv().AutoRejoin then
		startCrashDetection()
	else
		stopCrashDetection()
	end
end)

CrashGroup:AddLabel("Detects stuck/crashed missions\nand auto returns to lobby")

task.spawn(function()
	while not Library.Unloaded do
		pcall(function()
			labelSessionTime:SetText("Session Time: "  .. getSessionTime())
			labelGames:SetText("Games Played: "        .. sessionStats.gamesPlayed)
			labelGold:SetText("Total Gold: "           .. sessionStats.totalGold)
			labelGems:SetText("Total Gems: "           .. sessionStats.totalGems)
			labelXP:SetText("Total XP: "               .. sessionStats.totalXP)
			labelMythicals:SetText("Mythical Drops: "  .. sessionStats.mythicalDrops)
			labelCrashes:SetText("Crashes Detected: "  .. sessionStats.crashes)
			labelGoldHour:SetText("Gold / Hour: "      .. getGoldPerHour())
			labelGamesHour:SetText("Games / Hour: "    .. getGamesPerHour())
			local avgGold = sessionStats.gamesPlayed > 0
				and math.floor(sessionStats.totalGold / sessionStats.gamesPlayed) or 0
			labelAvgGold:SetText("Avg Gold / Game: "   .. avgGold)
		end)
		task.wait(1)
	end
end)

-- ==========================================
-- AUTO SELL / ACHIEVEMENTS / ARTIFACTS / SHIFTERS / LOADOUTS
-- ==========================================

do -- isolate locals to avoid 200-register limit at top scope
-- AUTO SELL (Tabs.Upgrades)
local AutoSellGroup = Tabs.Upgrades:AddRightGroupbox("Auto-Sell", "trash-2")

AutoSellGroup:AddDropdown("AutoSellRarityDropdown", {
	Text = "Sell Rarity",
	Values = {"Common","Rare","Epic","Legendary","Mythic","Secret"},
	Default = 1,
	Multi = true,
})

AutoSellGroup:AddToggle("AutoSellToggle", {
	Text = "Auto-Sell Perks",
	Default = false,
	Tooltip = "Sells perks of selected rarities (Secrets and equipped items are never sold)",
})

AutoSellGroup:AddToggle("AutoSellArtifactsToggle", {
	Text = "Auto-Sell Artifacts",
	Default = false,
	Tooltip = "Sells artifacts of selected rarities (Secrets and equipped items are never sold)",
})

-- v8.5: real save shapes (live-audited 2026-10-17, place 14916516914 PV9150):
--   Perks.Storage      = {uuid -> {Name, Level, XP}}         (no Rarity field)
--   Perks.Equipped     = {Slot -> uuid}
--   Artifacts.Storage  = {uuid -> {Name, Stats, Locked}}     (Locked = per-stat
--     REROLL locks, NOT sell locks — the game's only sell guard is "equipped")
--   Artifacts.Equipped = {Body/Head -> {Vanity, ID}}
-- Rarity is resolved by name: game catalogs (Storage.Perks / Storage.Items for
-- artifacts). Delete contract (decompiled Equipment.Delete, 2026-10-17): one
-- batched GET S_Equipment/Delete ("Perk"|"Artifact", {id, ...}) per pass,
-- payload = Storage ids, returns the new full save.
local _artifactRarity = nil
local function ResolveArtifactRarity(name)
	if _artifactRarity == nil then
		_artifactRarity = {}
		local catalog = moduleLoader({ "Modules", "Storage", "Items" })
		if catalog then
			for itemName, data in pairs(catalog) do
				if type(data) == "table" and data.Rarity then _artifactRarity[itemName] = data.Rarity end
			end
		end
	end
	return _artifactRarity[name]
end

-- Never sells: equipped items (game rule: "Cannot sell an equipped item!"),
-- unresolved-rarity items, the legacy Secret tier (see GetPerkRarity), and
-- anything whose rarity the user did not select.
local function sellable(entry, id, equippedIds, raritySet, rarityOf)
	if type(entry) ~= "table" then return false end
	if equippedIds[id] then return false end
	local rarity = rarityOf(entry.Name)
	if rarity == nil or rarity == "Secret" then return false end
	return raritySet[rarity] == true
end

local function collectBatch(storage, equipped, raritySet, rarityOf, cap)
	local equippedIds = {}
	for _, v in pairs(equipped) do
		local id = type(v) == "table" and v.ID or v
		if type(id) == "string" and id ~= "" then equippedIds[id] = true end
	end
	local batch = {}
	for id, entry in pairs(storage) do
		if sellable(entry, id, equippedIds, raritySet, rarityOf) then
			table.insert(batch, id)
			if #batch >= cap then break end
		end
	end
	return batch
end

Toggles.AutoSellToggle:OnChanged(function()
	getgenv().AutoSellPerks = Toggles.AutoSellToggle.Value
	if not getgenv().AutoSellPerks then return end
	task.spawn(function()
		local rarities = Options.AutoSellRarityDropdown.Value or {}
		if #rarities == 0 then
			Library:Notify({ Title = "Auto Sell", Description = "Select at least one rarity!", Time = 3 })
			getgenv().AutoSellPerks = false
			Toggles.AutoSellToggle:SetValue(false)
			return
		end
		local raritySet = {}
		for _, r in ipairs(rarities) do raritySet[r] = true end
		while getgenv().AutoSellPerks do
			local pData = GetPlayerData()
			local slot = lp:GetAttribute("Slot") or (pData and pData.Current_Slot)
			local slotData = pData and pData.Slots and slot and pData.Slots[slot]
			if slotData then
				local perks = slotData.Perks or {}
				local batch = collectBatch(perks.Storage or {}, perks.Equipped or {}, raritySet, GetPerkRarity, 10)
				if #batch > 0 then
					if _G.AOTR.deletePerk(batch) then
						lastPlayerData, lastPlayerDataTime = nil, 0
						Library:Notify({ Title = "Auto Sell", Description = "Sold " .. #batch .. (#batch == 1 and " perk" or " perks"), Time = 1.5 })
					end
					task.wait(humanWait(0.6, 0.5))
				end
			end
			task.wait(humanWait(2, 1.2))
		end
	end)
end)

Toggles.AutoSellArtifactsToggle:OnChanged(function()
	getgenv().AutoSellArtifacts = Toggles.AutoSellArtifactsToggle.Value
	if not getgenv().AutoSellArtifacts then return end
	task.spawn(function()
		local rarities = Options.AutoSellRarityDropdown.Value or {}
		if #rarities == 0 then
			Library:Notify({ Title = "Auto Sell", Description = "Select at least one rarity!", Time = 3 })
			getgenv().AutoSellArtifacts = false
			Toggles.AutoSellArtifactsToggle:SetValue(false)
			return
		end
		local raritySet = {}
		for _, r in ipairs(rarities) do raritySet[r] = true end
		while getgenv().AutoSellArtifacts do
			local pData = GetPlayerData()
			local slot = lp:GetAttribute("Slot") or (pData and pData.Current_Slot)
			local slotData = pData and pData.Slots and slot and pData.Slots[slot]
			if slotData then
				local artifacts = slotData.Artifacts or {}
				local batch = collectBatch(artifacts.Storage or {}, artifacts.Equipped or {}, raritySet, ResolveArtifactRarity, 10)
				if #batch > 0 then
					if _G.AOTR.deleteArtifact(batch) then
						lastPlayerData, lastPlayerDataTime = nil, 0
						Library:Notify({ Title = "Auto Sell", Description = "Sold " .. #batch .. (#batch == 1 and " artifact" or " artifacts"), Time = 1.5 })
					end
					task.wait(humanWait(0.6, 0.5))
				end
			end
			task.wait(humanWait(2, 1.2))
		end
	end)
end)

-- ACHIEVEMENTS (Tabs.Upgrades)
local AchievementsGroup = Tabs.Upgrades:AddRightGroupbox("Achievement Hunter", "award")

AchievementsGroup:AddSlider("AchievementScanSlider", {
	Text = "Max Achievement ID",
	Default = 50,
	Min = 1,
	Max = 200,
	Rounding = 0,
})

AchievementsGroup:AddToggle("AutoAchievementsToggle", {
	Text = "Auto Claim Achievements",
	Default = false,
	Tooltip = "Claims all ready achievements up to the scan range",
})

Toggles.AutoAchievementsToggle:OnChanged(function()
	getgenv().AutoAchievements = Toggles.AutoAchievementsToggle.Value
	if not getgenv().AutoAchievements then return end
	task.spawn(function()
		local maxId = Options.AchievementScanSlider.Value or 50
		while getgenv().AutoAchievements do
			local claimed = 0
			for id = 1, maxId do
				if not getgenv().AutoAchievements then break end
				local ok, res = pcall(function() return _G.AOTR.claimAchievement(id) end)
				if ok and res ~= nil then claimed += 1 end
				task.wait(0.15 + math.random() * 0.1)
			end
			-- v8.2: single summary notify (was one popup per ID — notify spam)
			if claimed > 0 then
				Library:Notify({ Title = "Achievements", Description = "Claimed " .. claimed .. " reward(s)", Time = 3 })
			end
			task.wait(5)
		end
	end)
end)

-- ARTIFACTS (Tabs.Upgrades)
local ArtifactGroup = Tabs.Upgrades:AddLeftGroupbox("Artifacts", "gem")

ArtifactGroup:AddDropdown("AutoArtifactCategoryDropdown", {
	Text = "Artifact Category",
	Values = {"Hat","Face","Neck","Back"},
	Default = 1,
})

ArtifactGroup:AddDropdown("AutoArtifactTargetDropdown", {
	Text = "Artifact",
	Values = {"None"},
	Default = 1,
})

ArtifactGroup:AddToggle("AutoArtifactEquipToggle", {
	Text = "Auto-Equip Target",
	Default = false,
	Tooltip = "Equips the selected artifact when available",
})

ArtifactGroup:AddToggle("AutoArtifactRollToggle", {
	Text = "Auto-Roll Target",
	Default = false,
	Tooltip = "Rolls the selected artifact with selected dice",
})

ArtifactGroup:AddDropdown("AutoArtifactDiceDropdown", {
	Text = "Dice",
	Values = {"None","Ascendant"},
	Default = 1,
})

Toggles.AutoArtifactEquipToggle:OnChanged(function()
	getgenv().AutoArtifactEquip = Toggles.AutoArtifactEquipToggle.Value
	if not getgenv().AutoArtifactEquip then return end
	task.spawn(function()
		local target = Options.AutoArtifactTargetDropdown.Value
		local cat = Options.AutoArtifactCategoryDropdown.Value
		if not target or target == "None" then
			Library:Notify({ Title = "Auto Artifact", Description = "Select a target artifact!", Time = 3 })
			getgenv().AutoArtifactEquip = false
			Toggles.AutoArtifactEquipToggle:SetValue(false)
			return
		end
		while getgenv().AutoArtifactEquip do
			local ok = _G.AOTR.equipArtifact(target, cat)
			if ok then
				Library:Notify({ Title = "Auto Artifact", Description = "Equipped " .. target, Time = 1.5 })
				getgenv().AutoArtifactEquip = false
				Toggles.AutoArtifactEquipToggle:SetValue(false)
				break
			end
			task.wait(1)
		end
	end)
end)

Toggles.AutoArtifactRollToggle:OnChanged(function()
	getgenv().AutoArtifactRoll = Toggles.AutoArtifactRollToggle.Value
	if not getgenv().AutoArtifactRoll then return end
	task.spawn(function()
		local target = Options.AutoArtifactTargetDropdown.Value
		local dice = Options.AutoArtifactDiceDropdown.Value
		if not target or target == "None" then
			Library:Notify({ Title = "Auto Artifact", Description = "Select a target artifact!", Time = 3 })
			getgenv().AutoArtifactRoll = false
			Toggles.AutoArtifactRollToggle:SetValue(false)
			return
		end
		local using = (dice and dice ~= "None") and dice or nil
		while getgenv().AutoArtifactRoll do
			local ok = _G.AOTR.rollArtifact(target, using)
			if ok then
				Library:Notify({ Title = "Auto Artifact", Description = "Rolled " .. target, Time = 1.5 })
			end
			task.wait(1 + math.random() * 0.5)
		end
	end)
end)

-- SHIFTERS (Tabs.Upgrades)
local ShifterGroup = Tabs.Upgrades:AddLeftGroupbox("Shifter Skills", "user")

ShifterGroup:AddDropdown("AutoShifterSkillDropdown", {
	Text = "Shifter Skill",
	Values = {"None"},
	Default = 1,
})

ShifterGroup:AddToggle("AutoShifterUnlockToggle", {
	Text = "Auto-Unlock Shifter Skill",
	Default = false,
	Tooltip = "Unlocks the selected shifter skill when SP available",
})

Toggles.AutoShifterUnlockToggle:OnChanged(function()
	getgenv().AutoShifterUnlock = Toggles.AutoShifterUnlockToggle.Value
	if not getgenv().AutoShifterUnlock then return end
	task.spawn(function()
		local skill = Options.AutoShifterSkillDropdown.Value
		if not skill or skill == "None" then
			Library:Notify({ Title = "Auto Shifter", Description = "Select a skill to unlock!", Time = 3 })
			getgenv().AutoShifterUnlock = false
			Toggles.AutoShifterUnlockToggle:SetValue(false)
			return
		end
		while getgenv().AutoShifterUnlock do
			local ok = _G.AOTR.unlockSkill(skill)
			if ok then
				Library:Notify({ Title = "Auto Shifter", Description = "Unlocked " .. skill, Time = 1.5 })
				getgenv().AutoShifterUnlock = false
				Toggles.AutoShifterUnlockToggle:SetValue(false)
				break
			end
			task.wait(1)
		end
	end)
end)

-- LOADOUTS (Tabs.Global)
local LoadoutGroup = Tabs.Global:AddRightGroupbox("Loadouts", "layers")

LoadoutGroup:AddDropdown("AutoLoadoutCategoryDropdown", {
	Text = "Loadout Slot",
	Values = {"1","2","3","4","5"},
	Default = 1,
})

LoadoutGroup:AddDropdown("AutoLoadoutNameDropdown", {
	Text = "Primary",
	Values = {"None"},
	Default = 1,
})

LoadoutGroup:AddDropdown("AutoLoadoutName2Dropdown", {
	Text = "Secondary",
	Values = {"None"},
	Default = 1,
})

LoadoutGroup:AddToggle("AutoLoadoutToggle", {
	Text = "Auto-Apply Loadout",
	Default = false,
	Tooltip = "Configures the selected loadout slot with chosen presets",
})

Toggles.AutoLoadoutToggle:OnChanged(function()
	getgenv().AutoLoadout = Toggles.AutoLoadoutToggle.Value
	if not getgenv().AutoLoadout then return end
	task.spawn(function()
		local cat = Options.AutoLoadoutCategoryDropdown.Value
		local n1 = Options.AutoLoadoutNameDropdown.Value
		local n2 = Options.AutoLoadoutName2Dropdown.Value
		if not cat then
			getgenv().AutoLoadout = false
			Toggles.AutoLoadoutToggle:SetValue(false)
			return
		end
		while getgenv().AutoLoadout do
			local ok = _G.AOTR.configureLoadout(cat, n1, n2)
			if ok then
				Library:Notify({ Title = "Auto Loadout", Description = "Configured slot " .. cat, Time = 1.5 })
			end
			task.wait(2)
		end
	end)
end)

end -- end of AUTO SELL / ACHIEVEMENTS / ARTIFACTS / SHIFTERS / LOADOUTS block

-- ==========================================
-- SETTINGS TAB
-- ==========================================

SettingsGroup:AddLabel("Menu Hotkey"):AddKeyPicker("MenuKeybind", { Default = "RightControl", NoUI = true, Text = "Menu keybind" })
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

ThemeManager:SetFolder("THUB1/aotr")
SaveManager:SetFolder("THUB1/aotr")

-- v8.3 house theme: Mint palette + BuilderSans. This REPLACES the built-in
-- "Default" entry data (the name "Default" stays in the list; the selectable
-- "THub" snapshot is created below on first run).
ThemeManager:SetDefaultTheme({
	FontColor       = Color3.fromRGB(255, 255, 255),
	MainColor       = Color3.fromRGB(36, 36, 36),
	AccentColor     = Color3.fromRGB(61, 180, 136),
	BackgroundColor = Color3.fromRGB(28, 28, 28),
	OutlineColor    = Color3.fromRGB(55, 55, 55),
	FontFace        = Font.fromName("BuilderSans", Enum.FontWeight.Medium),
})

SaveManager:BuildConfigSection(Tabs.Settings)

-- v8.4 DoD fix: a saved default theme carrying a background image crashes
-- ApplyToTab from the INSIDE (internal LoadDefault → DownloadAsset →
-- RecursiveCreatePath throws when the image can't be cached). Stash the
-- user's default.txt, build the tab clean, restore, then load guarded.
local _stashedDefault = nil
pcall(function()
	if isfile("THUB1/aotr/themes/default.txt") then
		_stashedDefault = readfile("THUB1/aotr/themes/default.txt")
		writefile("THUB1/aotr/themes/default.txt.bak", _stashedDefault) -- crash-proof backup
		delfile("THUB1/aotr/themes/default.txt")
	end
end)
ThemeManager:ApplyToTab(Tabs.Theme)
if _stashedDefault then
	pcall(writefile, "THUB1/aotr/themes/default.txt", _stashedDefault)
	_stashedDefault = nil
end

local _themeLoaded, _themeErr = pcall(function() ThemeManager:LoadDefault() end)
if not _themeLoaded then
	Library:Notify({ Title = "AOTR Hub", Description = "Saved theme skipped (bad background image). Re-save it without an image.", Time = 8 })
end
SaveManager:LoadAutoloadConfig()

-- v8.3: re-arm auto-execute when the flag survived via autoload config
-- (fresh environments reset getgenv, so without this the chain dies after
-- the first teleport even with queue_on_teleport working).
if getgenv().AutoExecute then
	task.spawn(function()
		task.wait(3)
		pcall(setupAutoExecute)
	end)
end

-- v8.3 THub theme snapshot: first run saves current (Mint + BuilderSans) as
-- "THub" and defaults it; legacy "Predeterminado" custom theme is migrated.
pcall(function()
	local tdir = "THUB1/aotr/themes"
	if isfile(tdir .. "/Predeterminado.json") and not isfile(tdir .. "/THub.json") then
		writefile(tdir .. "/THub.json", readfile(tdir .. "/Predeterminado.json"))
		pcall(delfile, tdir .. "/Predeterminado.json")
	end
	if isfile(tdir .. "/default.txt") then
		if readfile(tdir .. "/default.txt") == "Predeterminado" then
			writefile(tdir .. "/default.txt", "THub")
		end
	elseif not isfile(tdir .. "/THub.json") then
		if ThemeManager:SaveCustomTheme("THub") then
			ThemeManager:SaveDefault("THub")
		end
	end
end)

-- v8.3: tell the user the hide key (default or their configured one).
task.spawn(function()
	task.wait(2)
	pcall(function()
		local key = Options.MenuKeybind and Options.MenuKeybind.Value
		Library:Notify({
			Title = "AOTR Hub",
			Description = "Press " .. tostring(key or "RightControl") .. " to show/hide the menu",
			Time = 6,
		})
	end)
end)

Library:OnUnload(function()
	setNoclip(false)
	Library.Unloaded = true
end)

task.spawn(function()
	while not Library.Unloaded do
		local success, err = pcall(ExecuteImmediateAutomation)
		task.wait(0.5)
	end
end)

-- Anti-AFK
local virtualUser = game:GetService("VirtualUser")
lp.Idled:Connect(function()
	virtualUser:CaptureController()
	virtualUser:ClickButton2(Vector2.new())
end)

-- Auto Hide Logic
task.spawn(function()
	task.wait(0.5)
	if getgenv().DeleteMap then DeleteMap() end
	if Toggles.AutoHideToggle.Value then
		Library:Toggle(false)
		Library:Notify({ Title = "AOTR Hub", Description = "Auto Hid GUI", Time = 2 })
	end
end)

task.spawn(function()
	task.wait(1)
	pcall(function() Library:SetFont(Enum.Font.Gotham) end)
end)