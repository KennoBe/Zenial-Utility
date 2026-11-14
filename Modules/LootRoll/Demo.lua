local _, NS = ...
local D = {}
NS.LootRollDemo = D
local M, N, T, tr = NS.LootRollModel, NS.LootRollNative, NS.Theme, NS.Text

-- A preview of the loot roll window with invented rolls and players. It plays only with the model:
-- no RollOnLoot, no entry in the history, nothing is suppressed. It works with the module off.

-- Same numbering as Enum.EncounterLootDropRollState, so the demo needs no client enum.
local ENUM = {NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5}
local PLAYERS = {"Aldric", "Brynja Eisenfaust", "Corvin", "Dalia", "Ewan"}
local DURATION = 40

-- Demo ids are strings, so they never collide with the numeric ids of real rolls.
local IDS = {"demo-1", "demo-2", "demo-3"}

local function itemLink(id, name) return "|cff0070dd|Hitem:" .. id .. "::::::::1:::::::|h[" .. name .. "]|h|r" end

local function rollInfo(index, state, roll, winner)
    return {playerName = PLAYERS[index], playerGUID = "demo-" .. index, playerClass = ({"MAGE", "WARRIOR", "ROGUE", "PRIEST", "HUNTER"})[index],
        isSelf = false, state = state, roll = roll, isWinner = winner == true}
end

local function drop(infos, extra)
    local out = {lootListKey = 0, rollInfos = infos, isTied = false, allPassed = false}
    for key, value in pairs(extra or {}) do out[key] = value end
    return out
end

-- Seconds after the start -> what the group does. Results come through ApplyDropTo, like history data.
local function script()
    local N_, G, P, W = ENUM.NeedMainSpec, ENUM.Greed, ENUM.Pass, ENUM.NoRoll
    return {
        {1, IDS[1], drop({rollInfo(1, N_), rollInfo(2, G), rollInfo(3, P), rollInfo(4, W), rollInfo(5, W)})},
        {2, IDS[3], drop({rollInfo(1, N_), rollInfo(2, N_), rollInfo(3, G), rollInfo(4, P), rollInfo(5, P)})},
        {3, IDS[1], drop({rollInfo(1, N_, 87), rollInfo(2, G, 55), rollInfo(3, P), rollInfo(4, G, 12), rollInfo(5, P)},
            {currentLeader = rollInfo(1, N_, 87)})},
        {4, IDS[3], drop({rollInfo(1, N_, 64), rollInfo(2, N_, 64), rollInfo(3, G, 80), rollInfo(4, P), rollInfo(5, P)},
            {currentLeader = rollInfo(1, N_, 64), isTied = true})},
        {5, IDS[2], drop({rollInfo(1, P), rollInfo(2, P), rollInfo(3, P), rollInfo(4, P), rollInfo(5, P)}, {allPassed = true})},
        {7, IDS[1], drop({rollInfo(1, N_, 87, true), rollInfo(2, G, 55), rollInfo(3, P), rollInfo(4, G, 12), rollInfo(5, P)},
            {winner = rollInfo(1, N_, 87, true)})},
        {9, IDS[3], drop({rollInfo(1, N_, 64), rollInfo(2, N_, 91, true), rollInfo(3, G, 80), rollInfo(4, P), rollInfo(5, P)},
            {winner = rollInfo(2, N_, 91, true)})},
    }
end

-- True while the script runs or demo cards are still on screen.
function D.Running()
    if D.driver and D.driver:GetScript("OnUpdate") ~= nil then return true end
    for _, roll in pairs(NS.LootRoll.state.rolls) do
        if roll.demo then return true end
    end
    return false
end

function D.Stop()
    if D.driver then D.driver:SetScript("OnUpdate", nil) end
    D.steps = nil
    NS.LootRoll.RemoveDemo()
    NS.LootRoll.Update()
end

function D.Start()
    local R = NS.LootRoll
    D.Stop()
    local now = N.Now()
    local icon = T.assets.neutralIcon
    local ring = itemLink(25, tr("Demo-Ring", "Demo Ring"))
    local staff = itemLink(26, tr("Demo-Stab", "Demo Staff"))
    local function add(id, link, name, quality, offers, allowed)
        M.Add(R.state, id, {link = link, name = name, icon = icon, count = 1, quality = quality, bop = quality >= 3,
            duration = DURATION, timeLeft = DURATION, allowed = allowed, offers = offers, demo = true}, now)
    end
    local all = {[0] = true, [1] = true, [2] = true}
    -- Two identical items and a third, different one.
    add(IDS[1], ring, tr("Demo-Ring", "Demo Ring"), 3, {1, 2, 0}, all)
    add(IDS[2], ring, tr("Demo-Ring", "Demo Ring"), 3, {1, 2, 0}, all)
    add(IDS[3], staff, tr("Demo-Stab", "Demo Staff"), 4, {1, 2, 0}, all)
    D.steps, D.elapsed = script(), 0
    if not D.driver then D.driver = CreateFrame("Frame") end
    D.driver:SetScript("OnUpdate", function(_, dt)
        D.elapsed = D.elapsed + dt
        local steps = D.steps
        while steps and steps[1] and steps[1][1] <= D.elapsed do
            local step = table.remove(steps, 1)
            M.ApplyDropTo(R.state, step[2], step[3], ENUM, N.Now())
        end
        if steps and #steps == 0 then D.driver:SetScript("OnUpdate", nil) end
        R.Update()
    end)
    R.Update()
end
