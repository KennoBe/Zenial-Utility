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
    rollTracker = true,
    -- Everything below came with 0.2.0. Anything that shows new things on screen or acts
    -- for the player starts off, so an update changes nothing until it is switched on.
    questDifficulty = "all", -- all | nogray | nogreen
    questRepeatable = false,
    questRewardValue = false,
    questZoneTrack = false,
    ammoThreshold = 100,
    warnSound = false,
    modBuffs = false,
    buffMounted = false, -- also warn while mounted
    buffResting = true, -- also warn in rested areas
    buffGroup = true,
    warnOnBars = true,
    modInfoBar = false,
    infoCompact = false,
    infoIcons = true,
    infoScale = 1,
    infoFont = 12,
    infoAlpha = .75,
    infoLocked = true,
    infoColors = true,
    goldScope = "all", -- all | faction | current
    modInventory = true,
    bagMove = false,
    xpText = false,
    xpPercent = false,
    mailAlts = false,
    destroyGray = false,
    destroyConfirm = true,
    modTooltip = true,
    ttUnit = false,
    ttLayout = "compact", -- compact | lines | blizz
    ttLevel = true,
    ttClass = true,
    ttRace = true,
    ttFaction = true,
    ttGuild = true,
    ttGuildRank = true,
    ttTarget = true,
    ttItemLevel = false,
    ttAnchor = "default", -- default | TOPLEFT | TOPRIGHT | BOTTOMLEFT | BOTTOMRIGHT
    ttHealthBar = "default", -- default | flat | soft
    ttGathering = false,
    modQoL = true,
    fastLoot = false,
    lootConfirmSolo = false,
    lootFeed = false,
    lootFeedTime = 3,
    lootFeedScale = 1,
    lootFeedQuality = false,
    lootFeedTooltip = false,
    lootGreed = false,
    skipGossip = false,
    declineDuels = false,
    bgRelease = false,
    errorFilter = false,
    errResource = true,
    errCooldown = true,
    errRange = true,
    errTarget = false,
    errAll = false, -- every UI_ERROR_MESSAGE, not only the kinds above
    errShowText = false, -- filtered kinds still show their red text
    errPlaySound = false, -- filtered kinds still play their error sound or voice line
    hideBags = "show", -- show | hide | hover
    hideMicro = "show",
    hideClock = "show",
    hideCalendar = "show",
    hideTracking = "show",
    hideZoneText = "show",
}

L.Bounds = {
    revealAlpha = {.2, 1},
    durabilityPercent = {5, 50},
    bagSlots = {1, 20},
    lootFeedTime = {2, 5},
    lootFeedScale = {.6, 1.6},
    ammoThreshold = {10, 5000},
    infoScale = {.6, 1.6},
    infoFont = {8, 20},
    infoAlpha = {0, 1},
}

local VISIBILITY = {show = true, hide = true, hover = true}
local CHOICES = {
    mapReveal = {off = true, soft = true, full = true},
    questDifficulty = {all = true, nogray = true, nogreen = true},
    goldScope = {all = true, faction = true, current = true},
    ttLayout = {compact = true, lines = true, blizz = true},
    ttAnchor = {default = true, TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true},
    ttHealthBar = {default = true, flat = true, soft = true},
    hideBags = VISIBILITY, hideMicro = VISIBILITY, hideClock = VISIBILITY, hideCalendar = VISIBILITY,
    hideTracking = VISIBILITY, hideZoneText = VISIBILITY,
}
-- Account data that belongs to no profile and is kept as it is.
local EXTRA = {"setup", "cvarBackup", "pendingRevert", "imported", "macroInputs", "macroSets", "played", "rollWindow",
    "profiles", "charProfiles", "characters", "charData", "sellStats", "bagPosition", "lootFeedPosition", "layoutLibrary"}
L.DataVersion = 2

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
    for key, repair in pairs(L.Structured) do out[key] = repair(raw[key]) end
    out.dataVersion = L.DataVersion
    return out
end

----------------------------------------------------------------------
-- Nested settings. Sanitize rebuilds the whole table, so each one has its own repair function:
-- a nested key that is not handled here would be lost on the next change.
----------------------------------------------------------------------
L.GeneralBar = "general"
L.MaxBars = 12

