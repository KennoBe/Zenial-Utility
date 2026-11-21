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

-- Forever may report the realm as "". The last real realm of this character (keyed by the stable
-- player GUID) or the only saved character of this name and faction then keeps the old keys in use.
-- Nothing is invented: without any hint the realm stays "".
function A.Realm(name)
    if A.realm then return A.realm end
    local api = A.Call(GetRealmName)
    api = type(api) == "string" and api ~= "" and api or nil
    local guid = A.Call(UnitGUID, "player")
    guid = type(guid) == "string" and guid ~= "" and guid or nil
    local data = NS.App and NS.App.db
    if type(data) ~= "table" then return api or "" end
    if type(data.realms) ~= "table" then data.realms = {} end
    if api then
        if guid then data.realms[guid] = api end
        A.realm = api
        return api
    end
    local saved = guid and data.realms[guid]
    if type(saved) == "string" and saved ~= "" then A.realm = saved; return saved end
    if type(name) ~= "string" then return "" end
    local faction = A.Call(UnitFactionGroup, "player")
    -- Keys hold only the first name, so several characters can share it: the stored class and faction must match too.
    local okClass, _, class = pcall(UnitClass, "player")
    class = okClass and type(class) == "string" and class or nil
    local found, count = nil, 0
    for key, row in pairs(type(data.characters) == "table" and data.characters or {}) do
        if type(key) == "string" and type(row) == "table" and key:sub(1, #name + 1) == name .. "-" then
            local realm = key:sub(#name + 2)
            if realm ~= "" and realm ~= found and not (row.faction and faction and row.faction ~= faction)
                and not (row.class and class and row.class ~= class) then
                found, count = realm, count + 1
            end
        end
    end
    -- Only a known realm is kept for the session; an empty answer is asked again (the GUID may not be ready yet).
    local realm = count == 1 and found or ""
    if realm ~= "" then A.realm = realm end
    return realm
end

function A.Scope()
    local name = A.Call(UnitName, "player")
    if type(name) ~= "string" then return nil end
    return name .. "-" .. A.Realm(name)
end

-- Character key as shown to the player: no dangling "-" when the realm is unknown.
function A.ScopeLabel(scope)
    return (tostring(scope):gsub("%-$", ""))
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
