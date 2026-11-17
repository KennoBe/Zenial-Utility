local _, NS = ...
-- The settings window: one page description (SettingsPages.lua and the list pages of the modules) builds the own
-- window (/zutil) and the view embedded in the Community addon manager through the shared Window and Form.
-- Setting rows are shared Form rows; the free list pages (macros, UI profiles, graphics) draw their own content
-- on a fixed page. What each page contains is declared in SettingsPages.lua.
local U = {views = {}, builders = {}, fixed = {}, Pages = {}, ById = {}, Order = {}, Titles = {}, KeyTitles = {}}
NS.SettingsUI = U
local T, tr, A = NS.Theme, NS.Text, NS.Adapter
local Window, Form = NS.Window, NS.Form

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
-- Window position, version, reset
----------------------------------------------------------------------
local function version()
    local value = A.Call(_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata, "ZenialUtility", "Version")
    return type(value) == "string" and value or nil
end

local function loadPosition()
    local saved = db() and db().settingsWindow
    if type(saved) == "table" and type(saved.point) == "string" and type(saved.x) == "number" and type(saved.y) == "number" then
        return saved.point, type(saved.relative) == "string" and saved.relative or saved.point, saved.x, saved.y
    end
end

local function savePosition(point, relative, x, y)
    db().settingsWindow = {point = point, relative = relative or point, x = x, y = y}
end

function U.ResetWindow()
    db().settingsWindow = {}
    if U.standalone then
        local frame = U.standalone.frame
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
        frame:SetScale(U.standalone.window:FitScale())
    end
end

----------------------------------------------------------------------
-- Rows: every setting node of a page becomes a row of the shared Form
----------------------------------------------------------------------
local function rowSpec(node)
    local spec = {
        key = node.key, anchor = node.id or node.key, label = node.title, desc = node.desc, tip = node.tip,
        default = node.default, parent = node.parent, parentHint = node.parentHint,
        get = node.get, set = node.set, onChange = node.change, visible = node.show,
    }
    if node.enabled then
        local enabled, reason = node.enabled, node.parentHint
        spec.enabled = function()
            if enabled() then return true end
            return false, reason
        end
    end
    return spec
end

local function buttonList(host, list)
    local out = {}
    for _, button in ipairs(list) do
        out[#out + 1] = {text = button.text, tip = button.tip, variant = button.variant, width = button.width,
            enabled = button.enabled, onClick = function() button.action(host) end}
    end
    return out
end

local function render(form, host, def)
    for _, node in ipairs(def.nodes or {}) do
        local kind = node.kind
        if kind == "section" then
            form:Card(node.title, node.desc, node.id)
        elseif kind == "toggle" then
            form:Toggle(rowSpec(node))
        elseif kind == "slider" then
            local spec = rowSpec(node)
            spec.min, spec.max, spec.step = node.min, node.max, node.step
            if type(node.format) == "function" then spec.format = node.format else spec.suffix = node.suffix end
            form:Slider(spec)
        elseif kind == "choice" then
            local spec = rowSpec(node)
            spec.options = node.options
            form:Select(spec)
        elseif kind == "buttons" then
            form:Buttons(buttonList(host, node.buttons))
        elseif kind == "note" then
            local text = node.text
            form:Note({text = text, anchor = node.ref, tone = node.color == "gold" and "warning" or nil, visible = node.show})
        elseif kind == "custom" then
            node.build(form, host, def)
        end
    end
end

-- "Restore defaults" of a page: a last card with one button, only on pages that have something to restore.
function U.ConfirmPageReset(host, def)
    local title = pick(def.title)
    U.Confirm(host, tr("Standardwerte wiederherstellen?", "Restore defaults?"),
        string.format(tr("Alle Einstellungen auf der Seite „%s“ werden auf die Standardwerte zurückgesetzt. Andere Seiten bleiben unverändert.",
            "All settings on the “%s” page go back to their defaults. Other pages stay as they are."), title),
        tr("Zurücksetzen", "Reset"), function()
            if A.Combat() then host:SetMessage(tr("Im Kampf nicht möglich.", "Not possible in combat.")); return end
            NS.Logic.ResetKeys(db(), U.ResetKeys(def))
            if def.resetExtra then def.resetExtra(db()) end
            host:Changed()
            host:SetMessage(string.format(tr("Standardwerte für „%s“ wiederhergestellt.", "Defaults restored for “%s”."), title))
        end, "danger")
end

local function addReset(form, host, def)
    if #U.ResetKeys(def) == 0 and not def.resetExtra then return end
    form:Card()
    form:Buttons({{text = {"Standardwerte wiederherstellen", "Restore defaults"}, width = 260,
        tip = {"Setzt nur die Einstellungen dieser Seite zurück. Vorher wird nachgefragt.", "Resets only the settings on this page. You are asked first."},
        onClick = function() U.ConfirmPageReset(host, def) end}})
end

-- The shared confirm dialog of the window.
function U.Confirm(host, title, text, accept, onAccept, variant)
    host.window:Confirm({title = title, text = text, accept = accept, variant = variant, onAccept = onAccept})
end

local function newContext()
    return {
        tr = pick,
        read = function(key) return db()[key] end,
        write = function(key, value) db()[key] = value end,
        changed = function() NS.App:Changed() end,
        default = function(key) return NS.Logic.Defaults[key] end,
    }
end

-- The note on the right of the status line.
local function refreshHint(host)
    local window = host.window
    if not window then return end
    window:SetNote(A.Combat() and tr("Im Kampf sind einige Aktionen gesperrt.", "Some actions are locked in combat.")
        or tr("Änderungen werden sofort gespeichert.", "Changes are saved immediately."))
end

