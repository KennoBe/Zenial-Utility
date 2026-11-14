local _, NS = ...
local B = {frames = {}, moving = false, preview = false}
NS.WarnBars = B
local A, L, T, tr, W = NS.Adapter, NS.Logic, NS.Theme, NS.Text, NS.Widgets

local GAP = 4
local STATE_COLOR = {missing = "danger", expiring = "gold", rank = "accentBlue", group = "online"}

local function db() return NS.App.db end

-- Icons, the name and the gaps all move the whole bar while move mode is on.
local function dragStart(self)
    local bar = self.bar or self
    if B.moving then bar:StartMoving() end
end
local function dragStop(self)
    local bar = self.bar or self
    if not B.moving then return end
    bar:StopMovingOrSizing()
    if bar.SavePosition then bar:SavePosition() end
end

local function iconFrame(bar)
    local icon = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate" or nil)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", 2, -2)
    icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.texture:SetTexCoord(.08, .92, .08, .92)
    icon.edge = {}
    for index, point in ipairs({{"TOPLEFT", "TOPRIGHT"}, {"BOTTOMLEFT", "BOTTOMRIGHT"}, {"TOPLEFT", "BOTTOMLEFT"}, {"TOPRIGHT", "BOTTOMRIGHT"}}) do
        local line = icon:CreateTexture(nil, "OVERLAY")
        line:SetPoint(point[1])
        line:SetPoint(point[2])
        if index <= 2 then line:SetHeight(2) else line:SetWidth(2) end
        icon.edge[index] = line
    end
    icon.time = T.Text(icon, "", "NumberFontNormal", "text")
    icon.time:SetPoint("CENTER", 0, 0)
    icon.time:SetJustifyH("CENTER")
    icon.count = T.Text(icon, "", "NumberFontNormalSmall", "text")
    icon.count:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.count:SetJustifyH("RIGHT")
    icon:EnableMouse(true)
    icon.bar = bar
    icon:RegisterForDrag("LeftButton")
    icon:SetScript("OnDragStart", dragStart)
    icon:SetScript("OnDragStop", dragStop)
    icon:SetScript("OnEnter", function(self)
        local tip, item = _G.GameTooltip, self.item
        if not tip or not tip.SetOwner or not item then return end
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:SetText(item.title or "")
        local text = (item.state == "missing" and tr("Fehlt", "Missing"))
            or (item.state == "expiring" and tr("Läuft bald aus", "Expiring soon"))
            or (item.state == "rank" and tr("Höherer Rang verfügbar", "Higher rank available"))
            or tr("Fehlt Gruppenmitgliedern", "Missing on group members")
        tip:AddLine(text, 1, 1, 1, true)
        if item.count then tip:AddLine(string.format(tr("%d Gruppenmitglieder in Reichweite ohne diesen Buff", "%d group members in range without this buff"), item.count), 1, 1, 1, true) end
        tip:Show()
    end)
    icon:SetScript("OnLeave", function()
        if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
    end)
    return icon
end

local function savePosition(frame, id)
    for _, bar in ipairs(db().warnBars) do
        if bar.id == id then
            bar.x, bar.y = frame:GetLeft(), frame:GetBottom()
            NS.Profiles.Store()
            return
        end
    end
end

local function barFrame(id)
    local frame = B.frames[id]
    if frame then return frame end
    frame = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame.icons = {}
    frame.id = id
    function frame:SavePosition() savePosition(self, self.id) end
    frame:SetScript("OnDragStart", dragStart)
    frame:SetScript("OnDragStop", dragStop)
    frame.label = T.Text(frame, "", "GameFontHighlightSmall", "gold")
    frame.label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    -- The name above the bar is a handle of its own in move mode.
    frame.handle = CreateFrame("Frame", nil, frame)
    frame.handle.bar = frame
    frame.handle:SetPoint("TOPLEFT", frame.label, "TOPLEFT", -2, 2)
    frame.handle:SetPoint("BOTTOMRIGHT", frame.label, "BOTTOMRIGHT", 2, -2)
    frame.handle:RegisterForDrag("LeftButton")
    frame.handle:SetScript("OnDragStart", dragStart)
    frame.handle:SetScript("OnDragStop", dragStop)
    frame.handle:EnableMouse(false)
    B.frames[id] = frame
    return frame
end

-- Lines wrap by themselves at the screen edge, whatever the direction.
function B.PerLine(spec, screen)
    local step = spec.size + GAP
    local room
    local x = spec.x or (screen.width / 2)
    local y = spec.y or screen.height / 2
    if spec.grow == "RIGHT" then room = screen.width - x
    elseif spec.grow == "LEFT" then room = x + spec.size
    elseif spec.grow == "UP" then room = screen.height - y
    else room = y + spec.size end
    return math.max(1, math.floor(room / step))
