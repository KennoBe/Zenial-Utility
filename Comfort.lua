local _, NS = ...
local C = {}
NS.Comfort = C
local A, tr = NS.Adapter, NS.Text

local function db() return NS.App.db end
local function on(key) return db().modQoL and db()[key] end

----------------------------------------------------------------------
-- Faster auto loot. Follows the player's own auto-loot setting and modifier.
----------------------------------------------------------------------
function C.AutoLootActive()
    local default = A.Call(GetCVarBool, "autoLootDefault") == true
    local modified = A.Call(IsModifiedClick, "AUTOLOOTTOGGLE") == true
    return default ~= modified
end

function C.FastLoot()
    if not on("fastLoot") or not C.AutoLootActive() then return end
    local now = tonumber(A.Call(GetTime)) or 0
    -- The event comes twice for one window.
    if C.lootAt and now - C.lootAt < .2 then return end
    C.lootAt = now
    for slot = tonumber(A.Call(GetNumLootItems)) or 0, 1, -1 do
        local locked = select(6, A.Call(GetLootSlotInfo, slot))
        if not locked then A.Call(LootSlot, slot) end
    end
end

-- Greed on uncommon items that bind on equip or not at all. Never need, never bind-on-pickup.
function C.LootRoll(rollID)
    if not on("lootGreed") or not rollID then return end
    local _, _, _, quality, bindOnPickup, _, canGreed = A.Call(GetLootRollItemInfo, rollID)
    if quality == 2 and canGreed == true and bindOnPickup ~= true then A.Call(RollOnLoot, rollID, 2) end
end

----------------------------------------------------------------------
-- Gossip: only when one service is the sole option, is recognised, and no quest is attached.
----------------------------------------------------------------------
-- File IDs of the game's own gossip icons. Binding a hearthstone and guild charters stay manual:
-- they are decisions and not a way through to a window.
C.ServiceIcons = {
    [132060] = true, -- vendor
    [132058] = true, -- trainer
    [132057] = true, -- flight master
    [132050] = true, -- bank
    [528409] = true, -- auction house
    [132051] = true, -- battlemaster
    [132056] = true, -- tabard
    [1673939] = true, -- transmog
}

function C.SkipGossip()
    if not on("skipGossip") or A.Shift() then return end
    local api = _G.C_GossipInfo
    if not api then return end
    if (tonumber(A.Call(api.GetNumActiveQuests)) or 0) > 0 or (tonumber(A.Call(api.GetNumAvailableQuests)) or 0) > 0 then return end
    local options = A.Call(api.GetOptions)
    if type(options) ~= "table" or #options ~= 1 then return end
    local option = options[1]
    if type(option) ~= "table" or not C.ServiceIcons[option.icon] or not option.gossipOptionID then return end
    A.Call(api.SelectOption, option.gossipOptionID)
end

----------------------------------------------------------------------
-- Interruptions
----------------------------------------------------------------------
function C.DuelRequested(name)
    if not on("declineDuels") or A.Shift() then return end
    A.Call(CancelDuel)
    A.Call(StaticPopup_Hide, "DUEL_REQUESTED")
    if type(name) == "string" and A.Public(name) then
        A.Print(string.format(tr("Duell von %s abgelehnt.", "Declined a duel from %s."), name))
    end
end

function C.PlayerDead()
    if not on("bgRelease") or A.Shift() then return end
    local inside, kind = A.Call(IsInInstance)
    if inside ~= true or kind ~= "pvp" then return end
    -- A soulstone is the player's choice to make.
    local death = _G.C_DeathInfo
    local options = death and A.Call(death.GetSelfResurrectOptions)
    if type(options) == "table" and #options > 0 then return end
    A.Call(RepopMe)
end

