local _, NS = ...
local C = {}
NS.Characters = C
local A = NS.Adapter

-- Account-wide record of the player's own characters: gold, mail list and cooldowns read from it.
function C.Own()
    local scope = A.Scope()
    if not scope then return nil, nil end
    local data = NS.App.db.characters
    data[scope] = type(data[scope]) == "table" and data[scope] or {}
    return data[scope], scope
end

-- Per-character settings that belong to no profile.
function C.Data(section)
    local scope = A.Scope() or "?"
    local data = NS.App.db.charData
    data[scope] = type(data[scope]) == "table" and data[scope] or {}
    if section then
        data[scope][section] = type(data[scope][section]) == "table" and data[scope][section] or {}
        return data[scope][section]
    end
    return data[scope]
end

function C.Update()
    if not NS.App.db then return end
    local row = C.Own()
    if not row then return end
    row.money = tonumber(A.Call(GetMoney)) or row.money or 0
    row.level = tonumber(A.Call(UnitLevel, "player")) or row.level
    row.class = A.PlayerClass()
    row.faction = (A.Call(UnitFactionGroup, "player")) or row.faction
    row.name = (A.Call(UnitName, "player")) or row.name
    row.realm = (A.Call(GetRealmName)) or row.realm
    row.seen = A.Call(GetServerTime) or row.seen
end

-- Removes a stale character from every account list. The own character cannot be removed.
function C.Forget(scope)
    if scope == A.Scope() then return false end
    local data = NS.App.db
    data.characters[scope], data.charData[scope], data.charProfiles[scope] = nil, nil, nil
    return true
end

local listener = A.Listener({PLAYER_MONEY = C.Update, PLAYER_LEVEL_UP = C.Update, PLAYER_LOGOUT = C.Update})
function C.SettingsChanged() listener:Set(true) end
