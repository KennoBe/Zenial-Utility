local _, NS = ...
local L = {}
NS.Logic = L

-- Modules a player can switch on or off. Only harmless display helpers start enabled:
-- anything that spends gold, sells items, answers NPCs or changes the map asks first.
L.Defaults = {
    modMap = true,
    modComfort = true,
    modWarnings = true,
    modExtras = true,
    mapReveal = "off", -- off | soft | full
    revealAlpha = .6,
    mapCoords = true,
    waypoints = true,
    vendorJunk = false,
    vendorRepair = false,
    vendorGuildRepair = false,
    vendorChat = true,
    questAccept = false,
    questTurnIn = false,
    warnDurability = true,
    durabilityPercent = 20,
    warnBags = true,
    bagSlots = 3,
    warnAmmo = true,
    warnPoison = true,
    warnReagents = true,
    screenshotLevel = false,
    screenshotBoss = false,
    tooltipIDs = false,
    tooltipPrice = true,
    pullEnabled = true,
    pullSeconds = 10,
    rollTracker = true,
}

L.Bounds = {
    revealAlpha = {.2, 1},
    durabilityPercent = {5, 50},
    bagSlots = {1, 20},
    pullSeconds = {3, 30},
}

local CHOICES = {mapReveal = {off = true, soft = true, full = true}}
local EXTRA = {"setup", "cvarBackup", "pendingRevert", "imported", "macroInputs", "macroSets", "played", "rollWindow"}

function L.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = L.Copy(item) end
    return result
end

local function clamp(key, value, fallback)
    if type(value) ~= "number" or value ~= value then return fallback end
    local bounds = L.Bounds[key]
    if not bounds then return value end
    return math.max(bounds[1], math.min(bounds[2], value))
end

function L.Sanitize(raw)
    raw = type(raw) == "table" and raw or {}
    local out = {}
    for key, fallback in pairs(L.Defaults) do
        local value = raw[key]
        if CHOICES[key] then
            out[key] = CHOICES[key][value] and value or fallback
        elseif type(fallback) == "boolean" then
            if type(value) == "boolean" then out[key] = value else out[key] = fallback end
        else
            out[key] = clamp(key, value, fallback)
        end
    end
    for _, key in ipairs(EXTRA) do
        out[key] = type(raw[key]) == "table" and raw[key] or {}
    end
    return out
end

-- Trims a name to a byte limit without cutting a UTF-8 character in half.
function L.TrimUTF8(value, limit)
    if #value <= limit then return value end
    local stop = limit
    while stop > 0 do
        local byte = value:byte(stop + 1)
        if not byte or byte < 128 or byte >= 192 then break end
        stop = stop - 1
    end
    return value:sub(1, stop)
end

-- Accepts "45.2 67.8", "45,2 67,8" and "45.2, 67.8", with an optional title afterwards.
function L.ParseWaypoint(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    local x, y, title = text:match("^(%d+[%.,]?%d*)[%s,;]+(%d+[%.,]?%d*)%s*(.*)$")
    if not x then return nil end
    x, y = tonumber((x:gsub(",", "."))), tonumber((y:gsub(",", ".")))
    if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then return nil end
    return x / 100, y / 100, title ~= "" and title or nil
end

function L.FormatPercent(x, y)
    return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- "1 Tag 4 Std." style text for a /played value in seconds.
function L.FormatPlayed(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return string.format(NS.Text("%d T %d Std %d Min", "%dd %dh %dm"), days, hours, minutes)
end

-- Parses a system roll line through the client's own localized RANDOM_ROLL_RESULT pattern.
function L.RollPattern(template)
    if type(template) ~= "string" then return nil end
    local pattern = template:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%%%?%d?%$?s", "(.+)"):gsub("%%%%?%d?%$?d", "(%%d+)")
    return "^" .. pattern .. "$"
end

function L.ParseRoll(message, pattern)
    if type(message) ~= "string" or not pattern then return nil end
    local name, roll, low, high = message:match(pattern)
    roll, low, high = tonumber(roll), tonumber(low), tonumber(high)
    if not name or not roll or not low or not high then return nil end
    return {name = name, roll = roll, low = low, high = high}
end

-- A 1-50 roll next to 1-100 rolls would mislead, so anything but the usual range is named.
function L.RollRange(row)
    if row.low == 1 and row.high == 100 then return "" end
    return string.format(" (%d-%d)", row.low, row.high)
end

-- Chat lines for a sorted roll list: the header first, split between entries at the chat limit.
function L.RollAnnouncement(rolls, header, limit)
    limit = limit or 255
    local lines, current = {}, header
    if #rolls == 0 then return lines end
    for index, row in ipairs(rolls) do
        local entry = string.format("%d. %s %d%s", index, row.name, row.roll, L.RollRange(row))
        local separator = index == 1 and " " or ", "
        if #current + #separator + #entry > limit then
            lines[#lines + 1] = current
            current = entry
        else
            current = current .. separator .. entry
        end
    end
    lines[#lines + 1] = current
    return lines
end