----------------------------------------------------------------------
-- Error filter. Only the chosen kinds of red messages; everything else passes through untouched.
----------------------------------------------------------------------
local ERROR_GROUPS = {
    errResource = {"LE_GAME_ERR_OUT_OF_MANA", "LE_GAME_ERR_OUT_OF_ENERGY", "LE_GAME_ERR_OUT_OF_RAGE", "LE_GAME_ERR_OUT_OF_FOCUS", "LE_GAME_ERR_OUT_OF_POWER_DISPLAY"},
    errCooldown = {"LE_GAME_ERR_ABILITY_COOLDOWN", "LE_GAME_ERR_SPELL_COOLDOWN", "LE_GAME_ERR_ITEM_COOLDOWN"},
    errRange = {"LE_GAME_ERR_OUT_OF_RANGE", "LE_GAME_ERR_SPELL_OUT_OF_RANGE", "LE_GAME_ERR_USE_TOO_FAR", "LE_GAME_ERR_AUTOFOLLOW_TOO_FAR", "LE_GAME_ERR_BADATTACKPOS"},
    errTarget = {"LE_GAME_ERR_GENERIC_NO_TARGET", "LE_GAME_ERR_INVALID_ATTACK_TARGET", "LE_GAME_ERR_NO_ATTACK_TARGET"},
}

function C.IsFiltered(messageType)
    if not on("errorFilter") or not A.Public(messageType) or type(messageType) ~= "number" then return false end
    if db().errAll then return true end
    for key, names in pairs(ERROR_GROUPS) do
        if db()[key] then
            for _, name in ipairs(names) do
                if _G[name] == messageType then return true end
            end
        end
    end
    return false
end

-- The client's TryDisplayMessage shows the text and then plays the sound of the same message type
-- (GetGameMessageInfo: voice line, otherwise sound kit). For a filtered type, the two parts are
-- rebuilt separately with the same public calls, so text and sound can be switched independently.
local function playErrorSound(messageType)
    local _, soundKitID, voiceID = A.Call(_G.GetGameMessageInfo, messageType)
    local sound = _G.C_Sound
    if voiceID then
        if sound and type(sound.PlayVocalErrorSound) == "function" then A.Call(sound.PlayVocalErrorSound, voiceID)
        else A.Call(_G.PlayVocalErrorSoundID, voiceID) end
    elseif soundKitID then
        A.Call(_G.PlaySound, soundKitID)
    end
end

local function showFiltered(frame, messageType, message, r, g, b)
    local data = db()
    local text, sound = data.errShowText == true, data.errPlaySound == true
    if text and sound then return frame:TryDisplayMessage(messageType, message, r, g, b) end
    if not text and not sound then return end
    if type(frame.GetMessagesSuppressed) == "function" and frame:GetMessagesSuppressed() then return end
    if type(frame.ShouldDisplayMessageType) == "function" and not frame:ShouldDisplayMessageType(messageType, message) then return end
    if text then frame:AddMessage(message, r, g, b, 1.0, messageType) end
    if sound then playErrorSound(messageType) end
end

local errorListener = A.Listener({UI_ERROR_MESSAGE = function(messageType, message)
    local frame = _G.UIErrorsFrame
    if not frame then return end
    local color = _G.RED_FONT_COLOR
    local r, g, b = 1, .1, .1
    if color and color.GetRGB then r, g, b = color:GetRGB() end
    if C.IsFiltered(messageType) then return showFiltered(frame, messageType, message, r, g, b) end
    frame:TryDisplayMessage(messageType, message, r, g, b)
end})

local function setErrorFilter(active)
    local frame = _G.UIErrorsFrame
    if not frame or type(frame.TryDisplayMessage) ~= "function" or not frame.UnregisterEvent then return end
    if active == (C.errorActive == true) then return end
    C.errorActive = active
    errorListener:Set(active)
    if active then frame:UnregisterEvent("UI_ERROR_MESSAGE") else frame:RegisterEvent("UI_ERROR_MESSAGE") end
end