end

local function place(frame, spec)
    frame:ClearAllPoints()
    if spec.x then frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", spec.x, spec.y)
    else frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, spec.y) end
end

local function drawIcon(icon, item, spec, now)
    icon.item = item
    icon:SetSize(spec.size, spec.size)
    icon.texture:SetTexture(item.icon)
    if icon.texture.SetDesaturated then icon.texture:SetDesaturated(item.state == "missing") end
    for _, line in ipairs(icon.edge) do T.Tint(line, "SetColorTexture", STATE_COLOR[item.state] or "gold") end
    local text = item.text or ""
    if spec.countdown and item.left and text == "" then
        local left = item.expires and item.expires - now or item.left
        text = L.ShortTime(left)
    end
    icon.time:SetText(text)
    icon.count:SetText(item.count and tostring(item.count) or "")
    icon:Show()
end

local function layout(frame, spec, items)
    local screen = {width = UIParent:GetWidth(), height = UIParent:GetHeight()}
    local perLine = B.PerLine(spec, screen)
    local step = spec.size + GAP
    local now = tonumber(A.Call(GetTime)) or 0
    local columns, rows = 0, 0
    for index, item in ipairs(items) do
        local icon = frame.icons[index]
        if not icon then
            icon = iconFrame(frame)
            frame.icons[index] = icon
        end
        drawIcon(icon, item, spec, now)
        local along, across = (index - 1) % perLine, math.floor((index - 1) / perLine)
        icon:ClearAllPoints()
        if spec.grow == "RIGHT" then icon:SetPoint("BOTTOMLEFT", along * step, across * step)
        elseif spec.grow == "LEFT" then icon:SetPoint("BOTTOMRIGHT", -along * step, across * step)
        elseif spec.grow == "UP" then icon:SetPoint("BOTTOMLEFT", across * step, along * step)
        else icon:SetPoint("TOPLEFT", across * step, -along * step) end
        if along + 1 > columns then columns = along + 1 end
        if across + 1 > rows then rows = across + 1 end
    end
    for index = #items + 1, #frame.icons do frame.icons[index]:Hide() end
    columns, rows = math.max(columns, 1), math.max(rows, 1)
    local horizontal = spec.grow == "RIGHT" or spec.grow == "LEFT"
    frame:SetSize((horizontal and columns or rows) * step, (horizontal and rows or columns) * step)
end

local function sampleItems(spec)
    return {
        {key = "s1", title = tr("Beispiel: fehlt", "Sample: missing"), icon = "Interface\\Icons\\Spell_Holy_WordFortitude", state = "missing", bar = spec.id},
        {key = "s2", title = tr("Beispiel: läuft aus", "Sample: expiring"), icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", state = "expiring", left = 42, bar = spec.id},
        {key = "s3", title = tr("Beispiel: höherer Rang", "Sample: higher rank"), icon = "Interface\\Icons\\Spell_Nature_Regeneration", state = "rank", bar = spec.id},
        {key = "s4", title = tr("Beispiel: Gruppe", "Sample: group"), icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", state = "group", count = 3, bar = spec.id},
    }
end

-- Shows the given items on their bars; a bar without anything stays out of the way.
function B.Render(items)
    local data = db()
    local used = {}
    B.last = items
    local on = data.modBuffs == true or B.preview or B.moving
    if on then
        local byBar = {}
        for _, item in ipairs(items or {}) do
            byBar[item.bar] = byBar[item.bar] or {}
            table.insert(byBar[item.bar], item)
        end
        for _, spec in ipairs(data.warnBars) do
            used[spec.id] = true
            local list = B.preview and sampleItems(spec) or byBar[spec.id] or {}
            local frame = barFrame(spec.id)
            place(frame, spec)
            layout(frame, spec, list)
            frame:EnableMouse(B.moving)
            frame.handle:EnableMouse(B.moving)
            frame.label:SetText(spec.name)
            frame.label:SetShown(B.moving or B.preview)
            if B.moving then T.Panel(frame, "inset") elseif frame.SetBackdrop then frame:SetBackdrop(nil) end
            frame:SetShown(#list > 0 or B.moving)
        end
    end
    for id, frame in pairs(B.frames) do
        if not used[id] then frame:Hide() end
    end
end

function B.SetMoving(on)
    B.moving = on == true
    B.Render(B.last or {})
end

function B.SetPreview(on)
    B.preview = on == true
    B.Render(B.last or {})
end
