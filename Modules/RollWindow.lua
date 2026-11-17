local _, NS = ...
local R = {rows = {}}
NS.RollWindow = R
local T, K, L, A, tr = NS.Theme, NS.Kit, NS.Logic, NS.Adapter, NS.Text

local WIDTH, ROW_HEIGHT, MAX_VISIBLE, CHROME = 250, 18, 10, 122

local function place(f)
    local saved = NS.App.db.rollWindow
    f:ClearAllPoints()
    if type(saved.x) == "number" and type(saved.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -280, -200)
    end
end

local function createRow(f, index)
    local row = CreateFrame("Frame", nil, f.content)
    row:SetSize(f.content:GetWidth(), ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row.name = T.Text(row, "", "GameFontHighlightSmall", "text")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetWidth(122)
    row.name:SetWordWrap(false)
    row.value = T.Text(row, "", "GameFontHighlightSmall", "gold")
    row.value:SetPoint("RIGHT", -4, 0)
    row.value:SetWidth(68)
    row.value:SetJustifyH("RIGHT")
    f.rows[index] = row
    return row
end

local function create()
    local f = CreateFrame("Frame", "ZenialUtilityRolls", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetWidth(WIDTH)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    -- Stored by the top edge, so the window grows downward with new rolls.
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        NS.App.db.rollWindow = {x = self:GetLeft(), y = self:GetTop()}
        place(self)
    end)
    T.Shell(f)
    f.rows = R.rows

    -- Shared dialog header: title band and close button.
    local title = K.Text(f, tr("Würfe", "Rolls"), "title")
    K.DialogHeader(f, title, function() f:Hide() end)
    f.start = T.Text(f, "", "GameFontHighlightSmall", "muted")
    f.start:SetPoint("LEFT", title, "LEFT", 70, 0)
    f.winner = T.Text(f, "", "GameFontHighlightSmall", "gold")
    f.winner:SetPoint("TOPLEFT", 14, -52)
    f.winner:SetWidth(WIDTH - 28)
    f.winner:SetWordWrap(false)

    local scroll, content = NS.Window.ScrollArea(f, WIDTH - 50)
    scroll:SetPoint("TOPLEFT", 14, -72)
    scroll:SetPoint("BOTTOMLEFT", 14, 46)
    f.scroll = scroll
    content:SetHeight(ROW_HEIGHT)
    f.content = content
    f.empty = T.Text(content, tr("Noch keine Würfe.", "No rolls yet."), "GameFontHighlightSmall", "muted")
    f.empty:SetPoint("TOPLEFT", 4, -3)

    local reset = T.Button(f, tr("Zurücksetzen", "Reset"), 110, 26, function() NS.Helpers.ClearRolls() end, "secondary")
    reset:SetPoint("BOTTOMLEFT", 12, 12)
    local announce = T.Button(f, tr("In den Chat", "To chat"), 110, 26, function()
        if not NS.Helpers.AnnounceRolls() then A.Print(tr("Dafür braucht es einen Wurf und eine Gruppe.", "This needs a roll and a group.")) end
    end, "secondary")
    announce:SetPoint("BOTTOMRIGHT", -12, 12)

    place(f)
    f:Hide()
    R.frame = f
end

local function winnerText(winners)
    if #winners == 0 then return "" end
    if #winners == 1 then return string.format(tr("Gewinner: %s (%d)", "Winner: %s (%d)"), winners[1].name, winners[1].roll) end
    local names = {}
    for _, row in ipairs(winners) do names[#names + 1] = row.name end
    return string.format(tr("Gleichstand (%d): %s", "Tie (%d): %s"), winners[1].roll, table.concat(names, ", "))
end

function R.Refresh()
    local f = R.frame
    if not f then return end
    local rolls, started = NS.Helpers.rolls, NS.Helpers.rollStart
    local winners, first = L.RollWinners(rolls)
    local won = {}
    for _, row in ipairs(winners) do won[row] = true end
    f.start:SetText(started and string.format(tr("Start %s", "Started %s"), started) or "")
    f.winner:SetText(winnerText(winners))
    f.empty:SetShown(#rolls == 0)
    for index, data in ipairs(rolls) do
        local row = f.rows[index] or createRow(f, index)
        row.name:SetText(index .. ". " .. data.name)
        row.value:SetText(data.roll .. L.RollRange(data))
        -- Gold for the winner, dimmed for a roll in another range: it cannot win.
        local color = won[data] and "gold" or (L.RollValid(data, first) and "text" or "muted")
        T.Tint(row.name, "SetTextColor", color)
        T.Tint(row.value, "SetTextColor", won[data] and "gold" or (color == "muted" and "muted" or "goldText"))
        row:Show()
    end
    for index = #rolls + 1, #f.rows do f.rows[index]:Hide() end
    f:SetHeight(CHROME + math.min(MAX_VISIBLE, math.max(1, #rolls)) * ROW_HEIGHT)
    f.content:SetHeight(math.max(1, #rolls) * ROW_HEIGHT)
    f.scroll:UpdateScrollChildRect()
    f.scroll:RefreshScrollbar()
end

-- show opens the window; without it an open window only follows the list.
function R.Update(show)
    if show and not R.frame then create() end
    if not R.frame then return end
    R.Refresh()
    if show then R.frame:Show() end
end

function R.SettingsChanged()
    local db = NS.App.db
    if R.frame and not (db.modExtras and db.rollTracker) then R.frame:Hide() end
end
