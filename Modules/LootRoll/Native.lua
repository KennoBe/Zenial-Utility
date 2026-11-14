local _, NS = ...
local N = {}
NS.LootRollNative = N
local A = NS.Adapter

-- The only file with client calls for group loot rolls. The game's own roll window is not touched:
-- it opens from a private START_LOOT_ROLL handler, and only that handler is switched off here
-- (GameEvent.UnregisterInternalEvent). GroupLootContainer, GroupLootFrame1..4, LootFrame and
-- AlertFrame are only ever read.

local ACTION_PASS, ACTION_NEED, ACTION_GREED, ACTION_TRANSMOG = 0, 1, 2, 4
local OTHER_ADDONS = {"AuxyLoot", "ForeverLootRoll", "ForeverLootRolls"}

local function isFunction(value) return type(value) == "function" end

function N.Available()
    return isFunction(_G.GetLootRollItemInfo) and isFunction(_G.RollOnLoot) and isFunction(_G.GetActiveLootRollIDs)
end

function N.Now() return tonumber(A.Call(_G.GetTime)) or 0 end
function N.ServerTime() return tonumber(A.Call(_G.GetServerTime)) or 0 end

-- Milliseconds in the client, seconds here.
function N.TimeLeft(rollID)
    local milliseconds = A.Call(_G.GetLootRollTimeLeft, rollID)
    if type(milliseconds) == "number" then return math.max(0, milliseconds / 1000) end
    return nil
end

local function totalSeconds(rollID)
    local api = _G.C_Loot
    local milliseconds = api and A.Call(api.GetLootRollDuration, rollID)
    if type(milliseconds) == "number" and milliseconds > 0 then return milliseconds / 1000 end
    return nil
end

local function reasonText(reason)
    if type(reason) ~= "number" then return nil end
    local text = _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason]
    return type(text) == "string" and text or nil
end

-- A roll as the model takes it, or nil when the client does not give it out (hidden values,
-- missing data). The caller then hands the roll to the game's own window.
function N.Read(rollID, rollTimeMs)
    local texture, name, count, quality, bindOnPickup, canNeed, canGreed, _, reasonNeed, reasonGreed, _, _, canTransmog =
        A.Call(_G.GetLootRollItemInfo, rollID)
    if type(name) ~= "string" or name == "" then return nil end
    local link = A.Call(_G.GetLootRollItemLink, rollID)
    local left = N.TimeLeft(rollID) or (type(rollTimeMs) == "number" and rollTimeMs / 1000) or nil
    local duration = totalSeconds(rollID) or (type(rollTimeMs) == "number" and rollTimeMs / 1000) or left
    -- Transmog stands in for greed, as in the game's own window.
    local third = canTransmog == true and ACTION_TRANSMOG or ACTION_GREED
    local allowed = {[ACTION_PASS] = true, [ACTION_NEED] = canNeed == true,
        [ACTION_GREED] = canTransmog ~= true and canGreed == true, [ACTION_TRANSMOG] = canTransmog == true}
    local reasons = {}
    if canNeed ~= true then reasons[ACTION_NEED] = reasonText(reasonNeed) end
    if canTransmog ~= true and canGreed ~= true then reasons[ACTION_GREED] = reasonText(reasonGreed) end
    return {link = type(link) == "string" and link or nil, name = name, icon = texture, count = tonumber(count) or 1,
        quality = tonumber(quality), bop = bindOnPickup == true, duration = duration, timeLeft = left or duration,
        allowed = allowed, reasons = reasons, offers = {ACTION_NEED, third, ACTION_PASS}}
end

-- true when the client took the call.
function N.Roll(rollID, action)
    if not isFunction(_G.RollOnLoot) then return false end
    return (pcall(_G.RollOnLoot, rollID, action))
end

function N.ActiveSet()
    local set = {}
    local list = A.Call(_G.GetActiveLootRollIDs)
    if type(list) == "table" then
        for _, rollID in ipairs(list) do set[rollID] = true end
    end
    return set
end

function N.Gamepad()
    local input = _G.InputUtil
    return type(input) == "table" and A.Call(input.IsGamepadUIEnabled) == true
end

-- Name of another loot roll addon that is loaded, or nil.
function N.Conflict()
    local api = _G.C_AddOns
    local check = api and api.IsAddOnLoaded or _G.IsAddOnLoaded
    for _, name in ipairs(OTHER_ADDONS) do
        if A.Call(check, name) == true then return name end
    end
    return nil
end

local function hasGameEvent()
    local game = _G.GameEvent
    return type(game) == "table" and isFunction(game.RegisterInternalEvent) and isFunction(game.UnregisterInternalEvent)
        and isFunction(game.HandleStartLootRoll)
end

-- Whether the module may take the roll windows over, and if not, why.
function N.CanReplace()
    if N.Gamepad() then return false, "gamepad" end
    if not N.Available() or not hasGameEvent() then return false, "unsupported" end
    local other = N.Conflict()
    if other then return false, "conflict:" .. other end
    return true
end

function N.Suppress(on)
    on = on == true
    if on == (N.suppressed == true) then return true end
    if not hasGameEvent() then return false end
    local game = _G.GameEvent
    local ok
    if on then
        ok = pcall(game.UnregisterInternalEvent, "START_LOOT_ROLL")
    else
        ok = pcall(game.RegisterInternalEvent, "START_LOOT_ROLL", function(...) _G.GameEvent.HandleStartLootRoll(...) end)
    end
    if ok then N.suppressed = on end
    return ok
end

-- Hands one roll to the game's own window.
function N.ShowNative(rollID, rollTimeMs)
    if not hasGameEvent() then return false end
    return (pcall(_G.GameEvent.HandleStartLootRoll, nil, "START_LOOT_ROLL", rollID, rollTimeMs))
end

-- Read only: does one of the game's roll windows show this roll?
function N.NativeShows(rollID)
    for index = 1, 4 do
        local frame = _G["GroupLootFrame" .. index]
        if type(frame) == "table" and isFunction(frame.IsShown) then
            local shown, id = A.Call(frame.IsShown, frame), frame.rollID
            if shown == true and A.Public(id) and id == rollID then return true end
        end
    end
    return false
end

function N.HideConfirm(rollID)
    A.Call(_G.StaticPopup_Hide, "CONFIRM_LOOT_ROLL", rollID)
end

function N.Drops(encounterID)
    local api = _G.C_LootHistory
    local drops = api and A.Call(api.GetSortedDropsForEncounter, encounterID)
    return type(drops) == "table" and drops or nil
end

function N.Enum()
    local enum = _G.Enum
    return type(enum) == "table" and type(enum.EncounterLootDropRollState) == "table" and enum.EncounterLootDropRollState or nil
end

function N.HistoryNow()
    local api = _G.C_LootHistory
    local now = api and A.Call(api.GetLootHistoryTime)
    return type(now) == "number" and now or nil
end

-- The client's own roll line texts, by global string name.
function N.Strings()
    local out = {}
    for _, key in ipairs(NS.LootRollModel.CHAT_KEYS) do
        local value = _G[key]
        if type(value) == "string" and A.Public(value) then out[key] = value end
    end
    return out
end

function N.OwnName()
    local name = A.Call(_G.UnitName, "player")
    return type(name) == "string" and name or nil
end
