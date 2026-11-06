local _, NS = ...
local A = {}
NS.Adapter = A

-- Protected or missing client values must never break the addon, so every game call goes through here.
function A.Public(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return false end
    return true
end

local function finish(ok, ...)
    if not ok then return nil end
    for index = 1, select("#", ...) do
        if not A.Public((select(index, ...))) then return nil end
    end
    return ...
end

function A.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return finish(pcall(fn, ...))
end

function A.Combat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

function A.Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffcc44ZENIAL Utility|r · " .. message) end
end

function A.Scope()
    local name = A.Call(UnitName, "player")
    local realm = A.Call(GetRealmName)
    if type(name) ~= "string" then return nil end
    return name .. "-" .. (type(realm) == "string" and realm or "")
end

function A.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    -- The client moved this into C_CurrencyInfo; the global only exists on older clients.
    local api = _G.C_CurrencyInfo
    local text = A.Call(api and api.GetCoinTextureString or GetCoinTextureString, copper)
    if type(text) == "string" and text ~= "" then return text end
    return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

function A.SpellName(spell)
    local api = _G.C_Spell
    local name = api and A.Call(api.GetSpellName, spell)
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

function A.SpellIcon(spell)
    local api = _G.C_Spell
    return api and A.Call(api.GetSpellTexture, spell) or nil
end

-- A spell counts as known by rank-independent name, so rank 1 IDs still match a higher learned rank.
function A.SpellKnown(spell)
    if A.Call(IsPlayerSpell, spell) == true then return true end
    if A.Call(IsSpellKnown, spell) == true or A.Call(IsSpellKnown, spell, true) == true then return true end
    local name = A.SpellName(spell)
    local api = _G.C_Spell
    if not name or not api then return false end
    return A.Call(api.GetSpellInfo, name) ~= nil
end

function A.PlayerClass()
    local _, classFile = A.Call(UnitClass, "player")
    return type(classFile) == "string" and classFile or "GENERAL"
end

-- One event frame per module. Events are registered only while the module is on,
-- so a switched-off feature costs nothing. An event the client does not know is skipped.
function A.Listener(handlers, units)
    local frame = CreateFrame("Frame")
    local listener = {frame = frame, active = false}
    frame:SetScript("OnEvent", function(_, event, ...)
        local handler = handlers[event]
        if handler then handler(...) end
    end)
    function listener:Set(on)
        on = on == true
        if on == self.active then return end
        self.active = on
        if not on then frame:UnregisterAllEvents(); return end
        for event in pairs(handlers) do
            local unit = units and units[event]
            if unit then pcall(frame.RegisterUnitEvent, frame, event, unit)
            else pcall(frame.RegisterEvent, frame, event) end
        end
    end
    return listener
end

-- Temporary enchant on an inventory slot: has it, seconds left. nil means unknown, not missing:
-- an unreadable answer must not raise a false warning. The global GetWeaponEnchantInfo is only a
-- deprecation wrapper on this client, so it is the fallback.
local function readEnchant(info) return info.remainingTimeMs end

function A.WeaponEnchant(slot)
    local paper = _G.C_PaperDollInfo
    if paper and type(paper.GetTemporaryEnchantmentInfo) == "function" then
        local ok, info = pcall(paper.GetTemporaryEnchantmentInfo, slot)
        if not ok or not A.Public(info) then return nil end
        if not info then return false, 0 end
        local read, ms = pcall(readEnchant, info)
        if not read or not A.Public(ms) then return nil end
        return true, (tonumber(ms) or 0) / 1000
    end
    if type(_G.GetWeaponEnchantInfo) ~= "function" then return nil end
    local main, mainLeft, _, _, off, offLeft = A.Call(_G.GetWeaponEnchantInfo)
    if main == nil then return nil end
    if slot == 16 then return main == true, main == true and (tonumber(mainLeft) or 0) / 1000 or 0 end
    return off == true, off == true and (tonumber(offLeft) or 0) / 1000 or 0
end

function A.Shift() return A.Call(IsShiftKeyDown) == true end

function A.GroupUnits()
    local units = {}
    if A.Call(IsInRaid) == true then
        for index = 1, tonumber(A.Call(GetNumGroupMembers)) or 0 do units[#units + 1] = "raid" .. index end
    elseif A.Call(IsInGroup) == true then
        for index = 1, 4 do
            if A.Call(UnitExists, "party" .. index) == true then units[#units + 1] = "party" .. index end
        end
    end
    return units
end

function A.ItemCount(item)
    local api = _G.C_Item
    return api and tonumber(A.Call(api.GetItemCount, item)) or 0
end

function A.PlaySound(kit)
    local api = _G.C_Sound
    if api then A.Call(api.PlaySound, kit) end
end
