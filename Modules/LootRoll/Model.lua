local _, NS = ...
local M = {}
NS.LootRollModel = M
local L = NS.Logic

-- Pure logic of the loot roll window: no frames and no client calls. Everything that comes from the
-- client (time, item data, loot history drops, the roll state enum, global strings) is passed in.
--
-- The client gives no link between a roll id and a loot history drop. A drop is only matched to a
-- roll by the full item link and only when exactly one of each exists. In every other case the roll
-- shows no group data: a wrong winner would be worse than none.

M.ACTION = {PASS = 0, NEED = 1, GREED = 2, TRANSMOG = 4}
M.ClickGap = 0.5 -- seconds a click blocks the next one (double click)
M.ResultGrace = 20 -- seconds after the roll time until a roll without result ends as unknown
M.SessionMaxAge = 300 -- a snapshot older than this (seconds) is not restored after /reload
M.MatchTolerance = .5 -- how far (as a share of the roll time) a drop's age may differ from the roll's age

local KINDS = {NEED = true, GREED = true, TRANSMOG = true, PASS = true, WAITING = true, UNKNOWN = true}
local CHOICE_KINDS = {NEED = true, GREED = true, TRANSMOG = true, PASS = true}
local ACTION_KIND = {[0] = "PASS", [1] = "NEED", [2] = "GREED", [4] = "TRANSMOG"}
-- Who may overwrite the own choice: the loot history knows what the server saw.
local SOURCE_RANK = {history = 4, chat = 3, click = 2, auto = 2}

-- Accepts a RollOnLoot action or a kind string.
function M.ActionKind(action)
    if type(action) == "string" then return KINDS[action] and action or "UNKNOWN" end
    return ACTION_KIND[action] or "UNKNOWN"
end

local function ended(roll) return roll.status == "FINISHED" or roll.status == "CANCELLED" end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
-- `used` remembers every drop key that was ever matched, also after the roll is archived: an old,
-- decided drop of the same item must never be taken for a new roll.
function M.New()
    return {rolls = {}, order = {}, keys = {}, used = {}}
end

local function copyFlags(source)
    local out = {}
    if type(source) == "table" then
        for key, value in pairs(source) do out[key] = value end
    end
    return out
end

