local _, NS = ...
local U = {views = {}, builders = {}, fixed = {}}
NS.SettingsUI = U
local T, tr, L, A, W = NS.Theme, NS.Text, NS.Logic, NS.Adapter, NS.Widgets

local ICONS = {
    overview = "Interface\\Icons\\INV_Misc_Book_09",
    macros = "Interface\\Icons\\INV_Misc_Note_01",
    graphics = "Interface\\Icons\\INV_Misc_Spyglass_02",
    layouts = "Interface\\Icons\\INV_Misc_Map02",
    map = "Interface\\Icons\\INV_Misc_Map_01",
    comfort = "Interface\\Icons\\INV_Misc_Coin_01",
    warnings = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    extras = "Interface\\Icons\\INV_Misc_Dice_01",
    characters = "Interface\\Icons\\Trade_Engineering",
    buffs = "Interface\\Icons\\Spell_Holy_WordFortitude",
    infobar = "Interface\\Icons\\INV_Misc_Note_02",
    merchant = "Interface\\Icons\\INV_Misc_Bag_10",
    tooltip = "Interface\\Icons\\INV_Misc_Book_11",
    inventory = "Interface\\Icons\\INV_Misc_Bag_08",
    interface = "Interface\\Icons\\INV_Misc_Gear_01",
    profiles = "Interface\\Icons\\INV_Misc_Note_05",
}
U.Order = {"overview", "macros", "graphics", "layouts", "map", "comfort", "merchant", "warnings", "buffs", "infobar", "tooltip", "inventory", "interface", "extras", "characters", "profiles"}
U.Titles = {
    overview = tr("Übersicht", "Overview"), macros = tr("Makros", "Macros"), graphics = tr("Grafik", "Graphics"), layouts = tr("Layouts", "Layouts"),
    map = tr("Karte", "Map"), comfort = tr("Komfort", "Comfort"), warnings = tr("Warnungen", "Warnings"),
    extras = tr("Extras", "Extras"), characters = tr("Charaktere", "Characters"),
    buffs = tr("Buffs", "Buffs"), infobar = tr("Infoleiste", "Info bar"), merchant = tr("Händler", "Merchant"),
    tooltip = tr("Tooltips", "Tooltips"), inventory = tr("Inventar", "Inventory"), interface = tr("Oberfläche", "Interface"),
    profiles = tr("Profile", "Profiles"),
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
        text = tr("Fertige Makros für alle Klassen, einzeln übernehmen.", "Ready-made macros for every class, copied one by one."),
        status = function()
            return string.format(tr("%d Makros verfügbar", "%d macros available"), #NS.MacroData)
        end},
    {page = "graphics", title = U.Titles.graphics,
        text = tr("Einstellungen, die das Spielmenü nicht anbietet. Alte Werte bleiben gesichert.",
            "Settings the game menu does not offer. Previous values stay saved."),
        status = function()
            local changed = NS.Graphics.ChangedCount(db())
            if changed == 0 then return tr("Keine Änderungen aktiv", "No changes active") end
            return string.format(tr("%d Einstellungen geändert", "%d settings changed"), changed)
        end},
    {page = "layouts", title = U.Titles.layouts,
        text = tr("Layouts für Bearbeitungsmodus und Cooldown Manager sammeln, ansehen und teilen.",
            "Collect, view and share Edit Mode and Cooldown Manager layouts."),
        status = function()
            return string.format(tr("%d gespeichert", "%d saved"), #NS.Layouts.Library().entries)
        end},
    {page = "map", title = U.Titles.map, toggle = "modMap",
        text = tr("Unerkundete Gebiete zeigen und Wegpunkte setzen.", "Show unexplored areas and set waypoints."),
        status = function()
            local mode = db().mapReveal
            return (mode == "off" and tr("Aufdecken: aus", "Reveal: off")) or (mode == "soft" and tr("Aufdecken: halbtransparent", "Reveal: translucent")) or tr("Aufdecken: voll", "Reveal: full")
        end},
    {page = "comfort", title = U.Titles.comfort, toggle = "modComfort",
        text = tr("Müll verkaufen, reparieren, Quests annehmen und abgeben.", "Sell junk, repair, accept and turn in quests."),
        status = function() return enabledText({"vendorJunk", "vendorRepair", "questAccept", "questTurnIn"}) end},
    {page = "warnings", title = U.Titles.warnings, toggle = "modWarnings",
        text = tr("Haltbarkeit, Taschen, Munition, Reagenzien und Gift.", "Durability, bags, ammo, reagents and poison."),
        status = function() return enabledText({"warnDurability", "warnBags", "warnAmmo", "warnPoison", "warnReagents"}) end},
    {page = "extras", title = U.Titles.extras, toggle = "modExtras",
        text = tr("Screenshots, IDs im Tooltip und Würfelfenster.", "Screenshots, IDs in tooltips and the roll window."),
        status = function() return enabledText({"screenshotLevel", "screenshotBoss", "tooltipIDs", "rollTracker"}) end},
    {page = "buffs", title = U.Titles.buffs, toggle = "modBuffs",
        text = tr("Leisten für fehlende und auslaufende Buffs, Gifte und Verbrauchsmaterial.",
            "Bars for missing and expiring buffs, poisons and consumables."),
        status = function() return #NS.Reminders.items > 0 and string.format(tr("%d Warnungen aktiv", "%d warnings active"), #NS.Reminders.items) or tr("Nichts offen", "Nothing open") end},
    {page = "infobar", title = U.Titles.infobar, toggle = "modInfoBar",
        text = tr("Verschiebbare Leiste mit Gold, Zeit, Ort, Haltbarkeit und mehr.", "Movable bar with gold, time, location, durability and more."),
        status = function() return db().modInfoBar and tr("Sichtbar", "Visible") or tr("Aus", "Off") end},
    {page = "merchant", title = U.Titles.merchant,
        text = tr("Reagenzien, Giftzutaten und Munition nachkaufen. Listen pro Charakter.",
            "Restock reagents, poison ingredients and ammo. Lists per character."),
        status = function() return NS.AutoBuy.Settings().enabled and tr("Einkaufsliste an", "Shopping list on") or tr("Aus", "Off") end},
    {page = "tooltip", title = U.Titles.tooltip, toggle = "modTooltip",
        text = tr("Charakter-Tooltips, Position, Lebensbalken und Sammelfertigkeit.",
            "Character tooltips, position, health bar and gathering skill."),
        status = function() return enabledText({"ttUnit", "ttGathering", "ttItemLevel"}) end},
    {page = "inventory", title = U.Titles.inventory, toggle = "modInventory",
        text = tr("Taschenfenster verschieben, XP-Zahlen, Twinks als Empfänger, Graues zerstören.",
            "Move the bag window, XP numbers, alts as recipients, destroy grey items."),
        status = function() return enabledText({"bagMove", "xpText", "mailAlts", "destroyGray"}) end},
    {page = "interface", title = U.Titles.interface, toggle = "modQoL",
        text = tr("Quicker Loot, Dialoge, Fehlerfilter, Zauberränge auf Aktionsleisten und Elemente ausblenden.",
            "Quicker Loot, dialogs, error filter, spell ranks on action bars and hiding elements."),
        status = function() return enabledText({"fastLoot", "lootFeed", "lootGreed", "skipGossip", "declineDuels", "bgRelease", "errorFilter", "rankCheck"}) end},
    {page = "profiles", title = U.Titles.profiles,
        text = tr("Benannte Einstellungen, als Text teilbar.", "Named settings, shareable as text."),
        status = function() return tr("Aktiv: ", "Active: ") .. NS.Profiles.Active() end},
    {page = "characters", title = U.Titles.characters,
        text = tr("Spielzeit aller Charaktere und Charakter-Makros für Twinks.",
            "Playtime of all characters and character macros for alts."),
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
            W.Tooltip(check, card.title, tr("Ganzes Thema an oder aus. Einzelne Einstellungen bleiben erhalten.",
                "Whole topic on or off. Individual settings are kept."))
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

-- Search reads every text a page writes. Page texts only exist once a page is built,
-- so the first search builds all pages. They stay hidden until selected.
function U.Note(v, text)
    if type(text) ~= "string" or not v.building then return end
    v.searchTexts[#v.searchTexts + 1] = {page = v.building, text = text, low = text:lower()}
end

local function section(v, p, title, y)
    U.Note(v, title)
    return W.Section(p, title, y)
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
    section(v, p, tr("Karte aufdecken", "Reveal map"), 0)
    v:Label(p, tr("Nur die Anzeige ändert sich. Erkundung, Erfahrung und Erfolge bleiben unberührt.",
        "Only the display changes. Exploration, experience and achievements stay untouched."), 0, -28, 552, 20, "GameFontHighlightSmall", "muted")
    v:Dropdown(p, "mapReveal", 0, -52, 300, {{"off", tr("Aus", "Off")}, {"soft", tr("Halbtransparent", "Translucent")}, {"full", tr("Voll aufgedeckt", "Fully revealed")}})
    v:Number(p, "revealAlpha", tr("Deckkraft bei halbtransparent", "Opacity when translucent"), -90, .2, 1, .05)
    section(v, p, tr("Wegpunkte", "Waypoints"), -172)
    local y = checks(v, p, -200, {
        {"waypoints", tr("Wegpunkte per Befehl", "Waypoints by command"),
            tr("/zway 45.2 67.8 setzt einen Wegpunkt in deiner Zone, /zway clear entfernt ihn.", "/zway 45.2 67.8 sets a waypoint in your zone, /zway clear removes it.")},
    })
    v:Label(p, tr("Koordinaten zeigt die Weltkarte selbst an. Das Aufdecken lässt sich auch im Filtermenü der Weltkarte umschalten.",
        "The world map shows coordinates itself. Revealing can also be toggled in the world map's filter menu."), 0, y - 8, 552, 36, "GameFontHighlightSmall", "muted")
    y = y - 60
    section(v, p, tr("Levelbereiche", "Level ranges"), y)
    y = checks(v, p, y - 28, {
        {"mapLevels", tr("Levelbereiche auf Kontinentkarten", "Level ranges on continent maps"),
            tr("Grün: passend für deine Stufe, grau: zu niedrig, rot: zu hoch. Die Maus über einem Gebiet zeigt Mindest- und Höchststufe.",
                "Green: right for your level, grey: too low, red: too high. Hovering a zone shows its minimum and maximum level.")},
        {"mapLevelDungeons", tr("Dungeons des Gebiets im Tooltip", "The zone's dungeons in the tooltip")},
    })
    v:Label(p, tr("Anzeige", "Display"), 0, y - 4, 120, 20, "GameFontHighlightSmall", "muted")
    v:Dropdown(p, "mapLevelMode", 124, y, 300, {{"labels", tr("Kartenbeschriftung und Tooltip", "Map labels and tooltip")}, {"tooltip", tr("Nur Tooltip", "Tooltip only")}})
    y = y - 38
    local other = NS.MapTools.LevelsElsewhere()
    if other then
        v:Label(p, string.format(tr("%s zeigt Levelbereiche bereits auf der Karte an. Die eigene Anzeige bleibt deshalb aus.",
            "%s already shows level ranges on the map, so this display stays off."), other), 0, y, 552, 36, "GameFontHighlightSmall", "muted")
        y = y - 40
    end
    return -y + 60
end

function U.builders.comfort(v, p)
    section(v, p, tr("Beim Händler", "At vendors"), 0)
    local y = checks(v, p, -28, {
        {"vendorJunk", tr("Graue Gegenstände automatisch verkaufen", "Sell grey items automatically"), tr("Shift beim Öffnen überspringt alles einmal.", "Shift while opening skips everything once.")},
        {"vendorRepair", tr("Automatisch reparieren", "Repair automatically")},
        {"vendorGuildRepair", tr("Zuerst aus der Gildenbank reparieren", "Repair from the guild bank first")},
        {"vendorChat", tr("Betrag im Chat anzeigen", "Show the amount in chat")},
    })
    section(v, p, tr("Quests", "Quests"), y - 10)
    y = checks(v, p, y - 38, {
        {"questAccept", tr("Quests automatisch annehmen", "Accept quests automatically")},
        {"questTurnIn", tr("Fertige Quests automatisch abgeben", "Turn in finished quests automatically"), tr("Nicht bei Belohnungswahl oder Goldkosten. Shift pausiert.", "Not with a reward choice or gold cost. Shift pauses.")},
        {"questRepeatable", tr("Wiederholbare Quests mit annehmen", "Also accept repeatable quests")},
        {"questRewardValue", tr("Händlerwert auf den Belohnungen anzeigen", "Show vendor value on rewards")},
        {"questZoneTrack", tr("Gebiet-Häkchen im Questlog", "Zone checkbox in the quest log"), tr("Verfolgt alle Quests eines Gebiets bis zum Limit der Questverfolgung.", "Tracks all quests of a zone up to the tracker's limit.")},
    })
    v:Label(p, tr("Annehmen bis", "Accept up to"), 0, y - 5, 200, 24)
    v:Dropdown(p, "questDifficulty", 210, y, 300, {{"all", tr("Alle Schwierigkeiten", "All difficulties")}, {"nogray", tr("Ohne graue Quests", "Without grey quests")}, {"nogreen", tr("Ohne graue und grüne Quests", "Without grey and green quests")}})
    y = y - 36
    return -y + 20
end

function U.builders.warnings(v, p)
    section(v, p, tr("Warnungen", "Warnings"), 0)
    v:Label(p, tr("Einmal beim Erreichen des Grenzwerts, wieder erst nach einer Erholung.",
        "Once when the limit is reached, again only after recovering."), 0, -28, 552, 20, "GameFontHighlightSmall", "muted")
    local y = checks(v, p, -52, {{"warnDurability", tr("Niedrige Haltbarkeit", "Low durability")}})
    v:Number(p, "durabilityPercent", tr("Warnen ab (%)", "Warn at (%)"), y, 5, 50, 5)
    y = checks(v, p, y - 70, {{"warnBags", tr("Fast volle Taschen", "Nearly full bags")}})
    v:Number(p, "bagSlots", tr("Warnen ab freien Plätzen", "Warn at free slots"), y, 1, 20, 1)
    y = checks(v, p, y - 70, {{"warnSound", tr("Warnton spielen", "Play a warning sound")}})
    y = checks(v, p, y, {{"warnAmmo", tr("Wenig Munition", "Low ammo"), tr("Zählt alle passende Munition in den Taschen.", "Counts all matching ammo in your bags.")}})
    v:Number(p, "ammoThreshold", tr("Warnen ab Schuss", "Warn at rounds"), y, 10, 5000, 10)
    y = checks(v, p, y - 70, {
        {"warnPoison", tr("Abgelaufenes Waffengift (Schurke)", "Expired weapon poison (Rogue)")},
        {"warnReagents", tr("Reagenzien gehen aus", "Reagents running out"), tr("Nur für Reagenzien, die du tatsächlich bei dir hattest.", "Only for reagents you actually carried.")},
    })
    return -y + 20
end

function U.builders.extras(v, p)
    section(v, p, tr("Screenshots", "Screenshots"), 0)
    local y = checks(v, p, -28, {
        {"screenshotLevel", tr("Screenshot beim Levelaufstieg", "Screenshot on level up")},
        {"screenshotBoss", tr("Screenshot beim Bosskill", "Screenshot on boss kill")},
    })
    section(v, p, tr("Tooltips", "Tooltips"), y - 10)
    y = checks(v, p, y - 38, {{"tooltipIDs", tr("Item- und Zauber-IDs anzeigen", "Show item and spell IDs")}})
    section(v, p, tr("Würfeln", "Rolls"), y - 10)
    y = checks(v, p, y - 38, {{"rollTracker", tr("Würfelfenster für /roll", "Roll window for /roll"),
        tr("Eigene Würfe und die der Gruppe. Bedarf und Gier zählen nicht. Nach 2 Minuten Pause beginnt eine neue Runde.",
            "Your own rolls and your group's. Need and Greed do not count. A new round starts after a 2 minute pause.")}})
    v.rollLabel = v:Label(p, "", 0, y, 552, 104, "GameFontHighlightSmall")
    v:Button(p, tr("Fenster zeigen", "Show window"), 0, y - 110, 150, function() NS.RollWindow.Update(true) end, "secondary")
    v:Button(p, tr("Liste leeren", "Clear list"), 160, y - 110, 150, function() NS.Helpers.ClearRolls() end, "secondary")
    v:Button(p, tr("Gewinner ansagen", "Announce winner"), 320, y - 110, 190, function()
        if not NS.Helpers.AnnounceWinner() then v:SetMessage(tr("Dafür braucht es einen Wurf und eine Gruppe.", "This needs a roll and a group.")) end
    end, "secondary")
    return -y + 160
end

function U.builders.characters(v, p)
    section(v, p, tr("Spielzeit", "Playtime"), 0)
    v.playedLabel = v:Label(p, "", 0, -28, 552, 150, "GameFontHighlightSmall")
    v:Button(p, tr("Spielzeit aktualisieren", "Update playtime"), 0, -184, 220, function() A.Call(RequestTimePlayed) end, "secondary")
    v:Label(p, tr("Auch /played wird erfasst.", "/played is recorded too."), 232, -190, 320, 20, "GameFontHighlightSmall", "muted")
    section(v, p, tr("Charakter-Makros übertragen", "Carry over character macros"), -232)
    v:Label(p, tr("Hier sichern, dann auf dem anderen Charakter übernehmen. Vorhandene Namen bleiben unberührt.",
        "Save here, then import on the other character. Existing names stay untouched."), 0, -260, 552, 36, "GameFontHighlightSmall", "muted")
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
    if v.index == "interface" and v.rankRows then
        U.RefreshRankRows(v)
    elseif v.index == "extras" and v.rollLabel then
        local lines = {}
        local won = {}
        for _, row in ipairs(L.RollWinners(NS.Helpers.rolls)) do won[row] = true end
        for index, row in ipairs(NS.Helpers.rolls) do
            if index > 6 then break end
            local line = string.format("%d.  %s  ·  %d  (%d–%d)", index, row.name, row.roll, row.low, row.high)
            lines[#lines + 1] = won[row] and ("|cffffd100" .. line .. "|r") or line
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
    v.searchTexts = {}
    local baseLabel = v.Label
    function v:Label(parent, value, ...)
        U.Note(self, value)
        return baseLabel(self, parent, value, ...)
    end
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
        local button = T.Button(f, U.Titles[key], embedded and 88 or 140, 30, function() v:SelectPage(id) end, "secondary")
        if embedded then
            -- Two rows of nine fit the 856-pixel Community canvas; the last slot holds the search.
            button:SetPoint("TOPLEFT", 12 + (index - 1) % 9 * 92, -8 - math.floor((index - 1) / 9) * 34)
        else
            button:SetPoint("TOPLEFT", 18, -80 - (index - 1) * 34)
            T.StyleNav(button, ICONS[key])
        end
        v.nav[key] = button
    end
    local top = -80
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
    -- Macros, graphics and layouts bring their own lists, so they use the area without the outer scroll.
    local fixed = CreateFrame("Frame", nil, f)
    fixed:SetPoint("TOPLEFT", left, top)
    fixed:SetPoint("BOTTOMRIGHT", embedded and -16 or -20, bottom)
    fixed:Hide()
    v.fixedHost = fixed
    -- Search box: on the free spot of the second tab row, or in the title bar of the own window.
    local search = W.Edit(f, 0, 0, embedded and 88 or 220, function(text) U.ShowSearch(v, text) end)
    search:ClearAllPoints()
    if embedded then search:SetPoint("TOPLEFT", 12 + 8 * 92, -42)
    else search:SetPoint("TOPRIGHT", -60, -26) end
    W.Tooltip(search, tr("Einstellungen suchen", "Search settings"))
    v.search = search
    v.searchHint = T.Text(search, tr("Suchen …", "Search …"), "GameFontHighlightSmall", "muted")
    v.searchHint:SetPoint("LEFT", 8, 0)
    local results = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    results:SetSize(380, 40)
    results:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -2)
    results:SetFrameStrata("FULLSCREEN_DIALOG")
    results:EnableMouse(true)
    T.Panel(results, "surface")
    results:Hide()
    v.searchResults = results
    results.rows = {}
    for index = 1, 8 do
        local row = T.Button(results, "", 364, 24, function(self)
            results:Hide()
            v.search:SetText("")
            v.searchHint:Show()
            v:SelectPage(self.page)
        end, "secondary")
        row:SetPoint("TOPLEFT", 8, -6 - (index - 1) * 26)
        row:Hide()
        results.rows[index] = row
    end
    function v:SelectPage(id)
        self:CloseTransient()
        self.index, self.draft = id, NS.App.db
        self:SetMessage("")
        for _, page in pairs(self.pages) do page:Hide() end
        local isFixed = U.fixed[id] ~= nil
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
        for key, button in pairs(self.nav) do T.SetSelected(button, key == id) end
        self:Refresh()
    end
    function v:BuildPage(id)
        if self.pages[id] then return end
        local index = self.index
        self.index = id
        self.updates[id] = {}
        self.building = id
        if U.fixed[id] ~= nil then
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
        self.building = nil
        self.pages[id]:Hide()
        self.index = index
    end
    -- All matches of a word, each page once per text, the title of a page first.
    function v:Search(text)
        text = (text or ""):match("^%s*(.-)%s*$"):lower()
        if text == "" then return {} end
        for _, id in ipairs(U.Order) do self:BuildPage(id) end
        local out, seen = {}, {}
        for _, id in ipairs(U.Order) do
            if U.Titles[id]:lower():find(text, 1, true) then
                out[#out + 1] = {page = id, text = U.Titles[id]}
                seen[id .. U.Titles[id]] = true
            end
        end
        for _, row in ipairs(self.searchTexts) do
            local key = row.page .. row.text
            if not seen[key] and row.low:find(text, 1, true) then
                seen[key] = true
                out[#out + 1] = {page = row.page, text = row.text}
            end
        end
        return out
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

function U.ShowSearch(v, text)
    v.searchHint:SetShown(text == "")
    local results = v.searchResults
    local rows = v:Search(text)
    for index, button in ipairs(results.rows) do
        local row = rows[index]
        button.page = row and row.page
        if row then
            local shown = L.TrimUTF8(row.text, 48)
            if shown ~= row.text then shown = shown .. "…" end
            button:SetText(U.Titles[row.page] .. ": " .. shown)
        end
        button:SetShown(row ~= nil)
    end
    results:SetHeight(math.min(#rows, 8) * 26 + 12)
    results:SetShown(#rows > 0)
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
