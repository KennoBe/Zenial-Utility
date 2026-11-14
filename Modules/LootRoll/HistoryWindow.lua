local _, NS = ...
local H = {filter = "all", rows = {}}
NS.LootRollHistory = H
local T, W, A, L, M, tr = NS.Theme, NS.Widgets, NS.Adapter, NS.Logic, NS.LootRollModel, NS.Text

-- The finished rolls of this character, newest first. The window only reads the history and sends
-- nothing: no roll choice, no chat line. A shift click puts the item link into the chat input.

local WIDTH, HEIGHT, ROW_HEIGHT = 580, 440, 22
local CONFIRM_SECONDS = 4
local FILTERS = {
    {"all", {"Alle", "All"}}, {"won", {"Gewonnen", "Won"}}, {"need", {"Bedarf", "Need"}}, {"greed", {"Gier", "Greed"}},
}

local function kindLabel(kind)
    local cards = NS.LootRollCards
    return cards and cards.KindLabel(kind) or tostring(kind or "?")
end

local function place(f)
    local saved = NS.Characters.Data("lootRoll").window
    f:ClearAllPoints()
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

local function itemText(entry)
    local name, prefix = L.LinkParts(entry.link)
    local text = (prefix or "") .. "[" .. (name or "?") .. "]" .. (prefix and "|r" or "")
    if (entry.count or 1) > 1 then text = text .. " x" .. entry.count end
    return text
end

local function resultText(entry)
    if entry.result == "won" and entry.winner then
        local winner = entry.winner
        local text = tr("Gewinner: ", "Winner: ") .. (winner.name or "?") .. " (" .. kindLabel(winner.kind)
        if winner.roll then text = text .. " " .. winner.roll end
        return text .. ")", entry.selfWon and "online" or "text"
    elseif entry.result == "allPassed" then
        return tr("Alle haben gepasst", "Everyone passed"), "muted"
    end
    return tr("Ergebnis unbekannt", "Result unknown"), "muted"
end

local function timeText(entry)
    local text = entry.t and entry.t > 0 and A.Call(_G.date, tr("%d.%m. %H:%M", "%m/%d %H:%M"), entry.t)
    return type(text) == "string" and text or ""
end

local function showTip(row)
    local entry, tip = row.entry, _G.GameTooltip
    if not entry or not tip or not tip.SetOwner then return end
    tip:SetOwner(row, "ANCHOR_RIGHT")
    if not (tip.SetHyperlink and pcall(tip.SetHyperlink, tip, entry.link)) then tip:SetText(itemText(entry)) end
    if #entry.players > 0 then
        tip:AddLine(" ")
        for _, player in ipairs(entry.players) do
            local line = (player.name or "?") .. "  " .. kindLabel(player.kind) .. (player.roll and (" " .. player.roll) or "")
            if player.win then tip:AddLine(line, 1, .82, 0) else tip:AddLine(line, 1, 1, 1) end
        end
    end
    tip:Show()
end