function M.Add(state, rollID, info, now)
    if rollID == nil then return nil end
    if state.rolls[rollID] then return state.rolls[rollID] end
    info = type(info) == "table" and info or {}
    local left = tonumber(info.timeLeft) or tonumber(info.duration) or 0
    local roll = {
        rollID = rollID, link = info.link, itemID = L.LinkItemID(info.link), name = info.name, icon = info.icon,
        count = info.count or 1, quality = info.quality, bop = info.bop == true,
        startedAt = now, endsAt = now + left, duration = tonumber(info.duration) or left,
        status = "PENDING", allowed = copyFlags(info.allowed), reasons = copyFlags(info.reasons), demo = info.demo == true,
        offers = type(info.offers) == "table" and {unpack(info.offers)} or {1, 2, 0},
        players = {}, isTied = false, allPassed = false,
    }
    state.rolls[rollID] = roll
    state.order[#state.order + 1] = rollID
    return roll
end

function M.Click(state, rollID, action, now)
    local roll = state.rolls[rollID]
    if not roll then return false, "unknown" end
    if roll.status ~= "PENDING" then return false, "closed" end
    -- A roll the game's own window shows belongs to that window.
    if roll.native then return false, "native" end
    if roll.allowed[action] ~= true then return false, "not allowed" end
    if roll.clickedAt and now - roll.clickedAt < M.ClickGap then return false, "too fast" end
    roll.pendingChoice, roll.clickedAt = action, now
    return true
end

function M.ClickFailed(state, rollID)
    local roll = state.rolls[rollID]
    if roll then roll.pendingChoice = nil end
end

-- `action` is a RollOnLoot action or a kind; the stored choice is always the kind.
function M.NoteOwnChoice(state, rollID, action, source)
    local roll = state.rolls[rollID]
    local kind = M.ActionKind(action)
    if not roll or kind == "UNKNOWN" then return false end
    local rank = SOURCE_RANK[source] or 1
    if roll.ownChoice and rank < (SOURCE_RANK[roll.ownSource] or 1) then return false end
    roll.ownChoice, roll.ownSource = kind, source
    return true
end

-- The client stops offering the roll as soon as the own choice is made; it does not mean the result
-- is known. The roll stays and waits for the group data.
local function stopActing(state, roll)
    if roll.status ~= "PENDING" then return end
    roll.status = "WAITING"
    if roll.pendingChoice and not roll.ownChoice then
        M.NoteOwnChoice(state, roll.rollID, roll.pendingChoice, "click")
    end
    roll.pendingChoice = nil
end

function M.NoLongerActionable(state, rollID, now)
    local roll = state.rolls[rollID]
    if roll then stopActing(state, roll) end
end

function M.CancelAll(state, now)
    for _, rollID in ipairs(state.order) do stopActing(state, state.rolls[rollID]) end
end

-- Returns the rolls to archive and removes them. Demo rolls come back flagged `demo`.
function M.Tick(state, now, resultTime)
    resultTime = tonumber(resultTime) or 0
    local removed, kept = {}, {}
    for _, rollID in ipairs(state.order) do
        local roll = state.rolls[rollID]
        if not ended(roll) and now > roll.endsAt + M.ResultGrace then
            roll.status, roll.finishedAt = "CANCELLED", now
        end
        if ended(roll) and (roll.finishedAt or now) + resultTime <= now then
            removed[#removed + 1] = roll
            state.rolls[rollID] = nil
            if roll.key and state.keys[roll.key] == rollID then state.keys[roll.key] = nil end
        else
            kept[#kept + 1] = rollID
        end
    end
    state.order = kept
    return removed
end

function M.Visible(state, now)
    local groups = {{}, {}, {}}
    for index, rollID in ipairs(state.order) do
        local roll = state.rolls[rollID]
        if roll then
            local group = roll.status == "PENDING" and 1 or roll.status == "WAITING" and 2 or 3
            groups[group][#groups[group] + 1] = {roll = roll, index = index}
        end
    end
    table.sort(groups[1], function(a, b)
        local left, other = math.max(0, a.roll.endsAt - now), math.max(0, b.roll.endsAt - now)
        if left ~= other then return left < other end
        return a.index < b.index
    end)
    local out = {}
    for _, group in ipairs(groups) do
        for _, item in ipairs(group) do out[#out + 1] = item.roll end
    end
    return out
end

-- Nothing is left out: what does not fit as a large card becomes a compact one.
function M.Layout(rolls, maxLarge)
    maxLarge = maxLarge or 3
    local large, compact = {}, {}
    for index, roll in ipairs(rolls) do
        if index <= maxLarge then large[#large + 1] = roll else compact[#compact + 1] = roll end
    end
    return large, compact
end

----------------------------------------------------------------------
-- Loot history
----------------------------------------------------------------------
function M.NormalizePlayer(info, enum)
    if type(info) ~= "table" or type(enum) ~= "table" then return nil end
    local state, kind, offSpec = info.state, "UNKNOWN", nil
    if state ~= nil then
        if state == enum.NeedMainSpec then kind = "NEED"
        elseif state == enum.NeedOffSpec then kind, offSpec = "NEED", true
        elseif state == enum.Transmog then kind = "TRANSMOG"
        elseif state == enum.Greed then kind = "GREED"
        elseif state == enum.Pass then kind = "PASS"
        elseif state == enum.NoRoll then kind = "WAITING" end
    end
    return {guid = info.playerGUID, name = info.playerName, class = info.playerClass, kind = kind, offSpec = offSpec,
        roll = info.roll, isWinner = info.isWinner == true, isSelf = info.isSelf == true}
end

local function finish(roll, now)
    roll.status = "FINISHED"
    roll.finishedAt = roll.finishedAt or now
end

local function updateFromDrop(state, roll, drop, enum, now)
    local players, winner = {}, M.NormalizePlayer(drop.winner, enum)
    for _, info in ipairs(drop.rollInfos or {}) do
        local player = M.NormalizePlayer(info, enum)
        if player then
            if winner and ((player.guid and player.guid == winner.guid) or (not player.guid and player.name == winner.name)) then
                player.isWinner = true
            end
            players[#players + 1] = player
        end
    end
    roll.players = players
    roll.leader = M.NormalizePlayer(drop.currentLeader, enum)
    roll.isTied = drop.isTied == true
    roll.winner = winner
    roll.allPassed = drop.allPassed == true
    roll.source = "history"
    for _, player in ipairs(players) do
        if player.isSelf and CHOICE_KINDS[player.kind] then
            M.NoteOwnChoice(state, roll.rollID, player.kind, "history")
        end
    end
    if winner or roll.allPassed then finish(roll, now) end
end

local function dropKey(encounterID, lootListKey)
    return tostring(encounterID) .. ":" .. tostring(lootListKey)
end

-- Direct use for rolls that never get a key (the demo). No matching, no key.
function M.ApplyDropTo(state, rollID, drop, enum, now)
    local roll = state.rolls[rollID]
    if not roll or type(drop) ~= "table" or type(enum) ~= "table" then return false end
    updateFromDrop(state, roll, drop, enum, now)
    return true
end

-- Blizzard compares GetLootHistoryTime() - startTime with duration; the unit is not documented,
-- so ages are compared as shares of the roll time instead of seconds.
local function fractions(roll, drop, now, historyNow)
    if type(historyNow) ~= "number" or type(drop.startTime) ~= "number" or type(drop.duration) ~= "number"
        or drop.duration <= 0 or type(roll.duration) ~= "number" or roll.duration <= 0 then
        return nil
    end
    return (historyNow - drop.startTime) / drop.duration, (now - roll.startedAt) / roll.duration
end

local function plausible(roll, drop, now, historyNow)
    local dropShare, rollShare = fractions(roll, drop, now, historyNow)
    return dropShare == nil or math.abs(dropShare - rollShare) <= M.MatchTolerance
end

function M.ApplyDrops(state, encounterID, drops, enum, now, historyNow)
    if type(drops) ~= "table" or type(enum) ~= "table" then return end
    state.used = state.used or {}
    local byLink, links = {}, {}
    for _, drop in ipairs(drops) do
        if type(drop) == "table" and drop.lootListKey ~= nil then
            local key = dropKey(encounterID, drop.lootListKey)
            local roll = state.rolls[state.keys[key]]
            if roll then
                updateFromDrop(state, roll, drop, enum, now)
            elseif not state.used[key] and type(drop.itemHyperlink) == "string" then
                if not byLink[drop.itemHyperlink] then
                    byLink[drop.itemHyperlink] = {}
                    links[#links + 1] = drop.itemHyperlink
                end
                local list = byLink[drop.itemHyperlink]
                list[#list + 1] = drop
            end
        end
    end
    for _, link in ipairs(links) do
        local candidates = {}
        for _, rollID in ipairs(state.order) do
            local roll = state.rolls[rollID]
            if roll.link == link and not roll.key and not roll.demo then candidates[#candidates + 1] = roll end
        end
        if #candidates == 1 then
            local roll, fit = candidates[1], {}
            for _, drop in ipairs(byLink[link]) do
                if plausible(roll, drop, now, historyNow) then fit[#fit + 1] = drop end
            end
            if #fit == 1 then
                local drop = fit[1]
                roll.key, roll.encounterID, roll.lootListKey = dropKey(encounterID, drop.lootListKey), encounterID, drop.lootListKey
                state.keys[roll.key], state.used[roll.key] = roll.rollID, true
                roll.match = "unique"
                roll.dropShare, roll.rollShare = fractions(roll, drop, now, historyNow)
                updateFromDrop(state, roll, drop, enum, now)
            elseif #fit > 1 then
                roll.match = "ambiguous"
            end
        elseif #candidates > 1 then
            -- Several identical rolls: any drop that could belong to one of them makes it unclear.
            for _, drop in ipairs(byLink[link]) do
                local any = false
                for _, roll in ipairs(candidates) do any = any or plausible(roll, drop, now, historyNow) end
                if any then
                    for _, roll in ipairs(candidates) do roll.match = "ambiguous" end
                    break
                end
            end
        end
    end
end

-- Keeps what was taken over; only the link between roll and drop is dropped.
function M.ClearHistoryKeys(state)
    state.keys, state.used = {}, {}
    for _, roll in pairs(state.rolls) do roll.key, roll.encounterID, roll.lootListKey = nil, nil, nil end
end

----------------------------------------------------------------------
-- Chat fallback (second choice: the lines carry no drop key)
----------------------------------------------------------------------
-- Order matters: the general "%s passed on: %s" would also swallow "You passed on: ..." and
-- "Everyone passed on: ...", so the specific texts come first.
local CHAT_FORMATS = {
    {"LOOT_ROLL_ALL_PASSED", "allPassed"},
    {"LOOT_ROLL_PASSED_SELF_AUTO", "choice", "PASS", true}, {"LOOT_ROLL_PASSED_AUTO", "choice", "PASS"},
    {"LOOT_ROLL_PASSED_SELF", "choice", "PASS", true}, {"LOOT_ROLL_PASSED", "choice", "PASS"},
    {"LOOT_ROLL_NEED_SELF", "choice", "NEED", true}, {"LOOT_ROLL_NEED", "choice", "NEED"},
    {"LOOT_ROLL_GREED_SELF", "choice", "GREED", true}, {"LOOT_ROLL_GREED", "choice", "GREED"},
    {"LOOT_ROLL_TRANSMOG_SELF", "choice", "TRANSMOG", true}, {"LOOT_ROLL_TRANSMOG", "choice", "TRANSMOG"},
    {"LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "rolled", "NEED"}, {"LOOT_ROLL_ROLLED_NEED", "rolled", "NEED"},
    {"LOOT_ROLL_ROLLED_GREED", "rolled", "GREED"}, {"LOOT_ROLL_ROLLED_TRANSMOG", "rolled", "TRANSMOG"},
    {"LOOT_ROLL_YOU_WON", "won", nil, true}, {"LOOT_ROLL_WON", "won"},
}

M.CHAT_KEYS = {}
for _, spec in ipairs(CHAT_FORMATS) do M.CHAT_KEYS[#M.CHAT_KEYS + 1] = spec[1] end

-- "d" or "s" per format argument, so a number is never taken for a name.
local function argumentKinds(template)
    local kinds, position, count = {}, 1, 0
    while position <= #template do
        local at = template:find("%", position, true)
        if not at then break end
        local index, kind, stop = template:match("^(%d+)%$([sd])()", at + 1)
        if not index then kind, stop = template:match("^([sd])()", at + 1) end
        if kind then
            count = count + 1
            kinds[tonumber(index) or count] = kind
            position = stop
        else
            position = at + (template:sub(at + 1, at + 1) == "%" and 2 or 1)
        end
    end
    return kinds
end

function M.ChatPatterns(strings)
    local out = {}
    if type(strings) ~= "table" then return out end
    for _, spec in ipairs(CHAT_FORMATS) do
        local template = strings[spec[1]]
        local format = L.FormatPattern(template)
        if format then
            out[#out + 1] = {id = spec[1], type = spec[2], kind = spec[3], self = spec[4] == true, format = format,
                kinds = argumentKinds(template)}
        end
    end
    return out
end

-- "|HlootHistory:233239809|h[Loot]|h: text" -> "text", 233239809
function M.StripHistoryLink(message)
    if type(message) ~= "string" then return nil end
    local id, text = message:match("^|HlootHistory:(%d+)|h.-|h:?%s*(.*)$")
    if not id then return message end
    return text, tonumber(id)
end

local function isLink(text)
    return text:find("|Hitem:", 1, true) ~= nil and (text:sub(-2) == "|r" or text:sub(-2) == "|h")
end

function M.ParseChat(message, patterns)
    local text, encounterID = M.StripHistoryLink(message)
    if type(text) ~= "string" or type(patterns) ~= "table" then return nil end
    for _, pattern in ipairs(patterns) do
        local values = L.MatchFormat(text, pattern.format)
        if values then
            local event = {type = pattern.type, kind = pattern.kind, encounterID = encounterID}
            local valid = true
            for argument, value in pairs(values) do
                if pattern.kinds[argument] == "d" then
                    event.roll = tonumber(value)
                elseif isLink(value) then
                    event.link = value
                elseif value:find("|H", 1, true) then
                    valid = false
                else
                    event.name = value
                end
            end
            -- A text that only fits by swallowing more of the line (name or link wrong) is no match.
            if valid and event.link and (pattern.self or event.name or pattern.type == "allPassed") then
                if pattern.self then event.name = nil end
                return event
            end
        end
    end
    return nil
end

local function unassigned(state, link)
    local found = {}
    for _, rollID in ipairs(state.order) do
        local roll = state.rolls[rollID]
        if roll.link == link and not roll.demo and not roll.key and roll.source ~= "history" then
            found[#found + 1] = roll
        end
    end
    return found
end

local function findPlayer(roll, name, isSelf)
    for _, player in ipairs(roll.players) do
        if (isSelf and player.isSelf) or (name and player.name == name) then return player end
    end
    local player = {name = name, kind = "WAITING", isWinner = false, isSelf = isSelf}
    roll.players[#roll.players + 1] = player
    return player
end

function M.ApplyChat(state, event, ownName, now)
    if type(event) ~= "table" or type(event.link) ~= "string" then return false end
    local candidates = unassigned(state, event.link)
    if #candidates == 0 then return false end
    if #candidates > 1 then
        for _, roll in ipairs(candidates) do roll.match = "ambiguous" end
        return false
    end
    local roll = candidates[1]
    if roll.match == "ambiguous" then return false end
    roll.match, roll.source = "unique", "chat"
    local name = event.name
    local isSelf = name == nil or (ownName ~= nil and name == ownName)
    if name == nil then name = ownName end
    if event.type == "allPassed" then
        roll.allPassed = true
        finish(roll, now)
        return true
    end
    local player = findPlayer(roll, name, isSelf)
    if event.type == "choice" then
        player.kind = event.kind
        if isSelf then M.NoteOwnChoice(state, roll.rollID, event.kind, "chat") end
    elseif event.type == "rolled" then
        player.kind, player.roll = event.kind, event.roll
    elseif event.type == "won" then
        for _, other in ipairs(roll.players) do other.isWinner = false end
        player.isWinner = true
        roll.winner = player
        finish(roll, now)
    end
    return true
end

----------------------------------------------------------------------
-- Local history per character
----------------------------------------------------------------------
local function brief(player)
    return {name = player.name, class = player.class, kind = player.kind, roll = player.roll}
end

function M.Entry(roll, when)
    local entry = {t = when, link = roll.link, count = roll.count or 1, own = roll.ownChoice, result = "unknown",
        selfWon = false, players = {}, source = roll.source}
    if roll.status == "FINISHED" and roll.match ~= "ambiguous" then
        if roll.winner then
            entry.result, entry.winner, entry.selfWon = "won", brief(roll.winner), roll.winner.isSelf == true
        elseif roll.allPassed then
            entry.result = "allPassed"
        end
        for _, player in ipairs(roll.players) do
            local row = brief(player)
            row.win = player.isWinner == true
            entry.players[#entry.players + 1] = row
        end
    end
    return entry
end

function M.Push(list, entry, limit)
    table.insert(list, 1, entry)
    limit = tonumber(limit) or #list
    while #list > limit do list[#list] = nil end
    return list
end

function M.Filter(list, filter)
    local out = {}
    for _, entry in ipairs(list) do
        local winnerKind = entry.result == "won" and entry.winner and entry.winner.kind
        if filter == "won" then
            if entry.selfWon then out[#out + 1] = entry end
        elseif filter == "need" then
            if winnerKind == "NEED" then out[#out + 1] = entry end
        elseif filter == "greed" then
            if winnerKind == "GREED" then out[#out + 1] = entry end
        else
            out[#out + 1] = entry
        end
    end
    return out
end

local function cleanPlayer(raw, withWin)
    if type(raw) ~= "table" then return nil end
    local out = {name = type(raw.name) == "string" and raw.name or nil, class = type(raw.class) == "string" and raw.class or nil,
        kind = KINDS[raw.kind] and raw.kind or nil, roll = type(raw.roll) == "number" and raw.roll or nil}
    if withWin then out.win = raw.win == true end
    return out
end

function M.RepairHistory(raw, limit)
    local out = {}
    if type(raw) ~= "table" then return out end
    limit = tonumber(limit) or 100
    for _, item in ipairs(raw) do
        if #out >= limit then break end
        if type(item) == "table" and type(item.link) == "string" then
            local entry = {t = type(item.t) == "number" and item.t or 0,
                link = item.link, count = type(item.count) == "number" and math.max(1, math.floor(item.count)) or 1,
                own = KINDS[item.own] and item.own or nil,
                result = (item.result == "won" or item.result == "allPassed") and item.result or "unknown",
                selfWon = item.selfWon == true, players = {}, source = (item.source == "history" or item.source == "chat") and item.source or nil}
            entry.winner = entry.result == "won" and cleanPlayer(item.winner) or nil
            if entry.result == "won" and not entry.winner then entry.result, entry.selfWon = "unknown", false end
            for _, player in ipairs(type(item.players) == "table" and item.players or {}) do
                local row = cleanPlayer(player, true)
                if row then entry.players[#entry.players + 1] = row end
            end
            out[#out + 1] = entry
        end
    end
    return out
end

----------------------------------------------------------------------
-- /reload
----------------------------------------------------------------------
-- `now` (optional) stores the remaining time instead of the absolute GetTime value, which does not
-- survive a client restart.
function M.Snapshot(state, when, now)
    local rolls = {}
    for _, rollID in ipairs(state.order) do
        local roll = state.rolls[rollID]
        if roll and not roll.demo then
            local copy = L.Copy(roll)
            copy.pendingChoice, copy.clickedAt = nil, nil
            if now then copy.endsAtLeft, copy.startedAgo = roll.endsAt - now, now - roll.startedAt end
            rolls[#rolls + 1] = copy
        end
    end
    return {t = when, rolls = rolls}
end

function M.Restore(snapshot, activeIDs, now, when)
    local state = M.New()
    if type(snapshot) ~= "table" or type(snapshot.t) ~= "number" or type(when) ~= "number"
        or when - snapshot.t > M.SessionMaxAge or when < snapshot.t or type(snapshot.rolls) ~= "table" then
        return state
    end
    activeIDs = type(activeIDs) == "table" and activeIDs or {}
    for _, saved in ipairs(snapshot.rolls) do
        if type(saved) == "table" and saved.rollID ~= nil and not state.rolls[saved.rollID] then
            local roll = L.Copy(saved)
            if roll.endsAtLeft then
                roll.endsAt, roll.startedAt = now + roll.endsAtLeft, now - (roll.startedAgo or 0)
                roll.endsAtLeft, roll.startedAgo = nil, nil
            end
            roll.pendingChoice, roll.clickedAt = nil, nil
            roll.players = type(roll.players) == "table" and roll.players or {}
            roll.allowed = type(roll.allowed) == "table" and roll.allowed or {}
            roll.reasons = type(roll.reasons) == "table" and roll.reasons or {}
            if ended(roll) then
                roll.finishedAt = now
            else
                roll.status = activeIDs[roll.rollID] and "PENDING" or "WAITING"
            end
            state.rolls[roll.rollID] = roll
            state.order[#state.order + 1] = roll.rollID
            if roll.key then state.keys[roll.key], state.used[roll.key] = roll.rollID, true end
        end
    end
    return state
end
