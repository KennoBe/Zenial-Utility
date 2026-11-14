local _, NS = ...
local K = {marks = {}, overlays = {}, book = {}, bookDirty = true}
NS.ActionRanks = K
local A, L, tr, D = NS.Adapter, NS.Logic, NS.Text, NS.BuffData

-- Marks action buttons that still hold a lower rank of a spell than the highest one learned.
-- It only reads: bars, macros and buttons are never changed. The mark is a small own frame in the
-- free top-left corner, so full-button glows of other addons stay visible next to it.
local MAX_SLOT, DELAY = 180, .15
-- Blizzard's bar buttons. Skins such as ZENIAL UI keep these frames; buttons of other bar addons are not read.
local BARS = {"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button"}

local function db() return NS.App.db end

function K.Enabled()
    local data = db()
    return data ~= nil and data.modQoL == true and data.rankCheck == true
end

-- Slots belong to one character, so their exceptions sit in its own data, not in a profile.
function K.IgnoredSlots()
    local data = NS.Characters.Data()
    data.rankSlots = L.RepairIdSet(data.rankSlots)
    return data.rankSlots
end

function K.IgnoreSpell(spell, on)
    if type(spell) ~= "number" then return end
    db().rankIgnore[spell] = on and true or nil
end

function K.IgnoreSlot(slot, on)
    if type(slot) ~= "number" then return end
    K.IgnoredSlots()[slot] = on and true or nil
end

----------------------------------------------------------------------
-- Rank lookup
----------------------------------------------------------------------
-- The buff catalog lists rank chains by ID. Those answer first, through the same check as the warning bars.
local function chainIndex()
    if K.chains then return K.chains end
    K.chains = {}
    for _, entry in ipairs(D.classes[A.PlayerClass()] or {}) do
        for _, chain in ipairs(entry.ranks or {}) do
            if #chain > 1 then
                for index, spell in ipairs(chain) do K.chains[spell] = {chain = chain, index = index} end
            end
        end
    end
    return K.chains
end

local function subtextRank(spell)
    local api = _G.C_Spell
    return api and L.RankNumber(A.Call(api.GetSpellSubtext, spell)) or nil
end

-- Known spells of the spell book grouped by the client's own spell name, which every rank shares.
-- The name only groups; which rank is higher comes from the rank number.
local function readBook()
    local book, out, byID = _G.C_SpellBook, {}, {}
    if not book or type(book.GetSpellBookItemInfo) ~= "function" then return out, byID end
    local enum = _G.Enum
    local bank = enum and enum.SpellBookSpellBank and enum.SpellBookSpellBank.Player or 0
    local spellType = enum and enum.SpellBookItemType and enum.SpellBookItemType.Spell
    for line = 1, tonumber(A.Call(book.GetNumSpellBookSkillLines)) or 0 do
        local info = A.Call(book.GetSpellBookSkillLineInfo, line)
        local offset = type(info) == "table" and tonumber(info.itemIndexOffset)
        local count = type(info) == "table" and tonumber(info.numSpellBookItems)
        if offset and count then
            for index = offset + 1, offset + count do
                local item = A.Call(book.GetSpellBookItemInfo, index, bank)
                local spell = type(item) == "table" and tonumber(item.spellID)
                local known = spell and (spellType == nil or item.itemType == spellType) and A.Call(IsPlayerSpell, spell) == true
                if known and not item.isPassive then
                    local name = A.SpellName(spell)
                    local row = {spell = spell, rank = L.RankNumber(item.subName) or subtextRank(spell)}
                    if name then
                        out[name] = out[name] or {}
                        table.insert(out[name], row)
                    end
                    byID[spell] = row
                end
            end
        end
    end
    return out, byID
end

-- Current rank and best learned rank of a spell, or nil when the spell is the best one.
local function verdict(spell)
    local link = chainIndex()[spell]
    if link then
        local learned = NS.Reminders.LearnedRankIndex(link.chain)
        if learned and learned > link.index then
            return {spell = spell, rank = link.index}, {spell = link.chain[learned], rank = learned}
        end
        return nil
    end
    local name = A.SpellName(spell)
    local rows = name and K.book[name]
    if not rows then return nil end
    local current = K.bookByID[spell] or {spell = spell, rank = subtextRank(spell)}
    local best = L.BestRank(rows)
    if L.RankBetter(best, current) then return current, best end
    return nil
end
K.Verdict = verdict