----------------------------------------------------------------------
-- Hide interface elements. Invisible also means not clickable: mouse input goes off for the frame
-- and its children, and comes back on hover or when shown again. Nothing is reparented.
----------------------------------------------------------------------
C.HideTargets = {
    hideBags = function() return _G.BagsBar end,
    hideMicro = function() return _G.MicroMenuContainer or _G.MicroMenu end,
    hideClock = function() return _G.TimeManagerClockButton end,
    hideCalendar = function() return _G.GameTimeFrame end,
    hideTracking = function() return _G.MinimapCluster and _G.MinimapCluster.Tracking end,
    hideZoneText = function() return _G.MinimapCluster and _G.MinimapCluster.ZoneTextButton end,
}
C.hidden = {}

local function setMouse(frame, value, memory)
    if frame.EnableMouse and frame.IsMouseEnabled then
        if value then
            if memory[frame] then frame:EnableMouse(true) end
        else
            if frame:IsMouseEnabled() then memory[frame] = true end
            frame:EnableMouse(false)
        end
    end
    if frame.GetChildren then
        for _, child in ipairs({frame:GetChildren()}) do setMouse(child, value, memory) end
    end
end

local function hasProtected(frame)
    if frame.IsProtected and frame:IsProtected() then return true end
    if frame.GetChildren then
        for _, child in ipairs({frame:GetChildren()}) do
            if hasProtected(child) then return true end
        end
    end
    return false
end

local function setVisible(key, frame, visible)
    local state = C.hidden[key]
    if not state then
        state = {memory = {}, visible = true}
        C.hidden[key] = state
    end
    if state.visible == visible then return true end
    -- A protected frame can't change its mouse state in combat. The end of combat catches up.
    if A.Combat() and hasProtected(frame) then C.pendingHide = true; return false end
    state.visible = visible
    frame:SetAlpha(visible and 1 or 0)
    setMouse(frame, visible, state.memory)
    return true
end

function C.ApplyHide()
    C.pendingHide = false
    local hover = false
    for key, find in pairs(C.HideTargets) do
        local frame = find()
        local mode = db().modQoL and db()[key] or "show"
        if frame then
            if mode == "hover" then
                hover = true
                setVisible(key, frame, frame.IsMouseOver and frame:IsMouseOver() or false)
            else
                setVisible(key, frame, mode == "show")
            end
        end
    end
    C.hoverActive = hover
    C.SetHoverClock(hover)
end

local hoverFrame = CreateFrame("Frame")
local hoverWait = 0
local function hoverTick(_, dt)
    hoverWait = hoverWait + dt
    if hoverWait < .2 then return end
    hoverWait = 0
    for key, find in pairs(C.HideTargets) do
        if db()[key] == "hover" then
            local frame = find()
            if frame and frame.IsMouseOver then setVisible(key, frame, frame:IsMouseOver()) end
        end
    end
end

-- A clock frame only exists for the time a hover mode is in use.
function C.SetHoverClock(active) hoverFrame:SetScript("OnUpdate", active and hoverTick or nil) end

----------------------------------------------------------------------
local listener = A.Listener({
    LOOT_READY = C.FastLoot,
    START_LOOT_ROLL = C.LootRoll,
    GOSSIP_SHOW = C.SkipGossip,
    DUEL_REQUESTED = C.DuelRequested,
    PLAYER_DEAD = C.PlayerDead,
    PLAYER_REGEN_ENABLED = function() if C.pendingHide then C.ApplyHide() end end,
    ADDON_LOADED = function() C.ApplyHide() end,
})

function C.SettingsChanged()
    local data = db()
    local anyHide = false
    for key in pairs(C.HideTargets) do anyHide = anyHide or data[key] ~= "show" end
    local any = data.modQoL and (data.fastLoot or data.lootGreed or data.skipGossip or data.declineDuels or data.bgRelease or anyHide)
    listener:Set(any == true or next(C.hidden) ~= nil)
    setErrorFilter(on("errorFilter") == true)
    if anyHide or next(C.hidden) ~= nil then C.ApplyHide() end
end