local function buildPage(host, def, page, view)
    local previous = host.index
    host.index = def.id
    host.updates[def.id] = {}
    if def.fixed then
        U.fixed[def.id](host, page.frame)
        page.refresh = function()
            host.index = def.id
            for _, update in ipairs(host.updates[def.id]) do update() end
            host:RefreshData()
            refreshHint(host)
        end
        page.onHide = function() host:CloseTransient() end
    else
        local form = Form.New(newContext(), page.content, view.formWidth)
        page.form = form
        render(form, host, def)
        addReset(form, host, def)
        page.refresh = function()
            host.index = def.id
            for _, update in ipairs(host.updates[def.id]) do update() end
            host:RefreshData()
            form:Refresh()
            page.content:SetHeight(form:Height())
            refreshHint(host)
        end
    end
    host.index = previous
end

----------------------------------------------------------------------
-- Search box: the header area of the window (top bar of the own window, status line of the embedded view). Hits
-- jump to the row; the hit list opens downwards in the top bar and upwards in the status line.
----------------------------------------------------------------------
local function buildSearch(host, frame, view)
    local embedded = view.embedded
    local search = Form.Edit(frame, {width = frame:GetWidth(), live = true, maxLetters = 120,
        placeholder = tr("Einstellung suchen …", "Search settings …"),
        set = function(text) U.ShowSearch(host, text) end})
    search:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    Form.Tooltip(search, tr("Einstellungen suchen", "Search settings"),
        tr("Durchsucht alle Seiten, auf Deutsch und Englisch. Enter öffnet den ersten Treffer.", "Searches every page, in German and English. Enter opens the first match."))
    search:SetScript("OnEnterPressed", function(self)
        local first = host.searchResults.rows[1]
        if host.searchResults:IsShown() and first:IsShown() then first:Click() end
        self:ClearFocus()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); U.ShowSearch(host, ""); self:ClearFocus() end)
    host.search = search
    local results = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    results:SetSize(420, 40)
    if embedded then
        results:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 0, 2)
    else
        results:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -2)
    end
    results:SetFrameStrata("FULLSCREEN_DIALOG")
    results:EnableMouse(true)
    T.Panel(results, "surface")
    results:Hide()
    host.searchResults = results
    results.rows = {}
    for index = 1, 8 do
        local row = T.Button(results, "", 404, 26, function(self)
            results:Hide()
            host.search:SetText("")
            host:Jump(self.page, self.anchor)
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
    host.popups[#host.popups + 1] = results
end

function U.ShowSearch(host, text)
    local results = host.searchResults
    local query = (text or ""):match("^%s*(.-)%s*$")
    if query == "" then results:Hide(); return end
    local rows = host:Search(query)
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

----------------------------------------------------------------------
-- A settings view: the shared Window plus the state the pages share (what the old view carried)
----------------------------------------------------------------------

local function newHost(embedded)
    -- The wizard base only supplies the dropdown and update list that the list pages draw with.
    local host = NS.ConfigWizard.New({store = {}})
    host.embedded = embedded
    host.index = nil
    host.draft = nil
    function host:Changed() NS.App:Changed() end
    function host:SetMessage(message) if self.window then self.window:SetStatus(message or "") end end
    function host:SelectPage(id) return self.window:SelectPage(U.Resolve(id) or "overview") end
    function host:Jump(id, anchor) return self.window:Jump(U.Resolve(id) or "overview", anchor) end
    function host:Form(id) local page = self.window:Page(id); return page and page.form end
    function host:Search(text)
        local out = {}
        for _, entry in ipairs(NS.SettingsSearch.Find(text, U.Order)) do
            out[#out + 1] = {page = entry.page, text = pick(entry.title), id = entry.id, section = entry.section}
        end
        return out
    end
    function host:RefreshData() U.RefreshPageData(self) end
    function host:Refresh() self.window:Refresh() end
    return host
end

local function windowSpec(host, embedded)
    local pages = {}
    for _, def in ipairs(U.Pages) do
        pages[#pages + 1] = {
            key = def.id, title = def.title, subtitle = def.desc, group = def.group, icon = def.icon, fixed = def.fixed,
            build = function(page, view) buildPage(host, def, page, view) end,
        }
    end
    return {
        name = not embedded and "ZenialUtilitySettings" or nil, label = "Utility", version = version, tr = pick, pages = pages,
        position = not embedded and {load = loadPosition, save = savePosition} or nil,
        header = function(frame, view) buildSearch(host, frame, view) end,
        onPage = function(key) host.index = key end,
        onLeave = function() host:CloseTransient() end,
        onHide = function() host:CloseTransient() end,
    }
end

function U.Create(parent, embedded)
    local host = newHost(embedded)
    local view = Window.New(windowSpec(host, embedded), embedded and parent or nil)
    host.window, host.frame = view, view.frame
    refreshHint(host)
    U.views[#U.views + 1] = host
    if embedded then view:SelectPage("overview") end
    return host
end

function U.Refresh() for _, host in ipairs(U.views) do host:Refresh() end end
function U.RefreshData() for _, host in ipairs(U.views) do if host.frame:IsVisible() then host:RefreshData() end end end
function U.HideAll()
    for _, host in ipairs(U.views) do
        host:CloseTransient()
        if not host.embedded then host.window:Close() end
    end
end
function U.Open(page)
    if NS.Setup and NS.Setup.wizard and NS.Setup.wizard.frame then NS.Setup.wizard.frame:Hide() end
    U.standalone = U.standalone or U.Create(nil, false)
    U.standalone.window:Open(U.Resolve(page) or "overview")
    return U.standalone
end
function U.Toggle()
    if U.standalone and U.standalone.window:IsShown() then U.standalone.window:Close() else U.Open() end
end
