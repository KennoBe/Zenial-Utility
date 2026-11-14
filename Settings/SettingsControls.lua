local _, NS = ...
-- Reusable controls for the settings pages. Every control follows the same rules:
--   * a short name, an optional one-line explanation underneath and an optional tooltip,
--   * reads and writes one value through get/set (default: the setting `key`),
--   * greys out while its parent option is off (`parent` = setting key or function),
--   * right-click on a slider or a choice restores the shipped value,
--   * every change is saved at once through view:Changed().
-- A Form lays the controls out top to bottom and remembers where each one sits for the search.
local C = {}
NS.SettingsControls = C
local T, tr, W, L = NS.Theme, NS.Text, NS.Widgets, NS.Logic

C.Width = 600
C.Indent = 28
C.Column = 300 -- where choices start on their row

function C.Pick(value)
    if type(value) == "table" then return tr(value[1], value[2]) end
    return value
end

local function hide(tip) if tip and tip.Hide then tip:Hide() end end

-- Tooltip with a title, a body and an optional muted last line (default value, right-click hint).
function C.Tooltip(frame, title, body, extra)
    frame:EnableMouse(true)
    frame:HookScript("OnEnter", function(self)
        local tip = _G.GameTooltip
        if not tip or not tip.SetOwner then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(type(title) == "function" and title() or title)
        local text = type(body) == "function" and body() or body
        if text and text ~= "" then tip:AddLine(text, 1, 1, 1, true) end
        local last = type(extra) == "function" and extra() or extra
        if last and last ~= "" then tip:AddLine(last, .65, .6, .5, true) end
        tip:Show()
    end)
    frame:HookScript("OnLeave", function() hide(_G.GameTooltip) end)
end

local function binding(v, spec)
    local get = spec.get or function() return v.draft[spec.key] end
    local set = spec.set or function(value) v.draft[spec.key] = value end
    return get, set
end

-- nil when the control is always usable.
local function enabledFn(v, spec)
    local parent, extra = spec.parent, spec.enabled
    if not parent and not extra then return nil end
    return function()
        if type(parent) == "string" and not v.draft[parent] then return false end
        if type(parent) == "function" and not parent() then return false end
        if extra and not extra() then return false end
        return true
    end
end

local function default(spec)
    if spec.default ~= nil then return spec.default end
    if spec.key then return L.Defaults[spec.key] end
    return nil
end

local function textHeight(fontString, minimum)
    local height = fontString.GetStringHeight and fontString:GetStringHeight() or 14
    return math.max(minimum or 14, math.ceil(tonumber(height) or 14))
end

local function dim(fontString, on, normal)
    T.Tint(fontString, "SetTextColor", on and (normal or "text") or "disabledText")
end

