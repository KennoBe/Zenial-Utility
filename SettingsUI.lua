local _, NS = ...
-- The settings window: sidebar, page header, scrolling page and the search across all pages.
-- What each page contains is declared in SettingsPages.lua; the controls live in SettingsControls.lua.
local U = {views = {}, builders = {}, fixed = {}, Pages = {}, ById = {}, Order = {}, Titles = {}, KeyTitles = {}}
NS.SettingsUI = U
local T, tr, A, W = NS.Theme, NS.Text, NS.Adapter, NS.Widgets

local WIDTH, HEIGHT, SIDEBAR = 900, 680, 196
local NAV_TOP = -84
-- Inside the ZENIAL Community addon manager (856-pixel logical canvas, at least 464 high) the same
-- sidebar layout is used, only narrower and without the window's title bar.
local EMBED_SIDEBAR, EMBED_NAV_TOP, EMBED_TOP = 176, -12, -40

-- Old page names keep working for /zutil <page> and for links from other addons.
U.Aliases = {
    merchant = "loot", extras = "comfort", inventory = "comfort", warnings = "interface",
    characters = "advanced", profiles = "advanced", setup = "advanced",
}

local function db() return NS.App.db end
local function pick(value) return NS.SettingsControls.Pick(value) end

function U.Resolve(id)
    id = U.Aliases[id] or id
    return U.ById[id] and id or nil
end

