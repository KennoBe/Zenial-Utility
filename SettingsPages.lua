local _, NS = ...
-- What the settings window shows, page by page. Each option is declared once here:
-- the page renders it, the search indexes it, "Restore defaults" resets it and the overview
-- reuses its wording. New features add a node to a page; nothing else has to change.
--
-- Texts are {German, English}; the client language picks one, the search reads both.
-- Node kinds: section, toggle, slider, choice, buttons, note, custom (free layout), space.
local U = NS.SettingsUI
local C = NS.SettingsControls
local T, tr, L, A, W = NS.Theme, NS.Text, NS.Logic, NS.Adapter, NS.Widgets

local function db() return NS.App.db end
local pick = C.Pick

local function section(id, title, desc, keywords) return {kind = "section", id = id, title = title, desc = desc, keywords = keywords} end
local function toggle(key, title, desc, extra)
    local node = extra or {}
    node.kind, node.key, node.title, node.desc = "toggle", key, title, desc
    return node
end
local function slider(key, title, minimum, maximum, step, extra)
    local node = extra or {}
    node.kind, node.key, node.title, node.min, node.max, node.step = "slider", key, title, minimum, maximum, step
    return node
end
local function choice(key, title, options, extra)
    local node = extra or {}
    node.kind, node.key, node.title, node.options = "choice", key, title, options
    return node
end
local function buttons(list, extra)
    local node = extra or {}
    node.kind, node.buttons = "buttons", list
    return node
end
local function note(text, extra)
    local node = extra or {}
    node.kind, node.text = "note", text
    return node
end
local function custom(id, build, search) return {kind = "custom", id = id, build = build, search = search} end

local function percent(value) return math.floor(value * 100 + .5) .. " %" end
local function seconds(value)
    if value == 1 then return tr("1 Sekunde", "1 second") end
    return string.format(tr("%d Sekunden", "%d seconds"), value)
end
local function scaleText(value) return percent(value) end

local GROUP_SETTINGS = {"Einstellungen", "Settings"}
local GROUP_TOOLS = {"Werkzeuge", "Tools"}
local GROUP_MORE = {"Sonstiges", "More"}

----------------------------------------------------------------------
-- Shared small pieces
----------------------------------------------------------------------
local function row(form, height) local y = form.y; form.y = form.y - height; return y end

