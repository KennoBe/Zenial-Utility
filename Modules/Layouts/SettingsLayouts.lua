local _, NS = ...
local U = NS.SettingsUI
local T, tr, W, Y = NS.Theme, NS.Text, NS.Widgets, NS.Layouts

local ROW_HEIGHT, MAX_ROWS, ICON_COUNT = 36, 14, 12
local KINDS = {"ui", "cdm"}
local KIND_TITLES = {ui = tr("Oberfläche", "Interface"), cdm = tr("Cooldown Manager", "Cooldown Manager")}
local SOURCES = {preset = tr("Vorlage", "Preset"), own = tr("Eigenes", "Own"), game = tr("Aus dem Spiel", "From the game")}
-- The raid target star exists in every client; the font has no star glyph.
local STAR_ON, STAR_OFF = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t ", ""

local function boxColor(key)
    if key == "ActionBar" then return "goldDim" end
    if key == "UnitFrame" then return "accentBlue" end
    if key == "CooldownViewer" or key == "AuraFrame" then return "online" end
    return "dim"
end

local function sourceText(row)
    return row.preset and SOURCES.preset or SOURCES[row.source] or SOURCES.own
end

----------------------------------------------------------------------
-- Preview: drawn boxes for Edit Mode, icons and counts for the Cooldown Manager, a picture for presets.
----------------------------------------------------------------------
local function boxFrame(canvas, index)
    local box = canvas.boxes[index]
    if box then return box end
    box = CreateFrame("Frame", nil, canvas)
    box.fill = box:CreateTexture(nil, "ARTWORK")
    box.fill:SetAllPoints()
    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.label:SetPoint("CENTER")
    box.label:SetWordWrap(false)
    box:EnableMouse(true)
    box:SetScript("OnEnter", function(self)
        local tip = _G.GameTooltip
        if not tip or not tip.SetOwner or not self.title then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(self.title)
        tip:Show()
    end)
    box:SetScript("OnLeave", function() if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end end)
    canvas.boxes[index] = box
    return box
end

local function clearPreview(preview)
    for _, box in ipairs(preview.canvas.boxes) do box:Hide() end
    for _, icon in ipairs(preview.icons) do icon:Hide() end
    preview.screen:Hide()
    preview.image:Hide()
    preview.lines:SetText("")
end

