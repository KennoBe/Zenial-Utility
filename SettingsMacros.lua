local _, NS = ...
local U = NS.SettingsUI
local T, tr, A, W, M = NS.Theme, NS.Text, NS.Adapter, NS.Widgets, NS.Macros

local ROW_HEIGHT, MAX_ROWS = 38, 14
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Note_01"

local function db() return NS.App.db end

local function entryIcon(entry)
    return entry.spells and A.SpellIcon(entry.spells[1]) or FALLBACK_ICON
end

local function missingText(missing)
    local names = {}
    for _, spell in ipairs(missing) do names[#names + 1] = A.SpellName(spell) or tostring(spell) end
    return table.concat(names, ", ")
end

function U.fixed.macros(v, page)
    local state = {class = A.PlayerClass(), cat = "ALL", text = "", knownOnly = false, offset = 0, scope = "account"}
    v.macroState = state
    if not M.Classes[state.class] then state.class = "ALL" end

    -- Filters
    local classes = {{"ALL", tr("Alle Klassen", "All classes")}}
    for _, key in ipairs(M.ClassOrder) do classes[#classes + 1] = {key, M.ClassName(key)} end
    local categories = {{"ALL", tr("Alle Kategorien", "All categories")}}
    for _, key in ipairs(M.CategoryOrder) do categories[#categories + 1] = {key, M.CategoryName(key)} end
    v:Dropdown(page, "macroClass", 0, 0, 150, classes, function() return state.class end, function(value) state.class = value; state.offset = 0 end)
    v:Dropdown(page, "macroCategory", 156, 0, 170, categories, function() return state.cat end, function(value) state.cat = value; state.offset = 0 end)
    local search = W.Edit(page, 334, 0, 190, function(value) state.text = value; state.offset = 0; v:RenderMacros() end)
    v.macroSearch = search
    local hint = T.Text(search, tr("Suchen", "Search"), "GameFontHighlightSmall", "muted")
    hint:SetPoint("LEFT", 8, 0)
    search:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)

    local known = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    known:SetSize(22, 22)
    known:SetPoint("TOPLEFT", 0, -34)
    T.StyleCheckbox(known)
    known:SetScript("OnClick", function(self) state.knownOnly = self:GetChecked() == true; state.offset = 0; v:RenderMacros() end)
    v.macroKnown = known
    local knownLabel = T.Text(page, tr("Nur Makros mit gelernten Zaubern", "Only macros with learned spells"), "GameFontHighlightSmall", "text")
    knownLabel:SetPoint("TOPLEFT", 26, -38)
    v.macroCount = T.Text(page, "", "GameFontHighlightSmall", "muted")
    v.macroCount:SetPoint("TOPRIGHT", 0, -38)
    v.macroCount:SetJustifyH("RIGHT")

    -- List
    local list = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
    list:SetPoint("TOPLEFT", 0, -62)
    list:SetPoint("BOTTOMLEFT", 0, 0)
    list:SetWidth(260)
    T.Panel(list, "inset")
    v.macroRows = {}
    for index = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, list, BackdropTemplateMixin and "BackdropTemplate" or nil)
        row:SetHeight(ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 5, -5 - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -20, -5 - (index - 1) * ROW_HEIGHT)
        T.StyleRow(row)
        row.zenialRowIcon:SetSize(24, 24)
        row.title = T.Text(row, "", "GameFontHighlightSmall", "text")
        row.title:SetPoint("TOPLEFT", 38, -5)
        row.title:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.title:SetWordWrap(false)
        row.sub = T.Text(row, "", "GameFontHighlightSmall", "muted")
        row.sub:SetPoint("TOPLEFT", 38, -20)
        row.sub:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.sub:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            state.selected, state.armed = self.entry, nil
            v:SetMessage("")
            v:RenderMacros()
        end)
        v.macroRows[index] = row
    end
    local bar = T.CreateScrollBar(list, function(value)
        local next = math.floor(value + .5)
        if next ~= state.offset then state.offset = next; v:RenderMacros() end
    end)
    bar:SetPoint("TOPRIGHT", -4, -6)
    v.macroBar = bar
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        state.offset = math.max(0, state.offset - delta)
        v:RenderMacros()
    end)
    v.macroList = list

    -- Details
    local detail = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
    detail:SetPoint("BOTTOMRIGHT", 0, 0)
    T.Panel(detail, "surface")
    local icon = detail:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 14, -14)
    local title = T.Text(detail, "", "GameFontNormal", "gold")
    title:SetPoint("TOPLEFT", 58, -14)
    title:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    local meta = T.Text(detail, "", "GameFontHighlightSmall", "muted")
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    meta:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    local text = T.Text(detail, "", "GameFontHighlightSmall", "text")
    text:SetPoint("TOPLEFT", 14, -60)
    text:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
    local note = T.Text(detail, "", "GameFontHighlightSmall", "muted")
    note:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
    note:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
    local code = CreateFrame("Frame", nil, detail, BackdropTemplateMixin and "BackdropTemplate" or nil)
    code:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -2, -8)
    code:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    code:SetHeight(112)
    T.Panel(code, "inset")
    local body = T.Text(code, "", "GameFontHighlightSmall", "goldText")
    T.Tint(body, "SetTextColor", "goldText")
    body:SetPoint("TOPLEFT", 10, -9)
    body:SetPoint("BOTTOMRIGHT", -10, 9)

    local inputs = {}
    for index = 1, 2 do
        local row = CreateFrame("Frame", nil, detail)
        row:SetHeight(46)
        row:SetPoint("TOPLEFT", code, "BOTTOMLEFT", 2, -6 - (index - 1) * 48)
        row:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
        row.label = T.Text(row, "", "GameFontHighlightSmall", "text")
        row.label:SetPoint("TOPLEFT", 0, 0)
        row.edit = W.Edit(row, 0, -16, 300, function(value)
            db().macroInputs[row.key] = value
            state.armed = nil
            v:RenderMacroDetail()
        end)
        row:Hide()
        inputs[index] = row
    end
    v.macroInputs = inputs

    local footer = CreateFrame("Frame", nil, detail)
    footer:SetPoint("BOTTOMLEFT", 14, 10)
    footer:SetPoint("BOTTOMRIGHT", -14, 10)
    footer:SetHeight(32)
    v:Dropdown(footer, "macroScope", 0, 0, 150, {{"account", tr("Für den Account", "For the account")}, {"character", tr("Für diesen Charakter", "For this character")}},
        function() return state.scope end, function(value) state.scope = value; state.armed = nil end)
    v.macroImport = T.Button(footer, tr("Importieren", "Import"), 110, 28, function() v:ImportMacro() end, "primary")
    v.macroImport:SetPoint("TOPLEFT", 156, 0)
    v.macroPickup = T.Button(footer, tr("Aufnehmen", "Pick up"), 90, 28, function()
        local name = state.selected and M.ShortName(state.selected)
        local index = name and A.Call(GetMacroIndexByName, name)
        if type(index) == "number" and index > 0 and not A.Combat() then A.Call(PickupMacro, index) end
    end, "secondary")
    v.macroPickup:SetPoint("TOPLEFT", 270, 0)
    W.Tooltip(v.macroPickup, tr("Aufnehmen", "Pick up"), tr("Legt das Makro auf den Mauszeiger, damit du es auf eine Aktionsleiste ziehen kannst.", "Puts the macro on the cursor so you can drop it on an action bar."))

    function v:ImportMacro()
        local entry = state.selected
        if not entry then return end
        local replace = state.armed == entry.id
        local ok, reason, value = M.Import(entry, db().macroInputs, state.scope == "character", replace)
        state.armed = (not ok and reason == "exists") and entry.id or nil
        self:SetMessage(M.Reason(reason, value))
        if ok then db().imported[entry.id] = true end
        self:RenderMacros()
    end

    function v:RenderMacroDetail()
        local entry = state.selected
        detail:SetShown(entry ~= nil)
        if not entry then return end
        icon:SetTexture(entryIcon(entry))
        title:SetText(M.Name(entry))
        local knowledge, missing = M.Knowledge(entry)
        local status = M.ClassName(entry.class) .. "  ·  " .. M.CategoryName(entry.cat)
        if knowledge == "unknown" or knowledge == "partial" then
            status = status .. "\n" .. string.format(tr("Noch nicht gelernt: %s", "Not learned yet: %s"), missingText(missing))
        end
        meta:SetText(status)
        text:SetPoint("TOPLEFT", 14, #missing > 0 and -74 or -60)
        text:SetText(M.Description(entry))
        note:SetText(M.Note(entry))
        body:SetText(M.Preview(entry, db().macroInputs))
        local keys = M.InputKeys(entry)
        for index, row in ipairs(inputs) do
            local key = keys[index]
            row.key = key
            if key then
                row.label:SetText(M.InputName(key))
                if row.edit.lastKey ~= key then
                    row.edit:SetText(db().macroInputs[key] or "")
                    row.edit.lastKey = key
                end
                row:Show()
            else
                row:Hide()
            end
        end
        local expanded = M.Expand(entry, db().macroInputs)
        local existing = expanded and M.Existing(M.ShortName(entry), expanded)
        self.macroPickup:SetEnabled(existing ~= nil and not A.Combat())
        self.macroImport:SetEnabled(not A.Combat())
        self.macroImport:SetText(state.armed == entry.id and tr("Ersetzen", "Replace") or tr("Importieren", "Import"))
    end

    function v:RenderMacros()
        local rows = M.Filter(state)
        local visible = math.max(1, math.min(MAX_ROWS, math.floor(((list:GetHeight() or 400) - 10) / ROW_HEIGHT)))
        local maximum = math.max(0, #rows - visible)
        state.offset = math.max(0, math.min(maximum, state.offset))
        for index, row in ipairs(self.macroRows) do
            local entry = index <= visible and rows[index + state.offset] or nil
            row.entry = entry
            if entry then
                local knowledge = M.Knowledge(entry)
                T.UpdateRow(row, {selected = state.selected == entry, icon = {file = entryIcon(entry)}})
                row.title:SetText(M.Name(entry))
                row.sub:SetText(M.CategoryName(entry.cat))
                T.Tint(row.title, "SetTextColor", knowledge == "unknown" and "disabledText" or "text")
                if row.zenialRowIcon.SetDesaturated then row.zenialRowIcon:SetDesaturated(knowledge == "unknown") end
                row:Show()
            else
                row:Hide()
            end
        end
        T.UpdateScrollBar(self.macroBar, maximum, state.offset, list:GetHeight() or 400, (list:GetHeight() or 400) + maximum * ROW_HEIGHT)
        local slots = M.Slots()
        self.macroCount:SetText(string.format(tr("%d Treffer  ·  Account %d/%d  ·  Charakter %d/%d", "%d found  ·  account %d/%d  ·  character %d/%d"),
            #rows, slots.account, slots.accountMax, slots.character, slots.characterMax))
        if not state.selected then state.selected = rows[1] end
        self:RenderMacroDetail()
    end

    list:SetScript("OnSizeChanged", function() if v.index == "macros" then v:RenderMacros() end end)
    v:AddUpdate(function() v:RenderMacros() end)
end
