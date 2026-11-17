local _, NS = ...
-- What the settings pages need besides the shared Form: the text pick for {German, English} pairs and the
-- two tiles of the overview (a switch tile and a navigation tile). Every ordinary control is a row of the
-- shared Form (NS.Form); the tiles are free drawing inside a Form:Custom row, painted with the shared skin.
-- A tile reads and writes through get/set (default: the setting `key`), like a Form row, and is refreshed by
-- the page through v:AddUpdate.
local C = {}
NS.SettingsControls = C
local T, tr, Form = NS.Theme, NS.Text, NS.Form

C.Indent = 28

function C.Pick(value)
    if type(value) == "table" then return tr(value[1], value[2]) end
    return value
end

local function binding(spec)
    local get = spec.get or function() return NS.App.db[spec.key] end
    local set = spec.set or function(value) NS.App.db[spec.key] = value end
    return get, set
end

local function dim(fontString, on, normal)
    T.Tint(fontString, "SetTextColor", on and (normal or "text") or "disabledText")
end

C.TileHeight = 92
C.NavTileHeight = 58

-- spec: key | get/set, title, desc, enabled (fn), blocked (fn -> reason text or nil), open (fn), openTip
function C.SwitchTile(v, parent, width, spec)
    local get, set = binding(spec)
    local blocked = spec.blocked or function() return nil end
    local tile = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    tile:SetSize(width, C.TileHeight)
    T.Panel(tile, "inset")
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
        Form.Tooltip(open, tr("Einstellen", "Configure"), spec.openTip and C.Pick(spec.openTip)
            or tr("Öffnet die Seite mit allen Optionen zu dieser Funktion.", "Opens the page with all options for this feature."))
        tile.open = open
    end
    Form.Tooltip(tile, C.Pick(spec.title), spec.tip and C.Pick(spec.tip) or C.Pick(spec.desc), function() return blocked() or "" end)
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

-- spec: title, desc, icon (name in the icon atlas), action (fn(v)), status (fn -> text, optional)
function C.NavTile(v, parent, width, spec)
    local tile = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    tile:SetSize(width, C.NavTileHeight)
    T.Panel(tile, "inset")
    local x = 12
    if spec.icon then
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 10, 0)
        T.SetIcon(icon, spec.icon, "gold")
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
    Form.Tooltip(tile, C.Pick(spec.title), C.Pick(spec.tip or spec.desc), tr("Klicken zum Öffnen.", "Click to open."))
    if spec.status then v:AddUpdate(function() sub:SetText(spec.status() or C.Pick(spec.desc)) end) end
    return tile
end