local function createRow(f, index)
    local row = CreateFrame("Button", nil, f.content)
    row:SetSize(f.content:GetWidth(), ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row.when = T.Text(row, "", "GameFontHighlightSmall", "muted")
    row.when:SetPoint("LEFT", 4, 0); row.when:SetWidth(70)
    row.item = T.Text(row, "", "GameFontHighlightSmall", "text")
    row.item:SetPoint("LEFT", 78, 0); row.item:SetWidth(170); row.item:SetWordWrap(false)
    row.own = T.Text(row, "", "GameFontHighlightSmall", "dim")
    row.own:SetPoint("LEFT", 252, 0); row.own:SetWidth(64); row.own:SetWordWrap(false)
    row.result = T.Text(row, "", "GameFontHighlightSmall", "text")
    row.result:SetPoint("LEFT", 320, 0); row.result:SetWidth(WIDTH - 14 - 36 - 320 - 4); row.result:SetWordWrap(false)
    row:SetScript("OnEnter", showTip)
    row:SetScript("OnLeave", function()
        local tip = _G.GameTooltip
        if tip and tip.Hide then tip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
        if self.entry and A.Shift() then A.Call(_G.HandleModifiedItemClick, self.entry.link) end
    end)
    f.rows[index] = row
    return row
end

local function create()
    local f = CreateFrame("Frame", "ZenialUtilityLootRollHistory", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.GetLeft and self.GetTop then
            NS.Characters.Data("lootRoll").window = {x = self:GetLeft(), y = self:GetTop()}
            place(self)
        end
    end)
    T.Panel(f, "surface")
    f.rows = H.rows

    f.title = T.Text(f, "", "GameFontNormal", "gold")
    f.title:SetPoint("TOPLEFT", 14, -14)
    f.title:SetWidth(WIDTH - 60)
    f.title:SetWordWrap(false)
    local close = W.CloseButton(f, function() f:Hide() end)
    close:SetSize(26, 26)

    f.filters = {}
    for index, spec in ipairs(FILTERS) do
        local button = T.Button(f, NS.SettingsControls.Pick(spec[2]), 100, 24, function()
            H.filter = spec[1]
            H.Refresh()
        end, "secondary")
        button:SetPoint("TOPLEFT", 14 + (index - 1) * 106, -42)
        button.filter = spec[1]
        f.filters[index] = button
    end

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 14, -76)
    scroll:SetPoint("BOTTOMRIGHT", -36, 50)
    f.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 50, ROW_HEIGHT)
    scroll:SetScrollChild(content)
    f.content = content
    W.ScrollBar(scroll, ROW_HEIGHT * 3)
    f.empty = T.Text(content, "", "GameFontHighlightSmall", "muted")
    f.empty:SetPoint("TOPLEFT", 4, -4)
    f.empty:SetWidth(WIDTH - 60)

    f.clear = T.Button(f, tr("Verlauf löschen", "Clear history"), 170, 26, function() H.Clear() end, "danger")
    f.clear:SetPoint("BOTTOMLEFT", 12, 12)
    f.count = T.Text(f, "", "GameFontHighlightSmall", "muted")
    f.count:SetPoint("BOTTOMRIGHT", -16, 18)
    f.count:SetJustifyH("RIGHT")
    f.count:SetWidth(240)

    place(f)
    f:SetScript("OnHide", function() H.Disarm() end)
    if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, "ZenialUtilityLootRollHistory") end
    f:Hide()
    H.frame = f
end

function H.Refresh()
    local f = H.frame
    if not f or not f:IsShown() then return end
    local name = A.Call(_G.UnitName, "player")
    f.title:SetText(tr("Loot-Würfe: Verlauf", "Loot rolls: history") .. (type(name) == "string" and (" - " .. name) or ""))
    for _, button in ipairs(f.filters) do T.StyleButton(button, button.filter == H.filter and "primary" or "secondary") end
    local all = NS.LootRoll.History()
    local list = M.Filter(all, H.filter)
    f.empty:SetText(#all == 0 and tr("Noch keine Würfe im Verlauf.", "No rolls in the history yet.")
        or tr("Keine Einträge für diesen Filter.", "No entries for this filter."))
    f.empty:SetShown(#list == 0)
    for index, entry in ipairs(list) do
        local row = f.rows[index] or createRow(f, index)
        row.entry = entry
        row.when:SetText(timeText(entry))
        row.item:SetText(itemText(entry))
        row.own:SetText(entry.own and (tr("Du: ", "You: ") .. kindLabel(entry.own)) or "")
        local text, key = resultText(entry)
        row.result:SetText(text)
        T.Tint(row.result, "SetTextColor", key)
        row:Show()
    end
    for index = #list + 1, #f.rows do f.rows[index].entry = nil; f.rows[index]:Hide() end
    f.count:SetText(string.format("%d / %d", #list, #all))
    f.content:SetHeight(math.max(1, #list) * ROW_HEIGHT)
    f.scroll:UpdateScrollChildRect()
    if f.scroll.RefreshScrollbar then f.scroll:RefreshScrollbar() end
end

----------------------------------------------------------------------
-- Clearing needs a second click within a few seconds.
----------------------------------------------------------------------
function H.Disarm()
    H.armedUntil = nil
    local f = H.frame
    if f then
        f.clear:SetText(tr("Verlauf löschen", "Clear history"))
        f.clear:SetScript("OnUpdate", nil)
    end
end

function H.Clear()
    local f = H.frame
    if not f then return false end
    local now = NS.LootRollNative.Now()
    if H.armedUntil and now <= H.armedUntil then
        H.Disarm()
        NS.LootRoll.ClearHistory()
        return true
    end
    H.armedUntil = now + CONFIRM_SECONDS
    f.clear:SetText(tr("Wirklich löschen?", "Really clear?"))
    f.clear:SetScript("OnUpdate", function()
        if H.armedUntil and NS.LootRollNative.Now() > H.armedUntil then H.Disarm() end
    end)
    return false
end

function H.Show()
    if not H.frame then create() end
    H.frame:Show()
    H.Refresh()
end

function H.Toggle()
    if H.frame and H.frame:IsShown() then H.frame:Hide() else H.Show() end
end