----------------------------------------------------------------------
-- Choice menu: one shared popup per view, filled when it opens.
----------------------------------------------------------------------
function C.OpenMenu(v, owner, options, current, choose)
    local menu = v.menu
    if not menu then
        menu = CreateFrame("Frame", nil, v.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        T.Panel(menu, "surface")
        menu.rows = {}
        menu:Hide()
        v.popups[#v.popups + 1] = menu
        v.menu = menu
    end
    if menu:IsShown() and menu.owner == owner then menu:Hide(); return end
    v:ClosePopups()
    menu.owner = owner
    local width = math.max(120, owner:GetWidth() or 200)
    for index, option in ipairs(options) do
        local row = menu.rows[index]
        if not row then
            row = T.Button(menu, "", width - 12, 24, function(self)
                menu:Hide()
                if self.choose then self.choose(self.value) end
            end, "secondary")
            menu.rows[index] = row
        end
        row:SetWidth(width - 12)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -6 - (index - 1) * 26)
        row.value, row.choose = option[1], choose
        row:SetText(option[1] == current and ("|cff" .. T.PaletteHex("gold") .. option[2] .. "|r") or option[2])
        row:Show()
    end
    for index = #options + 1, #menu.rows do menu.rows[index]:Hide() end
    menu:SetSize(width, #options * 26 + 10)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

-- A dropdown button. `options` is a list of {value, label} or a function returning one.
function C.Dropdown(v, parent, width, options, get, set, fallback)
    local button = T.Button(parent, "", width, 26, nil, "secondary")
    T.StyleDropdown(button)
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local function list() return type(options) == "function" and options() or options end
    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            if fallback ~= nil and get() ~= fallback then set(fallback); v:Changed() end
            return
        end
        C.OpenMenu(v, self, list(), get(), function(value)
            if value ~= get() then set(value); v:Changed() end
        end)
    end)
    function button:Caption()
        local current = get()
        for _, option in ipairs(list()) do
            if option[1] == current then return option[2] end
        end
        return tr("Keine Auswahl", "No selection")
    end
    v:AddUpdate(function() button:SetText(button:Caption()) end)
    return button
end

----------------------------------------------------------------------
-- Confirmation for anything that overwrites or deletes. One per view.
----------------------------------------------------------------------
function C.Confirm(v, title, text, acceptText, onAccept, variant)
    local d = v.confirm
    if not d then
        d = CreateFrame("Frame", nil, v.frame)
        d:SetAllPoints(v.frame)
        d:SetFrameStrata("FULLSCREEN_DIALOG")
        d:EnableMouse(true)
        local shade = d:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints()
        shade:SetColorTexture(0, 0, 0, .55)
        local box = CreateFrame("Frame", nil, d, BackdropTemplateMixin and "BackdropTemplate" or nil)
        box:SetWidth(440)
        box:SetPoint("CENTER", d, "CENTER", 0, 40)
        T.Panel(box, "surface")
        d.box = box
        d.title = T.Text(box, "", "GameFontNormal", "gold")
        d.title:SetPoint("TOPLEFT", 18, -16)
        d.title:SetWidth(404)
        d.text = T.Text(box, "", "GameFontHighlight", "text")
        d.text:SetPoint("TOPLEFT", 18, -40)
        d.text:SetWidth(404)
        d.accept = T.Button(box, "", 200, 28, function()
            d:Hide()
            if d.action then d.action() end
        end, "primary")
        d.accept:SetPoint("BOTTOMLEFT", 18, 16)
        d.cancel = T.Button(box, tr("Abbrechen", "Cancel"), 140, 28, function() d:Hide() end, "secondary")
        d.cancel:SetPoint("BOTTOMRIGHT", -18, 16)
        d:Hide()
        v.popups[#v.popups + 1] = d
        v.confirm = d
    end
    v:ClosePopups()
    d.title:SetText(title)
    d.text:SetText(text)
    d.accept:SetText(acceptText)
    T.StyleButton(d.accept, variant or "primary")
    d.action = onAccept
    d.box:SetHeight(40 + textHeight(d.text, 16) + 64)
    d:Show()
    return d
end

----------------------------------------------------------------------
-- Form: stacks controls and keeps their position for search jumps.
----------------------------------------------------------------------
local Form = {}
Form.__index = Form

function C.Form(v, page, pageId)
    return setmetatable({v = v, page = page, id = pageId, y = 0, width = C.Width, first = true}, Form)
end

function Form:Anchor(id, y, height)
    if not id then return end
    self.v.anchors[self.id .. ":" .. id] = {page = self.id, y = -y, height = height}
end

function Form:Space(amount) self.y = self.y - (amount or 10) end

function Form:Text(text, x, width, font, color)
    local f = T.Text(self.page, text, font or "GameFontHighlightSmall", color or "dim")
    f:SetPoint("TOPLEFT", x or 0, self.y)
    f:SetWidth(width or (self.width - (x or 0)))
    return f, textHeight(f)
end

function Form:Section(spec)
    if not self.first then self.y = self.y - 16 end
    self.first = false
    local top = self.y
    W.Section(self.page, C.Pick(spec.title), self.y, self.width)
    self.y = self.y - 28
    if spec.desc then
        local _, height = self:Text(C.Pick(spec.desc))
        self.y = self.y - height - 8
    end
    self:Anchor(spec.id, top, top - self.y)
end

function Form:Note(spec)
    local x = spec.indent and C.Indent or 0
    local text = type(spec.text) == "function" and "" or C.Pick(spec.text)
    local f, height = self:Text(text, x, nil, spec.font, spec.color)
    if type(spec.text) == "function" then
        height = spec.height or height
        f:SetHeight(height)
        self.v:AddUpdate(function() f:SetText(spec.text() or "") end)
    end
    if spec.ref then self.v[spec.ref] = f end
    self.y = self.y - height - 8
    return f
end

function Form:Toggle(spec)
    local v, p = self.v, self.page
    local x = (spec.parent or spec.indent) and C.Indent or 0
    local top = self.y
    local get, set = binding(v, spec)
    local enabled = enabledFn(v, spec)
    local check = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, top)
    T.StyleCheckbox(check)
    local title = T.Text(p, C.Pick(spec.title), "GameFontHighlight", "text")
    title:SetPoint("TOPLEFT", x + 30, top - 5)
    title:SetWidth(self.width - x - 30)
    local height = 26
    local desc
    if spec.desc then
        desc = T.Text(p, C.Pick(spec.desc), "GameFontHighlightSmall", "dim")
        desc:SetPoint("TOPLEFT", x + 30, top - 23)
        desc:SetWidth(self.width - x - 30)
        height = 24 + textHeight(desc) + 2
    end
    local function apply(value)
        set(value)
        if spec.change then spec.change(value) end
        v:Changed()
    end
    check:SetScript("OnClick", function(self) apply(self:GetChecked() == true) end)
    -- The whole text is part of the switch, as in the game's own settings.
    local hit = CreateFrame("Button", nil, p)
    hit:SetPoint("TOPLEFT", x + 28, top)
    hit:SetSize(self.width - x - 28, height)
    hit:SetScript("OnClick", function()
        if not check:IsEnabled() then return end
        check:SetChecked(not check:GetChecked())
        apply(check:GetChecked() == true)
    end)
    local fallback = default(spec)
    C.Tooltip(hit, C.Pick(spec.title), spec.tip and C.Pick(spec.tip) or (desc and desc:GetText()), function()
        local lines = {}
        if enabled and not enabled() and spec.parentHint then lines[#lines + 1] = C.Pick(spec.parentHint) end
        if type(fallback) == "boolean" then
            lines[#lines + 1] = tr("Standard: ", "Default: ") .. (fallback and tr("An", "On") or tr("Aus", "Off"))
        end
        return table.concat(lines, "\n")
    end)
    v:AddUpdate(function()
        check:SetChecked(get() == true)
        local on = not enabled or enabled()
        check:SetEnabled(on)
        dim(title, on)
        if desc then dim(desc, on, "dim") end
    end)
    v.controls[spec.key or spec.id or tostring(check)] = check
    self.y = top - height - 6
    self:Anchor(spec.id or spec.key, top, height)
    return check
end

local function formatValue(spec, value)
    if spec.format then return spec.format(value) end
    local text = string.format(spec.step < 1 and "%.2f" or "%.0f", value)
    if spec.step < 1 then text = text:gsub("0$", "") end
    if NS.IsGerman() then text = text:gsub("%.", ",") end
    return text .. (spec.suffix or "")
end
C.FormatValue = formatValue

function Form:Slider(spec)
    local v, p = self.v, self.page
    local x = (spec.parent or spec.indent) and C.Indent or 0
    local top = self.y
    local get, set = binding(v, spec)
    local enabled = enabledFn(v, spec)
    local width = math.min(spec.width or 360, self.width - x - 16)
    local title = T.Text(p, C.Pick(spec.title), "GameFontHighlight", "text")
    title:SetPoint("TOPLEFT", x, top - 2)
    title:SetWidth(width - 70)
    local value = T.Text(p, "", "GameFontHighlight", "gold")
    value:SetPoint("TOPLEFT", x + width - 70, top - 2)
    value:SetWidth(70)
    value:SetJustifyH("RIGHT")
    local slider = CreateFrame("Slider", nil, p, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x + 4, top - 24)
    slider:SetSize(width - 8, 16)
    local function upper() return type(spec.max) == "function" and spec.max() or spec.max end
    slider:SetMinMaxValues(spec.min, upper())
    slider:SetValueStep(spec.step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    if slider.Text then slider.Text:SetText("") end
    if slider.Low then slider.Low:SetText(formatValue(spec, spec.min)) end
    if slider.High then slider.High:SetText(formatValue(spec, upper())) end
    local updating = false
    slider:SetScript("OnValueChanged", function(_, raw)
        if updating then return end
        local rounded = math.max(spec.min, math.min(upper(), math.floor(raw / spec.step + .5) * spec.step))
        if rounded ~= get() then set(rounded); v:Changed() end
    end)
    local fallback = default(spec)
    slider:HookScript("OnMouseUp", function(_, mouse)
        if mouse == "RightButton" and fallback ~= nil and (not enabled or enabled()) then set(fallback); v:Changed() end
    end)
    C.Tooltip(slider, C.Pick(spec.title), spec.tip and C.Pick(spec.tip), function()
        if fallback == nil then return "" end
        return string.format(tr("Standard: %s  ·  Rechtsklick stellt ihn wieder her.", "Default: %s  ·  Right-click restores it."), formatValue(spec, fallback))
    end)
    local height = 54
    local desc
    if spec.desc then
        desc = T.Text(p, C.Pick(spec.desc), "GameFontHighlightSmall", "dim")
        desc:SetPoint("TOPLEFT", x, top - 54)
        desc:SetWidth(self.width - x)
        height = height + textHeight(desc) + 2
    end
    v:AddUpdate(function()
        local current = tonumber(get()) or spec.min
        updating = true
        slider:SetMinMaxValues(spec.min, upper())
        slider:SetValue(current)
        updating = false
        if slider.High then slider.High:SetText(formatValue(spec, upper())) end
        value:SetText(formatValue(spec, current))
        local on = not enabled or enabled()
        if slider.SetEnabled then slider:SetEnabled(on) elseif on then slider:Enable() else slider:Disable() end
        dim(title, on)
        T.Tint(value, "SetTextColor", on and "gold" or "disabledText")
        if desc then dim(desc, on, "dim") end
    end)
    v.controls[spec.key or spec.id or tostring(slider)] = slider
    self.y = top - height - 6
    self:Anchor(spec.id or spec.key, top, height)
    return slider
end

function Form:Choice(spec)
    local v, p = self.v, self.page
    local x = (spec.parent or spec.indent) and C.Indent or 0
    local top = self.y
    local get, set = binding(v, spec)
    local enabled = enabledFn(v, spec)
    local title = T.Text(p, C.Pick(spec.title), "GameFontHighlight", "text")
    title:SetPoint("TOPLEFT", x, top - 6)
    title:SetWidth(C.Column - x - 10)
    local options = spec.options
    if type(options) == "table" then
        local resolved = {}
        for index, option in ipairs(options) do resolved[index] = {option[1], C.Pick(option[2])} end
        options = resolved
    end
    local button = C.Dropdown(v, p, spec.width or 260, options, get, set, default(spec))
    button:SetPoint("TOPLEFT", C.Column, top)
    local fallback = default(spec)
    C.Tooltip(button, C.Pick(spec.title), spec.tip and C.Pick(spec.tip), function()
        if fallback == nil then return "" end
        for _, option in ipairs(type(options) == "function" and options() or options) do
            if option[1] == fallback then
                return string.format(tr("Standard: %s  ·  Rechtsklick stellt ihn wieder her.", "Default: %s  ·  Right-click restores it."), option[2])
            end
        end
        return ""
    end)
    local height = 28
    local desc
    if spec.desc then
        desc = T.Text(p, C.Pick(spec.desc), "GameFontHighlightSmall", "dim")
        desc:SetPoint("TOPLEFT", x, top - 30)
        desc:SetWidth(self.width - x)
        height = 30 + textHeight(desc)
    end
    v:AddUpdate(function()
        local on = not enabled or enabled()
        button:SetEnabled(on)
        dim(title, on)
        if desc then dim(desc, on, "dim") end
    end)
    v.controls[spec.key or spec.id or tostring(button)] = button
    self.y = top - height - 8
    self:Anchor(spec.id or spec.key, top, height)
    return button
end

-- A row of action buttons. Each: {text, action, variant, width, tip, enabled = fn, ref}.
function Form:Buttons(list, indent)
    local v, p = self.v, self.page
    local x = indent and C.Indent or 0
    local start = x
    for _, spec in ipairs(list) do
        local width = spec.width or 180
        if x > start and x + width > self.width then
            x = start
            self.y = self.y - 32
        end
        local button = T.Button(p, C.Pick(spec.text), width, 26, function() spec.action(v) end, spec.variant or "secondary")
        button:SetPoint("TOPLEFT", x, self.y)
        if spec.tip then C.Tooltip(button, C.Pick(spec.text), C.Pick(spec.tip)) end
        if spec.enabled then v:AddUpdate(function() button:SetEnabled(spec.enabled() == true) end) end
        if spec.ref then v[spec.ref] = button end
        x = x + width + 8
    end
    self.y = self.y - 36
end

----------------------------------------------------------------------
-- Tiles for the overview: a switch tile and a navigation tile. Same binding rules as Toggle.
----------------------------------------------------------------------
C.TileHeight = 92
C.NavTileHeight = 58

-- spec: key | get/set, title, desc, enabled (fn), blocked (fn -> reason text or nil), open (fn), openTip
function C.SwitchTile(v, parent, width, spec)
    local get, set = binding(v, spec)
    local blocked = spec.blocked or function() return nil end
    local tile = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    tile:SetSize(width, C.TileHeight)
    T.Panel(tile, "surface")
    local check = CreateFrame("CheckButton", nil, tile, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 10, -10)
    T.StyleCheckbox(check)
    local title = T.Text(tile, C.Pick(spec.title), "GameFontHighlight", "text")
    title:SetPoint("TOPLEFT", 40, -15)
    title:SetWidth(width - 50)
    title:SetWordWrap(false)
    local desc = T.Text(tile, C.Pick(spec.desc), "GameFontHighlightSmall", "dim")
    desc:SetPoint("TOPLEFT", 40, -35)
    desc:SetWidth(width - 50)
    desc:SetHeight(26)
    local status = T.Text(tile, "", "GameFontHighlightSmall", "muted")
    status:SetPoint("BOTTOMLEFT", 40, 12)
    status:SetWidth(width - 50 - (spec.open and 108 or 0))
    status:SetWordWrap(false)
    local function usable() return blocked() == nil end
    local function apply(value)
        set(value)
        if spec.change then spec.change(value) end
        v:Changed()
    end
    check:SetScript("OnClick", function(self) apply(self:GetChecked() == true) end)
    -- The whole tile is the switch; the settings button keeps its own click.
    tile:SetScript("OnClick", function()
        if not usable() then return end
        check:SetChecked(not check:GetChecked())
        apply(check:GetChecked() == true)
    end)
    if spec.open then
        local open = T.Button(tile, tr("Einstellen", "Configure"), 100, 22, function() spec.open(v) end, "secondary")
        open:SetPoint("BOTTOMRIGHT", -8, 8)
        C.Tooltip(open, tr("Einstellen", "Configure"), spec.openTip and C.Pick(spec.openTip)
            or tr("Öffnet die Seite mit allen Optionen zu dieser Funktion.", "Opens the page with all options for this feature."))
        tile.open = open
    end
    C.Tooltip(tile, C.Pick(spec.title), spec.tip and C.Pick(spec.tip) or C.Pick(spec.desc), function() return blocked() or "" end)
    v:AddUpdate(function()
        local reason = blocked()
        local on = get() == true
        check:SetChecked(on and reason == nil)
        check:SetEnabled(reason == nil)
        dim(title, reason == nil)
        dim(desc, reason == nil, "dim")
        if reason then
            status:SetText(reason)
            T.Tint(status, "SetTextColor", "disabledText")
        else
            status:SetText(on and tr("Aktiv", "Active") or tr("Aus", "Off"))
            T.Tint(status, "SetTextColor", on and "toastText" or "muted")
        end
    end)
    tile.check, tile.status = check, status
    v.controls[spec.id or spec.key] = check
    return tile
end

-- spec: title, desc, icon, action (fn(v)), status (fn -> text, optional)
function C.NavTile(v, parent, width, spec)
    local tile = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    tile:SetSize(width, C.NavTileHeight)
    T.Panel(tile, "surface")
    local x = 12
    if spec.icon then
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexture(spec.icon)
        if icon.SetTexCoord then icon:SetTexCoord(.08, .92, .08, .92) end
        x = 44
    end
    local title = T.Text(tile, C.Pick(spec.title), "GameFontNormal", "gold")
    title:SetPoint("TOPLEFT", x, -12)
    title:SetWidth(width - x - 10)
    title:SetWordWrap(false)
    local sub = T.Text(tile, C.Pick(spec.desc), "GameFontHighlightSmall", "textSoft")
    sub:SetPoint("TOPLEFT", x, -32)
    sub:SetWidth(width - x - 10)
    sub:SetWordWrap(false)
    tile:SetScript("OnClick", function() spec.action(v) end)
    C.Tooltip(tile, C.Pick(spec.title), C.Pick(spec.tip or spec.desc), tr("Klicken zum Öffnen.", "Click to open."))
    if spec.status then v:AddUpdate(function() sub:SetText(spec.status() or C.Pick(spec.desc)) end) end
    return tile
end

-- Free-form part of a page: build(form) places its frames from form.y down and moves form.y.
function Form:Custom(spec)
    local top = self.y
    spec.build(self, self.v, self.page)
    self:Anchor(spec.id, top, top - self.y)
end

function Form:Render(nodes)
    for _, node in ipairs(nodes) do
        if node.show == nil or node.show() then
            local kind = node.kind
            if kind == "section" then self:Section(node)
            elseif kind == "toggle" then self:Toggle(node)
            elseif kind == "slider" then self:Slider(node)
            elseif kind == "choice" then self:Choice(node)
            elseif kind == "buttons" then self:Buttons(node.buttons, node.indent)
            elseif kind == "note" then self:Note(node)
            elseif kind == "custom" then self:Custom(node)
            elseif kind == "space" then self:Space(node.height) end
        end
    end
    return -self.y + 16
end
