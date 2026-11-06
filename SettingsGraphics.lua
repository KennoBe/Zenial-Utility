local _, NS = ...
local U = NS.SettingsUI
local T, tr, A, W, G = NS.Theme, NS.Text, NS.Adapter, NS.Widgets, NS.Graphics

local COST = {
    [0] = {tr("Kaum FPS-Kosten", "Hardly any FPS cost"), "online"},
    [1] = {tr("Geringe FPS-Kosten", "Low FPS cost"), "goldText"},
    [2] = {tr("Mittlere FPS-Kosten", "Medium FPS cost"), "goldDim"},
    [3] = {tr("Hohe FPS-Kosten", "High FPS cost"), "dangerText"},
}

local function db() return NS.App.db end

local function shown(value)
    local number = tonumber(value)
    if not number then return tostring(value) end
    local text = number == math.floor(number) and tostring(math.floor(number)) or string.format("%.2f", number):gsub("0$", "")
    if NS.IsGerman() then text = text:gsub("%.", ",") end
    return text
end

local function buildRow(v, content, row, y)
    local frame = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetHeight(54)
    frame:SetPoint("TOPLEFT", 0, y)
    frame:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    W.Tooltip(frame, row.title, row.hint .. "\n\n" .. row.name)
    local title = T.Text(frame, row.title, "GameFontHighlight", "text")
    title:SetPoint("TOPLEFT", 4, -6)
    title:SetWidth(250)
    local cost = T.Text(frame, COST[row.cost][1], "GameFontHighlightSmall", "muted")
    T.Tint(cost, "SetTextColor", COST[row.cost][2])
    cost:SetPoint("TOPLEFT", 4, -24)
    cost:SetWidth(250)
    local value = T.Text(frame, "", "GameFontHighlightSmall", "muted")
    value:SetPoint("TOPLEFT", 4, -38)
    value:SetWidth(280)
    local reset = T.Button(frame, tr("Standard", "Default"), 78, 24, function()
        local ok, changed = G.ResetOne(db(), row.name)
        if not ok then v:SetMessage(tr("Im Kampf nicht möglich.", "Not possible in combat.")) end
        if changed then v:SetMessage("") end
        U.Refresh()
    end, "secondary")
    reset:SetPoint("TOPRIGHT", -2, -8)
    W.Tooltip(reset, tr("Spielstandard", "Game default"), tr("Setzt nur diese Einstellung auf den Standardwert des Spiels zurück.", "Resets only this setting to the game's default value."))

    local updating = false
    local control
    if row.kind == "toggle" then
        control = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        control:SetSize(24, 24)
        control:SetPoint("TOPRIGHT", -92, -8)
        T.StyleCheckbox(control)
        control:SetScript("OnClick", function(self)
            G.Stage(row.name, self:GetChecked() and 1 or 0)
            U.Refresh()
        end)
    else
        control = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
        control:SetSize(170, 16)
        control:SetPoint("TOPRIGHT", -92, -12)
        control:SetMinMaxValues(row.minimum, row.maximum)
        control:SetValueStep(row.step)
        if control.SetObeyStepOnDrag then control:SetObeyStepOnDrag(true) end
        if control.Low then control.Low:SetText(shown(row.minimum)) end
        if control.High then control.High:SetText(shown(row.maximum)) end
        control:SetScript("OnValueChanged", function(_, raw)
            if updating then return end
            local rounded = math.floor(raw / row.step + .5) * row.step
            G.Stage(row.name, rounded)
            U.Refresh()
        end)
    end
    v:AddUpdate(function()
        local current, pending = G.Current(row.name), G.pending[row.name]
        local active = pending or current
        updating = true
        if row.kind == "toggle" then
            control:SetChecked(tonumber(active) == 1)
        else
            control:SetValue(math.max(row.minimum, math.min(row.maximum, tonumber(active) or row.minimum)))
        end
        updating = false
        local caption = string.format(tr("Aktuell %s  ·  Standard %s", "Current %s  ·  default %s"), shown(current), shown(G.Default(row.name) or "–"))
        if pending then caption = caption .. "  ·  |cff" .. T.PaletteHex("gold") .. tr("neu ", "new ") .. shown(pending) .. "|r" end
        value:SetText(caption)
        reset:SetEnabled(not A.Combat())
    end)
    return frame