-- Pages register in order. Called from SettingsPages.lua while the files load.
function U.AddPage(def)
    U.Pages[#U.Pages + 1] = def
    U.ById[def.id] = def
    U.Order[#U.Order + 1] = def.id
    U.Titles[def.id] = pick(def.title)
end

-- Kept for older page code; the search now reads the schema instead of page texts.
function U.Note() end

----------------------------------------------------------------------
-- Search index from the schema. Built once; searching never builds a page.
----------------------------------------------------------------------
function U.BuildIndex()
    local S = NS.SettingsSearch
    S.Clear()
    for _, def in ipairs(U.Pages) do
        S.Add({kind = "page", page = def.id, title = def.title, desc = def.desc, keywords = def.keywords})
        local section
        local function add(entry, id)
            entry.page, entry.id, entry.section = def.id, id, section and section.title
            S.Add(entry)
        end
        for _, node in ipairs(def.nodes or {}) do
            if node.kind == "section" then
                section = node
                add({kind = "section", title = node.title, desc = node.desc, keywords = node.keywords}, node.id)
            elseif node.kind == "toggle" or node.kind == "slider" or node.kind == "choice" then
                local id = node.id or node.key
                add({kind = node.kind, title = node.title, desc = node.desc or node.tip, keywords = node.keywords}, id)
                if node.key then U.KeyTitles[node.key] = node.title end
            elseif node.kind == "buttons" then
                for _, button in ipairs(node.buttons) do
                    add({kind = "action", title = button.text, desc = button.tip, keywords = button.keywords}, section and section.id)
                end
            end
            for _, extra in ipairs(node.search or {}) do
                add({kind = "custom", title = extra.title, desc = extra.desc, keywords = extra.keywords}, extra.id or node.id or (section and section.id))
            end
        end
        for _, extra in ipairs(def.search or {}) do
            section = nil
            add({kind = "custom", title = extra.title, desc = extra.desc, keywords = extra.keywords}, extra.id)
        end
    end
end

-- The setting keys a page's "Restore defaults" covers.
function U.ResetKeys(def)
    local keys, seen = {}, {}
    local function add(key) if key and not seen[key] then seen[key] = true; keys[#keys + 1] = key end end
    for _, node in ipairs(def.nodes or {}) do
        if node.key and node.reset ~= false then add(node.key) end
    end
    for _, key in ipairs(def.resetKeys or {}) do add(key) end
    return keys
end

function U.KeyTitle(key) return pick(U.KeyTitles[key]) or key end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local function savePosition(f)
    local point, _, relative, x, y = f:GetPoint(1)
    if type(point) == "string" and type(x) == "number" and type(y) == "number" then
        db().settingsWindow = {point = point, relative = relative or point, x = x, y = y}
    end
end

local function restorePosition(f)
    local saved = db().settingsWindow
    f:ClearAllPoints()
    if type(saved) == "table" and type(saved.point) == "string" and type(saved.x) == "number" and type(saved.y) == "number" then
        f:SetPoint(saved.point, UIParent, type(saved.relative) == "string" and saved.relative or saved.point, saved.x, saved.y)
    else
        f:SetPoint("CENTER")
    end
end

-- Small screens or a large UI scale: the window shrinks so it always fits completely.
local function fitScale(f)
    local h, w = UIParent:GetHeight() or 0, UIParent:GetWidth() or 0
    if h > 0 and w > 0 then f:SetScale(math.min(1, (h - 40) / HEIGHT, (w - 40) / WIDTH)) end
end

function U.ResetWindow()
    db().settingsWindow = {}
    if U.standalone then
        local f = U.standalone.frame
        restorePosition(f)
        fitScale(f)
    end
end

local function navButton(v, f, def, width)
    local id = def.id
    local button = T.Button(f, pick(def.title), width, 28, function() v:SelectPage(id) end, "secondary")
    T.StyleNav(button, def.icon)
    -- The label starts right of the icon instead of centred over it; a long name
    -- switches to the smaller font rather than running into the icon or the edge.
    local label = button.GetFontString and button:GetFontString()
    if label and def.icon then
        label:ClearAllPoints()
        label:SetPoint("LEFT", 36, 0)
        label:SetPoint("RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        if label.SetWordWrap then label:SetWordWrap(false) end
        local room = button:GetWidth() - 44
        if (label:GetStringWidth() or 0) > room then
            -- The template swaps fonts on hover, so the button's own font objects change.
            if button.SetNormalFontObject then button:SetNormalFontObject("GameFontNormalSmall") end
            if button.SetHighlightFontObject then button:SetHighlightFontObject("GameFontHighlightSmall") end
            if button.SetDisabledFontObject then button:SetDisabledFontObject("GameFontDisableSmall") end
            label:SetFontObject("GameFontNormalSmall")
        end
    end
    W.Tooltip(button, pick(def.title), pick(def.desc))
    return button
end

function U.Create(parent, embedded)
    local C = NS.SettingsControls
    local f = CreateFrame("Frame", not embedded and "ZenialUtilitySettings" or nil, parent or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if embedded then
        f:SetAllPoints(parent)
    else
        f:SetSize(WIDTH, HEIGHT)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self) end)
        T.Shell(f)
        restorePosition(f)
        UISpecialFrames[#UISpecialFrames + 1] = "ZenialUtilitySettings"
    end
    local v = NS.ConfigWizard.New({store = {}})
    v.frame, v.embedded, v.draft = f, embedded, NS.App.db
    v.anchors = {}
    function v:Changed() NS.App.db = self.draft; NS.App:Changed() end

    local sidebar = embedded and EMBED_SIDEBAR or SIDEBAR
    local sideX = embedded and 0 or 14
    local navTop = embedded and EMBED_NAV_TOP or NAV_TOP
    local left = embedded and sideX + sidebar + 20 or SIDEBAR + 32
    local top = embedded and EMBED_TOP or NAV_TOP

    -- Title bar
    if not embedded then
        local heading = T.Text(f, "ZENIAL UTILITY", "GameFontNormalLarge", "gold")
        heading:SetPoint("TOPLEFT", 24, -28)
        local version = A.Call(_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata, "ZenialUtility", "Version")
        local sub = T.Text(f, tr("Einstellungen", "Settings") .. (type(version) == "string" and ("  ·  " .. version) or ""), "GameFontHighlightSmall", "muted")
        sub:SetPoint("TOPLEFT", 26, -48)
        v.close = W.CloseButton(f, function() f:Hide() end)
    end
    -- Sidebar
    local side = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    side:SetPoint("TOPLEFT", sideX, navTop + 8)
    side:SetPoint("BOTTOMLEFT", sideX, embedded and 0 or 14)
    side:SetWidth(sidebar)
    T.Panel(side, "inset")

    -- Navigation, with small group headings in the sidebar.
    v.nav = {}
    local y, lastGroup = navTop, nil
    for _, def in ipairs(U.Pages) do
        local button = navButton(v, f, def, sidebar - 24)
        if def.group and def.group ~= lastGroup then
            if lastGroup then y = y - 6 end
            local label = T.Text(f, pick(def.group), "GameFontHighlightSmall", "muted")
            label:SetPoint("TOPLEFT", sideX + 14, y - 4)
            y = y - 20
            lastGroup = def.group
        end
        button:SetPoint("TOPLEFT", sideX + 12, y)
        y = y - 30
        v.nav[def.id] = button
    end

    -- Page header: title, one-line description, restore defaults.
    local headerWidth = (embedded and 856 or WIDTH) - left - 40
    v.pageTitle = T.Text(f, "", "GameFontNormalLarge", "gold")
    v.pageTitle:SetPoint("TOPLEFT", left, top)
    v.pageTitle:SetWidth(headerWidth - 220)
    v.pageDesc = T.Text(f, "", "GameFontHighlightSmall", "textSoft")
    v.pageDesc:SetPoint("TOPLEFT", left, top - 24)
    v.pageDesc:SetWidth(headerWidth)
    v.pageDesc:SetHeight(28)
    v.resetPage = T.Button(f, tr("Standardwerte wiederherstellen", "Restore defaults"), 220, 24, function() U.ConfirmPageReset(v) end, "secondary")
    v.resetPage:SetPoint("TOPRIGHT", embedded and -20 or -40, top + 2)
    W.Tooltip(v.resetPage, tr("Standardwerte wiederherstellen", "Restore defaults"),
        tr("Setzt nur die Einstellungen dieser Seite zurück. Vorher wird nachgefragt.", "Resets only the settings on this page. You are asked first."))
    local divider = T.Divider(f)
    divider:SetPoint("TOPLEFT", left, top - 56)
    divider:SetPoint("TOPRIGHT", embedded and -16 or -24, top - 56)
    local bodyTop = top - 66
    local bottom = embedded and 24 or 40

    -- Footer: result of the last action, autosave note.
    v.message = T.Text(f, "", "GameFontHighlightSmall", "gold")
    v.message:SetPoint("BOTTOMLEFT", left, embedded and 6 or 16)
    v.message:SetWidth(embedded and 380 or 420)
    v.footer = T.Text(f, "", "GameFontHighlightSmall", "muted")
    v.footer:SetPoint("BOTTOMRIGHT", embedded and -20 or -28, embedded and 6 or 16)
    v.footer:SetWidth(260)
    v.footer:SetJustifyH("RIGHT")
    function v:SetMessage(message) self.message:SetText(message or "") end

    -- Scrolling page area and the fixed area for the list pages (macros, UI profiles, graphics).
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", left, bodyTop)
    scroll:SetPoint("BOTTOMRIGHT", -44, bottom)
    v.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(C.Width + 12, 500)
    scroll:SetScrollChild(content)
    v.content = content
    W.ScrollBar(scroll, 40)
    local fixed = CreateFrame("Frame", nil, f)
    fixed:SetPoint("TOPLEFT", left, bodyTop)
    fixed:SetPoint("BOTTOMRIGHT", embedded and -16 or -24, bottom)
    fixed:Hide()
    v.fixedHost = fixed

    -- Search box: top right, in the title bar of the own window or above the page header when embedded.
    local search = W.Edit(f, 0, 0, 260, function(text) U.ShowSearch(v, text) end)
    search:ClearAllPoints()
    search:SetPoint("TOPRIGHT", embedded and -20 or -52, embedded and -6 or -24)
    W.Tooltip(search, tr("Einstellungen suchen", "Search settings"),
        tr("Durchsucht alle Seiten, auf Deutsch und Englisch. Enter öffnet den ersten Treffer.", "Searches every page, in German and English. Enter opens the first match."))
    search:SetScript("OnEnterPressed", function(self)
        local first = v.searchResults.rows[1]
        if v.searchResults:IsShown() and first:IsShown() then first:Click() end
        self:ClearFocus()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); U.ShowSearch(v, ""); self:ClearFocus() end)
    v.search = search
    v.searchHint = T.Text(search, tr("Einstellung suchen …", "Search settings …"), "GameFontHighlightSmall", "muted")
    v.searchHint:SetPoint("LEFT", 8, 0)
    local results = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    results:SetSize(420, 40)
    results:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -2)
    results:SetFrameStrata("FULLSCREEN_DIALOG")
    results:EnableMouse(true)
    T.Panel(results, "surface")
    results:Hide()
    v.searchResults = results
    results.rows = {}
    for index = 1, 8 do
        local row = T.Button(results, "", 404, 26, function(self)
            results:Hide()
            v.search:SetText("")
            v.searchHint:Show()
            v:Jump(self.page, self.anchor)
        end, "secondary")
        row:SetPoint("TOPLEFT", 8, -6 - (index - 1) * 28)
        row.where = T.Text(row, "", "GameFontHighlightSmall", "muted")
        row.where:SetPoint("RIGHT", -10, 0)
        row.where:SetWidth(150)
        row.where:SetJustifyH("RIGHT")
        row.where:SetJustifyV("MIDDLE")
        row:Hide()
        results.rows[index] = row
    end
    results.empty = T.Text(results, "", "GameFontHighlightSmall", "textSoft")
    results.empty:SetPoint("TOPLEFT", 12, -10)
    results.empty:SetWidth(396)
    results.more = T.Text(results, "", "GameFontHighlightSmall", "muted")
    results.more:SetPoint("BOTTOMLEFT", 12, 8)
    results.more:SetWidth(396)
    v.popups[#v.popups + 1] = results

    function v:SelectPage(id)
        id = U.Resolve(id) or "overview"
        self:CloseTransient()
        self.index, self.draft = id, NS.App.db
        self:SetMessage("")
        for _, page in pairs(self.pages) do
            page:Hide()
            if page.flash then page.flash:Hide() end
        end
        local def = U.ById[id]
        local isFixed = def.fixed == true
        self:BuildPage(id)
        self.pages[id]:Show()
        scroll:SetShown(not isFixed)
        fixed:SetShown(isFixed)
        if not isFixed then
            self.content:SetHeight(self.pages[id].height + 24)
            scroll:SetVerticalScroll(0)
            scroll:UpdateScrollChildRect()
            scroll:RefreshScrollbar()
        end
        self.pageTitle:SetText(pick(def.heading or def.title))
        self.pageDesc:SetText(pick(def.desc) or "")
        self.resetPage:SetShown(#U.ResetKeys(def) > 0 or def.resetExtra ~= nil)
        for key, button in pairs(self.nav) do T.SetSelected(button, key == id) end
        self:Refresh()
    end
    function v:BuildPage(id)
        if self.pages[id] then return end
        local def = U.ById[id]
        local index = self.index
        self.index = id
        self.updates[id] = {}
        if def.fixed then
            local page = CreateFrame("Frame", nil, fixed)
            page:SetAllPoints(fixed)
            self.pages[id] = page
            U.fixed[id](self, page)
        else
            local page = CreateFrame("Frame", nil, self.content)
            page:SetPoint("TOPLEFT", 6, -8)
            page:SetWidth(C.Width)
            self.pages[id] = page
            page.height = C.Form(self, page, id):Render(def.nodes)
            page:SetHeight(page.height)
        end
        self.pages[id]:Hide()
        self.index = index
    end
    -- Opens a page and brings one setting into view with a short highlight.
    function v:Jump(id, anchor)
        self:SelectPage(id)
        id = self.index
        local spot = anchor and self.anchors[id .. ":" .. anchor]
        local page = self.pages[id]
        if not spot or U.ById[id].fixed then return end
        local range = scroll:GetVerticalScrollRange() or 0
        scroll:SetVerticalScroll(math.max(0, math.min(range, spot.y - 24)))
        scroll:RefreshScrollbar()
        if not page.flash then
            page.flash = page:CreateTexture(nil, "BACKGROUND")
            T.Tint(page.flash, "SetColorTexture", "gold", .14)
        end
        page.flash:ClearAllPoints()
        page.flash:SetPoint("TOPLEFT", page, "TOPLEFT", -6, -spot.y + 4)
        page.flash:SetSize(C.Width + 12, spot.height + 8)
        page.flash:Show()
        local timer = _G.C_Timer
        if timer and type(timer.After) == "function" then
            local flash = page.flash
            timer.After(1.8, function() flash:Hide() end)
        end
    end
    function v:Search(text)
        local out = {}
        for _, entry in ipairs(NS.SettingsSearch.Find(text, U.Order)) do
            out[#out + 1] = {page = entry.page, text = pick(entry.title), id = entry.id, section = entry.section}
        end
        return out
    end
    function v:RefreshData() U.RefreshPageData(self) end
    function v:Refresh()
        self.draft = NS.App.db
        for _, update in ipairs(self.updates[self.index] or {}) do update() end
        self:RefreshData()
        self.footer:SetText(A.Combat() and tr("Im Kampf sind einige Aktionen gesperrt.", "Some actions are locked in combat.")
            or tr("Änderungen werden sofort gespeichert.", "Changes are saved immediately."))
    end
    f:SetScript("OnShow", function(self)
        if not embedded then fitScale(self) end
        v:Refresh()
    end)
    f:SetScript("OnHide", function() v:CloseTransient() end)
    U.views[#U.views + 1] = v
    v:SelectPage("overview")
    f:Hide()
    return v
end

function U.ConfirmPageReset(v)
    local def = U.ById[v.index]
    local title = pick(def.title)
    NS.SettingsControls.Confirm(v, tr("Standardwerte wiederherstellen?", "Restore defaults?"),
        string.format(tr("Alle Einstellungen auf der Seite „%s“ werden auf die Standardwerte zurückgesetzt. Andere Seiten bleiben unverändert.",
            "All settings on the “%s” page go back to their defaults. Other pages stay as they are."), title),
        tr("Zurücksetzen", "Reset"), function()
            if A.Combat() then v:SetMessage(tr("Im Kampf nicht möglich.", "Not possible in combat.")); return end
            NS.Logic.ResetKeys(db(), U.ResetKeys(def))
            if def.resetExtra then def.resetExtra(db()) end
            v:Changed()
            v:SetMessage(string.format(tr("Standardwerte für „%s“ wiederhergestellt.", "Defaults restored for “%s”."), title))
        end, "danger")
end

function U.ShowSearch(v, text)
    v.searchHint:SetShown(text == "")
    local results = v.searchResults
    local query = (text or ""):match("^%s*(.-)%s*$")
    if query == "" then results:Hide(); return end
    local rows = v:Search(query)
    for index, button in ipairs(results.rows) do
        local row = rows[index]
        button.page, button.anchor = row and row.page, row and row.id
        if row then
            local shown = NS.Logic.TrimUTF8(row.text or "", 46)
            if shown ~= row.text then shown = shown .. "…" end
            button:SetText(shown)
            button.where:SetText(U.Titles[row.page] or "")
        end
        button:SetShown(row ~= nil)
    end
    local count = math.min(#rows, #results.rows)
    results.empty:SetText(#rows == 0 and string.format(tr("Keine Einstellung gefunden für „%s“. Versuche ein anderes Wort, zum Beispiel „Loot“, „Ton“ oder „Karte“.",
        "No setting found for “%s”. Try another word, for example “loot”, “sound” or “map”."), query) or "")
    results.empty:SetShown(#rows == 0)
    results.more:SetText(#rows > count and string.format(tr("%d weitere Treffer. Suchbegriff genauer fassen.", "%d more matches. Narrow the search."), #rows - count) or "")
    results:SetHeight(#rows == 0 and 56 or (count * 28 + 12 + (#rows > count and 20 or 0)))
    results:Show()
end

function U.Refresh() for _, v in ipairs(U.views) do v:Refresh() end end
function U.RefreshData() for _, v in ipairs(U.views) do if v.frame:IsVisible() then v:RefreshData() end end end
function U.HideAll()
    for _, v in ipairs(U.views) do
        v:CloseTransient()
        if not v.embedded then v.frame:Hide() end
    end
end
function U.Open(page)
    if NS.Setup and NS.Setup.wizard and NS.Setup.wizard.frame then NS.Setup.wizard.frame:Hide() end
    U.standalone = U.standalone or U.Create(nil, false)
    U.standalone:SelectPage(page or "overview")
    U.standalone.frame:Show()
    return U.standalone
end
function U.Toggle()
    if U.standalone and U.standalone.frame:IsShown() then U.standalone.frame:Hide() else U.Open() end
end
