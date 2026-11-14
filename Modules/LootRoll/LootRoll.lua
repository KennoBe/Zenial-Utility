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
local function removeWhere(test)
    local doomed = {}
    for _, rollID in ipairs(R.state.order) do
        local roll = R.state.rolls[rollID]
        if roll and test(roll) then doomed[#doomed + 1] = roll end
    end
    for _, roll in ipairs(doomed) do M.Remove(R.state, roll.rollID) end
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
    local active = N.ActiveSet()
    for rollID in pairs(active) do
        if not R.state.rolls[rollID] then
            local info = N.Read(rollID)
            if info then M.Add(R.state, rollID, info, now) end
        end
    end
    -- The game opens its own windows for the rolls still open after a load, at most four at a time;
    -- the rest waits in a queue. If it shows any, all open rolls are its.
    local shown = false
    for rollID in pairs(active) do
        if N.NativeShows(rollID) then shown = true; break end
    end
    if shown then
        for rollID in pairs(active) do
            local roll = R.state.rolls[rollID]
            if roll and not roll.demo then roll.native = true end
        end
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
        M.NoteAutoChoice(R.state, rollID, action, N.Now())
        R.Update()
    else
        R.autoPending[rollID] = action
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local function started(rollID, rollTime, lootHandle)
    if not R.active or N.Gamepad() then return end
    if not A.Public(rollID) or type(rollID) ~= "number" then
        N.ShowNative(rollID, rollTime)
        notice("badid", tr("Ein Wurf hatte keine lesbare Kennung und läuft im Blizzard-Fenster.", "A roll had no readable id and runs in the Blizzard window."))
        return
    end
    local info = N.Read(rollID, rollTime)
    local old = R.state.rolls[rollID]
    -- The same event twice: nothing to do.
    if old and info and old.status == "PENDING" and old.link == info.link then return end
    if not info then
        N.ShowNative(rollID, rollTime)
        notice("unreadable", tr("Ein Wurf war nicht lesbar und läuft im Blizzard-Fenster.", "A roll could not be read and runs in the Blizzard window."))
        return
    end
    -- The client reused the id: the old roll is over, archive it before the new one takes its place.
    if old then
        if not old.demo then archive(old) end
        M.Remove(R.state, rollID)
    end
    local roll = M.Add(R.state, rollID, info, N.Now())
    roll.lootHandle = lootHandle
    roll.rollTimeMs = type(rollTime) == "number" and rollTime or nil
    local auto = R.autoPending[rollID]
    R.autoPending[rollID] = nil
    if auto then M.NoteAutoChoice(R.state, rollID, auto, N.Now()) end
    R.Update()
end

local function cancelled(rollID)
    if not A.Public(rollID) then return end
    local roll = R.state.rolls[rollID]
    M.NoLongerActionable(R.state, rollID, N.Now())
    -- The native window would close its question here; without it the dialog would stay. Only the
    -- question of this very roll, and only for a roll of ours.
    if roll and not roll.native and N.ConfirmVisible(rollID) then N.HideConfirm(rollID) end
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
-- "off" | "active" | "gamepad" | "conflict:<name>" | "unsupported" | "reload"
-- "reload": the game's own window was switched off earlier in this session and stays off until /reload,
-- so the module stays in charge although it is switched off.
function R.Status()
    local ok, why = N.CanReplace()
    if wanted() then return ok and "active" or why end
    if N.suppressed then return "reload" end
    return "off"
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
    local wantedNow = wanted()
    local active = wantedNow and N.CanReplace() and N.Suppress()
    -- Once the game's window is switched off, this module stays in charge until /reload.
    if not active and N.suppressed then active = true end
    if active then
        R.active = true
        listener():Set(true)
        if not wantedNow then
            notice("reload", tr("Loot-Würfe: Das Blizzard-Fenster kommt nach /reload zurück. Bis dahin bleibt das Zenial-Fenster zuständig.",
                "Loot rolls: the Blizzard window returns after /reload. Until then the Zenial window stays in charge."))
        end
    else
        R.active = false
        if R.listener then R.listener:Set(false) end
        -- Real rolls leave with the module; a running demo stays.
        removeWhere(function(roll) return not roll.demo end)
        if wantedNow then
            local status = R.Status()
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
