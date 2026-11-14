local _, NS = ...
local R = {state = nil, autoPending = {}, notices = {}, accum = 0}
NS.LootRoll = R
local A, M, N, tr = NS.Adapter, NS.LootRollModel, NS.LootRollNative, NS.Text

-- Optional window for group loot rolls instead of the game's own roll frames. The window sends
-- RollOnLoot only from a click on a card button of a real roll. Timers, events, restoring after
-- /reload and the demo never send a choice.

R.state = M.New()

local function db() return NS.App.db end
local function cards() return NS.LootRollCards end

local function wanted()
    local data = db()
    return data ~= nil and data.modQoL == true and data.lootRoll == true
end

-- One note per topic and session: a chat line per roll would only be noise.
local function notice(key, text)
    if R.notices[key] then return end
    R.notices[key] = true
    A.Print(text)
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local function remove(roll)
    local state = R.state
    state.rolls[roll.rollID] = nil
    if roll.key and state.keys[roll.key] == roll.rollID then state.keys[roll.key] = nil end
    for index, rollID in ipairs(state.order) do
        if rollID == roll.rollID then table.remove(state.order, index); break end
    end
end

local function removeWhere(test)
    local doomed = {}
    for _, rollID in ipairs(R.state.order) do
        local roll = R.state.rolls[rollID]
        if roll and test(roll) then doomed[#doomed + 1] = roll end
    end
    for _, roll in ipairs(doomed) do remove(roll) end
end

function R.RemoveDemo() removeWhere(function(roll) return roll.demo end) end

local function data() return NS.Characters.Data("lootRoll") end

local function archive(roll)
    local store = data()
    store.history = M.RepairHistory(store.history, db().lootRollHistorySize)
    M.Push(store.history, M.Entry(roll, N.ServerTime()), db().lootRollHistorySize)
    if NS.LootRollHistory then NS.LootRollHistory.Refresh() end
end

----------------------------------------------------------------------
-- Tick: runs only while a roll exists
----------------------------------------------------------------------
local function afterWorld()
    local store = data()
    local now, serverTime = N.Now(), N.ServerTime()
    if not R.restored then
        R.restored = true
        local back = M.Restore(store.session, N.ActiveSet(), now, serverTime)
        store.session = nil
        for _, rollID in ipairs(back.order) do
            if not R.state.rolls[rollID] then
                local roll = back.rolls[rollID]
                R.state.rolls[rollID] = roll
                R.state.order[#R.state.order + 1] = rollID
                if roll.key then R.state.keys[roll.key], R.state.used[roll.key] = rollID, true end
            end
        end
        store.history = M.RepairHistory(store.history, db().lootRollHistorySize)
    end
    -- The game opens its own windows for rolls still open after a load; those rolls are its.
    for rollID in pairs(N.ActiveSet()) do
        if not R.state.rolls[rollID] then
            local info = N.Read(rollID)
            if info then M.Add(R.state, rollID, info, now) end
        end
    end
    for _, rollID in ipairs(R.state.order) do
        local roll = R.state.rolls[rollID]
        if not roll.demo and N.NativeShows(rollID) then roll.native = true end
    end
end

local function tick(_, elapsed)
    R.accum = R.accum + elapsed
    if R.deferred then
        R.deferred = false
        if R.active then afterWorld() end
    elseif R.accum < .1 then
        return
    end
    R.accum = 0
    local removed = M.Tick(R.state, N.Now(), db().lootRollResultTime)
    for _, roll in ipairs(removed) do
        if not roll.demo then archive(roll) end
    end
    R.Update()
    if #R.state.order == 0 and not R.deferred then R.driver:SetScript("OnUpdate", nil) end
end

function R.Wake()
    if not R.driver then R.driver = CreateFrame("Frame") end
    R.driver:SetScript("OnUpdate", tick)
end

-- Cards follow the state; the tick keeps running while a roll exists.
function R.Update()
    local ui = cards()
    if ui then ui.Refresh() end
    if #R.state.order > 0 or R.deferred then R.Wake() end
end

----------------------------------------------------------------------
-- Choosing
----------------------------------------------------------------------
-- The native window for exactly this roll: used when the roll cannot be read or sent.
local function handOver(roll, why)
    roll.native = true
    N.ShowNative(roll.rollID, roll.rollTimeMs or math.floor((roll.duration or 0) * 1000))
    if not roll.reported then
        roll.reported = true
        A.Print(why)
    end
end

-- Called from a click on a card button and nowhere else.
function R.Choose(rollID, action)
    local state, roll = R.state, R.state.rolls[rollID]
    if not roll then return false end
    local now = N.Now()
    if roll.demo then
        -- The demo only plays with the model; nothing goes to the client.
        if M.Click(state, rollID, action, now) then M.NoLongerActionable(state, rollID, now) end
        R.Update()
        return false
    end
    local ok, reason = M.Click(state, rollID, action, now)
    if not ok then return false, reason end
    if not N.Roll(rollID, action) then
        M.ClickFailed(state, rollID)
        handOver(roll, tr("Die Wahl konnte nicht gesendet werden. Der Wurf läuft im Blizzard-Fenster weiter.",
            "The choice could not be sent. The roll continues in the Blizzard window."))
    end
    R.Update()
    return true
end

-- Greed on green from Comfort: the choice is made without a click, the card only shows it.
-- The two START_LOOT_ROLL handlers run in either order.
function R.AutoChoice(rollID, action)
    if not R.active then return end
    if R.state.rolls[rollID] then
        M.NoteOwnChoice(R.state, rollID, action, "auto")
        R.Update()
    else
        R.autoPending[rollID] = action
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local function started(rollID, rollTime, lootHandle)
    if not R.active or N.Gamepad() or type(rollID) ~= "number" or not A.Public(rollID) then return end
    if R.state.rolls[rollID] then return end
    local info = N.Read(rollID, rollTime)
    if not info then
        N.ShowNative(rollID, rollTime)
        notice("unreadable", tr("Ein Wurf war nicht lesbar und läuft im Blizzard-Fenster.", "A roll could not be read and runs in the Blizzard window."))
        return
    end
    local roll = M.Add(R.state, rollID, info, N.Now())
    roll.lootHandle = lootHandle
    roll.rollTimeMs = type(rollTime) == "number" and rollTime or nil
    local auto = R.autoPending[rollID]
    R.autoPending[rollID] = nil
    if auto then M.NoteOwnChoice(R.state, rollID, auto, "auto") end
    R.Update()
end

local function cancelled(rollID)
    if not A.Public(rollID) then return end
    M.NoLongerActionable(R.state, rollID, N.Now())
    -- The native window would close its question here; without it the dialog would stay.
    N.HideConfirm(rollID)
    R.Update()
end

local function cancelledAll()
    M.CancelAll(R.state, N.Now())
    R.Update()
end

local function historyChanged(encounterID)
    if not A.Public(encounterID) or #R.state.order == 0 then return end
    M.ApplyDrops(R.state, encounterID, N.Drops(encounterID), N.Enum(), N.Now(), N.HistoryNow())
    R.Update()
end

local function historyCleared()
    M.ClearHistoryKeys(R.state)
end

local function chatLine(message)
    if type(message) ~= "string" or not A.Public(message) or #R.state.order == 0 then return end
    R.patterns = R.patterns or M.ChatPatterns(N.Strings())
    local event = M.ParseChat(message, R.patterns)
    if event and M.ApplyChat(R.state, event, N.OwnName(), N.Now()) then R.Update() end
end

local function enteringWorld()
    R.autoPending = {}
    R.deferred = true
    R.Wake()
end

local function loggingOut()
    local store = data()
    local snapshot = M.Snapshot(R.state, N.ServerTime(), N.Now())
    store.session = #snapshot.rolls > 0 and snapshot or nil
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
-- "off" | "active" | "gamepad" | "conflict:<name>" | "unsupported"
function R.Status()
    if not wanted() then return "off" end
    local ok, why = N.CanReplace()
    if ok then return "active" end
    return why
end

-- Created on first use: a module that is off has no frame and no registered event.
local function listener()
    if not R.listener then
        R.listener = A.Listener({
            START_LOOT_ROLL = started, CANCEL_LOOT_ROLL = cancelled, CANCEL_ALL_LOOT_ROLLS = cancelledAll,
            LOOT_HISTORY_UPDATE_DROP = historyChanged, LOOT_HISTORY_UPDATE_ENCOUNTER = historyChanged,
            LOOT_HISTORY_CLEAR_HISTORY = historyCleared, CHAT_MSG_LOOT = chatLine,
            PLAYER_ENTERING_WORLD = enteringWorld, PLAYER_LOGOUT = loggingOut,
        })
    end
    return R.listener
end

function R.SettingsChanged()
    if not db() then return end
    local status = R.Status()
    local active = status == "active" and N.Suppress(true)
    if active then
        R.active = true
        listener():Set(true)
    else
        local wasSuppressed = N.suppressed == true
        R.active = false
        if R.listener then R.listener:Set(false) end
        if wasSuppressed then
            N.Suppress(false)
            notice("off", tr("Loot-Würfe: Das Blizzard-Fenster ist wieder zuständig. Ein /reload stellt den Originalzustand vollständig her.",
                "Loot rolls: the Blizzard window is in charge again. A /reload fully restores the original state."))
        end
        -- An open roll would be without a window until its time runs out: the game's own window takes it.
        local now = N.Now()
        for _, rollID in ipairs(R.state.order) do
            local roll = R.state.rolls[rollID]
            if not roll.demo and roll.status == "PENDING" and not roll.native then
                local left = N.TimeLeft(rollID) or math.max(0, roll.endsAt - now)
                N.ShowNative(rollID, math.floor(left * 1000))
            end
        end
        -- Real rolls leave with the module; a running demo stays.
        removeWhere(function(roll) return not roll.demo end)
        if wanted() then
            if status == "unsupported" then
                notice("unsupported", tr("Loot-Würfe: Dieser Client bietet die nötigen Schnittstellen nicht. Das Blizzard-Fenster bleibt zuständig.",
                    "Loot rolls: this client lacks the needed interfaces. The Blizzard window stays in charge."))
            elseif status:find("^conflict:") then
                notice("conflict", tr("Loot-Würfe: ", "Loot rolls: ") .. status:sub(10) ..
                    tr(" ist geladen. Das Blizzard-Fenster bleibt zuständig.", " is loaded. The Blizzard window stays in charge."))
            end
        end
    end
    local ui = cards()
    if ui then ui.SettingsChanged() end
    R.Update()
end

----------------------------------------------------------------------
-- For the settings page and diagnostics (used in step 3)
----------------------------------------------------------------------
function R.History()
    return data().history or {}
end

function R.ClearHistory()
    data().history = {}
    if NS.LootRollHistory then NS.LootRollHistory.Refresh() end
end

local function share(value) return value and string.format("%.2f", value) or "?" end

function R.Dump()
    local lines = {}
    for _, rollID in ipairs(R.state.order) do
        local roll = R.state.rolls[rollID]
        lines[#lines + 1] = string.format("roll %s handle %s %s match %s key %s own %s/%s native %s shares drop %s roll %s",
            tostring(rollID), tostring(roll.lootHandle), roll.status, tostring(roll.match), tostring(roll.key),
            tostring(roll.ownChoice), tostring(roll.ownSource), tostring(roll.native == true), share(roll.dropShare), share(roll.rollShare))
    end
    return lines
end
