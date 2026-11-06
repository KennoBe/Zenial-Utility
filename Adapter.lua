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
    local text = A.Call(GetCoinTextureString, copper)
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