local function defaultBar(id, name, y)
    return {id = id, name = name, size = 36, grow = "RIGHT", countdown = true, x = false, y = y}
end

function L.DefaultBars()
    return {
        defaultBar(L.GeneralBar, NS.Text("Allgemeine Warnungen", "General warnings"), 260),
        defaultBar("combat", NS.Text("Kampfbuffs", "Combat buffs"), 210),
        defaultBar("consumables", NS.Text("Verbrauchsmaterial", "Consumables"), 160),
    }
end

local GROW = {RIGHT = true, LEFT = true, UP = true, DOWN = true}

local function repairBars(raw)
    local out, seen = {}, {}
    if type(raw) == "table" then
        for _, bar in ipairs(raw) do
            if type(bar) == "table" and type(bar.id) == "string" and bar.id ~= "" and not seen[bar.id] and #out < L.MaxBars then
                seen[bar.id] = true
                local size = tonumber(bar.size) or 36
                out[#out + 1] = {
                    id = bar.id,
                    name = type(bar.name) == "string" and bar.name ~= "" and L.TrimUTF8(bar.name, 40) or bar.id,
                    size = math.max(16, math.min(64, size)),
                    grow = GROW[bar.grow] and bar.grow or "RIGHT",
                    countdown = bar.countdown ~= false,
                    x = type(bar.x) == "number" and bar.x or false,
                    y = type(bar.y) == "number" and bar.y or 200,
                }
            end
        end
    end
    if #out == 0 then return L.DefaultBars() end
    -- The general bar takes the entries of deleted bars, so it always exists and comes first.
    if not seen[L.GeneralBar] then table.insert(out, 1, L.DefaultBars()[1]) end
    return out
end

