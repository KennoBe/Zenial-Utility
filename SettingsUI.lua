local _, NS = ...
local U = {views = {}, builders = {}, fixed = {}}
NS.SettingsUI = U
local T, tr, L, A, W = NS.Theme, NS.Text, NS.Logic, NS.Adapter, NS.Widgets

local ICONS = {
    overview = "Interface\\Icons\\INV_Misc_Book_09",
    macros = "Interface\\Icons\\INV_Misc_Note_01",
    graphics = "Interface\\Icons\\INV_Misc_Spyglass_02",
    map = "Interface\\Icons\\INV_Misc_Map_01",
    comfort = "Interface\\Icons\\INV_Misc_Coin_01",
    warnings = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    extras = "Interface\\Icons\\INV_Misc_Dice_01",
    characters = "Interface\\Icons\\Trade_Engineering",
}
U.Order = {"overview", "macros", "graphics", "map", "comfort", "warnings", "extras", "characters"}
U.Titles = {
    overview = tr("Übersicht", "Overview"), macros = tr("Makros", "Macros"), graphics = tr("Grafik", "Graphics"),
    map = tr("Karte", "Map"), comfort = tr("Komfort", "Comfort"), warnings = tr("Warnungen", "Warnings"),
    extras = tr("Extras", "Extras"), characters = tr("Charaktere", "Characters"),
}

local function db() return NS.App.db end

local function countOn(keys)
    local on = 0
    for _, key in ipairs(keys) do if db()[key] then on = on + 1 end end
    return on, #keys
end

local function enabledText(keys)
    local on, total = countOn(keys)
    return string.format(tr("%d von %d Funktionen an", "%d of %d features on"), on, total)
end

