local _, NS = ...
local W = {}
NS.Widgets = W
local T = NS.Theme

-- Utility-local text palette override. Keep the shared Theme.lua in sync with
-- other addons; only Utility needs these brighter settings colors.
local function paletteColor(hex)
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
    return {tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, 1}
end
T.palette.text = paletteColor("#fbf6e8")
T.palette.textSoft = paletteColor("#e9e1cc")
T.palette.dim = paletteColor("#cfc5ad")
T.palette.muted = paletteColor("#b9af95")
T.palette.disabledText = paletteColor("#928973")
T.colors.text = {T.PaletteColor("text")}
T.colors.muted = {T.PaletteColor("dim")}

function T.Text(parent, value, font, textColor)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    f:SetText(value or "")
    f:SetJustifyH("LEFT")
    f:SetJustifyV("TOP")
    local key = textColor or "text"
    if T.palette[key] then
        T.Tint(f, "SetTextColor", key)
    else
        local c = T.colors[key] or T.colors.surface
        f:SetTextColor(c[1], c[2], c[3], c[4])
    end
    return f
end

function W.CloseButton(parent, action)
    local ok, button = pcall(CreateFrame, "Button", nil, parent, "UIPanelCloseButton")
    if not ok or type(button) ~= "table" or not button.SetPoint then
        button = T.Button(parent, "×", 28, 28, action)
    end
    button:SetPoint("TOPRIGHT", -5, -5)
    button:SetScript("OnClick", action)
    return button
end

function W.Edit(parent, x, y, width, changed)
    local edit = CreateFrame("EditBox", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    edit:SetSize(width, 28)
    edit:SetPoint("TOPLEFT", x, y)
    edit:SetFontObject("GameFontHighlight")
    edit:EnableMouse(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(120)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    T.StyleEditBox(edit)
    if changed then
        edit:SetScript("OnTextChanged", function(self, user) if user then changed(self:GetText()) end end)
    end
    return edit
end

-- Thin gold section heading with a line underneath: the one structural element every page shares.
function W.Section(parent, title, y, width)
    local text = T.Text(parent, title, "GameFontNormal", "gold")
    text:SetPoint("TOPLEFT", 0, y)
    text:SetWidth(width or 552)
    local line = T.Divider(parent)
    line:SetPoint("TOPLEFT", 0, y - 19)
    line:SetWidth(width or 552)
    return text, line
end

function W.Tooltip(frame, title, body)
    frame:EnableMouse(true)
    frame:HookScript("OnEnter", function(self)
        local tip = _G.GameTooltip
        if not tip or not tip.SetOwner then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(title)
        if body and body ~= "" then tip:AddLine(body, 1, 1, 1, true) end
        tip:Show()
    end)
    frame:HookScript("OnLeave", function()
        local tip = _G.GameTooltip
        if tip and tip.Hide then tip:Hide() end
    end)
end

-- Rail outside the clipped viewport, as in the other ZENIAL windows: Blizzard's unnamed
-- scroll template did not show a visible bar in the Forever client.
function W.ScrollBar(scroll, step)
    T.StyleScroll(scroll)
    -- StyleScroll brings its own inner slider for scroll frames without a rail. Here the rail is the only bar.
    if scroll.zenialScrollBar then
        scroll.zenialScrollBar:Hide()
        scroll.zenialScrollBar = nil
    end
    local rail = CreateFrame("Frame", nil, scroll:GetParent(), BackdropTemplateMixin and "BackdropTemplate" or nil)
    rail:SetWidth(16)
    rail:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    rail:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    rail:SetFrameLevel(scroll:GetFrameLevel() + 3)
    T.Panel(rail, "inset")
    local bar = CreateFrame("Slider", nil, rail)
    bar:SetPoint("TOPLEFT", 2, -16)
    bar:SetPoint("BOTTOMRIGHT", -2, 16)
    bar:SetOrientation("VERTICAL")
    bar:EnableMouse(true)
    bar:SetValueStep(1)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    T.Tint(thumb, "SetColorTexture", "goldDim")
    thumb:SetSize(10, 24)
    bar:SetThumbTexture(thumb)
    local up = CreateFrame("Button", nil, rail)
    up:SetSize(16, 16)
    up:SetPoint("TOP")
    up:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    local down = CreateFrame("Button", nil, rail)
    down:SetSize(16, 16)
    down:SetPoint("BOTTOM")
    down:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    local updating = false
    local function refresh()
        if updating then return end
        updating = true
        local maximum = math.max(0, scroll:GetVerticalScrollRange() or 0)
        local current = scroll:GetVerticalScroll() or 0
        local value = math.max(0, math.min(maximum, current))
        if value ~= current then scroll:SetVerticalScroll(value) end
        bar:SetMinMaxValues(0, maximum)
        bar:SetValue(value)
        local viewport = math.max(1, scroll:GetHeight())
        local track = math.max(1, viewport - 32)
        thumb:SetHeight(math.min(track, math.max(18, track * viewport / (viewport + maximum))))
        up:SetEnabled(value > 0)
        down:SetEnabled(value < maximum)
        up:SetAlpha(value > 0 and 1 or .3)
        down:SetAlpha(value < maximum and 1 or .3)
        rail:SetShown(scroll:IsShown() and maximum > 0)
        updating = false
    end
    local function move(value)
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange() or 0, value)))
        refresh()
    end
    bar:SetScript("OnValueChanged", function(_, value) if not updating then move(value) end end)
    up:SetScript("OnClick", function() move((scroll:GetVerticalScroll() or 0) - step) end)
    down:SetScript("OnClick", function() move((scroll:GetVerticalScroll() or 0) + step) end)
    local function wheel(_, delta) move((scroll:GetVerticalScroll() or 0) - delta * step) end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", wheel)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", wheel)
    scroll:HookScript("OnVerticalScroll", refresh)
    scroll:HookScript("OnScrollRangeChanged", refresh)
    scroll:HookScript("OnSizeChanged", refresh)
    scroll:HookScript("OnShow", refresh)
    scroll:HookScript("OnHide", function() rail:Hide() end)
    scroll.RefreshScrollbar = refresh
    refresh()
end