end

function U.fixed.graphics(v, page)
    local intro = CreateFrame("Frame", nil, page)
    intro:SetPoint("TOPLEFT", 0, 0)
    intro:SetPoint("TOPRIGHT", 0, 0)
    intro:SetHeight(76)
    local text = T.Text(intro, tr("Vorlagen ändern nur die aufgeführten Einstellungen und werden erst mit „Übernehmen“ wirksam. Änderungen müssen danach innerhalb von 30 Sekunden bestätigt werden.",
        "Presets only change the listed settings and take effect on Apply. Changes then have to be confirmed within 30 seconds."), "GameFontHighlightSmall", "muted")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetPoint("RIGHT", intro, "RIGHT", 0, 0)
    local x = 0
    for _, preset in ipairs(NS.GraphicsPresets) do
        local width = preset.key == "hdr" and 150 or 260
        local button = T.Button(intro, preset.title, width, 28, function()
            G.StagePreset(preset.key)
            U.Refresh()
        end, "secondary")
        button:SetPoint("TOPLEFT", x, -34)
        W.Tooltip(button, preset.title, preset.hint)
        x = x + width + 8
    end

    local footer = CreateFrame("Frame", nil, page)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    -- Embedded pages are wide enough for one row, which leaves more room for the list.
    footer:SetHeight(v.embedded and 34 or 72)
    v.graphicsApply = T.Button(footer, tr("Übernehmen", "Apply"), 130, 28, function()
        local ok, changed, refused = G.Apply(db())
        if ok == false and changed == "combat" then
            v:SetMessage(tr("Im Kampf nicht möglich. Deine Auswahl bleibt vorgemerkt.", "Not possible in combat. Your selection stays staged."))
        elseif refused and #refused > 0 then
            v:SetMessage(string.format(tr("Das Spiel hat abgelehnt: %s", "The game refused: %s"), table.concat(refused, ", ")))
        else
            v:SetMessage("")
        end
        U.Refresh()
    end, "primary")
    v.graphicsApply:SetPoint("TOPLEFT", 0, -6)
    v.graphicsDiscard = T.Button(footer, tr("Verwerfen", "Discard"), 110, 28, function()
        G.Discard()
        U.Refresh()
    end, "secondary")
    v.graphicsDiscard:SetPoint("TOPLEFT", 138, -6)
    local pending = T.Text(footer, "", "GameFontHighlightSmall", "muted")
    pending:SetPoint("LEFT", v.graphicsDiscard, "RIGHT", 10, 0)
    v.graphicsBackup = T.Button(footer, tr("Meine früheren Werte", "My previous values"), 190, 26, function()
        local ok = G.RestoreBackup(db())
        if not ok then v:SetMessage(tr("Im Kampf nicht möglich.", "Not possible in combat.")) end
        U.Refresh()
    end, "secondary")
    v.graphicsBackup:SetPoint("TOPLEFT", v.embedded and 256 or 0, v.embedded and -6 or -38)
    W.Tooltip(v.graphicsBackup, tr("Meine früheren Werte", "My previous values"), tr("Stellt alles her, was du vor der ersten Änderung durch ZENIAL Utility eingestellt hattest.", "Restores everything you had set before ZENIAL Utility first changed it."))
    v.graphicsDefaults = T.Button(footer, tr("Alles auf Spielstandard", "All to game default"), 190, 26, function()
        local ok = G.RestoreDefaults(db())
        if not ok then v:SetMessage(tr("Im Kampf nicht möglich.", "Not possible in combat.")) end
        U.Refresh()
    end, "danger")
    v.graphicsDefaults:SetPoint("TOPLEFT", v.embedded and 454 or 198, v.embedded and -6 or -38)
    if v.embedded then
        pending:ClearAllPoints()
        pending:SetPoint("LEFT", v.graphicsDefaults, "RIGHT", 10, 0)
    end

    local area = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
    area:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, 0)
    area:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 4)
    local scroll = CreateFrame("ScrollFrame", nil, area)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 400)
    scroll:SetScrollChild(content)
    W.ScrollBar(scroll, 54)
    local y = -4
    local sections = G.Rows()
    v.graphicsRows = 0
    for _, section in ipairs(sections) do
        W.Section(content, section.title, y, 600)
        y = y - 26
        for _, row in ipairs(section.rows) do
            buildRow(v, content, row, y)
            v.graphicsRows = v.graphicsRows + 1
            y = y - 56
        end
        y = y - 8
    end
    if #sections == 0 then
        local empty = T.Text(content, tr("Dieser Client meldet keine der bekannten Einstellungen.", "This client reports none of the known settings."), "GameFontHighlight", "muted")
        empty:SetPoint("TOPLEFT", 4, -8)
    end
    content:SetHeight(-y + 8)
    local function fit()
        local width = (scroll:GetWidth() or 600) - 4
        if width > 100 then content:SetWidth(width) end
        scroll:UpdateScrollChildRect()
        scroll:RefreshScrollbar()
    end
    scroll:HookScript("OnSizeChanged", fit)
    v:AddUpdate(function()
        fit()
        local count = G.PendingCount()
        pending:SetText(count > 0 and string.format(tr("%d Änderungen vorgemerkt", "%d changes staged"), count) or "")
        v.graphicsApply:SetEnabled(count > 0 and not A.Combat())
        v.graphicsDiscard:SetEnabled(count > 0)
        v.graphicsBackup:SetEnabled(G.ChangedCount(db()) > 0 and not A.Combat())
        v.graphicsDefaults:SetEnabled(not A.Combat())
    end)