-- A list row with a label and buttons on the right, filled later by a refresh function.
local function listRow(v, p, y, actions, width)
    local frame = CreateFrame("Frame", nil, p)
    frame:SetSize(width or C.Width, 28)
    frame:SetPoint("TOPLEFT", 0, y)
    frame.label = T.Text(frame, "", "GameFontHighlightSmall", "text")
    frame.label:SetPoint("LEFT", 4, 0)
    frame.label:SetWidth((width or C.Width) - #actions * 152 - 8)
    frame.label:SetWordWrap(false)
    local right = 0
    for index = #actions, 1, -1 do
        local spec = actions[index]
        local button = T.Button(frame, pick(spec[1]), 146, 24, function(self)
            spec[2](self:GetParent())
            v:Changed()
        end, spec[3] or "secondary")
        button:SetPoint("RIGHT", -right, 0)
        frame["button" .. index] = button
        right = right + 152
    end
    frame:Hide()
    return frame
end

----------------------------------------------------------------------
-- Overview: a compact dashboard. Profile line, eight quick switches, four direct links.
-- Every switch reads and writes the same key as its detail page, so both stay in step.
----------------------------------------------------------------------
-- Up to 0.3 some keys sat below a topic switch (Logic.Masters). The data migration turns
-- every topic switch on, but a quick switch still never claims to work while its topic is off,
-- and it never flips the topic switch itself, because that would change other features too.
local function masterOff(key)
    local d = db()
    for master, children in pairs(L.Masters) do
        if children[key] ~= nil and d[master] == false then return true end
    end
    return false
end

-- The error filter only does something when it hides the text or mutes the sound for at least
-- one kind of message. The quick switch shows that real state.
local ERROR_KINDS = {"errResource", "errCooldown", "errRange", "errTarget"}

local function errFilterWorks()
    local d = db()
    if d.errorFilter ~= true or (d.errShowText == true and d.errPlaySound == true) then return false end
    if d.errAll then return true end
    for _, key in ipairs(ERROR_KINDS) do if d[key] then return true end end
    return false
end

-- Turning it on from the overview restores the filter's own shipped choices only where it
-- would otherwise stay without effect. Nothing outside the error filter changes.
local function setErrFilter(on)
    local d = db()
    d.errorFilter = on
    if not on then return end
    if d.errShowText == true and d.errPlaySound == true then
        d.errShowText, d.errPlaySound = L.Defaults.errShowText, L.Defaults.errPlaySound
    end
    local any = d.errAll
    for _, key in ipairs(ERROR_KINDS) do any = any or d[key] end
    if not any then
        for _, key in ipairs(ERROR_KINDS) do d[key] = L.Defaults[key] end
    end
end

local function jumpTo(page, anchor) return function(v) v:Jump(page, anchor) end end

U.Quick = {
    {key = "vendorJunk", title = {"Müll automatisch verkaufen", "Sell junk automatically"},
        desc = {"Verkauft graue Gegenstände beim Händler.", "Sells grey items at vendors."}, open = jumpTo("loot", "vendor")},
    {key = "vendorRepair", title = {"Automatisch reparieren", "Repair automatically"},
        desc = {"Repariert Ausrüstung beim Händler.", "Repairs your gear at vendors."}, open = jumpTo("loot", "vendorRepair")},
    {key = "fastLoot", title = {"Quicker Loot", "Quicker Loot"},
        desc = {"Beschleunigt das Plündern von Gegenständen.", "Speeds up looting items."}},
    {key = "lootFeed", title = {"Loot-Anzeige", "Loot display"},
        desc = {"Blendet erhaltene Gegenstände kurz ein.", "Briefly shows items you receive."}, open = jumpTo("loot", "popup")},
    {key = "mapLevels", title = {"Karten-Level", "Map levels"},
        desc = {"Zeigt empfohlene Levelbereiche auf der Weltkarte.", "Shows recommended level ranges on the world map."}, open = jumpTo("map", "levels"),
        blocked = function()
            local other = NS.MapTools.LevelsElsewhere()
            return other and string.format(tr("Läuft über %s", "Shown by %s"), other) or nil
        end},
    {key = "modBuffs", title = {"Buff-Warnungen", "Buff warnings"},
        desc = {"Zeigt Hinweise auf fehlende oder auslaufende Buffs.", "Shows hints for missing or expiring buffs."}, open = jumpTo("buffs")},
    {key = "modInfoBar", title = {"Infoleiste", "Info bar"},
        desc = {"Zeigt Informationen wie Gold, Zeit und Ort.", "Shows information such as gold, time and location."}, open = jumpTo("infobar")},
    {id = "errorFilter", title = {"Fehlermeldungen filtern", "Filter error messages"},
        desc = {"Filtert ausgewählte wiederkehrende rote Fehlermeldungen.", "Filters selected recurring red error messages."},
        tip = {"Blendet die gewählten roten Meldungen aus und schaltet ihren Fehlerton stumm. Welche Meldungen und ob Text oder Ton, stellst du unter „Einstellen“ ein.",
            "Hides the chosen red messages and mutes their error sound. Which messages, and whether text or sound, is set under “Configure”."},
        get = errFilterWorks, set = setErrFilter, open = jumpTo("interface", "errors")},
}

function U.QuickActive(entry)
    local key = entry.key
    if entry.blocked and entry.blocked() then return false end
    if key and masterOff(key) then return false end
    if entry.get then return entry.get() == true end
    return db()[key] == true
end

local function quickBlocked(entry)
    return function()
        local reason = entry.blocked and entry.blocked()
        if reason then return reason end
        if entry.key and masterOff(entry.key) then return tr("Bereich ist aus", "Topic is off") end
        return nil
    end
end

local function setupDone() return type(db().setup) == "table" and db().setup.complete == true end

local function buildOverview(form, v, p)
    local width = C.Width
    -- Profile and how many quick switches are on.
    local status = form:Note({text = function()
        local on = 0
        for _, entry in ipairs(U.Quick) do if U.QuickActive(entry) then on = on + 1 end end
        return string.format(tr("Profil: %s   ·   %d von %d Schnellfunktionen aktiv", "Profile: %s   ·   %d of %d quick functions active"),
            NS.Profiles.Active(), on, #U.Quick)
    end, height = 16})
    T.Tint(status, "SetTextColor", "textSoft")
    v.overviewStatus = status

    -- First setup: offered prominently until the wizard was finished or skipped once.
    local bannerTop = form.y
    local banner = CreateFrame("Frame", nil, p, BackdropTemplateMixin and "BackdropTemplate" or nil)
    banner:SetPoint("TOPLEFT", 0, bannerTop)
    banner:SetSize(width, 64)
    T.Panel(banner, "surface")
    local bannerTitle = T.Text(banner, tr("Erste Schritte", "First steps"), "GameFontNormal", "gold")
    bannerTitle:SetPoint("TOPLEFT", 14, -12)
    local bannerText = T.Text(banner, tr("Der Einrichtungsassistent führt in wenigen Schritten durch die wichtigsten Helfer. Deine Einstellungen bleiben, bis du sie bestätigst.",
        "The setup wizard walks you through the main helpers in a few steps. Your settings stay until you confirm."), "GameFontHighlightSmall", "textSoft")
    bannerText:SetPoint("TOPLEFT", 14, -30)
    bannerText:SetWidth(width - 220)
    local start = T.Button(banner, tr("Einrichtung starten", "Start setup"), 180, 28, function() NS.Setup.Open() end, "primary")
    start:SetPoint("RIGHT", -14, 0)
    local BANNER = 76
    v.overviewBanner = banner

    -- Everything below moves up when the banner is not needed.
    local body = CreateFrame("Frame", nil, p)
    body:SetWidth(width)
    local by = 0
    W.Section(body, tr("Schnelleinstellungen", "Quick settings"), by, width)
    by = by - 28
    local hint = T.Text(body, tr("Direkt hier ein- und ausschalten. Gilt sofort und wird gespeichert.", "Switch on and off right here. Applies at once and is saved."), "GameFontHighlightSmall", "dim")
    hint:SetPoint("TOPLEFT", 0, by)
    hint:SetWidth(width)
    by = by - 22
    -- Two columns; the window scales as a whole, so the grid keeps its shape on small screens.
    local gap = 10
    local tileWidth = math.floor((width - gap) / 2)
    for index, entry in ipairs(U.Quick) do
        local column, line = (index - 1) % 2, math.floor((index - 1) / 2)
        local tile = C.SwitchTile(v, body, tileWidth, {
            key = entry.key, id = "quick:" .. (entry.key or entry.id), title = entry.title, desc = entry.desc, tip = entry.tip,
            get = entry.get, set = entry.set, open = entry.open, blocked = quickBlocked(entry)})
        tile:SetPoint("TOPLEFT", column * (tileWidth + gap), by - line * (C.TileHeight + gap))
    end
    by = by - math.ceil(#U.Quick / 2) * (C.TileHeight + gap) - 14

    W.Section(body, tr("Direkt öffnen", "Open directly"), by, width)
    by = by - 30
    local links = {
        {title = {"Makros", "Macros"}, desc = {"Makro-Browser", "Macro browser"}, icon = "Interface\\Icons\\INV_Misc_Note_01",
            tip = {"Fertige Makros suchen und übernehmen.", "Find and add ready-made macros."}, action = function() v:SelectPage("macros") end,
            status = function() return string.format(tr("%d Makros", "%d macros"), #NS.MacroData) end},
        {title = {"Grafik", "Graphics"}, desc = {"Erweiterte Grafik", "Advanced graphics"}, icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
            tip = {"Grafikeinstellungen, die das Spielmenü nicht anbietet.", "Graphics settings the game menu does not offer."}, action = function() v:SelectPage("graphics") end,
            status = function()
                local changed = NS.Graphics.ChangedCount(db())
                return changed == 0 and tr("Nichts geändert", "Nothing changed") or string.format(tr("%d geändert", "%d changed"), changed)
            end},
        {title = {"UI-Layouts", "UI layouts"}, desc = {"Layout-Bibliothek", "Layout library"}, icon = "Interface\\Icons\\INV_Misc_Map02",
            tip = {"Layouts für Bearbeitungsmodus und Cooldown Manager ansehen und importieren.", "View and import Edit Mode and Cooldown Manager layouts."}, action = function() v:SelectPage("layouts") end,
            status = function() return string.format(tr("%d gespeichert", "%d saved"), #NS.Layouts.Library().entries) end},
        {title = {"Profile", "Profiles"}, desc = {"Einstellungsprofile", "Settings profiles"}, icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
            tip = {"Profil wechseln, anlegen, teilen oder importieren.", "Switch, create, share or import a profile."}, action = function() v:Jump("advanced", "profiles") end,
            status = function() return NS.Profiles.Active() end},
    }
    local linkWidth = math.floor((width - 3 * 8) / 4)
    v.overviewLinks = {}
    for index, link in ipairs(links) do
        local tile = C.NavTile(v, body, linkWidth, link)
        v.overviewLinks[index] = tile
        tile:SetPoint("TOPLEFT", (index - 1) * (linkWidth + 8), by)
    end
    by = by - C.NavTileHeight - 16

    -- After setup only a small way back into the wizard.
    local again = T.Button(body, tr("Einrichtung erneut starten", "Run setup again"), 220, 24, function() NS.Setup.Open() end, "secondary")
    again:SetPoint("TOPLEFT", 0, by)
    C.Tooltip(again, tr("Einrichtung erneut starten", "Run setup again"),
        tr("Öffnet den Einrichtungsassistenten. Er übernimmt erst etwas, wenn du ihn abschließt.", "Opens the setup wizard. It only applies something once you finish it."))
    v.overviewAgain = again
    by = by - 30
    body:SetHeight(-by)

    v:AddUpdate(function()
        local done = setupDone()
        banner:SetShown(not done)
        again:SetShown(done)
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", 0, bannerTop - (done and 0 or BANNER))
    end)
    -- Room for the banner is always reserved in the page height; without it the page only scrolls a little less.
    form.y = bannerTop - BANNER + by
end

U.AddPage({id = "overview", title = {"Übersicht", "Overview"}, heading = {"ZENIAL Utility", "ZENIAL Utility"}, icon = "Interface\\Icons\\INV_Misc_Book_09",
    desc = {"Deine wichtigsten Einstellungen auf einen Blick.", "Your most important settings at a glance."},
    keywords = "start home übersicht overview dashboard schnell quick schnelleinstellungen",
    search = {
        {id = "quick", title = {"Schnelleinstellungen", "Quick settings"}, keywords = "schnell quick dashboard"},
        {id = "quick", title = {"Einrichtung erneut starten", "Run setup again"}, keywords = "setup assistent einrichtung wizard config"},
    },
    nodes = {custom("quick", buildOverview)}})

----------------------------------------------------------------------
-- Everyday comfort
----------------------------------------------------------------------
local function buildRolls(form, v, p)
    local y = row(form, 112)
    v.rollLabel = T.Text(p, "", "GameFontHighlightSmall", "text")
    v.rollLabel:SetPoint("TOPLEFT", C.Indent, y)
    v.rollLabel:SetWidth(C.Width - C.Indent)
    v.rollLabel:SetHeight(104)
end

U.AddPage({id = "comfort", group = GROUP_SETTINGS, title = {"Spielkomfort", "Everyday comfort"}, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    desc = {"Quests, NPC-Dialoge, Taschen, Post, Erfahrung, Screenshots und Würfeln.", "Quests, NPC dialogs, bags, mail, experience, screenshots and rolls."},
    keywords = "qol quality of life komfort comfort",
    nodes = {
        section("quests", {"Quests", "Quests"}, {"Shift beim Ansprechen des NPCs pausiert jede Automatik einmal.", "Holding Shift while talking to the NPC pauses each automation once."}, "quest auftrag"),
        toggle("questAccept", {"Quests automatisch annehmen", "Accept quests automatically"}, {"Nimmt angebotene Quests ohne Klick an.", "Accepts offered quests without a click."}, {keywords = "auto accept annehmen"}),
        toggle("questRepeatable", {"Auch wiederholbare Quests annehmen", "Also accept repeatable quests"}, {"Zum Beispiel tägliche Quests.", "For example daily quests."}, {parent = "questAccept", keywords = "daily täglich"}),
        choice("questDifficulty", {"Welche Quests annehmen", "Which quests to accept"},
            {{"all", {"Alle", "All"}}, {"nogray", {"Keine grauen", "No grey ones"}}, {"nogreen", {"Keine grauen und grünen", "No grey or green ones"}}},
            {parent = "questAccept", desc = {"Graue und grüne Quests geben wenig Erfahrung.", "Grey and green quests give little experience."}, keywords = "schwierigkeit difficulty grau grün trivial"}),
        toggle("questTurnIn", {"Fertige Quests automatisch abgeben", "Turn in finished quests automatically"}, {"Nicht bei einer Belohnungswahl oder wenn die Quest Gold kostet.", "Not when you choose a reward or the quest costs gold."}, {keywords = "abgeben turn in complete"}),
        toggle("questRewardValue", {"Händlerwert der Belohnungen anzeigen", "Show the vendor value of rewards"}, {"Hilft bei der Wahl der Belohnung: der wertvollste Gegenstand ist markiert.", "Helps choosing a reward: the most valuable item is marked."}, {keywords = "gold preis price belohnung reward"}),
        toggle("questZoneTrack", {"Gebiets-Häkchen im Questlog", "Zone checkbox in the quest log"}, {"Verfolgt alle Quests eines Gebiets auf einmal, bis zum Limit der Questverfolgung.", "Tracks all quests of a zone at once, up to the tracker's limit."}, {keywords = "tracker verfolgen questlog"}),

        section("dialogs", {"NPC-Dialoge und Unterbrechungen", "NPC dialogs and interruptions"}, nil, "gossip dialog"),
        toggle("skipGossip", {"Eindeutige Dienst-Dialoge überspringen", "Skip clear service dialogs"}, {"Öffnet Händler, Flugmeister oder Bank direkt, wenn der NPC nur das anbietet. Ruhestein binden nie.", "Opens the vendor, flight master or bank directly when the NPC offers only that. Never binds the hearthstone."}, {keywords = "gossip händler flugmeister bank skip"}),
        toggle("declineDuels", {"Duellanfragen ablehnen", "Decline duel requests"}, nil, {keywords = "duell duel pvp"}),
        toggle("bgRelease", {"Auf Schlachtfeldern sofort freilassen", "Release instantly in battlegrounds"}, {"Lässt den Geist nach dem Tod frei. Nicht mit Seelenstein.", "Releases your spirit after death. Not with a soulstone."}, {keywords = "battleground schlachtfeld pvp geist spirit release"}),

        section("bags", {"Taschen und Post", "Bags and mail"}, nil, "inventar inventory"),
        toggle("bagMove", {"Taschenfenster verschiebbar", "Movable bag window"}, {"Mit Shift ziehen. Gilt für das gemeinsame Taschenfenster.", "Shift-drag. Applies to the combined bag window."}, {keywords = "tasche bag verschieben move"}),
        buttons({{text = {"Taschenposition zurücksetzen", "Reset bag position"}, width = 240, action = function() NS.Inventory.ResetBagPosition() end}}, {indent = true}),
        toggle("mailAlts", {"Eigene Charaktere als Empfänger anbieten", "Offer own characters as recipients"}, {"Im Postfach: Twinks auf demselben Realm und derselben Fraktion zur Auswahl.", "In the mailbox: alts on the same realm and faction to choose from."}, {keywords = "post mail twink alt briefkasten"}),

        section("xp", {"Erfahrungsleiste", "Experience bar"}, nil, "xp exp level"),
        toggle("xpText", {"Erfahrungszahlen dauerhaft zeigen", "Always show experience numbers"}, nil, {keywords = "xp text"}),
        toggle("xpPercent", {"Prozentwert anzeigen", "Show the percentage"}, nil, {keywords = "prozent percent"}),

        section("screenshots", {"Screenshots", "Screenshots"}, nil, "bildschirmfoto screenshot"),
        toggle("screenshotLevel", {"Bei Stufenaufstieg", "On level up"}, nil, {keywords = "level up stufe"}),
        toggle("screenshotBoss", {"Beim Bosskill", "On boss kill"}, nil, {keywords = "boss raid dungeon"}),

        section("rolls", {"Würfeln", "Rolls"}, nil, "roll würfel /roll"),
        toggle("rollTracker", {"Würfelfenster für /roll", "Roll window for /roll"}, {"Sammelt eigene Würfe und die der Gruppe. Bedarf und Gier zählen nicht. Nach 2 Minuten Pause beginnt eine neue Runde.",
            "Collects your rolls and your group's. Need and Greed do not count. A new round starts after a 2 minute pause."}, {keywords = "roll würfeln dice"}),
        custom("rollList", buildRolls),
        buttons({
            {text = {"Würfelfenster zeigen", "Show roll window"}, width = 190, action = function() NS.RollWindow.Update(true) end},
            {text = {"Würfe leeren", "Clear rolls"}, width = 150, action = function() NS.Helpers.ClearRolls() end},
            {text = {"Gewinner ansagen", "Announce winner"}, width = 180, action = function(v)
                if not NS.Helpers.AnnounceWinner() then v:SetMessage(tr("Dafür braucht es einen Wurf und eine Gruppe.", "This needs a roll and a group.")) end
            end},
        }, {indent = true}),
    }})

----------------------------------------------------------------------
-- Loot and vendors
----------------------------------------------------------------------
local function buildRestock(form, v, p)
    local B = NS.AutoBuy
    local S = function() return B.Settings() end
    form:Toggle({id = "autoBuyEnabled", title = {"Einkaufsliste beim Händler zeigen", "Show the shopping list at vendors"},
        desc = {"Bietet fehlende Reagenzien, Giftzutaten und Munition zum Kauf an.", "Offers missing reagents, poison ingredients and ammo for purchase."},
        get = function() return S().enabled end, set = function(value) S().enabled = value end})
    form:Toggle({id = "autoBuyAuto", title = {"Ohne Nachfrage kaufen", "Buy without asking"},
        desc = {"Kauft beim Öffnen des Händlers sofort. Die Grenzen unten gelten immer.", "Buys as soon as the vendor opens. The limits below always apply."},
        parent = function() return S().enabled end,
        get = function() return S().auto == true and S().confirm == false end,
        set = function(value) S().auto = value; S().confirm = not value end})
    local enabled = function() return S().enabled end
    form:Slider({id = "maxCost", title = {"Höchstens pro Händlerbesuch", "At most per vendor visit"}, min = 0, max = 1000, step = 5, parent = enabled,
        format = function(value) return value == 0 and tr("Kein Limit", "No limit") or (value .. " " .. tr("Gold", "gold")) end,
        get = function() return tonumber(S().maxCost) or 0 end, set = function(value) S().maxCost = value end})
    form:Slider({id = "ammoTarget", title = {"Munition: Zielmenge", "Ammo: target amount"}, min = 0, max = 5000, step = 100, parent = enabled,
        format = function(value) return value == 0 and tr("Nicht kaufen", "Do not buy") or tostring(value) end,
        get = function() return tonumber(S().ammoTarget) or 0 end, set = function(value) S().ammoTarget = value end})
    if A.PlayerClass() == "ROGUE" then
        form:Slider({id = "poisonStop", title = {"Keine Giftzutaten ab so vielen Giften", "No poison ingredients from this many poisons"}, min = 0, max = 200, step = 5, parent = enabled,
            format = function(value) return value == 0 and tr("Immer kaufen", "Always buy") or tostring(value) end,
            get = function() return tonumber(S().poisonStop) or 0 end, set = function(value) S().poisonStop = value end})
    end
    local _, height = form:Text(tr("Zielmengen je Reagenz (0 = nicht kaufen). In Klammern: was du gerade dabei hast.", "Target amount per reagent (0 = do not buy). In brackets: what you carry right now."), 0)
    form.y = form.y - height - 6
    if B.HasReagentEconomy() then
        local _, h2 = form:Text(tr("Reagent Economy ist erlernt: mit „nicht nötig“ markierte Reagenzien brauchst du nicht mehr.", "Reagent Economy is learned: reagents marked “not needed” are no longer required."), 0)
        form.y = form.y - h2 - 6
    end
    local catalog = B.Catalog()
    if #catalog == 0 then
        local _, h3 = form:Text(tr("Deine Klasse braucht keine Reagenzien vom Händler.", "Your class needs no reagents from vendors."), 0, nil, nil, "textSoft")
        form.y = form.y - h3 - 6
    end
    local items = _G.C_Item
    for _, entry in ipairs(catalog) do
        local item = entry.item
        local y = row(form, 30)
        local label = T.Text(p, "", "GameFontHighlight", "text")
        label:SetPoint("TOPLEFT", 0, y - 5)
        label:SetWidth(420)
        v:AddUpdate(function()
            local itemName = items and A.Call(items.GetItemNameByID, item)
            -- Every class item can be chosen; a short note says when it is not needed yet.
            local note = (entry.spared and tr("  · nicht nötig", "  · not needed"))
                or (not entry.learned and tr("  · noch nicht erlernt", "  · not learned yet")) or ""
            label:SetText(string.format("%s  (%d)%s", itemName or ("#" .. item), A.ItemCount(item), note))
            T.Tint(label, "SetTextColor", enabled() and "text" or "disabledText")
        end)
        local edit = W.Edit(p, 440, y, 90, function(text)
            B.SetTarget(item, tonumber(text))
            B.SettingsChanged()
        end)
        W.Tooltip(edit, tr("Zielmenge", "Target amount"), tr("So viele sollen nach dem Einkauf in den Taschen sein.", "This many should be in your bags after shopping."))
        v:AddUpdate(function() if not edit:HasFocus() then edit:SetText(tostring(B.GetTarget(item))) end end)
    end
end

local function buildSellStats(form, v, p)
    local y = row(form, 22)
    local stats = T.Text(p, "", "GameFontHighlightSmall", "muted")
    stats:SetPoint("TOPLEFT", C.Indent, y)
    stats:SetWidth(C.Width - C.Indent)
    v:AddUpdate(function()
        local data = db().sellStats
        stats:SetText(string.format(tr("Bisher %d graue Gegenstände für %s verkauft.", "So far %d grey items sold for %s."), tonumber(data.count) or 0, A.Money(tonumber(data.total) or 0)))
    end)
end

U.AddPage({id = "loot", group = GROUP_SETTINGS, title = {"Beute & Händler", "Loot & vendors"}, icon = "Interface\\Icons\\INV_Misc_Bag_10",
    desc = {"Plündern, Loot-Popup, Verkaufen, Reparieren und Nachkaufen.", "Looting, loot popup, selling, repairing and restocking."},
    keywords = "loot beute plündern händler vendor merchant",
    nodes = {
        section("looting", {"Plündern", "Looting"}, nil, "loot beute plündern quicker loot"),
        toggle("fastLoot", {"Schnelles Plündern", "Fast looting"}, {"Sammelt alles sofort ein. Folgt deiner Einstellung für automatisches Plündern und der Taste dafür.", "Picks up everything at once. Follows your auto loot setting and its modifier key."}, {keywords = "quicker loot schnell fast auto loot autoloot"}),
        toggle("lootConfirmSolo", {"Bindungsfrage allein überspringen", "Skip the bind question when alone"}, {"Nur ohne Gruppe. In der Gruppe fragt das Spiel weiter.", "Only without a group. In a group the game still asks."}, {keywords = "bind binden seelengebunden soulbound bestätigen confirm"}),
        toggle("lootGreed", {"Bei grünen Gegenständen Gier würfeln", "Roll Greed on green items"}, {"Automatisch in der Gruppe. Nie bei Gegenständen, die beim Aufheben binden.", "Automatically in groups. Never on items that bind when picked up."}, {keywords = "gier greed würfeln roll need bedarf"}),

        section("popup", {"Loot-Popup", "Loot popup"}, {"Zeigt eingesammelte Gegenstände kurz am Bildschirm an.", "Briefly shows items you pick up on screen."}, "loot anzeige feed popup beute"),
        toggle("lootFeed", {"Loot-Popup anzeigen", "Show the loot popup"}, nil, {keywords = "loot feed anzeige display beute"}),
        slider("lootFeedTime", {"Anzeigedauer", "Display time"}, 2, 5, 1, {parent = "lootFeed", format = seconds, keywords = "dauer duration zeit time"}),
        slider("lootFeedScale", {"Größe", "Size"}, .6, 1.6, .05, {parent = "lootFeed", format = scaleText, keywords = "skalierung scale größe size"}),
        toggle("lootFeedQuality", {"Nur ungewöhnliche und bessere Gegenstände", "Only uncommon and better items"}, {"Questgegenstände erscheinen immer.", "Quest items always appear."}, {parent = "lootFeed", keywords = "qualität quality grün green"}),
        toggle("lootFeedTooltip", {"Tooltip beim Hinzeigen", "Tooltip on hover"}, {"Die Einträge nehmen dann Mausklicks an.", "Entries then take mouse clicks."}, {parent = "lootFeed", keywords = "tooltip maus mouse"}),
        buttons({
            {text = {"Position ändern", "Change position"}, width = 170, tip = {"Popup ziehen, danach erneut klicken.", "Drag the popup, then click again."}, action = function(v)
                local F = NS.LootFeed
                F.SetMoving(not F.moving)
                v:SetMessage(F.moving and tr("Popup an die gewünschte Stelle ziehen, dann erneut auf „Position ändern“ klicken.", "Drag the popup where you want it, then click “Change position” again.") or tr("Position gespeichert.", "Position saved."))
            end},
            {text = {"Vorschau zeigen", "Show preview"}, width = 160, action = function(v)
                if not NS.LootFeed.Preview() then v:SetMessage(tr("Erst das Loot-Popup einschalten.", "Turn on the loot popup first.")) end
            end},
            {text = {"Position zurücksetzen", "Reset position"}, width = 190, action = function(v) NS.LootFeed.ResetPosition(); v:SetMessage(tr("Position zurückgesetzt.", "Position reset.")) end},
        }, {indent = true}),

        section("vendor", {"Beim Händler", "At vendors"}, {"Shift beim Öffnen des Händlers überspringt alles einmal.", "Holding Shift while opening the vendor skips everything once."}, "händler vendor merchant"),
        toggle("vendorJunk", {"Graue Gegenstände verkaufen", "Sell grey items"}, {"Verkauft Plunder automatisch beim Händler.", "Sells junk automatically at the vendor."}, {keywords = "junk müll plunder grau grey sell verkaufen"}),
        custom("sellStats", buildSellStats),
        toggle("vendorRepair", {"Automatisch reparieren", "Repair automatically"}, {"Repariert alle Gegenstände, sobald der Händler das kann.", "Repairs all items when the vendor can."}, {keywords = "repair reparatur reparieren haltbarkeit durability"}),
        toggle("vendorGuildRepair", {"Zuerst aus der Gildenbank reparieren", "Repair from the guild bank first"}, nil, {parent = "vendorRepair", keywords = "gilde guild"}),
        toggle("vendorChat", {"Betrag im Chat melden", "Report the amount in chat"}, {"Erlös und Reparaturkosten.", "Earnings and repair costs."}, {keywords = "chat gold"}),

        section("restock", {"Nachkaufen (nur dieser Charakter)", "Restock (this character only)"}, {"Reagenzien, Giftzutaten und Munition. Jeder Charakter hat seine eigene Liste.", "Reagents, poison ingredients and ammo. Each character has its own list."}, "reagenzien reagents munition ammo gift poison kaufen buy"),
        custom("restockList", buildRestock, {
            {id = "restock", title = {"Einkaufsliste beim Händler zeigen", "Show the shopping list at vendors"}, keywords = "auto buy einkaufen"},
            {id = "restock", title = {"Ohne Nachfrage kaufen", "Buy without asking"}, keywords = "auto buy automatik"},
            {id = "restock", title = {"Munition: Zielmenge", "Ammo: target amount"}, keywords = "pfeile kugeln arrows bullets"},
        }),

        section("destroy", {"Graue Gegenstände zerstören", "Destroy grey items"}, nil, "zerstören destroy löschen delete"),
        toggle("destroyGray", {"Zerstören per Klick erlauben", "Allow destroying by click"}, {"Shift-Klick auf „Billigster grauer Stapel“ der Infoleiste oder der Button hier. Nie im Kampf, nie automatisch.", "Shift-click the info bar's cheapest grey stack or the button here. Never in combat, never automatically."}, {keywords = "zerstören destroy"}),
        toggle("destroyConfirm", {"Vorher nachfragen", "Ask first"}, nil, {parent = "destroyGray"}),
        buttons({{text = {"Billigsten grauen Stapel zerstören", "Destroy cheapest grey stack"}, width = 290, enabled = function() return db().destroyGray == true end, action = function(v)
            if not NS.Inventory.RequestDestroy() then v:SetMessage(tr("Gerade nichts zu zerstören oder nicht erlaubt.", "Nothing to destroy right now, or not allowed.")) end
        end}}, {indent = true}),
    }})

----------------------------------------------------------------------
-- Interface and messages
----------------------------------------------------------------------
-- Two plain switches over the three stored error keys: hide the text, mute the sound.
local function errHide() local d = db(); return d.errorFilter == true and d.errShowText ~= true end
local function errMute() local d = db(); return d.errorFilter == true and d.errPlaySound ~= true end
local function setErrHide(on)
    local d, mute = db(), errMute()
    d.errShowText, d.errPlaySound, d.errorFilter = not on, not mute, on or mute
end
local function setErrMute(on)
    local d, hideText = db(), errHide()
    d.errPlaySound, d.errShowText, d.errorFilter = not on, not hideText, on or hideText
end
local function errKindsActive() return db().errorFilter == true end
local function errSingleKinds() return db().errorFilter == true and not db().errAll end

local VISIBILITY = {{"show", {"Anzeigen", "Show"}}, {"hover", {"Nur bei Mauskontakt", "Only on mouse over"}}, {"hide", {"Ausblenden", "Hide"}}}

local function spellLabel(spell, rank)
    local name = A.SpellName(spell) or ("#" .. tostring(spell))
    return rank and rank > 0 and string.format(tr("%s (Rang %d)", "%s (Rank %d)"), name, rank) or name
end

local RANK_ROWS = 8

function U.RefreshRankRows(v)
    local K = NS.ActionRanks
    local open, ignored = {}, {}
    for slot = 1, 180 do
        local mark = K.marks[slot]
        if mark and not mark.ignored then open[#open + 1] = mark end
    end
    local spells, slots = {}, {}
    for spell in pairs(db().rankIgnore) do spells[#spells + 1] = spell end
    for slot in pairs(K.IgnoredSlots()) do slots[#slots + 1] = slot end
    table.sort(spells)
    table.sort(slots)
    for _, spell in ipairs(spells) do ignored[#ignored + 1] = {spell = spell} end
    for _, slot in ipairs(slots) do ignored[#ignored + 1] = {slot = slot} end
    for index, frame in ipairs(v.rankRows) do
        local mark = open[index]
        frame.mark = mark
        if mark then
            frame.label:SetText(string.format(tr("Platz %d: %s – erlernt: Rang %d", "Slot %d: %s – learned: Rank %d"),
                mark.slot, spellLabel(mark.spell, mark.rank), mark.bestRank or 0))
        end
        frame:SetShown(mark ~= nil)
    end
    for index, frame in ipairs(v.rankIgnoreRows) do
        local entry = ignored[index]
        frame.entry = entry
        if entry and entry.spell then
            frame.label:SetText(tr("Zauber: ", "Spell: ") .. spellLabel(entry.spell))
        elseif entry then
            local kind, id = A.Call(GetActionInfo, entry.slot)
            local held = kind == "spell" and type(id) == "number" and ("  ·  " .. spellLabel(id)) or ""
            frame.label:SetText(string.format(tr("Platz %d", "Slot %d"), entry.slot) .. held)
        end
        frame:SetShown(entry ~= nil)
    end
    local status
    if not K.Enabled() then
        status = tr("Die Prüfung ist aus.", "The check is off.")
    elseif #open == 0 then
        status = tr("Keine veralteten Ränge auf den Aktionsleisten.", "No outdated ranks on the action bars.")
    else
        status = string.format(tr("%d Aktionsbutton(s) mit veraltetem Rang.", "%d action button(s) with an outdated rank."), #open)
        if #open > RANK_ROWS then status = status .. string.format(tr(" Die ersten %d stehen hier.", " The first %d are listed."), RANK_ROWS) end
    end
    v.rankStatus:SetText(status)
    v.rankIgnoreTitle:SetShown(#ignored > 0)
end

local function buildRanks(form, v, p)
    local K = NS.ActionRanks
    local y = row(form, 24)
    v.rankStatus = T.Text(p, "", "GameFontHighlightSmall", "textSoft")
    v.rankStatus:SetPoint("TOPLEFT", C.Indent, y)
    v.rankStatus:SetWidth(C.Width - C.Indent)
    v.rankRows = {}
    for index = 1, RANK_ROWS do
        v.rankRows[index] = listRow(v, p, form.y - (index - 1) * 30, {
            {{"Zauber ignorieren", "Ignore spell"}, function(frame) if frame.mark then K.IgnoreSpell(frame.mark.spell, true) end end},
            {{"Platz ignorieren", "Ignore slot"}, function(frame) if frame.mark then K.IgnoreSlot(frame.mark.slot, true) end end},
        })
    end
    form.y = form.y - RANK_ROWS * 30
    y = row(form, 26)
    v.rankIgnoreTitle = T.Text(p, tr("Ausnahmen (werden nicht markiert)", "Exceptions (not marked)"), "GameFontNormal", "gold")
    v.rankIgnoreTitle:SetPoint("TOPLEFT", 0, y - 4)
    v.rankIgnoreRows = {}
    for index = 1, RANK_ROWS do
        v.rankIgnoreRows[index] = listRow(v, p, form.y - (index - 1) * 30, {
            {{"Wieder prüfen", "Check again"}, function(frame)
                local entry = frame.entry
                if entry and entry.spell then K.IgnoreSpell(entry.spell, false) elseif entry then K.IgnoreSlot(entry.slot, false) end
            end},
        })
    end
    form.y = form.y - RANK_ROWS * 30
    v:AddUpdate(function() U.RefreshRankRows(v) end)
end

local function anyWarning()
    local d = db()
    return d.warnDurability or d.warnBags or d.warnAmmo or d.warnPoison or d.warnReagents
end

U.AddPage({id = "interface", group = GROUP_SETTINGS, title = {"Interface & Meldungen", "Interface & messages"}, icon = "Interface\\Icons\\INV_Misc_Gear_01",
    desc = {"Rote Fehlermeldungen und Fehlertöne, Warnhinweise, ausgeblendete Elemente und Zauberränge.", "Red error messages and error sounds, warnings, hidden elements and spell ranks."},
    keywords = "ui interface oberfläche meldung message",
    resetKeys = {"errorFilter", "errShowText", "errPlaySound"},
    nodes = {
        section("errors", {"Fehlermeldungen und Fehlertöne", "Error messages and error sounds"},
            {"Gilt für die roten Meldungen oben am Bildschirm, zum Beispiel „Nicht genug Mana“. Andere Sounds bleiben unberührt.", "Applies to the red messages at the top of the screen, for example “Not enough mana”. Other sounds stay untouched."},
            "error fehler rot red uierrors"),
        toggle(nil, {"Fehlertöne stummschalten", "Mute error sounds"}, {"Kein Warnton und keine Sprachausgabe wie „Das ist noch nicht bereit“.", "No warning tone and no voice line like “That ability isn't ready yet”."},
            {id = "errMute", get = errMute, set = setErrMute, keywords = "sound ton audio stumm mute voice sprache stimme warnton geräusch noise lautlos"}),
        toggle(nil, {"Rote Fehlermeldungen ausblenden", "Hide red error messages"}, {"Der Text erscheint nicht mehr am Bildschirm.", "The text no longer appears on screen."},
            {id = "errHide", get = errHide, set = setErrHide, keywords = "text meldung message verstecken hide unterdrücken suppress"}),
        toggle("errAll", {"Für alle gewöhnlichen Fehlermeldungen", "For all ordinary error messages"}, {"Sonst nur für die gewählten Arten darunter. Gelbe Hinweise und Systemmeldungen bleiben immer.", "Otherwise only for the kinds chosen below. Yellow notices and system messages always stay."},
            {parent = errKindsActive, parentHint = {"Erst Töne stummschalten oder Meldungen ausblenden.", "First mute sounds or hide messages."}, keywords = "alle all"}),
        toggle("errResource", {"Nicht genug Mana, Energie oder Wut", "Not enough mana, energy or rage"}, nil, {parent = errSingleKinds, keywords = "mana energie energy wut rage fokus focus ressource resource"}),
        toggle("errCooldown", {"Fähigkeit noch nicht bereit", "Ability not ready yet"}, nil, {parent = errSingleKinds, keywords = "abklingzeit cooldown bereit ready"}),
        toggle("errRange", {"Ziel außer Reichweite", "Target out of range"}, nil, {parent = errSingleKinds, keywords = "reichweite range entfernung distance"}),
        toggle("errTarget", {"Kein oder ungültiges Ziel", "No or invalid target"}, nil, {parent = errSingleKinds, keywords = "ziel target"}),

        section("warnings", {"Warnhinweise", "Warnings"}, {"Eine Meldung, sobald der Grenzwert erreicht ist. Erneut erst, nachdem sich der Wert erholt hat.", "One message once the limit is reached. Again only after the value has recovered."}, "warnung warning hinweis"),
        toggle("warnDurability", {"Niedrige Haltbarkeit", "Low durability"}, nil, {keywords = "haltbarkeit durability rüstung armor reparieren repair"}),
        slider("durabilityPercent", {"Warnen ab", "Warn at"}, 5, 50, 5, {parent = "warnDurability", suffix = " %"}),
        toggle("warnBags", {"Fast volle Taschen", "Nearly full bags"}, nil, {keywords = "tasche bag voll full platz space"}),
        slider("bagSlots", {"Warnen ab freien Plätzen", "Warn at free slots"}, 1, 20, 1, {parent = "warnBags"}),
        toggle("warnAmmo", {"Wenig Munition", "Low ammo"}, {"Zählt alle passende Munition in den Taschen.", "Counts all matching ammo in your bags."}, {keywords = "munition ammo pfeile arrows kugeln bullets jäger hunter"}),
        slider("ammoThreshold", {"Warnen ab Schuss", "Warn at rounds"}, 10, 5000, 10, {parent = "warnAmmo"}),
        toggle("warnPoison", {"Abgelaufenes Waffengift (Schurken)", "Expired weapon poison (Rogues)"}, nil, {keywords = "gift poison schurke rogue"}),
        toggle("warnReagents", {"Reagenzien gehen aus", "Reagents running out"}, {"Nur für Reagenzien, die du tatsächlich dabei hattest.", "Only for reagents you actually carried."}, {keywords = "reagenzien reagents"}),
        toggle("warnSound", {"Warnton dazu abspielen", "Play a warning sound with it"}, nil, {parent = anyWarning, keywords = "sound ton audio"}),

        section("hide", {"Elemente ausblenden", "Hide elements"}, {"Ausgeblendete Elemente sind auch nicht anklickbar. „Nur bei Mauskontakt“ zeigt sie, solange die Maus darüber ist.", "Hidden elements cannot be clicked either. “Only on mouse over” shows them while the mouse is over them."}, "ausblenden hide verstecken minimap"),
        choice("hideBags", {"Taschenleiste", "Bag bar"}, VISIBILITY, {keywords = "tasche bag"}),
        choice("hideMicro", {"Mikromenü", "Micro menu"}, VISIBILITY, {keywords = "menü menu"}),
        choice("hideClock", {"Uhr an der Minikarte", "Minimap clock"}, VISIBILITY, {keywords = "uhr clock zeit time minimap"}),
        choice("hideCalendar", {"Kalender an der Minikarte", "Minimap calendar"}, VISIBILITY, {keywords = "kalender calendar minimap"}),
        choice("hideTracking", {"Aufspüren an der Minikarte", "Minimap tracking"}, VISIBILITY, {keywords = "aufspüren tracking minimap"}),
        choice("hideZoneText", {"Gebietsname an der Minikarte", "Minimap zone name"}, VISIBILITY, {keywords = "gebiet zone name minimap"}),

        section("ranks", {"Zauberränge auf Aktionsleisten", "Spell ranks on action bars"}, {"Markiert Buttons mit einem niedrigeren Rang als dem erlernten. Leisten und Makros bleiben unverändert.", "Marks buttons with a lower rank than the one learned. Bars and macros stay unchanged."}, "rang rank aktionsleiste action bar downrank"),
        toggle("rankCheck", {"Veraltete Zauberränge markieren", "Mark outdated spell ranks"}, {"Kleiner Punkt oben links am Button und ein Hinweis im Tooltip. Nur direkt abgelegte Zauber, keine Makros.", "Small dot in the button's top-left corner and a note in the tooltip. Only spells placed directly, no macros."}, {keywords = "rang rank markieren mark"}),
        toggle("rankNotify", {"Nach dem Erlernen kurz im Chat melden", "Short chat note after learning"}, nil, {parent = "rankCheck", keywords = "chat"}),
        custom("rankList", buildRanks, {{id = "ranks", title = {"Zauber oder Platz ignorieren", "Ignore spell or slot"}, keywords = "ausnahme exception downranking"}}),
    }})

----------------------------------------------------------------------
-- Tooltips
----------------------------------------------------------------------
U.AddPage({id = "tooltip", group = GROUP_SETTINGS, title = {"Tooltips", "Tooltips"}, icon = "Interface\\Icons\\INV_Misc_Book_11",
    desc = {"Was Tooltips von Spielern und Gegenständen zeigen und wo sie erscheinen.", "What player and item tooltips show and where they appear."},
    keywords = "tooltip tooltips hinweis",
    nodes = {
        section("units", {"Charaktere", "Characters"}, nil, "spieler player unit"),
        toggle("ttUnit", {"Charakter-Tooltips anpassen", "Adjust character tooltips"}, {"Bestimmt, welche Angaben der Tooltip eines Spielers zeigt.", "Chooses what a player's tooltip shows."}, {keywords = "spieler player"}),
        choice("ttLayout", {"Aufbau", "Layout"}, {{"compact", {"Kompakt", "Compact"}}, {"lines", {"Eine Angabe pro Zeile", "One per line"}}, {"blizz", {"Wie im Spiel", "As in the game"}}}, {parent = "ttUnit"}),
        toggle("ttLevel", {"Stufe", "Level"}, nil, {parent = "ttUnit"}),
        toggle("ttClass", {"Klasse", "Class"}, nil, {parent = "ttUnit"}),
        toggle("ttRace", {"Volk", "Race"}, nil, {parent = "ttUnit"}),
        toggle("ttFaction", {"Fraktion", "Faction"}, nil, {parent = "ttUnit"}),
        toggle("ttGuild", {"Gilde", "Guild"}, nil, {parent = "ttUnit"}),
        toggle("ttGuildRank", {"Gildenrang", "Guild rank"}, nil, {parent = "ttUnit"}),
        toggle("ttTarget", {"Aktuelles Ziel", "Current target"}, nil, {parent = "ttUnit"}),
        toggle("ttItemLevel", {"Durchschnittliche Gegenstandsstufe", "Average item level"}, {"Bei anderen nur außerhalb des Kampfes und in der Nähe, ab dem zweiten Hinzeigen.", "For others only out of combat and nearby, from the second hover."}, {keywords = "ilvl itemlevel gegenstandsstufe gear"}),
        section("look", {"Darstellung", "Appearance"}),
        choice("ttAnchor", {"Position", "Position"}, {{"default", {"Wie im Spiel", "As in the game"}}, {"TOPLEFT", {"Oben links", "Top left"}}, {"TOPRIGHT", {"Oben rechts", "Top right"}}, {"BOTTOMLEFT", {"Unten links", "Bottom left"}}, {"BOTTOMRIGHT", {"Unten rechts", "Bottom right"}}}, {keywords = "anker anchor ecke corner"}),
        choice("ttHealthBar", {"Lebensbalken", "Health bar"}, {{"default", {"Wie im Spiel", "As in the game"}}, {"flat", {"Flach", "Flat"}}, {"soft", {"Weich", "Soft"}}}, {keywords = "leben health balken bar"}),
        section("extra", {"Zusatzinfos", "Extra info"}),
        toggle("ttGathering", {"Nötige Fertigkeit bei Kräutern, Erzen und Kürschnern", "Skill needed for herbs, ores and skinning"}, {"Klassische Werte. Neue Forever-Vorkommen fehlen noch.", "Classic values. New Forever nodes are not covered yet."}, {keywords = "kräuter herbs erz ore bergbau mining kürschnern skinning beruf profession sammeln gathering"}),
        toggle("tooltipIDs", {"Gegenstands- und Zauber-IDs", "Item and spell IDs"}, {"Für Makros, Datenbanken und Fehlerberichte.", "For macros, databases and bug reports."}, {keywords = "id ids itemid spellid"}),
    }})

----------------------------------------------------------------------
-- Buff warning bars
----------------------------------------------------------------------
local function selectedBar(v)
    local bars = db().warnBars
    v.barIndex = math.max(1, math.min(#bars, v.barIndex or 1))
    return bars[v.barIndex]
end

local function barOptions()
    local out = {}
    for _, bar in ipairs(db().warnBars) do out[#out + 1] = {bar.id, bar.name} end
    return out
end

local function buildBars(form, v, p)
    local R, B = NS.Reminders, NS.WarnBars
    local y = row(form, 34)
    local label = T.Text(p, tr("Leiste bearbeiten", "Edit bar"), "GameFontHighlight", "text")
    label:SetPoint("TOPLEFT", 0, y - 6)
    label:SetWidth(150)
    local pickBar = C.Dropdown(v, p, 200, barOptions, function() return selectedBar(v).id end, function(id)
        for index, bar in ipairs(db().warnBars) do if bar.id == id then v.barIndex = index end end
    end)
    pickBar:SetPoint("TOPLEFT", 150, y)
    local name = W.Edit(p, 360, y, 150, function(text)
        selectedBar(v).name = text ~= "" and text or selectedBar(v).id
        NS.Profiles.Store()
    end)
    W.Tooltip(name, tr("Name der Leiste", "Bar name"))
    v:AddUpdate(function() if not name:HasFocus() then name:SetText(selectedBar(v).name) end end)
    form:Buttons({
        {text = {"Neue Leiste", "New bar"}, width = 140, action = function()
            if not R.AddBar(tr("Neue Leiste", "New bar")) then v:SetMessage(tr("Mehr Leisten sind nicht möglich.", "No more bars possible.")); return end
            v.barIndex = #db().warnBars
            v:Changed()
        end},
        {text = {"Leiste löschen …", "Delete bar …"}, width = 150, variant = "danger", action = function()
            local bar = selectedBar(v)
            if bar.id == L.GeneralBar then v:SetMessage(tr("Die allgemeine Leiste bleibt bestehen.", "The general bar stays.")); return end
            C.Confirm(v, tr("Leiste löschen?", "Delete bar?"), string.format(tr("„%s“ wird gelöscht. Ihre Einträge wandern auf die allgemeine Leiste.", "“%s” is deleted. Its entries move to the general bar."), bar.name),
                tr("Löschen", "Delete"), function()
                    R.DeleteBar(bar.id)
                    v.barIndex = 1
                    v:Changed()
                end, "danger")
        end},
    })
    form:Slider({id = "barSize", title = {"Symbolgröße", "Icon size"}, min = 16, max = 64, step = 2, suffix = " px",
        get = function() return selectedBar(v).size end, set = function(value) selectedBar(v).size = value end})
    form:Choice({id = "barGrow", title = {"Wachstumsrichtung", "Growth direction"},
        options = {{"RIGHT", {"Nach rechts", "To the right"}}, {"LEFT", {"Nach links", "To the left"}}, {"UP", {"Nach oben", "Upward"}}, {"DOWN", {"Nach unten", "Downward"}}},
        get = function() return selectedBar(v).grow end, set = function(value) selectedBar(v).grow = value end})
    form:Toggle({id = "barCountdown", title = {"Restzeit auf den Symbolen", "Time left on the icons"},
        get = function() return selectedBar(v).countdown end, set = function(value) selectedBar(v).countdown = value end})
    form:Buttons({
        {text = {"Leisten verschieben", "Move bars"}, width = 180, action = function()
            B.SetMoving(not B.moving)
            v:SetMessage(B.moving and tr("Leisten ziehen, danach erneut klicken.", "Drag the bars, then click again.") or tr("Position gespeichert.", "Position saved."))
        end},
        {text = {"Vorschau zeigen", "Show preview"}, width = 160, action = function() B.SetPreview(not B.preview) end},
        {text = {"Alle Leisten zurücksetzen …", "Reset all bars …"}, width = 220, action = function()
            C.Confirm(v, tr("Alle Leisten zurücksetzen?", "Reset all bars?"), tr("Eigene Leisten werden gelöscht, Größe und Position kehren zum Standard zurück. Die Einträge bleiben eingestellt.", "Own bars are deleted, size and position return to the default. The entries keep their settings."),
                tr("Zurücksetzen", "Reset"), function()
                    db().warnBars = L.DefaultBars()
                    v.barIndex = 1
                    v:Changed()
                end, "danger")
        end},
    })
end

local function buildEntries(form, v, p)
    local R = NS.Reminders
    local classSet, generalSet = {}, {}
    for _, entry in ipairs(NS.BuffData.classes[A.PlayerClass()] or {}) do classSet[entry] = true end
    for _, entry in ipairs(NS.BuffData.general) do generalSet[entry] = true end
    local lastGroup
    local function barOf(entry) return R.BarOf(entry) end
    for _, entry in ipairs(R.AllEntries()) do
        local group = classSet[entry] and tr("Klasse", "Class") or generalSet[entry] and tr("Sammeln und Lager", "Gathering and camp") or tr("Verbrauchsmaterial", "Consumables")
        if group ~= lastGroup then
            lastGroup = group
            local y = row(form, 24)
            local heading = T.Text(p, group, "GameFontNormal", "gold")
            heading:SetPoint("TOPLEFT", 0, y - 4)
        end
        local y = form.y
        local check = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", 0, y)
        T.StyleCheckbox(check)
        local title = T.Text(p, R.Title(entry), "GameFontHighlight", "text")
        title:SetPoint("TOPLEFT", 30, y - 5)
        title:SetWidth(250)
        title:SetWordWrap(false)
        check:SetScript("OnClick", function(self) R.SetOn(entry.key, self:GetChecked() == true); v:Changed() end)
        local bar = C.Dropdown(v, p, 170, barOptions, function() return barOf(entry) end, function(id) R.SetBar(entry.key, id) end)
        bar:SetPoint("TOPLEFT", 290, y)
        W.Tooltip(bar, tr("Auf welcher Leiste", "On which bar"))
        local edit
        if entry.kind ~= "tracking" then
            edit = W.Edit(p, 470, y, 62, function(text)
                R.SetWarn(entry.key, tonumber(text))
                NS.Profiles.Store()
            end)
            W.Tooltip(edit, tr("Vorwarnzeit in Sekunden", "Warning time in seconds"),
                tr("Leer: je nach Dauer 10 s, 3 min oder 5 min vorher.", "Empty: depending on duration 10 s, 3 min or 5 min before."))
        end
        v:AddUpdate(function()
            local on = db().modBuffs == true
            check:SetChecked(R.IsOn(entry) == true)
            check:SetEnabled(on)
            bar:SetEnabled(on)
            T.Tint(title, "SetTextColor", on and "text" or "disabledText")
            if edit and not edit:HasFocus() then
                local saved = db().reminders[entry.key]
                edit:SetText(saved and saved.warn and tostring(saved.warn) or "")
            end
        end)
        form.y = y - 30
    end
end

U.AddPage({id = "buffs", group = GROUP_SETTINGS, title = {"Warnleisten", "Warning bars"}, icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
    desc = {"Symbole für fehlende oder auslaufende Buffs, Gifte und Verbrauchsmaterial.", "Icons for missing or expiring buffs, poisons and consumables."},
    keywords = "buff buffs reminder erinnerung verbrauchsmaterial consumables flask fläschchen",
    resetExtra = function(data) data.warnBars = L.DefaultBars(); data.reminders = {} end,
    nodes = {
        section("system", {"Warnleisten", "Warning bars"}, {"Erscheinen nur, wenn etwas fehlt, bald ausläuft oder ein höherer Rang erlernt ist. Im Kampf sperrt das Spiel Buffdaten; bis Kampfende bleibt der letzte Stand stehen.",
            "Appear only when something is missing, about to end or a higher rank is learned. In combat the game locks buff data; the last state stays until combat ends."}),
        toggle("modBuffs", {"Warnleisten anzeigen", "Show warning bars"}, nil, {keywords = "buff warnung warning"}),
        toggle("buffGroup", {"Gruppenbuffs zählen", "Count group buffs"}, {"Zeigt Mitglieder in Reichweite ohne deine Buffs. Die Reichweite ist grob.", "Shows members in range without your buffs. The range is rough."}, {parent = "modBuffs", keywords = "gruppe group party raid"}),
        toggle("buffMounted", {"Auch beritten warnen", "Also warn while mounted"}, nil, {parent = "modBuffs", keywords = "reittier mount"}),
        toggle("buffResting", {"Auch in Gasthäusern und Städten warnen", "Also warn in inns and cities"}, nil, {parent = "modBuffs", keywords = "gasthaus inn stadt city"}),
        toggle("warnOnBars", {"Haltbarkeit, Taschen und Munition auch hier zeigen", "Also show durability, bags and ammo here"}, {"Nutzt die Warnhinweise von „Interface & Meldungen“.", "Uses the warnings from “Interface & messages”."}, {parent = "modBuffs"}),
        section("bars", {"Leisten", "Bars"}, {"Mehrere Leisten, zum Beispiel getrennt für Kampf und Verbrauchsmaterial.", "Several bars, for example separate ones for combat and consumables."}, "leiste bar position"),
        custom("barEditor", buildBars, {
            {id = "bars", title = {"Leisten verschieben", "Move bars"}, keywords = "position"},
            {id = "bars", title = {"Symbolgröße", "Icon size"}, keywords = "größe size"},
        }),
        section("entries", {"Einträge", "Entries"}, {"Welche Buffs und Verbrauchsmaterialien warnen, auf welcher Leiste und wie früh. Es warnt nur, was erlernt ist.", "Which buffs and consumables warn, on which bar and how early. Only what is learned warns."}),
        custom("entryList", buildEntries),
    }})

----------------------------------------------------------------------
-- Info bar
----------------------------------------------------------------------
local function buildInfoModules(form, v, p)
    local I = NS.InfoBar
    for index = 1, #I.Modules do
        local key = function() return I.Order()[index] end
        local y = form.y
        local check = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", 0, y)
        T.StyleCheckbox(check)
        check:SetScript("OnClick", function(self) db().infoBar.on[key()] = self:GetChecked() == true; v:Changed() end)
        local label = T.Text(p, "", "GameFontHighlight", "text")
        label:SetPoint("TOPLEFT", 30, y - 5)
        label:SetWidth(400)
        local up = T.Button(p, "▲", 30, 22, function() if I.Move(key(), -1) then v:Changed() end end, "secondary")
        up:SetPoint("TOPLEFT", C.Width - 70, y)
        W.Tooltip(up, tr("Nach vorne", "Move forward"))
        local down = T.Button(p, "▼", 30, 22, function() if I.Move(key(), 1) then v:Changed() end end, "secondary")
        down:SetPoint("TOPLEFT", C.Width - 36, y)
        W.Tooltip(down, tr("Nach hinten", "Move back"))
        v:AddUpdate(function()
            local on = db().modInfoBar == true
            check:SetChecked(I.IsOn(key()) == true)
            check:SetEnabled(on)
            label:SetText(I.Title(I.ByKey[key()]))
            T.Tint(label, "SetTextColor", on and "text" or "disabledText")
            up:SetEnabled(on and index > 1)
            down:SetEnabled(on and index < #I.Modules)
        end)
        form.y = y - 28
    end
end

U.AddPage({id = "infobar", group = GROUP_SETTINGS, title = {"Infoleiste", "Info bar"}, icon = "Interface\\Icons\\INV_Misc_Note_02",
    desc = {"Verschiebbare Leiste mit Gold, Zeit, Ort, Haltbarkeit, Latenz und mehr.", "Movable bar with gold, time, location, durability, latency and more."},
    keywords = "infobar leiste bar gold fps latenz latency uhr clock",
    resetExtra = function(data) data.infoBar = {order = {}, on = {}, x = data.infoBar.x, y = data.infoBar.y} end,
    nodes = {
        section("bar", {"Infoleiste", "Info bar"}),
        toggle("modInfoBar", {"Infoleiste anzeigen", "Show the info bar"}, nil, {keywords = "anzeigen show"}),
        toggle("infoLocked", {"Position sperren", "Lock position"}, {"Ausgeschaltet lässt sich die Leiste mit der Maus ziehen.", "When off, the bar can be dragged with the mouse."}, {parent = "modInfoBar", keywords = "sperren lock verschieben move"}),
        toggle("infoCompact", {"Kompakt", "Compact"}, {"Kürzere Texte, ohne Symbole.", "Shorter texts, no icons."}, {parent = "modInfoBar"}),
        toggle("infoIcons", {"Symbole anzeigen", "Show icons"}, nil, {parent = "modInfoBar", enabled = function() return not db().infoCompact end, keywords = "icons symbole"}),
        toggle("infoColors", {"Statusfarben", "Status colours"}, {"Färbt zum Beispiel Latenz, Haltbarkeit und Munition nach Zustand.", "Colours for example latency, durability and ammo by state."}, {parent = "modInfoBar", keywords = "farbe color"}),
        slider("infoScale", {"Größe", "Size"}, .6, 1.6, .05, {parent = "modInfoBar", format = scaleText, keywords = "skalierung scale"}),
        slider("infoFont", {"Schriftgröße", "Font size"}, 8, 20, 1, {parent = "modInfoBar", suffix = " pt", keywords = "schrift font text"}),
        slider("infoAlpha", {"Hintergrund-Deckkraft", "Background opacity"}, 0, 1, .05, {parent = "modInfoBar", format = percent, keywords = "transparenz transparency alpha"}),
        choice("goldScope", {"Gold-Summe umfasst", "Gold total covers"}, {{"all", {"Alle Charaktere", "All characters"}}, {"faction", {"Eigene Fraktion", "Own faction"}}, {"current", {"Nur diesen Charakter", "This character only"}}}, {parent = "modInfoBar", keywords = "gold geld money"}),
        section("modules", {"Anzeigen und Reihenfolge", "Displays and order"}, {"Häkchen: wird angezeigt. Pfeile: Reihenfolge auf der Leiste.", "Tick: shown. Arrows: order on the bar."}),
        custom("moduleList", buildInfoModules),
    }})

----------------------------------------------------------------------
-- Map
----------------------------------------------------------------------
U.AddPage({id = "map", group = GROUP_SETTINGS, title = {"Karte & Navigation", "Map & navigation"}, icon = "Interface\\Icons\\INV_Misc_Map_01",
    desc = {"Unerkundete Gebiete, Levelbereiche auf der Weltkarte und Wegpunkte.", "Unexplored areas, level ranges on the world map and waypoints."},
    keywords = "karte map weltkarte world map navigation",
    nodes = {
        section("levels", {"Levelbereiche", "Level ranges"}, nil, "level stufe gebiet zone"),
        toggle("mapLevels", {"Levelbereiche auf Kontinentkarten", "Level ranges on continent maps"}, {"Grün: passend für deine Stufe, grau: zu niedrig, rot: zu hoch.", "Green: right for your level, grey: too low, red: too high."},
            {keywords = "level range stufe zone gebiet empfohlen recommended weltkarte",
                enabled = function() return NS.MapTools.LevelsElsewhere() == nil end}),
        choice("mapLevelMode", {"Anzeige", "Display"}, {{"labels", {"Auf der Karte und im Tooltip", "On the map and in the tooltip"}}, {"tooltip", {"Nur im Tooltip", "Tooltip only"}}}, {parent = "mapLevels"}),
        toggle("mapLevelDungeons", {"Dungeons des Gebiets im Tooltip", "The zone's dungeons in the tooltip"}, nil, {parent = "mapLevels", keywords = "dungeon instanz instance"}),
        note(function()
            local other = NS.MapTools.LevelsElsewhere()
            return other and string.format(tr("%s zeigt Levelbereiche bereits an. Die eigene Anzeige bleibt deshalb aus.", "%s already shows level ranges, so this display stays off."), other) or ""
        end, {height = 16, indent = true}),
        section("reveal", {"Karte aufdecken", "Reveal map"}, {"Nur die Anzeige ändert sich. Erkundung, Erfahrung und Erfolge bleiben unberührt. Auch im Filtermenü der Weltkarte umschaltbar.", "Only the display changes. Exploration, experience and achievements stay untouched. Can also be toggled in the world map's filter menu."}, "aufdecken reveal unerkundet unexplored fog nebel"),
        choice("mapReveal", {"Unerkundete Gebiete", "Unexplored areas"}, {{"off", {"Nicht aufdecken", "Do not reveal"}}, {"soft", {"Halbtransparent aufdecken", "Reveal translucent"}}, {"full", {"Voll aufdecken", "Reveal fully"}}}, {keywords = "aufdecken reveal"}),
        slider("revealAlpha", {"Deckkraft der aufgedeckten Gebiete", "Opacity of revealed areas"}, .2, 1, .05, {enabled = function() return db().mapReveal == "soft" end, indent = true, format = percent}),
        section("waypoints", {"Wegpunkte", "Waypoints"}, nil, "wegpunkt waypoint koordinaten coordinates"),
        toggle("waypoints", {"Wegpunkte per Befehl", "Waypoints by command"}, {"/zway 45.2 67.8 setzt einen Wegpunkt in deinem Gebiet, /zway clear entfernt ihn. Koordinaten zeigt die Weltkarte selbst.", "/zway 45.2 67.8 sets a waypoint in your zone, /zway clear removes it. The world map shows coordinates itself."}, {keywords = "zway wegpunkt waypoint pin"}),
    }})

----------------------------------------------------------------------
-- Tools: macros, UI profiles (layouts) and graphics keep their own list layouts.
----------------------------------------------------------------------
U.AddPage({id = "macros", group = GROUP_TOOLS, fixed = true, title = {"Makros", "Macros"}, icon = "Interface\\Icons\\INV_Misc_Note_01",
    desc = {"Fertige Makros für alle Klassen suchen, ansehen und übernehmen. Auch: Charakter-Makros auf Twinks übertragen.", "Find, view and add ready-made macros for every class. Also: carry character macros over to alts."},
    keywords = "makro macro makros macros klasse class",
    search = {
        {title = {"Makro suchen und übernehmen", "Find and add a macro"}, keywords = "import importieren erstellen create"},
        {title = {"Charakter-Makros übertragen", "Carry over character macros"}, keywords = "twink alt kopieren copy sichern save"},
    }})

U.AddPage({id = "layouts", group = GROUP_TOOLS, fixed = true, title = {"UI-Profile", "UI profiles"}, icon = "Interface\\Icons\\INV_Misc_Map02",
    desc = {"Layouts für Bearbeitungsmodus und Cooldown Manager sammeln, ansehen, teilen und importieren.", "Collect, view, share and import Edit Mode and Cooldown Manager layouts."},
    keywords = "layout layouts edit mode bearbeitungsmodus cooldown manager cdm profil profile importstring import export ui",
    search = {
        {title = {"Layout importieren", "Import a layout"}, keywords = "importstring import einfügen paste"},
        {title = {"Layouts aus dem Spiel übernehmen", "Take over layouts from the game"}, keywords = "lesen read"},
    }})

U.AddPage({id = "graphics", group = GROUP_TOOLS, fixed = true, title = {"Grafik", "Graphics"}, icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
    desc = {"Grafikeinstellungen, die das Spielmenü nicht anbietet. Deine bisherigen Werte bleiben gesichert.", "Graphics settings the game menu does not offer. Your previous values stay saved."},
    keywords = "grafik graphics cvar gras grass sichtweite view distance schatten shadow hdr fps",
    search = {
        {title = {"Vorlage „Schöne Weitsicht“", "“Beautiful views” preset"}, keywords = "preset vorlage weitsicht"},
        {title = {"Meine früheren Grafikwerte", "My previous graphics values"}, keywords = "backup zurück restore"},
    }})

----------------------------------------------------------------------
-- Advanced
----------------------------------------------------------------------
-- Presets change several settings together; the confirmation lists every one first.
local function presetText(name)
    local changed = L.PresetChanges(db(), name)
    if #changed == 0 then return nil end
    local names = {}
    for _, key in ipairs(changed) do names[#names + 1] = "•  " .. U.KeyTitle(key) end
    return table.concat(names, "\n"), #changed
end

local function confirmPreset(v, name, title, intro)
    local list, count = presetText(name)
    if not list then v:SetMessage(tr("Schon so eingestellt. Nichts zu ändern.", "Already set up like this. Nothing to change.")); return end
    C.Confirm(v, title, intro .. "\n\n" .. list, tr("Übernehmen", "Apply"), function()
        L.ApplyPreset(db(), name)
        v:Changed()
        v:SetMessage(string.format(tr("%d Einstellungen geändert. Alles bleibt einzeln änderbar.", "%d settings changed. Each one stays adjustable."), count))
    end)
end

local function buildProfiles(form, v, p)
    local P = NS.Profiles
    local function report(ok, reason, done)
        if ok then v:SetMessage(done or "") else v:SetMessage(P.ReasonText(reason)) end
        v:Changed()
    end
    -- Choosing a profile loads it at once; in combat it follows after the fight.
    v.profilePick = form:Choice({id = "activeProfile", title = {"Aktives Profil dieses Charakters", "This character's active profile"},
        options = function()
            local out = {}
            for _, name in ipairs(P.Names()) do out[#out + 1] = {name, name} end
            return out
        end,
        get = function() return P.Active() end,
        set = function(name)
            local ok, reason = P.Switch(name)
            if ok then v:SetMessage(string.format(tr("Profil „%s“ geladen.", "Profile “%s” loaded."), name))
            else v:SetMessage(P.ReasonText(reason)) end
        end})
    local y = row(form, 34)
    local label = T.Text(p, tr("Name", "Name"), "GameFontHighlight", "text")
    label:SetPoint("TOPLEFT", 0, y - 6)
    local name = W.Edit(p, 60, y, 260, nil)
    name:SetMaxLetters(40)
    W.Tooltip(name, tr("Name für ein neues Profil oder zum Umbenennen", "Name for a new profile or for renaming"))
    v.profileName = name
    form:Buttons({
        {text = {"Neues Profil aus aktuellem", "New profile from current"}, width = 220, action = function()
            local ok, result = P.Create(name:GetText())
            report(ok, result, ok and string.format(tr("Profil „%s“ angelegt.", "Profile “%s” created."), result) or nil)
        end},
        {text = {"Aktives umbenennen", "Rename active"}, width = 170, action = function()
            local ok, result = P.Rename(P.Active(), name:GetText())
            report(ok, result, ok and tr("Umbenannt.", "Renamed.") or nil)
        end},
        {text = {"Aktives löschen …", "Delete active …"}, width = 170, variant = "danger", action = function()
            local active = P.Active()
            if active == P.DefaultName then v:SetMessage(P.ReasonText("default")); return end
            C.Confirm(v, tr("Profil löschen?", "Delete profile?"), string.format(tr("„%s“ wird gelöscht. Dieser Charakter nutzt danach das Standardprofil.", "“%s” is deleted. This character then uses the default profile."), active),
                tr("Löschen", "Delete"), function()
                    local ok, result = P.Delete(active)
                    report(ok, result, ok and tr("Profil gelöscht.", "Profile deleted.") or nil)
                end, "danger")
        end},
    })
    y = row(form, 22)
    local share = T.Text(p, tr("Teilen: Der Profiltext enthält alle Einstellungen dieses Profils. Import legt immer ein neues Profil an; beschädigter Text wird abgelehnt.",
        "Share: the profile text holds all settings of this profile. Import always creates a new profile; damaged text is refused."), "GameFontHighlightSmall", "dim")
    share:SetPoint("TOPLEFT", 0, y)
    share:SetWidth(C.Width)
    form.y = form.y - 12
    y = row(form, 34)
    local box = W.Edit(p, 0, y, C.Width, nil)
    box:SetMaxLetters(0)
    W.Tooltip(box, tr("Profiltext", "Profile text"), tr("Hier einfügen (Strg+V) oder nach „Profiltext erzeugen“ kopieren (Strg+C).", "Paste here (Ctrl+V) or copy after “Create profile text” (Ctrl+C)."))
    v.profileText = box
    form:Buttons({
        {text = {"Profiltext erzeugen", "Create profile text"}, width = 200, action = function()
            box:SetText(P.Export() or "")
            box:SetFocus()
            box:HighlightText()
            v:SetMessage(tr("Text ist markiert: mit Strg+C kopieren.", "The text is selected: copy with Ctrl+C."))
        end},
        {text = {"Profiltext importieren", "Import profile text"}, width = 200, action = function()
            local ok, result = P.Import(box:GetText())
            report(ok, result, ok and string.format(tr("Als neues Profil „%s“ importiert.", "Imported as new profile “%s”."), result) or nil)
        end},
    })
end

local function buildPlayed(form, v, p)
    local y = row(form, 130)
    v.playedLabel = T.Text(p, "", "GameFontHighlightSmall", "text")
    v.playedLabel:SetPoint("TOPLEFT", 0, y)
    v.playedLabel:SetWidth(C.Width)
    v.playedLabel:SetHeight(124)
end

U.AddPage({id = "advanced", group = GROUP_MORE, title = {"Erweitert", "Advanced"}, icon = "Interface\\Icons\\Trade_Engineering",
    desc = {"Einstellungsprofile, Spielzeit, Empfehlungen, Einrichtungsassistent und Zurücksetzen.", "Settings profiles, playtime, recommendations, setup wizard and resets."},
    keywords = "erweitert advanced profil profile reset zurücksetzen",
    nodes = {
        section("profiles", {"Einstellungsprofile", "Settings profiles"}, {"Alle Einstellungen, je Charakter gemerkt. Ohne Spielzeit, Gold, Makros, Einkaufslisten und UI-Profile.", "All settings, remembered per character. Without playtime, gold, macros, shopping lists and UI profiles."}, "profil profile teilen share export import"),
        custom("profileList", buildProfiles, {
            {id = "profiles", title = {"Profil wechseln oder anlegen", "Switch or create a profile"}, keywords = "laden load neu new umbenennen rename löschen delete"},
            {id = "profiles", title = {"Profiltext exportieren oder importieren", "Export or import profile text"}, keywords = "teilen share export import"},
        }),
        section("played", {"Spielzeit", "Playtime"}, {"Alle erfassten Charaktere. Auch /played wird erfasst.", "All recorded characters. /played is recorded too."}, "played spielzeit zeit time"),
        custom("playedList", buildPlayed),
        buttons({{text = {"Spielzeit aktualisieren", "Update playtime"}, width = 220, action = function() A.Call(RequestTimePlayed) end}}),
        section("presets", {"Empfohlene Einstellungen", "Recommended settings"},
            {"Vorschläge, die mehrere Einstellungen gemeinsam ändern. Vorher siehst du genau, was sich ändert.",
                "Suggestions that change several settings together. You see exactly what changes first."}, "preset vorlage empfohlen recommended"),
        buttons({
            {text = {"Komfort-Empfehlung …", "Comfort suggestion …"}, width = 220, keywords = "preset vorlage empfohlen recommended standard komfort",
                tip = {"Schaltet beliebte Helfer ein: Loot-Anzeige, schnelles Plündern, Verkaufen und Reparieren, Levelbereiche und mehr. Nichts wird ausgeschaltet.",
                    "Turns on popular helpers: loot display, fast looting, selling and repairing, level ranges and more. Nothing is turned off."},
                action = function(v) confirmPreset(v, "comfort", tr("Komfort-Empfehlung übernehmen?", "Apply the comfort suggestion?"),
                    tr("Diese Helfer werden eingeschaltet:", "These helpers are turned on:")) end},
            {text = {"Alle Automatiken aus …", "All automation off …"}, width = 220, keywords = "preset minimal manuell manual",
                tip = {"Schaltet alles aus, was für dich handelt: verkaufen, reparieren, Quests annehmen, NPCs antworten, würfeln. Anzeigen bleiben.",
                    "Turns off everything that acts for you: selling, repairing, accepting quests, answering NPCs, rolling. Displays stay."},
                action = function(v) confirmPreset(v, "manual", tr("Alle Automatiken ausschalten?", "Turn off all automation?"),
                    tr("Diese Automatiken werden ausgeschaltet:", "These automations are turned off:")) end},
        }),
        section("setup", {"Einrichtung und Zurücksetzen", "Setup and reset"}),
        buttons({
            {text = {"Einrichtungsassistent starten", "Run setup wizard"}, width = 250, action = function() NS.Setup.Open() end, keywords = "wizard assistent config"},
            {text = {"Fensterposition zurücksetzen", "Reset window position"}, width = 250, action = function(v) U.ResetWindow(); v:SetMessage(tr("Fenster wieder in der Mitte.", "Window back in the centre.")) end},
        }),
        buttons({{text = {"Alle Einstellungen auf Standard …", "All settings to default …"}, width = 300, variant = "danger",
            tip = {"Setzt das aktive Profil vollständig zurück. Makros, UI-Profile, Spielzeit und Grafikwerte bleiben.", "Resets the active profile completely. Macros, UI profiles, playtime and graphics values stay."},
            keywords = "reset alles everything werkseinstellung factory",
            action = function(v)
                local P = NS.Profiles
                C.Confirm(v, tr("Alle Einstellungen zurücksetzen?", "Reset all settings?"),
                    string.format(tr("Jede Einstellung im Profil „%s“ kehrt zum Standard zurück. Das lässt sich nicht rückgängig machen. Makros, UI-Profile, Spielzeit und Grafikwerte bleiben erhalten.",
                        "Every setting in the profile “%s” returns to its default. This cannot be undone. Macros, UI profiles, playtime and graphics values are kept."), P.Active()),
                    tr("Alles zurücksetzen", "Reset everything"), function()
                        local ok, reason = P.Reset(P.Active())
                        v:SetMessage(ok and tr("Alle Einstellungen auf Standard gesetzt.", "All settings set to default.") or P.ReasonText(reason == "combat" and "combatRefused" or reason))
                        v:Changed()
                    end, "danger")
            end}}),
        section("commands", {"Befehle", "Commands"}),
        note({"/zutil öffnet dieses Fenster  ·  /zutil config startet den Assistenten  ·  /zutil loot (oder eine andere Seite) öffnet sie direkt  ·  /zway setzt Wegpunkte",
            "/zutil opens this window  ·  /zutil config runs the wizard  ·  /zutil loot (or another page) opens it directly  ·  /zway sets waypoints"}, {color = "textSoft"}),
    }})

----------------------------------------------------------------------
-- Live data on the open page (rolls, playtime, ranks).
----------------------------------------------------------------------
function U.RefreshPageData(v)
    if v.index == "interface" and v.rankRows then
        U.RefreshRankRows(v)
    elseif v.index == "comfort" and v.rollLabel then
        local lines, won = {}, {}
        for _, entry in ipairs(L.RollWinners(NS.Helpers.rolls)) do won[entry] = true end
        for index, entry in ipairs(NS.Helpers.rolls) do
            if index > 6 then break end
            local line = string.format("%d.  %s  ·  %d  (%d–%d)", index, entry.name, entry.roll, entry.low, entry.high)
            lines[#lines + 1] = won[entry] and ("|cffffd100" .. line .. "|r") or line
        end
        v.rollLabel:SetText(#lines > 0 and table.concat(lines, "\n") or tr("Noch keine Würfe in dieser Runde.", "No rolls in this round yet."))
    elseif v.index == "advanced" and v.playedLabel then
        local rows, sum = NS.Helpers.PlayedRows()
        local lines = {}
        for index, entry in ipairs(rows) do
            if index > 7 then break end
            lines[#lines + 1] = entry.scope .. "  ·  " .. L.FormatPlayed(entry.total)
        end
        if #rows > 0 then lines[#lines + 1] = tr("Gesamt: ", "Total: ") .. L.FormatPlayed(sum) end
        v.playedLabel:SetText(#lines > 0 and table.concat(lines, "\n") or tr("Noch keine Spielzeit erfasst.", "No playtime recorded yet."))
    elseif v.index == "macros" and v.RenderMacroSets then
        v:RenderMacroSets()
    end
end

U.BuildIndex()