local function repairReminders(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for key, row in pairs(raw) do
        if type(key) == "string" and type(row) == "table" then
            local entry = {}
            if type(row.on) == "boolean" then entry.on = row.on end
            if type(row.bar) == "string" then entry.bar = row.bar end
            local warn = tonumber(row.warn)
            if warn and warn == warn then entry.warn = math.max(0, math.min(3600, math.floor(warn))) end
            out[key] = entry
        end
    end
    return out
end

local function repairInfoBar(raw)
    raw = type(raw) == "table" and raw or {}
    local out = {order = {}, on = {}, x = false, y = false}
    if type(raw.order) == "table" then
        local seen = {}
        for _, key in ipairs(raw.order) do
            if type(key) == "string" and not seen[key] then seen[key] = true; out.order[#out.order + 1] = key end
        end
    end
    if type(raw.on) == "table" then
        for key, value in pairs(raw.on) do
            if type(key) == "string" and type(value) == "boolean" then out.on[key] = value end
        end
    end
    if type(raw.x) == "number" and type(raw.y) == "number" then out.x, out.y = raw.x, raw.y end
    return out
end

L.Structured = {warnBars = repairBars, reminders = repairReminders, infoBar = repairInfoBar}

-- The settings a named profile carries. Measurements and per-character data stay outside.
function L.ProfileSnapshot(db)
    local out = {}
    for key in pairs(L.Defaults) do out[key] = db[key] end
    for key in pairs(L.Structured) do out[key] = L.Copy(db[key]) end
    return out
end

function L.ApplySnapshot(db, snapshot)
    for key in pairs(L.Defaults) do db[key] = snapshot[key] end
    for key in pairs(L.Structured) do db[key] = L.Copy(snapshot[key]) end
    return L.Sanitize(db)
end

----------------------------------------------------------------------
-- Profile text. A small length-prefixed format that is read by a strict parser:
-- imported text is never executed.
----------------------------------------------------------------------
local PREFIX = "ZUP1"
local MAX_DEPTH, MAX_TEXT = 8, 200000

local function encode(value, parts, depth)
    local kind = type(value)
    if kind == "string" then
        parts[#parts + 1] = "s" .. #value .. ":" .. value
    elseif kind == "number" then
        parts[#parts + 1] = "n" .. string.format("%.14g", value) .. ";"
    elseif kind == "boolean" then
        parts[#parts + 1] = value and "T" or "F"
    elseif kind == "table" then
        if depth >= MAX_DEPTH then error("too deep") end
        local keys = {}
        for key in pairs(value) do
            local keyKind = type(key)
            if keyKind == "string" or keyKind == "number" then keys[#keys + 1] = key end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        parts[#parts + 1] = "{"
        for _, key in ipairs(keys) do
            encode(key, parts, depth + 1)
            encode(value[key], parts, depth + 1)
        end
        parts[#parts + 1] = "}"
    else
        error("unsupported")
    end
end

local function decode(text, position, depth)
    local head = text:sub(position, position)
    if head == "T" then return true, position + 1 end
    if head == "F" then return false, position + 1 end
    if head == "n" then
        local stop = text:find(";", position, true)
        local number = stop and tonumber(text:sub(position + 1, stop - 1))
        if not number or number ~= number or number == math.huge or number == -math.huge then error("number") end
        return number, stop + 1
    end
    if head == "s" then
        local stop = text:find(":", position, true)
        local length = stop and tonumber(text:sub(position + 1, stop - 1))
        if not length or length < 0 or stop + length > #text then error("string") end
        return text:sub(stop + 1, stop + length), stop + length + 1
    end
    if head == "{" then
        if depth >= MAX_DEPTH then error("too deep") end
        local out = {}
        position = position + 1
        while text:sub(position, position) ~= "}" do
            if position > #text then error("open table") end
            local key, value
            key, position = decode(text, position, depth + 1)
            if type(key) ~= "string" and type(key) ~= "number" then error("key") end
            value, position = decode(text, position, depth + 1)
            out[key] = value
        end
        return out, position + 1
    end
    error("token")
end

local function checksum(text)
    local a, b = 1, 0
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%04x%04x", b, a)
end

function L.ExportText(name, snapshot)
    local parts = {}
    encode({name = name, data = snapshot}, parts, 0)
    local body = table.concat(parts)
    return PREFIX .. ":" .. checksum(body) .. ":" .. body
end

-- Returns name, snapshot, or nil and a reason. Damaged text never yields a partial profile.
function L.ImportText(text)
    if type(text) ~= "string" or #text > MAX_TEXT then return nil, "format" end
    text = text:match("^%s*(.-)%s*$")
    local sum, body = text:match("^" .. PREFIX .. ":(%x%x%x%x%x%x%x%x):(.*)$")
    if not sum then return nil, "format" end
    if checksum(body) ~= sum:lower() then return nil, "damaged" end
    local ok, value, stop = pcall(decode, body, 1, 0)
    if not ok or stop ~= #body + 1 or type(value) ~= "table" or type(value.data) ~= "table" then return nil, "damaged" end
    local name = type(value.name) == "string" and value.name ~= "" and L.TrimUTF8(value.name, 40) or "Import"
    -- Only known settings get through, repaired like any saved value.
    return name, L.ProfileSnapshot(L.Sanitize(value.data))
end

----------------------------------------------------------------------
-- Pure helpers for the warning system, the purchase plan and the info bar.
----------------------------------------------------------------------
-- A short buff warns shortly before it ends, a long one earlier. An own value wins.
function L.WarnSeconds(duration, override)
    if type(override) == "number" and override > 0 then return override end
    duration = tonumber(duration) or 0
    if duration <= 0 then return 0 end
    if duration < 600 then return 10 end
    if duration <= 1800 then return 180 end
    return 300
end

-- "12", "4:05", "12m", "2h" for icons and tooltips.
function L.ShortTime(seconds)
    seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
    if seconds < 60 then return tostring(seconds) end
    if seconds < 600 then return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60) end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    return math.floor(seconds / 3600 + .5) .. "h"
end

-- What to buy from one merchant. `wanted` rows: {item, target}. `stock` by item:
-- {index, price, stack, available, hasCost}. Whole vendor stacks only. A row that would
-- pass the gold limit is left out and reported, never bought in part without saying so.
function L.PurchasePlan(wanted, stock, have, money, maxCost)
    local plan, total, skipped = {}, 0, {}
    for _, row in ipairs(wanted) do
        local offer = stock[row.item]
        local missing = (tonumber(row.target) or 0) - (tonumber(have[row.item]) or 0)
        if offer and not offer.hasCost and missing > 0 then
            local stack = math.max(1, offer.stack or 1)
            local stacks = math.ceil(missing / stack)
            if offer.available and offer.available >= 0 then stacks = math.min(stacks, offer.available) end
            local cost = stacks * (offer.price or 0)
            if stacks > 0 then
                local limit = money
                if maxCost and maxCost > 0 then limit = math.min(limit, maxCost) end
                if total + cost <= limit then
                    total = total + cost
                    plan[#plan + 1] = {item = row.item, index = offer.index, quantity = stacks * stack, stack = stack, cost = cost, name = offer.name, icon = offer.icon}
                else
                    skipped[#skipped + 1] = {item = row.item, cost = cost, name = offer.name}
                end
            end
        end
    end
    return plan, total, skipped
end

-- Quest colour band: grey below the client's trivial line, green up to three levels under the player.
function L.QuestBand(level, playerLevel, trivial)
    if trivial == true then return "gray" end
    level, playerLevel = tonumber(level), tonumber(playerLevel)
    if not level or not playerLevel or level <= 0 then return "unknown" end
    if playerLevel - level >= 3 then return "green" end
    return "normal"
end

function L.QuestBandAllowed(mode, band)
    if mode == "nogray" then return band ~= "gray" end
    if mode == "nogreen" then return band ~= "gray" and band ~= "green" end
    return true
end

-- XP per hour from a session sample; nil until there is something to measure.
function L.XPRate(gained, seconds)
    gained, seconds = tonumber(gained) or 0, tonumber(seconds) or 0
    if gained <= 0 or seconds < 30 then return nil end
    return gained / seconds * 3600
end

-- Gold across recorded characters. Scope: all, faction or current.
function L.GoldTotal(characters, scope, ownKey, ownFaction)
    local total = 0
    for key, row in pairs(characters or {}) do
        if scope == "all" or (scope == "faction" and row.faction == ownFaction) or (scope == "current" and key == ownKey) then
            total = total + (tonumber(row.money) or 0)
        end
    end
    return total
end

-- Lowest-value grey stack. Quest, locked and unknown-price items never qualify.
function L.CheapestGray(rows)
    local best
    for _, row in ipairs(rows) do
        if not row.locked and not row.quest and (row.value or 0) > 0 and (not best or row.value < best.value) then best = row end
    end
    return best
end

-- The usual skinning rule: the skill a corpse of this level needs.
function L.SkinningSkill(level)
    level = tonumber(level) or 0
    if level <= 0 then return nil end
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
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

-- Turns a localized client format such as "%s rolls %d (%d-%d)" into a match pattern.
-- Positional forms ("%1$s", "%2$d") are read too, so a translation may reorder its arguments:
-- `order[n]` names the format argument behind capture n.
local MAGIC = {["^"] = true, ["$"] = true, ["("] = true, [")"] = true, ["%"] = true, ["."] = true,
    ["["] = true, ["]"] = true, ["*"] = true, ["+"] = true, ["-"] = true, ["?"] = true}

function L.FormatPattern(template)
    if type(template) ~= "string" or template == "" then return nil end
    local parts, order, position, argument = {"^"}, {}, 1, 0
    while position <= #template do
        local char = template:sub(position, position)
        if char == "%" then
            local index, kind, stop = template:match("^(%d+)%$([sd])()", position + 1)
            if not index then kind, stop = template:match("^([sd])()", position + 1) end
            if kind then
                argument = argument + 1
                order[#order + 1] = tonumber(index) or argument
                parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
                position = stop
            else
                -- "%%" and anything unknown stay literal characters.
                parts[#parts + 1] = "%%"
                position = position + (template:sub(position + 1, position + 1) == "%" and 2 or 1)
            end
        else
            parts[#parts + 1] = MAGIC[char] and ("%" .. char) or char
            position = position + 1
        end
    end
    parts[#parts + 1] = "$"
    return {pattern = table.concat(parts), order = order}
end

-- Values in format argument order, or nil when the text does not fit.
function L.MatchFormat(text, format)
    if type(text) ~= "string" or type(format) ~= "table" then return nil end
    local captures = {text:match(format.pattern)}
    if #captures == 0 then return nil end
    local values = {}
    for index, argument in ipairs(format.order) do values[argument] = captures[index] end
    return values
end

-- The roll line comes from the client's own RANDOM_ROLL_RESULT, so every client language works.
function L.RollPattern(template) return L.FormatPattern(template) end

function L.ParseRoll(message, pattern)
    local values = L.MatchFormat(message, pattern)
    if not values then return nil end
    local name, roll, low, high = values[1], tonumber(values[2]), tonumber(values[3]), tonumber(values[4])
    if type(name) ~= "string" or name == "" or not roll or not low or not high then return nil end
    return {name = name, roll = roll, low = low, high = high}
end

-- A pause this long between rolls starts a new round.
L.RollRoundGap = 120

-- Adds a roll to the round. A player's first roll counts; a repeat is only counted, never replaces it.
-- Returns the stored row and whether it was new. The list stays sorted, earlier rolls first on a tie.
function L.AddRoll(rolls, row)
    for _, existing in ipairs(rolls) do
        if existing.name == row.name then
            existing.repeats = (existing.repeats or 0) + 1
            return existing, false
        end
    end
    rolls.sequence = (rolls.sequence or 0) + 1
    row.sequence = rolls.sequence
    rolls[#rolls + 1] = row
    table.sort(rolls, function(a, b)
        if a.roll ~= b.roll then return a.roll > b.roll end
        return a.sequence < b.sequence
    end)
    return row, true
end

-- The range of the round's first roll is the valid one. Winners are the highest rolls in that range;
-- several on a tie. Rolls in another range never win.
function L.RollWinners(rolls)
    local first
    for _, row in ipairs(rolls) do
        if not first or row.sequence < first.sequence then first = row end
    end
    if not first then return {}, nil end
    local winners, best = {}, nil
    for _, row in ipairs(rolls) do
        if row.low == first.low and row.high == first.high then
            if not best or row.roll > best then best, winners = row.roll, {row}
            elseif row.roll == best then winners[#winners + 1] = row end
        end
    end
    return winners, first
end

function L.RollValid(row, first)
    return first ~= nil and row.low == first.low and row.high == first.high
end

-- Own loot from a CHAT_MSG_LOOT line, read through the client's LOOT_ITEM_SELF(_MULTIPLE) texts.
-- The multiple form goes first: the single form would also match "[Item]x3".
-- Returns the item link and the amount, or nil for anything else (other players, money, crafting).
function L.ParseOwnLoot(message, multiple, single)
    local values = L.MatchFormat(message, multiple)
    local link, count = values and values[1], values and tonumber(values[2])
    if not (link and count) then
        values = L.MatchFormat(message, single)
        link, count = values and values[1], 1
    end
    if type(link) ~= "string" or not link:find("|Hitem:", 1, true) then return nil end
    return link, math.max(1, math.floor(count or 1))
end

function L.LinkItemID(link)
    return type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
end

-- Name and colour prefix from an item link: "|cff1eff00" or the newer "|cnIQ2:".
function L.LinkParts(link)
    if type(link) ~= "string" then return nil end
    local name = link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]")
    local prefix = link:match("^(|c%x%x%x%x%x%x%x%x)") or link:match("^(|cn[^:|]+:)")
    return name, prefix
end

-- Quality from the link colour when the item data is not cached yet.
function L.LinkQuality(link, colors)
    if type(link) ~= "string" then return nil end
    local quality = tonumber(link:match("^|cnIQ(%d+):"))
    if quality then return quality end
    local hex = link:match("^|c(%x%x%x%x%x%x%x%x)")
    if hex and type(colors) == "table" then
        for index, color in pairs(colors) do
            local value = type(color) == "table" and (color.hex or (color.GenerateHexColor and color:GenerateHexColor()))
            if type(value) == "string" and value:lower():gsub("^|c", "") == hex:lower() then return tonumber(index) end
        end
    end
    return nil
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