end

----------------------------------------------------------------------
-- The timed question. Escape deliberately does not answer it.
----------------------------------------------------------------------
local Confirm = {}
NS.GraphicsConfirm = Confirm

function Confirm.Create()
    if Confirm.frame then return end
    local f = CreateFrame("Frame", "ZenialUtilityGraphicsConfirm", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(420, 150)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    T.Panel(f, "surface")
    local title = T.Text(f, tr("Grafikänderung behalten?", "Keep the graphics change?"), "GameFontNormal", "gold")
    title:SetPoint("TOPLEFT", 18, -16)
    Confirm.text = T.Text(f, "", "GameFontHighlight", "text")
    Confirm.text:SetPoint("TOPLEFT", 18, -40)
    Confirm.text:SetWidth(384)
    Confirm.keep = T.Button(f, tr("Behalten", "Keep"), 150, 30, function() G.Keep(db()) end, "primary")
    Confirm.keep:SetPoint("BOTTOMLEFT", 18, 16)
    Confirm.revert = T.Button(f, tr("Zurücksetzen", "Revert"), 150, 30, function() G.Revert(db()) end, "secondary")
    Confirm.revert:SetPoint("BOTTOMLEFT", 176, 16)
    Confirm.frame = f
    f:Hide()
end

function Confirm.Update()
    if not Confirm.frame or not G.deadline then return end
    local left = math.max(0, math.ceil(G.deadline))
    if A.Combat() and left == 0 then
        Confirm.text:SetText(tr("Wird nach dem Kampf zurückgesetzt, wenn du nicht bestätigst.", "Reverts after combat unless you confirm."))
    else
        Confirm.text:SetText(string.format(tr("Ohne Antwort stellt ZENIAL Utility in %d Sekunden die vorherigen Werte wieder her.",
            "Without an answer ZENIAL Utility restores the previous values in %d seconds."), left))
    end
end

function Confirm.Show()
    Confirm.Create()
    Confirm.Update()
    Confirm.frame:Show()
end

function Confirm.Hide()
    if Confirm.frame then Confirm.frame:Hide() end
end