-- Every topic once: what it does in one sentence, whether it runs, and the way in.
local CARDS = {
    {page = "macros", title = U.Titles.macros,
        text = tr("Fertige Makros für alle Klassen ansehen und gezielt in deinen Account oder Charakter übernehmen.",
            "Browse ready-made macros for every class and copy the ones you want to your account or character."),
        status = function()
            return string.format(tr("%d Makros verfügbar", "%d macros available"), #NS.MacroData)
        end},
    {page = "graphics", title = U.Titles.graphics,
        text = tr("Einstellungen, die das Spielmenü nicht anbietet. Deine alten Werte bleiben gesichert.",
            "Settings the game menu does not offer. Your previous values stay saved."),
        status = function()
            local changed = NS.Graphics.ChangedCount(db())
            if changed == 0 then return tr("Keine Änderungen aktiv", "No changes active") end
            return string.format(tr("%d Einstellungen geändert", "%d settings changed"), changed)
        end},
    {page = "map", title = U.Titles.map, toggle = "modMap",
        text = tr("Unerkundete Gebiete zeigen, Koordinaten einblenden und Wegpunkte setzen.",
            "Show unexplored areas, display coordinates and set waypoints."),
        status = function()
            local mode = db().mapReveal
            return (mode == "off" and tr("Aufdecken: aus", "Reveal: off")) or (mode == "soft" and tr("Aufdecken: halbtransparent", "Reveal: translucent")) or tr("Aufdecken: voll", "Reveal: full")
        end},
    {page = "comfort", title = U.Titles.comfort, toggle = "modComfort",
        text = tr("Beim Händler Müll verkaufen und reparieren, Quests schneller annehmen und abgeben.",
            "Sell junk and repair at vendors, accept and turn in quests faster."),
        status = function() return enabledText({"vendorJunk", "vendorRepair", "questAccept", "questTurnIn"}) end},
    {page = "warnings", title = U.Titles.warnings, toggle = "modWarnings",
        text = tr("Hinweis bei kaputter Ausrüstung, vollen Taschen, wenig Munition, Reagenzien oder abgelaufenem Gift.",
            "Alerts for damaged gear, full bags, low ammo or reagents and expired poison."),
        status = function() return enabledText({"warnDurability", "warnBags", "warnAmmo", "warnPoison", "warnReagents"}) end},
    {page = "extras", title = U.Titles.extras, toggle = "modExtras",
        text = tr("Automatische Screenshots, Preise und IDs im Tooltip, Pull-Countdown und Würfel-Liste.",
            "Automatic screenshots, prices and IDs in tooltips, pull countdown and roll list."),
        status = function() return enabledText({"screenshotLevel", "screenshotBoss", "tooltipIDs", "tooltipPrice", "pullEnabled", "rollTracker"}) end},
    {page = "characters", title = U.Titles.characters,
        text = tr("Spielzeit aller Charaktere sehen und Charakter-Makros auf einen Twink übertragen.",
            "See the playtime of all characters and carry character macros over to an alt."),
        status = function()
            local rows = NS.Helpers.PlayedRows()
            return string.format(tr("%d Charaktere erfasst", "%d characters recorded"), #rows)
        end},
}

function U.builders.overview(v, p)
    local width, height, gap = 270, 118, 12
    for index, card in ipairs(CARDS) do
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        local frame = CreateFrame("Frame", nil, p, BackdropTemplateMixin and "BackdropTemplate" or nil)
        frame:SetSize(width, height)
        frame:SetPoint("TOPLEFT", column * (width + gap), -row * (height + gap))
        T.Panel(frame, "surface")
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 12, -12)
        icon:SetTexture(ICONS[card.page])
        local title = T.Text(frame, card.title, "GameFontNormal", "gold")
        title:SetPoint("TOPLEFT", 48, -13)
        title:SetWidth(170)
        local text = T.Text(frame, card.text, "GameFontHighlightSmall", "text")
        text:SetPoint("TOPLEFT", 48, -31)
        text:SetWidth(210)
        local status = T.Text(frame, "", "GameFontHighlightSmall", "muted")
        status:SetPoint("BOTTOMLEFT", 12, 14)
        status:SetWidth(176)
        status:SetWordWrap(false)
        T.Tint(status, "SetTextColor", "dim")
        T.Tint(text, "SetTextColor", "textSoft")
        local open = T.Button(frame, tr("Öffnen", "Open"), 72, 24, function() v:SelectPage(card.page) end, "secondary")
        open:SetPoint("BOTTOMRIGHT", -8, 8)
        if card.toggle then
            local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
            check:SetSize(22, 22)
            check:SetPoint("TOPRIGHT", -8, -8)
            T.StyleCheckbox(check)
            W.Tooltip(check, card.title, tr("Schaltet das ganze Thema an oder aus. Einzelne Einstellungen bleiben erhalten.",
                "Turns the whole topic on or off. Individual settings are kept."))
            check:SetScript("OnClick", function(self)
                v.draft[card.toggle] = self:GetChecked() == true
                v:Changed()
            end)
            v:AddUpdate(function() check:SetChecked(v.draft[card.toggle] == true) end)
        end
        v:AddUpdate(function() status:SetText(card.status()) end)
    end
    local rows = math.ceil(#CARDS / 2)
    local y = -rows * (height + gap) - 4
    v:Button(p, tr("Einrichtungsassistent öffnen", "Open setup wizard"), 0, y, 270, function() NS.Setup.Open() end, "secondary")
    return -y + 40
end

local function checks(v, p, y, rows)
    for _, row in ipairs(rows) do
        v:Check(p, row[1], row[2], 0, y, nil, 520)
        y = y - 30
        if row[3] then
            v:Label(p, row[3], 30, y + 4, 520, 30, "GameFontHighlightSmall", "muted")
            y = y - 28
        end
    end
    return y
end

function U.builders.map(v, p)
    W.Section(p, tr("Karte aufdecken", "Reveal map"), 0)
    v:Label(p, tr("Zeigt Gebiete, in denen du noch nicht warst. Das ändert nur die Anzeige: Erkundung, Erfahrung und Erfolge bleiben unberührt.",
        "Shows areas you have not visited yet. This only changes the display: exploration, experience and achievements stay untouched."), 0, -28, 552, 36, "GameFontHighlightSmall", "muted")
    v:Dropdown(p, "mapReveal", 0, -68, 300, {{"off", tr("Aus", "Off")}, {"soft", tr("Halbtransparent", "Translucent")}, {"full", tr("Voll aufgedeckt", "Fully revealed")}})
    v:Number(p, "revealAlpha", tr("Deckkraft bei halbtransparent", "Opacity when translucent"), -106, .2, 1, .05)
    W.Section(p, tr("Koordinaten und Wegpunkte", "Coordinates and waypoints"), -188)
    local y = checks(v, p, -216, {
        {"mapCoords", tr("Koordinaten auf der Weltkarte anzeigen", "Show coordinates on the world map")},
        {"waypoints", tr("Wegpunkte per Befehl setzen", "Set waypoints by command"),
            tr("/zway 45.2 67.8 setzt einen Wegpunkt in deiner Zone. /zway clear entfernt ihn.", "/zway 45.2 67.8 sets a waypoint in your zone. /zway clear removes it.")},
    })
    v:Label(p, tr("Auch im Tracking-Menü der Weltkarte lässt sich das Aufdecken umschalten, neben den Einträgen von ZENIAL Community.",
        "Revealing can also be toggled in the world map's tracking menu, next to the ZENIAL Community entries."), 0, y - 8, 552, 36, "GameFontHighlightSmall", "muted")
    return -y + 60
end

function U.builders.comfort(v, p)
    W.Section(p, tr("Beim Händler", "At vendors"), 0)
    local y = checks(v, p, -28, {
        {"vendorJunk", tr("Graue Gegenstände automatisch verkaufen", "Sell grey items automatically"), tr("Shift beim Öffnen des Händlers überspringt alles einmalig.", "Holding Shift when opening the vendor skips everything once.")},
        {"vendorRepair", tr("Automatisch reparieren", "Repair automatically")},
        {"vendorGuildRepair", tr("Zuerst aus der Gildenbank reparieren", "Repair from the guild bank first")},
        {"vendorChat", tr("Betrag im Chat anzeigen", "Show the amount in chat")},
    })
    W.Section(p, tr("Quests", "Quests"), y - 10)
    y = checks(v, p, y - 38, {
        {"questAccept", tr("Quests automatisch annehmen", "Accept quests automatically")},
        {"questTurnIn", tr("Fertige Quests automatisch abgeben", "Turn in finished quests automatically"), tr("Bei mehreren Belohnungen wählst du selbst. Quests, die Gold kosten, bleiben stehen. Shift pausiert.", "With several rewards you choose yourself. Quests that cost gold are left alone. Shift pauses.")},
    })
    return -y + 20
end

function U.builders.warnings(v, p)
    W.Section(p, tr("Wann soll Utility warnen?", "When should Utility warn?"), 0)
    v:Label(p, tr("Jede Warnung erscheint einmal, wenn der Grenzwert erreicht wird, und erst nach einer Erholung wieder.",
        "Each warning appears once when its limit is reached, and again only after recovering."), 0, -28, 552, 36, "GameFontHighlightSmall", "muted")
    local y = checks(v, p, -66, {{"warnDurability", tr("Niedrige Haltbarkeit", "Low durability")}})
    v:Number(p, "durabilityPercent", tr("Warnen ab (%)", "Warn at (%)"), y, 5, 50, 5)
    y = checks(v, p, y - 70, {{"warnBags", tr("Fast volle Taschen", "Nearly full bags")}})
    v:Number(p, "bagSlots", tr("Warnen ab freien Plätzen", "Warn at free slots"), y, 1, 20, 1)
    y = checks(v, p, y - 70, {
        {"warnAmmo", tr("Wenig Munition", "Low ammo")},
        {"warnPoison", tr("Abgelaufenes Waffengift (Schurke)", "Expired weapon poison (Rogue)")},
        {"warnReagents", tr("Reagenzien gehen aus", "Reagents running out"), tr("Nur für Reagenzien, die du tatsächlich bei dir hattest.", "Only for reagents you actually carried.")},
    })
    return -y + 20
end

function U.builders.extras(v, p)
    W.Section(p, tr("Screenshots", "Screenshots"), 0)
    local y = checks(v, p, -28, {
        {"screenshotLevel", tr("Screenshot beim Levelaufstieg", "Screenshot on level up")},
        {"screenshotBoss", tr("Screenshot beim Bosskill", "Screenshot on boss kill")},
    })
    W.Section(p, tr("Tooltips", "Tooltips"), y - 10)
    y = checks(v, p, y - 38, {
        {"tooltipPrice", tr("Verkaufspreis und Stapelwert anzeigen", "Show sell price and stack value")},
        {"tooltipIDs", tr("Item- und Zauber-IDs anzeigen", "Show item and spell IDs")},
    })
    W.Section(p, tr("Pull-Countdown", "Pull countdown"), y - 10)
    y = checks(v, p, y - 38, {{"pullEnabled", tr("Befehl /zpull aktivieren", "Enable the /zpull command"), tr("/zpull 10 startet, /zpull stop bricht ab. Nutzt den Countdown des Spiels, sonst den Gruppenchat.", "/zpull 10 starts, /zpull stop cancels. Uses the game's countdown, otherwise group chat.")}})
    v:Number(p, "pullSeconds", tr("Standarddauer (s)", "Default length (s)"), y, 3, 30, 1)
    y = y - 70
    W.Section(p, tr("Würfel-Liste", "Roll list"), y)
    y = checks(v, p, y - 28, {{"rollTracker", tr("Würfe von /roll mitschreiben", "Track /roll results")}})
    v.rollLabel = v:Label(p, "", 0, y, 552, 104, "GameFontHighlightSmall")
    v:Button(p, tr("Liste leeren", "Clear list"), 0, y - 110, 150, function() NS.Helpers.ClearRolls() end, "secondary")
    v:Button(p, tr("Höchsten Wurf ansagen", "Announce highest roll"), 160, y - 110, 210, function()
        if not NS.Helpers.AnnounceWinner() then v:SetMessage(tr("Dafür braucht es einen Wurf und eine Gruppe.", "This needs a roll and a group.")) end
    end, "secondary")
    return -y + 160
end

function U.builders.characters(v, p)
    W.Section(p, tr("Spielzeit", "Playtime"), 0)
    v.playedLabel = v:Label(p, "", 0, -28, 552, 150, "GameFontHighlightSmall")
    v:Button(p, tr("Spielzeit aktualisieren", "Update playtime"), 0, -184, 220, function() A.Call(RequestTimePlayed) end, "secondary")
    v:Label(p, tr("Erfasst wird, wenn du hier klickst oder /played nutzt. Das Spiel schreibt den Wert zusätzlich in den Chat.",
        "Recorded when you click here or use /played. The game also prints the value to chat."), 232, -184, 320, 36, "GameFontHighlightSmall", "muted")
    W.Section(p, tr("Charakter-Makros übertragen", "Carry over character macros"), -232)
    v:Label(p, tr("Sichert die Makros dieses Charakters im Addon. Auf einem anderen Charakter übernimmst du sie dann hier. Vorhandene Namen bleiben unberührt.",
        "Saves this character's macros in the addon. You then import them here on another character. Existing names stay untouched."), 0, -260, 552, 36, "GameFontHighlightSmall", "muted")
    v:Button(p, tr("Makros dieses Charakters sichern", "Save this character's macros"), 0, -300, 290, function()
        local ok, count = NS.Macros.SaveCharacterSet(db())
        v:SetMessage(ok and string.format(tr("%d Makros gesichert.", "%d macros saved."), count) or tr("Im Kampf nicht möglich.", "Not possible in combat."))
        v:RefreshData()
    end, "secondary")
    v.setRows = {}
    for index = 1, 8 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(552, 30)
        row:SetPoint("TOPLEFT", 0, -340 - (index - 1) * 34)
        row.label = T.Text(row, "", "GameFontHighlightSmall", "text")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(390)
        row.button = T.Button(row, tr("Übernehmen", "Import"), 140, 26, function(self)
            local scope = self:GetParent().scope
            local ok, created, skipped = NS.Macros.LoadCharacterSet(db(), scope)
            v:SetMessage(ok and string.format(tr("%d Makros angelegt, %d übersprungen.", "%d macros created, %d skipped."), created, skipped) or tr("Im Kampf nicht möglich.", "Not possible in combat."))
        end, "secondary")
        row.button:SetPoint("RIGHT", 0, 0)
        row:Hide()
        v.setRows[index] = row
    end
    return 640
end

function U.RefreshPageData(v)
    if v.index == "extras" and v.rollLabel then
        local lines = {}
        for index, row in ipairs(NS.Helpers.rolls) do
            if index > 6 then break end
            lines[#lines + 1] = string.format("%d.  %s  ·  %d  (%d–%d)", index, row.name, row.roll, row.low, row.high)
        end
        v.rollLabel:SetText(#lines > 0 and table.concat(lines, "\n") or tr("Noch keine Würfe.", "No rolls yet."))
    elseif v.index == "characters" and v.playedLabel then
        local rows, sum = NS.Helpers.PlayedRows()
        local lines = {}
        for index, row in ipairs(rows) do
            if index > 7 then break end
            lines[#lines + 1] = row.scope .. "  ·  " .. L.FormatPlayed(row.total)
        end
        if #rows > 0 then lines[#lines + 1] = tr("Gesamt: ", "Total: ") .. L.FormatPlayed(sum) end
        v.playedLabel:SetText(#lines > 0 and table.concat(lines, "\n") or tr("Noch keine Spielzeit erfasst.", "No playtime recorded yet."))
        local scopes = {}
        for scope in pairs(db().macroSets) do scopes[#scopes + 1] = scope end
        table.sort(scopes)
        local own = A.Scope()
        for index, row in ipairs(v.setRows) do
            local scope = scopes[index]
            row.scope = scope
            if scope then
                row.label:SetText(scope .. "  ·  " .. string.format(tr("%d Makros", "%d macros"), #db().macroSets[scope]))
                row.button:SetEnabled(scope ~= own)
                row:Show()
            else
                row:Hide()
            end
        end
    end
end

function U.Create(parent, embedded)
    local f = CreateFrame("Frame", not embedded and "ZenialUtilitySettings" or nil, parent or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if embedded then
        f:SetAllPoints(parent)
    else
        f:SetSize(860, 660)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        T.Shell(f)
        UISpecialFrames[#UISpecialFrames + 1] = "ZenialUtilitySettings"
    end
    local v = NS.ConfigWizard.New({store = {}})
    v.frame, v.embedded, v.draft = f, embedded, NS.App.db
    function v:SetMessage(message) self.message:SetText(message or "") end
    function v:Changed() NS.App.db = self.draft; NS.App:Changed() end
    local left = embedded and 16 or 172
    v.message = T.Text(f, "", "GameFontHighlightSmall", "muted")
    v.message:SetPoint("BOTTOMLEFT", left, embedded and 6 or 14)
    v.message:SetWidth(552)
    -- Embedded, the host's tab already names the addon.
    if not embedded then
        local heading = T.Text(f, "ZENIAL UTILITY", "GameFontNormalLarge", "gold")
        v.close = W.CloseButton(f, function() f:Hide() end)
        heading:SetPoint("TOPLEFT", 24, -28)
    end
    v.nav = {}
    for index, key in ipairs(U.Order) do
        local id = key
        local button = T.Button(f, U.Titles[key], embedded and 98 or 140, 30, function() v:SelectPage(id) end, "secondary")
        if embedded then
            button:SetPoint("TOPLEFT", 12 + (index - 1) * 102, -8)
        else
            button:SetPoint("TOPLEFT", 18, -80 - (index - 1) * 36)
            T.StyleNav(button, ICONS[key])
        end
        v.nav[key] = button
    end
    local top = embedded and -46 or -80
    local bottom = embedded and 24 or 40
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", left, top)
    scroll:SetPoint("BOTTOMRIGHT", -44, bottom)
    v.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(576, 500)
    scroll:SetScrollChild(content)
    v.content = content
    W.ScrollBar(scroll, 40)
    -- Macros and graphics bring their own lists, so they use the area without the outer scroll.
    local fixed = CreateFrame("Frame", nil, f)
    fixed:SetPoint("TOPLEFT", left, top)
    fixed:SetPoint("BOTTOMRIGHT", embedded and -16 or -20, bottom)
    fixed:Hide()
    v.fixedHost = fixed
    function v:SelectPage(id)
        self:CloseTransient()
        self.index, self.draft = id, NS.App.db
        self:SetMessage("")
        for _, page in pairs(self.pages) do page:Hide() end
        local isFixed = U.fixed[id] ~= nil
        if not self.pages[id] then
            self.updates[id] = {}
            if isFixed then
                local page = CreateFrame("Frame", nil, fixed)
                page:SetAllPoints(fixed)
                self.pages[id] = page
                U.fixed[id](self, page)
            else
                local page = CreateFrame("Frame", nil, self.content)
                page:SetPoint("TOPLEFT", 12, -12)
                page:SetWidth(552)
                self.pages[id] = page
                page.height = U.builders[id](self, page)
                page:SetHeight(page.height)
            end
        end
        self.pages[id]:Show()
        scroll:SetShown(not isFixed)
        fixed:SetShown(isFixed)
        if not isFixed then
            self.content:SetHeight(self.pages[id].height + 24)
            scroll:SetVerticalScroll(0)
            scroll:UpdateScrollChildRect()
            scroll:RefreshScrollbar()
        end
        for key, button in pairs(self.nav) do T.SetSelected(button, key == id) end
        self:Refresh()
    end
    function v:RefreshData() U.RefreshPageData(self) end
    function v:Refresh()
        self.draft = NS.App.db
        for _, update in ipairs(self.updates[self.index] or {}) do update() end
        self:RefreshData()
    end
    f:SetScript("OnShow", function() v:Refresh() end)
    f:SetScript("OnHide", function() v:CloseTransient() end)
    U.views[#U.views + 1] = v
    v:SelectPage("overview")
    f:Hide()
    return v
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