----------------------------------------------------------------------
-- Scan and marks
----------------------------------------------------------------------
function K.Scan()
    K.pending = false
    local previous = K.marks
    K.marks = {}
    if K.Enabled() then
        if K.bookDirty or not K.bookByID then
            K.book, K.bookByID = readBook()
            K.bookDirty = false
        end
        local spells, slots, seen = db().rankIgnore, K.IgnoredSlots(), {}
        for slot = 1, MAX_SLOT do
            local kind, id = A.Call(GetActionInfo, slot)
            -- Macros stay out: a rank written into a macro is the player's choice.
            if kind == "spell" and type(id) == "number" then
                if seen[id] == nil then
                    local current, best = verdict(id)
                    seen[id] = best and {rank = current.rank, best = best.spell, bestRank = best.rank} or false
                end
                local found = seen[id]
                if found then
                    K.marks[slot] = {slot = slot, spell = id, rank = found.rank, best = found.best, bestRank = found.bestRank,
                        ignored = spells[id] == true or slots[slot] == true}
                end
            end
        end
        if K.learned then
            K.learned = false
            local fresh = 0
            for slot, mark in pairs(K.marks) do
                local old = previous[slot]
                if not mark.ignored and not (old and old.spell == mark.spell and old.bestRank == mark.bestRank) then fresh = fresh + 1 end
            end
            if fresh > 0 and db().rankNotify then
                A.Print(string.format(tr("Neuer Rang erlernt: %d Aktionsbutton(s) nutzen noch einen älteren Rang.",
                    "New rank learned: %d action button(s) still use an older rank."), fresh))
            end
        end
    end
    K.Render()
    if NS.SettingsUI and NS.SettingsUI.RefreshData then NS.SettingsUI.RefreshData() end
end

function K.Request(book)
    if book then K.bookDirty = true end
    if K.pending then return end
    K.pending = true
    -- A short one-shot timer gathers bursts of events and lets the bar buttons take their new slot first.
    local timer = _G.C_Timer
    if timer and type(timer.After) == "function" then timer.After(DELAY, K.Scan) else K.Scan() end
end

function K.Text(mark)
    return string.format(tr("Veralteter Rang: Rang %d – verfügbar: Rang %d", "Outdated rank: Rank %d – available: Rank %d"),
        mark.rank or 0, mark.bestRank or 0)
end

local function buttonSlot(button)
    local slot = button.action
    if not A.Public(slot) then return nil end
    return tonumber(slot)
end

local function createOverlay(button)
    local frame = CreateFrame("Frame", nil, button)
    frame:SetSize(10, 10)
    frame:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    frame:SetFrameLevel((tonumber(button:GetFrameLevel()) or 0) + 2)
    frame:EnableMouse(false)
    local edge = frame:CreateTexture(nil, "OVERLAY")
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, .8)
    local dot = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    dot:SetPoint("TOPLEFT", 1, -1)
    dot:SetPoint("BOTTOMRIGHT", -1, 1)
    dot:SetColorTexture(1, .55, .1, .95)
    frame:Hide()
    K.overlays[button] = frame
    return frame
end

-- Marks are own, unprotected frames. New ones are only made outside combat; in combat the
-- existing ones follow bar changes and the rest waits for the end of combat.
function K.Render()
    local on, combat = K.Enabled(), A.Combat()
    K.afterCombat = false
    for _, prefix in ipairs(BARS) do
        for index = 1, 12 do
            local button = _G[prefix .. index]
            if button then
                local mark = on and K.marks[buttonSlot(button)]
                local show = mark and not mark.ignored or false
                local overlay = K.overlays[button]
                if show and not overlay then
                    if combat then K.afterCombat = true else overlay = createOverlay(button) end
                end
                if overlay then overlay:SetShown(show) end
            end
        end
    end
end

local function onTooltip(tooltip, slot)
    if not K.Enabled() or not A.Public(slot) then return end
    local mark = K.marks[tonumber(slot)]
    if not mark or mark.ignored then return end
    tooltip:AddLine(K.Text(mark), 1, .6, .2, true)
    tooltip:Show()
end

local function hookTooltip()
    if K.hooked or not GameTooltip or type(hooksecurefunc) ~= "function" then return end
    K.hooked = true
    hooksecurefunc(GameTooltip, "SetAction", onTooltip)
end

local function render() if not K.pending then K.Render() end end

local listener = A.Listener({
    PLAYER_ENTERING_WORLD = function() K.Request(true) end,
    SPELLS_CHANGED = function() K.Request(true) end,
    LEARNED_SPELL_IN_TAB = function() K.learned = true; K.Request(true) end,
    LEARNED_SPELL_IN_SKILL_LINE = function() K.learned = true; K.Request(true) end,
    ACTIONBAR_SLOT_CHANGED = function() K.Request() end,
    ACTIONBAR_PAGE_CHANGED = function() K.Request() end,
    UPDATE_BONUS_ACTIONBAR = function() K.Request() end,
    PLAYER_REGEN_ENABLED = function() if K.afterCombat then render() end end,
})

function K.SettingsChanged()
    local on = K.Enabled()
    listener:Set(on)
    if on then hookTooltip() end
    if on and not K.wasOn then K.bookDirty = true end
    K.wasOn = on
    K.Request()
end