local function drawUI(preview, value)
    local boxes, info = Y.UIPreview(value)
    if not boxes then return Y.ReasonText(info) end
    local canvas = preview.canvas
    local width, height = Y.ScreenSize()
    local cw, ch = math.max(1, canvas:GetWidth() or 1), math.max(1, canvas:GetHeight() or 1)
    local scale = math.min(cw / width, ch / height)
    local ox, oy = (cw - width * scale) / 2, (ch - height * scale) / 2
    preview.screen:ClearAllPoints()
    preview.screen:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", ox, oy)
    preview.screen:SetSize(width * scale, height * scale)
    preview.screen:Show()
    for index, data in ipairs(boxes) do
        local box = boxFrame(canvas, index)
        local key = Y.SystemKey(data.system.system)
        local w, h = math.max(3, data.width * scale), math.max(3, data.height * scale)
        local x = math.max(0, math.min(width * scale - w, data.left * scale))
        local y = math.max(0, math.min(height * scale - h, data.bottom * scale))
        box:ClearAllPoints()
        box:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", ox + x, oy + y)
        box:SetSize(w, h)
        T.Tint(box.fill, "SetColorTexture", boxColor(key), .55)
        box.title = data.name or key
        box.label:SetText(w > 46 and h > 10 and box.title or "")
        box.label:SetWidth(w - 4)
        box:Show()
    end
    local known = 0
    for _, data in ipairs(boxes) do if data.known then known = known + 1 end end
    local text = string.format(tr("%d Elemente. Vereinfachte Vorschau: Positionen aus dem Text, Größen aus deinem Interface.",
        "%d elements. Simplified preview: positions from the text, sizes from your interface."), #boxes)
    if known < #boxes then text = text .. " " .. tr("Unbekannte Elemente als Platzhalter.", "Unknown elements as placeholders.") end
    return text
end

local function drawCooldown(preview, value)
    local data, reason = Y.DecodeCooldown(value)
    if not data then return Y.ReasonText(reason) end
    local rows = Y.CooldownSummary(data)
    if #rows == 0 then return tr("Kein Layout im Text.", "No layout in the text.") end
    local lines = {}
    for _, row in ipairs(rows) do
        local parts = {}
        if #row.order > 0 then parts[#parts + 1] = string.format(tr("%d sortiert", "%d sorted"), #row.order) end
        local moved = {}
        for category, amount in pairs(row.categories) do moved[#moved + 1] = Y.CategoryName(category) .. " " .. amount end
        table.sort(moved)
        if #moved > 0 then parts[#parts + 1] = table.concat(moved, ", ") end
        if row.alerts > 0 then parts[#parts + 1] = string.format(tr("%d Hinweise", "%d alerts"), row.alerts) end
        lines[#lines + 1] = "|cffffd100" .. (row.name or "?") .. "|r  ·  " .. Y.SpecText(row.classID, row.spec)
        lines[#lines + 1] = #parts > 0 and table.concat(parts, "  ·  ") or tr("Ohne Änderungen am Standard", "No changes to the default")
    end
    preview.lines:SetText(table.concat(lines, "\n"))
    -- Spell icons only resolve for cooldowns the client knows, usually those of your own class.
    local shown = 0
    for _, id in ipairs(rows[1].order) do
        if shown >= ICON_COUNT then break end
        local file = Y.CooldownIcon(id)
        if file then
            shown = shown + 1
            local icon = preview.icons[shown]
            icon:SetTexture(file)
            icon:Show()
        end
    end
    return tr("Inhalt aus dem Text. Positionen legt der Bearbeitungsmodus fest.", "Content from the text. Positions belong to Edit Mode.")
end

local function drawPreview(preview, row)
    clearPreview(preview)
    if not row then return "" end
    if row.image then
        preview.image:SetTexture(row.image)
        preview.image:Show()
    end
    local ok, result = pcall(row.kind == "ui" and drawUI or drawCooldown, preview, row.text)
    if not ok then return tr("Vorschau nicht möglich.", "Preview not possible.") end
    return result or ""
end

----------------------------------------------------------------------
function U.fixed.layouts(v, page)
    local state = {kind = "ui", favorites = false, offset = 0, mode = "view"}
    v.layoutState = state

    local function choose(key)
        state.selected, state.armed, state.previewKey = key, nil, nil
        v:SetMessage("")
    end

    -- Top bar
    v.layoutTabs = {}
    for index, kind in ipairs(KINDS) do
        local tab = T.Button(page, KIND_TITLES[kind], 150, 26, function()
            state.kind, state.offset, state.mode = kind, 0, "view"
            choose(nil)
            v:RenderLayouts()
        end, "secondary")
        tab:SetPoint("TOPLEFT", (index - 1) * 156, 0)
        v.layoutTabs[kind] = tab
    end
    local fav = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    fav:SetSize(22, 22)
    fav:SetPoint("TOPLEFT", 322, -2)
    T.StyleCheckbox(fav)
    fav:SetScript("OnClick", function(self) state.favorites = self:GetChecked() == true; state.offset = 0; v:RenderLayouts() end)
    local favLabel = T.Text(page, tr("Nur Favoriten", "Favourites only"), "GameFontHighlightSmall", "text")
    favLabel:SetPoint("TOPLEFT", 348, -7)
    U.Note(v, tr("Layout-Bibliothek", "Layout library"))
    v.layoutAdd = T.Button(page, tr("Hinzufügen", "Add"), 120, 26, function()
        state.mode = state.mode == "add" and "view" or "add"
        v:SetMessage("")
        v:RenderLayouts()
    end, "secondary")
    v.layoutAdd:SetPoint("TOPRIGHT", 0, 0)

    -- List
    local list = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
    list:SetPoint("TOPLEFT", 0, -36)
    list:SetPoint("BOTTOMLEFT", 0, 0)
    list:SetWidth(250)
    T.Panel(list, "inset")
    v.layoutRows = {}
    for index = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, list, BackdropTemplateMixin and "BackdropTemplate" or nil)
        row:SetHeight(ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 5, -5 - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -20, -5 - (index - 1) * ROW_HEIGHT)
        T.StyleRow(row)
        row.title = T.Text(row, "", "GameFontHighlightSmall", "text")
        row.title:SetPoint("TOPLEFT", 10, -4)
        row.title:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.title:SetWordWrap(false)
        row.sub = T.Text(row, "", "GameFontHighlightSmall", "muted")
        row.sub:SetPoint("TOPLEFT", 10, -18)
        row.sub:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.sub:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            state.mode = "view"
            choose(self.data and self.data.key)
            v:RenderLayouts()
        end)
        row:Hide()
        v.layoutRows[index] = row
    end
    local empty = T.Text(list, "", "GameFontHighlightSmall", "muted")
    empty:SetPoint("TOPLEFT", 12, -12)
    empty:SetWidth(224)
    v.layoutEmpty = empty
    local bar = T.CreateScrollBar(list, function(value)
        local next = math.floor(value + .5)
        if next ~= state.offset then state.offset = next; v:RenderLayouts() end
    end)
    bar:SetPoint("TOPRIGHT", -4, -6)
    v.layoutBar = bar
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) state.offset = math.max(0, state.offset - delta); v:RenderLayouts() end)
    v.layoutList = list

    -- Detail
    local detail = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
    detail:SetPoint("BOTTOMRIGHT", 0, 0)
    T.Panel(detail, "surface")

    local view = CreateFrame("Frame", nil, detail)
    view:SetPoint("TOPLEFT", 14, -12)
    view:SetPoint("BOTTOMRIGHT", -14, 10)
    v.layoutView = view
    local title = T.Text(view, "", "GameFontNormal", "gold")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    title:SetWordWrap(false)
    local meta = T.Text(view, "", "GameFontHighlightSmall", "muted")
    meta:SetPoint("TOPLEFT", 0, -18)
    meta:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    local desc = T.Text(view, "", "GameFontHighlightSmall", "text")
    desc:SetPoint("TOPLEFT", 0, -34)
    desc:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    desc:SetWordWrap(false)

    local preview = CreateFrame("Frame", nil, view, BackdropTemplateMixin and "BackdropTemplate" or nil)
    preview:SetPoint("TOPLEFT", 0, -52)
    preview:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    preview:SetHeight(170)
    T.Panel(preview, "inset")
    local canvas = CreateFrame("Frame", nil, preview)
    canvas:SetPoint("TOPLEFT", 8, -8)
    canvas:SetPoint("BOTTOMRIGHT", -8, 8)
    canvas.boxes = {}
    preview.canvas = canvas
    preview.screen = canvas:CreateTexture(nil, "BACKGROUND")
    T.Tint(preview.screen, "SetColorTexture", "panel", .9)
    preview.image = canvas:CreateTexture(nil, "ARTWORK")
    preview.image:SetAllPoints()
    preview.lines = T.Text(canvas, "", "GameFontHighlightSmall", "text")
    preview.lines:SetPoint("TOPLEFT", 4, -4)
    preview.lines:SetPoint("RIGHT", canvas, "RIGHT", -4, 0)
    preview.icons = {}
    for index = 1, ICON_COUNT do
        local icon = canvas:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("BOTTOMLEFT", 4 + (index - 1) * 30, 4)
        icon:Hide()
        preview.icons[index] = icon
    end
    v.layoutPreview = preview
    local status = T.Text(view, "", "GameFontHighlightSmall", "muted")
    status:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -6)
    status:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    v.layoutStatus = status

    -- Own entries: name and description
    local editRow = CreateFrame("Frame", nil, view)
    editRow:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -40)
    editRow:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    editRow:SetHeight(64)
    local nameEdit = W.Edit(editRow, 0, 0, 140, nil)
    nameEdit:SetMaxLetters(Y.MaxName)
    local descEdit = W.Edit(editRow, 146, 0, 120, nil)
    descEdit:ClearAllPoints()
    descEdit:SetPoint("TOPLEFT", 146, 0)
    descEdit:SetPoint("RIGHT", editRow, "RIGHT", -96, 0)
    descEdit:SetMaxLetters(Y.MaxDescription)
    W.Tooltip(nameEdit, tr("Name", "Name"))
    W.Tooltip(descEdit, tr("Beschreibung", "Description"))
    local save = T.Button(editRow, tr("Speichern", "Save"), 90, 26, function()
        local id = tonumber((state.selected or ""):match("^own:(%d+)$"))
        if id and Y.Rename(id, nameEdit:GetText()) and Y.Describe(id, descEdit:GetText()) then
            v:SetMessage(tr("Gespeichert.", "Saved."))
        else
            v:SetMessage(tr("Ein Name wird gebraucht.", "A name is needed."))
        end
        v:RenderLayouts()
    end, "secondary")
    save:SetPoint("TOPRIGHT", 0, 0)
    v.layoutNameEdit, v.layoutDescEdit, v.layoutEditRow = nameEdit, descEdit, editRow

    local actions = CreateFrame("Frame", nil, view)
    actions:SetPoint("TOPLEFT", editRow, "TOPLEFT", 0, -34)
    actions:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    actions:SetHeight(28)
    v.layoutFavorite = T.Button(actions, "", 120, 26, function()
        if state.selected and Y.ToggleFavorite(state.selected) then v:RenderLayouts() end
    end, "secondary")
    v.layoutFavorite:SetPoint("TOPLEFT", 0, 0)
    local export = W.Edit(view, 0, 0, 200, nil)
    export:SetMaxLetters(0)
    export:ClearAllPoints()
    export:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -8)
    export:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    export:Hide()
    v.layoutExport = export
    v.layoutExportButton = T.Button(actions, tr("Exportieren", "Export"), 120, 26, function()
        local row = v.layoutCurrent
        if not row then return end
        export:SetText(row.text)
        export:Show()
        export:SetFocus()
        export:HighlightText()
        v:SetMessage(tr("Mit Strg+C kopieren.", "Copy with Ctrl+C."))
    end, "secondary")
    v.layoutExportButton:SetPoint("TOPLEFT", 126, 0)
    v.layoutDelete = T.Button(actions, tr("Löschen", "Delete"), 120, 26, function()
        local id = tonumber((state.selected or ""):match("^own:(%d+)$"))
        if not id then return end
        if state.armed ~= id then
            state.armed = id
            v:SetMessage(tr("Noch einmal klicken zum Löschen. Layouts im Spiel bleiben unberührt.", "Click again to delete. Layouts in the game stay untouched."))
            v:RenderLayouts()
            return
        end
        Y.Delete(id)
        choose(nil)
        v:SetMessage(tr("Gelöscht.", "Deleted."))
        v:RenderLayouts()
    end, "danger")
    v.layoutDelete:SetPoint("TOPLEFT", 252, 0)
    local steps = T.Text(view, "", "GameFontHighlightSmall", "muted")
    steps:SetPoint("BOTTOMLEFT", 0, 0)
    steps:SetPoint("RIGHT", view, "RIGHT", 0, 0)
    v.layoutSteps = steps
    local placeholder = T.Text(view, tr("Wähle links ein Layout oder füge eines hinzu.", "Pick a layout on the left or add one."), "GameFontHighlightSmall", "muted")
    placeholder:SetPoint("TOPLEFT", 0, 0)
    placeholder:SetWidth(380)
    v.layoutPlaceholder = placeholder

    -- Adding
    local add = CreateFrame("Frame", nil, detail)
    add:SetPoint("TOPLEFT", 14, -12)
    add:SetPoint("BOTTOMRIGHT", -14, 10)
    add:Hide()
    v.layoutAddView = add
    local addTitle = T.Text(add, "", "GameFontNormal", "gold")
    addTitle:SetPoint("TOPLEFT", 0, 0)
    v.layoutAddTitle = addTitle
    local function field(label, y)
        local text = T.Text(add, label, "GameFontHighlightSmall", "text")
        text:SetPoint("TOPLEFT", 0, y)
        U.Note(v, label)
        local edit = W.Edit(add, 0, y - 16, 200, nil)
        edit:ClearAllPoints()
        edit:SetPoint("TOPLEFT", 0, y - 16)
        edit:SetPoint("RIGHT", add, "RIGHT", 0, 0)
        return edit
    end
    local addName = field(tr("Name", "Name"), -28)
    addName:SetMaxLetters(Y.MaxName)
    local addDesc = field(tr("Beschreibung (optional)", "Description (optional)"), -78)
    addDesc:SetMaxLetters(Y.MaxDescription)
    local addText = field(tr("Importstring", "Import string"), -128)
    addText:SetMaxLetters(0)
    local addHint = T.Text(add, tr("Wird unverändert gespeichert. Die Kategorie erkennt Utility am Text.", "Stored unchanged. Utility recognises the category from the text."), "GameFontHighlightSmall", "muted")
    addHint:SetPoint("TOPLEFT", 0, -178)
    addHint:SetPoint("RIGHT", add, "RIGHT", 0, 0)
    local saveNew = T.Button(add, tr("Speichern", "Save"), 120, 28, function()
        local entry, reason, existing = Y.Add(state.kind, addName:GetText(), addDesc:GetText(), addText:GetText(), "own")
        if not entry then
            v:SetMessage(Y.ReasonText(reason))
            if existing then state.mode = "view"; choose("own:" .. existing.id); v:RenderLayouts() end
            return
        end
        addName:SetText(""); addDesc:SetText(""); addText:SetText("")
        state.mode = "view"
        choose("own:" .. entry.id)
        v:SetMessage(tr("Layout gespeichert.", "Layout saved."))
        v:RenderLayouts()
    end, "primary")
    saveNew:SetPoint("TOPLEFT", 0, -214)
    local fromGame = T.Button(add, tr("Aus dem Spiel übernehmen", "Take over from the game"), 236, 28, function()
        local added, skipped = Y.ReadGame(state.kind)
        if not added then v:SetMessage(Y.ReasonText(skipped)); return end
        v:SetMessage(string.format(tr("%d übernommen, %d schon vorhanden.", "%d taken over, %d already there."), added, skipped))
        state.mode = "view"
        v:RenderLayouts()
    end, "secondary")
    fromGame:SetPoint("TOPLEFT", 0, -250)
    W.Tooltip(fromGame, tr("Aus dem Spiel übernehmen", "Take over from the game"),
        tr("Liest deine gespeicherten Layouts nur aus. Im Spiel wird nichts geändert.", "Only reads your saved layouts. Nothing changes in the game."))
    v.layoutFromGame = fromGame
    local cancel = T.Button(add, tr("Abbrechen", "Cancel"), 110, 28, function() state.mode = "view"; v:RenderLayouts() end, "secondary")
    cancel:SetPoint("TOPLEFT", 128, -214)
    v.layoutAddFields = {name = addName, desc = addDesc, text = addText}

    function v:RenderLayouts()
        if not self.layoutList then return end
        for kind, tab in pairs(self.layoutTabs) do T.SetSelected(tab, kind == state.kind) end
        fav:SetChecked(state.favorites)
        local rows = Y.Rows(state.kind, state.favorites)
        local visible = math.max(1, math.min(MAX_ROWS, math.floor(((list:GetHeight() or 400) - 10) / ROW_HEIGHT)))
        local maximum = math.max(0, #rows - visible)
        state.offset = math.max(0, math.min(maximum, state.offset))
        local current
        for _, row in ipairs(rows) do if row.key == state.selected then current = row end end
        if not current and state.mode == "view" then
            current = rows[1]
            state.selected = current and current.key or nil
        end
        self.layoutCurrent = current
        for index, button in ipairs(self.layoutRows) do
            local data = index <= visible and rows[index + state.offset] or nil
            button.data = data
            if data then
                T.UpdateRow(button, {selected = current == data})
                button.title:SetText((data.fav and STAR_ON or STAR_OFF) .. data.name)
                button.sub:SetText(sourceText(data))
                button:Show()
            else
                button:Hide()
            end
        end
        self.layoutEmpty:SetText(#rows == 0 and (state.favorites and tr("Keine Favoriten.", "No favourites.")
            or tr("Noch keine Layouts. Über „Hinzufügen“ fügst du einen Importstring ein oder übernimmst deine Layouts aus dem Spiel.",
                "No layouts yet. Use Add to paste an import string or take over your layouts from the game.")) or "")
        T.UpdateScrollBar(self.layoutBar, maximum, state.offset, list:GetHeight() or 400, (list:GetHeight() or 400) + maximum * ROW_HEIGHT)

        local adding = state.mode == "add"
        self.layoutAddView:SetShown(adding)
        self.layoutView:SetShown(not adding)
        self.layoutAdd:SetText(adding and tr("Zur Liste", "Back to list") or tr("Hinzufügen", "Add"))
        if adding then
            self.layoutAddTitle:SetText(string.format(tr("Neues Layout: %s", "New layout: %s"), KIND_TITLES[state.kind]))
            return
        end
        local has = current ~= nil
        self.layoutPlaceholder:SetShown(not has)
        for _, region in ipairs({title, meta, desc, preview, status, actions, steps}) do region:SetShown(has) end
        local own = has and current.id ~= nil
        self.layoutEditRow:SetShown(own)
        if not has then self.layoutExport:Hide(); return end
        title:SetText(current.name)
        meta:SetText(sourceText(current) .. "  ·  " .. KIND_TITLES[current.kind] .. (current.author and ("  ·  " .. current.author) or ""))
        desc:SetText(current.desc or "")
        if state.previewKey ~= current.key then
            state.previewKey = current.key
            self.layoutExport:Hide()
            status:SetText(drawPreview(preview, current))
            if own then
                nameEdit:SetText(current.name)
                descEdit:SetText(current.desc or "")
            end
        end
        self.layoutFavorite:SetText(current.fav and tr("Favorit entfernen", "Remove favourite") or tr("Als Favorit", "Add favourite"))
        self.layoutDelete:SetShown(own)
        self.layoutDelete:SetText(state.armed == current.id and tr("Wirklich?", "Sure?") or tr("Löschen", "Delete"))
        steps:SetText(Y.ImportSteps(current.kind))
    end

    list:SetScript("OnSizeChanged", function() if v.index == "layouts" then v:RenderLayouts() end end)
    canvas:SetScript("OnSizeChanged", function() state.previewKey = nil; if v.index == "layouts" then v:RenderLayouts() end end)
    v:AddUpdate(function() v:RenderLayouts() end)
end
