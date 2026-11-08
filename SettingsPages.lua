local _, NS = ...
local U = NS.SettingsUI
local T, tr, L, A, W = NS.Theme, NS.Text, NS.Logic, NS.Adapter, NS.Widgets

local function db() return NS.App.db end
local MUTED = "muted"

local function section(v, p, title, y)
    U.Note(v, title)
    W.Section(p, title, y)
end

local function hint(v, p, text, y, height)
    v:Label(p, text, 0, y, 552, height or 30, "GameFontHighlightSmall", MUTED)
end

local function checks(v, p, y, rows)
    for _, row in ipairs(rows) do
        v:Check(p, row[1], row[2], 0, y, nil, 520)
        y = y - 30
        if row[3] then
            v:Label(p, row[3], 30, y + 4, 520, 30, "GameFontHighlightSmall", MUTED)
            y = y - 28
        end
    end
    return y
end

local function customCheck(v, p, title, x, y, width, get, set)
    local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", x, y)
    T.StyleCheckbox(c)
    v:Label(p, title, x + 30, y - 3, width or 510, 28)
    c:SetScript("OnClick", function(self)
        set(self:GetChecked() == true)
        v:Changed()
    end)
    v:AddUpdate(function() c:SetChecked(get() == true) end)
    return c
end

local function visibility(v, p, key, title, y)
    v:Label(p, title, 0, y - 5, 250, 24)
    v:Dropdown(p, key, 260, y, 240, {{"show", tr("Anzeigen", "Show")}, {"hover", tr("Nur bei Mauskontakt", "Only on hover")}, {"hide", tr("Ausblenden", "Hide")}})
end

----------------------------------------------------------------------
-- Warnings: bars and entries
----------------------------------------------------------------------
local function selectedBar(v)
    local bars = db().warnBars
    v.barIndex = math.max(1, math.min(#bars, v.barIndex or 1))
    return bars[v.barIndex]
end

local function barName(id)
    for _, bar in ipairs(db().warnBars) do
        if bar.id == id then return bar.name end
    end
    return id
end

local function nextBarId(current)
    local bars = db().warnBars
    for index, bar in ipairs(bars) do
        if bar.id == current then return bars[index % #bars + 1].id end
    end
    return L.GeneralBar
end

local function reminderRow(v, p, entry, y)
    local R = NS.Reminders
    customCheck(v, p, R.Title(entry), 0, y, 250, function() return R.IsOn(entry) end, function(value) R.SetOn(entry.key, value) end)
    local bar = T.Button(p, "", 170, 24, function()
        R.SetBar(entry.key, nextBarId(R.BarOf(entry)))
        v:Changed()
    end, "secondary")
    bar:SetPoint("TOPLEFT", 288, y)
    W.Tooltip(bar, tr("Leiste", "Bar"), tr("Klick: nächste Leiste", "Click: next bar"))
    v:AddUpdate(function() bar:SetText(barName(R.BarOf(entry))) end)
    if entry.kind ~= "tracking" then
        local edit = W.Edit(p, 464, y, 62, function(text)
            R.SetWarn(entry.key, tonumber(text))
            NS.Profiles.Store()
        end)
        W.Tooltip(edit, tr("Warnzeit (Sekunden)", "Warning time (seconds)"),
            tr("Leer: nach Dauer 10 s, 3 min oder 5 min vorher.", "Empty: by duration 10 s, 3 min or 5 min before."))
        v:AddUpdate(function()
            if not edit:HasFocus() then
                local row = db().reminders[entry.key]
                edit:SetText(row and row.warn and tostring(row.warn) or "")
            end
        end)
    end
end

function U.builders.buffs(v, p)
    local R, B = NS.Reminders, NS.WarnBars
    section(v, p, tr("Warnsystem", "Warning system"), 0)
    local y = checks(v, p, -28, {
        {"modBuffs", tr("Warnleisten für Buffs und Verbrauchsmaterial anzeigen", "Show warning bars for buffs and consumables"),
            tr("Nur wenn etwas fehlt, bald ausläuft oder ein höherer Rang erlernt ist.", "Only when something is missing, about to end or a higher rank is learned.")},
        {"buffGroup", tr("Gruppenbuffs zählen", "Count group buffs"),
            tr("Mitglieder in Reichweite ohne deine Buffs. Die Reichweite ist grob.", "Members in range without your buffs. The range is rough.")},
        {"buffMounted", tr("Auch beritten warnen", "Also warn while mounted")},
        {"buffResting", tr("Auch in Gasthäusern und Städten warnen", "Also warn in inns and cities")},
        {"warnOnBars", tr("Haltbarkeit, Taschen und Munition auch auf der Leiste zeigen", "Also show durability, bags and ammo on the bar")},
    })
    hint(v, p, tr("Im Kampf sperrt das Spiel Buffdaten. Bis zum Kampfende bleibt der letzte Stand stehen.",
        "In combat the game locks buff data. The last state stays until combat ends."), y, 20)
    y = y - 26

    section(v, p, tr("Leisten", "Bars"), y)
    y = y - 28
    local pick = T.Button(p, "", 240, 26, function()
        v.barIndex = (v.barIndex or 1) % #db().warnBars + 1
        v:Changed()
    end, "secondary")
    pick:SetPoint("TOPLEFT", 0, y)
    W.Tooltip(pick, tr("Leiste wählen", "Choose a bar"), tr("Klick: nächste Leiste", "Click: next bar"))
    v:AddUpdate(function() pick:SetText(selectedBar(v).name) end)
    local name = W.Edit(p, 250, y, 180, function(text)
        selectedBar(v).name = text ~= "" and text or selectedBar(v).id
        NS.Profiles.Store()
    end)
    v:AddUpdate(function() if not name:HasFocus() then name:SetText(selectedBar(v).name) end end)
    v:Button(p, tr("Neu", "New"), 436, y, 54, function()
        local bar = R.AddBar(tr("Neue Leiste", "New bar"))
        if not bar then v:SetMessage(tr("Mehr Leisten sind nicht möglich.", "No more bars possible.")); return end
        v.barIndex = #db().warnBars
        v:Changed()
    end, "secondary")
    v:Button(p, tr("Löschen", "Delete"), 494, y, 58, function()
        local bar = selectedBar(v)
        if not R.DeleteBar(bar.id) then v:SetMessage(tr("Die allgemeine Leiste bleibt bestehen.", "The general bar stays.")); return end
        v.barIndex = 1
        v:Changed()
    end, "danger")
    y = y - 36
    v:Number(p, "barSize", tr("Symbolgröße", "Icon size"), y, 16, 64, 2, function() return selectedBar(v).size end, function(value) selectedBar(v).size = value end)
    y = y - 62
    v:Label(p, tr("Wachstumsrichtung", "Growth direction"), 0, y - 5, 200, 24)
    v:Dropdown(p, "barGrow", 210, y, 200, {{"RIGHT", tr("Nach rechts", "To the right")}, {"LEFT", tr("Nach links", "To the left")}, {"UP", tr("Nach oben", "Upward")}, {"DOWN", tr("Nach unten", "Downward")}},
        function() return selectedBar(v).grow end, function(value) selectedBar(v).grow = value end)
    y = y - 34
    customCheck(v, p, tr("Countdown anzeigen", "Show countdown"), 0, y, 300, function() return selectedBar(v).countdown end, function(value) selectedBar(v).countdown = value end)
    y = y - 34
    v:Button(p, tr("Leisten verschieben", "Move bars"), 0, y, 190, function()
        B.SetMoving(not B.moving)
        v:SetMessage(B.moving and tr("Leisten ziehen, erneut klicken zum Beenden.", "Drag the bars, click again to finish.") or "")
    end, "secondary")
    v:Button(p, tr("Vorschau", "Preview"), 200, y, 130, function() B.SetPreview(not B.preview) end, "secondary")
    v:Button(p, tr("Leisten zurücksetzen", "Reset bars"), 340, y, 190, function()
        db().warnBars = L.DefaultBars()
        v.barIndex = 1
        v:Changed()
    end, "secondary")
    y = y - 40

    section(v, p, tr("Einträge", "Entries"), y)
    y = y - 26
    hint(v, p, tr("Gilt für dieses Profil. Es warnt nur, was erlernt und gewählt ist.", "Applies to this profile. Only what is learned and chosen warns."), y, 18)
    y = y - 26
    local lastGroup
    local classSet = {}
    for _, entry in ipairs(NS.BuffData.classes[A.PlayerClass()] or {}) do classSet[entry] = true end
    local generalSet = {}
    for _, entry in ipairs(NS.BuffData.general) do generalSet[entry] = true end
    for _, entry in ipairs(R.AllEntries()) do
        local group = classSet[entry] and tr("Klasse", "Class") or generalSet[entry] and tr("Sammeln und Lager", "Gathering and camp") or tr("Verbrauchsmaterial", "Consumables")
        if group ~= lastGroup then
            lastGroup = group
            v:Label(p, group, 0, y - 4, 400, 20, "GameFontNormal", "gold")
            y = y - 24
        end
        reminderRow(v, p, entry, y)
        y = y - 30
    end
    return -y + 20
end

----------------------------------------------------------------------
-- Info bar
----------------------------------------------------------------------
function U.builders.infobar(v, p)
    local I = NS.InfoBar
    section(v, p, tr("Infoleiste", "Info bar"), 0)
    local y = checks(v, p, -28, {
        {"modInfoBar", tr("Infoleiste anzeigen", "Show the info bar")},
        {"infoLocked", tr("Position sperren", "Lock the position")},
        {"infoCompact", tr("Kompakt, ohne Symbole", "Compact, without icons")},
        {"infoIcons", tr("Symbole anzeigen", "Show icons")},
        {"infoColors", tr("Statusfarben", "Status colors"), tr("Zum Beispiel für Latenz, Haltbarkeit und Munition.", "For example for latency, durability and ammo.")},
    })
    v:Number(p, "infoScale", tr("Skalierung", "Scale"), y, .6, 1.6, .05)
    y = y - 62
    v:Number(p, "infoFont", tr("Schriftgröße", "Font size"), y, 8, 20, 1)
    y = y - 62
    v:Number(p, "infoAlpha", tr("Deckkraft des Hintergrunds", "Background opacity"), y, 0, 1, .05)
    y = y - 66
    v:Label(p, tr("Gold-Summe umfasst", "Gold total covers"), 0, y - 5, 200, 24)
    v:Dropdown(p, "goldScope", 210, y, 240, {{"all", tr("Alle Charaktere", "All characters")}, {"faction", tr("Eigene Fraktion", "Own faction")}, {"current", tr("Nur diesen Charakter", "This character only")}})
    y = y - 40
    section(v, p, tr("Anzeigen", "Displays"), y)
    y = y - 26
    hint(v, p, tr("Reihenfolge wie auf der Leiste.", "Same order as on the bar."), y, 18)
    y = y - 24
    for index = 1, #I.Modules do
        local key = function() return I.Order()[index] end
        customCheck(v, p, "", 0, y, 10, function() return I.IsOn(key()) end, function(value) db().infoBar.on[key()] = value end)
        local label = v:Label(p, "", 30, y - 3, 400, 22)
        v:AddUpdate(function() label:SetText(I.Title(I.ByKey[key()])) end)
        local up = T.Button(p, "▲", 30, 22, function() if I.Move(key(), -1) then v:Changed() end end, "secondary")
        up:SetPoint("TOPLEFT", 470, y)
        local down = T.Button(p, "▼", 30, 22, function() if I.Move(key(), 1) then v:Changed() end end, "secondary")
        down:SetPoint("TOPLEFT", 504, y)
        y = y - 28
    end
    return -y + 20
end

----------------------------------------------------------------------
-- Merchant: settings per character, because each one has its own reagents
----------------------------------------------------------------------
function U.builders.merchant(v, p)
    local B, S = NS.AutoBuy, function() return NS.AutoBuy.Settings() end
    section(v, p, tr("Nachkaufen (nur dieser Charakter)", "Restock (this character only)"), 0)
    local y = -28
    customCheck(v, p, tr("Einkaufsliste beim Händler zeigen", "Show the shopping list at merchants"), 0, y, 510, function() return S().enabled end, function(value) S().enabled = value end)
    y = y - 30
    customCheck(v, p, tr("Automatik: ohne Nachfrage kaufen", "Automation: buy without asking"), 0, y, 510, function() return S().auto == true and S().confirm == false end, function(value)
        S().auto = value
        S().confirm = not value
    end)
    y = y - 30
    hint(v, p, tr("Die Grenzen gelten immer, auch für die Buttons. 0 heißt: nur dein Gold begrenzt.",
        "The limits always apply, also for the buttons. 0 means only your gold limits it."), y, 20)
    y = y - 26
    v:Number(p, "maxCost", tr("Höchstens pro Händlerbesuch (Gold)", "At most per visit (gold)"), y, 0, 1000, 5, function() return tonumber(S().maxCost) or 0 end, function(value) S().maxCost = value end)
    y = y - 62
    v:Number(p, "ammoTarget", tr("Munition: Zielmenge", "Ammunition: target amount"), y, 0, 5000, 100, function() return tonumber(S().ammoTarget) or 0 end, function(value) S().ammoTarget = value end)
    y = y - 62
    if A.PlayerClass() == "ROGUE" then
        v:Number(p, "poisonStop", tr("Keine Giftzutaten ab so vielen fertigen Giften", "No poison ingredients from this many finished poisons"), y, 0, 200, 5, function() return tonumber(S().poisonStop) or 0 end, function(value) S().poisonStop = value end)
        y = y - 62
    end
    section(v, p, tr("Zielmengen", "Target amounts"), y)
    y = y - 28
    if B.HasReagentEconomy() then
        hint(v, p, tr("Reagent Economy ist erlernt: entfallende Reagenzien fehlen hier.", "Reagent Economy is learned: reagents it removes are left out."), y, 18)
        y = y - 22
    end
    local catalog = B.Catalog()
    if #catalog == 0 then
        hint(v, p, tr("Noch nichts einzustellen. Erlernte Zauber mit Reagenzien erscheinen von selbst.",
            "Nothing to set yet. Learned spells with reagents appear on their own."), y, 30)
        y = y - 34
    end
    local items = _G.C_Item
    for _, row in ipairs(catalog) do
        local item = row.item
        local label = v:Label(p, "", 0, y - 4, 420, 22)
        v:AddUpdate(function()
            local itemName = items and A.Call(items.GetItemNameByID, item)
            label:SetText(string.format("%s  (%d)", itemName or ("#" .. item), A.ItemCount(item)))
        end)
        local edit = W.Edit(p, 430, y, 80, function(text)
            B.SetTarget(item, tonumber(text))
            B.SettingsChanged()
        end)
        v:AddUpdate(function() if not edit:HasFocus() then edit:SetText(tostring(B.GetTarget(item))) end end)
        y = y - 30
    end
    y = y - 6
    section(v, p, tr("Grauer Verkauf", "Grey sales"), y)
    y = y - 28
    local stats = v:Label(p, "", 0, y, 552, 22)
    v:AddUpdate(function()
        local data = db().sellStats
        stats:SetText(string.format(tr("Bisher %d Gegenstände für %s verkauft.", "So far %d items sold for %s."), tonumber(data.count) or 0, A.Money(tonumber(data.total) or 0)))
    end)
    return -y + 30
end

----------------------------------------------------------------------
-- Tooltip
----------------------------------------------------------------------
function U.builders.tooltip(v, p)
    section(v, p, tr("Charaktere", "Characters"), 0)
    local y = checks(v, p, -28, {
        {"ttUnit", tr("Charakter-Tooltips anpassen", "Adjust character tooltips")},
    })
    v:Label(p, tr("Aufbau", "Layout"), 0, y - 5, 200, 24)
    v:Dropdown(p, "ttLayout", 210, y, 240, {{"compact", tr("Kompakt", "Compact")}, {"lines", tr("Eine Angabe pro Zeile", "One per line")}, {"blizz", tr("Wie im Spiel", "As in the game")}})
    y = checks(v, p, y - 36, {
        {"ttLevel", tr("Stufe", "Level")}, {"ttClass", tr("Klasse", "Class")}, {"ttRace", tr("Volk", "Race")},
        {"ttFaction", tr("Fraktion", "Faction")}, {"ttGuild", tr("Gilde", "Guild")}, {"ttGuildRank", tr("Gildenrang", "Guild rank")},
        {"ttTarget", tr("Aktuelles Ziel", "Current target")},
        {"ttItemLevel", tr("Durchschnittliche Gegenstandsstufe", "Average item level"), tr("Bei anderen nur außerhalb des Kampfes und in der Nähe, ab dem zweiten Hinzeigen.", "For others only out of combat and nearby, from the second hover.")},
    })
    section(v, p, tr("Darstellung", "Appearance"), y - 10)
    y = y - 38
    v:Label(p, tr("Position", "Position"), 0, y - 5, 200, 24)
    v:Dropdown(p, "ttAnchor", 210, y, 240, {{"default", tr("Wie im Spiel", "As in the game")}, {"TOPLEFT", tr("Oben links", "Top left")}, {"TOPRIGHT", tr("Oben rechts", "Top right")}, {"BOTTOMLEFT", tr("Unten links", "Bottom left")}, {"BOTTOMRIGHT", tr("Unten rechts", "Bottom right")}})
    y = y - 36
    v:Label(p, tr("Lebensbalken", "Health bar"), 0, y - 5, 200, 24)
    v:Dropdown(p, "ttHealthBar", 210, y, 240, {{"default", tr("Wie im Spiel", "As in the game")}, {"flat", tr("Flach", "Flat")}, {"soft", tr("Weich", "Soft")}})
    y = y - 40
    section(v, p, tr("Sammeln", "Gathering"), y)
    y = checks(v, p, y - 28, {
        {"ttGathering", tr("Nötige Fertigkeit bei Kräutern, Erzen und Kürschnern", "Skill needed for herbs, ores and skinning"), tr("Klassische Werte. Neue Forever-Vorkommen fehlen noch.", "Classic values. New Forever nodes are not covered yet.")},
    })
    hint(v, p, tr("IDs im Tooltip: unter „Extras“.", "IDs in tooltips: under Extras."), y - 4, 20)
    return -y + 30
end

----------------------------------------------------------------------
-- Inventory
----------------------------------------------------------------------
function U.builders.inventory(v, p)
    section(v, p, tr("Taschen", "Bags"), 0)
    local y = checks(v, p, -28, {
        {"bagMove", tr("Kombiniertes Taschenfenster verschiebbar", "Combined bag window movable"), tr("Mit Shift ziehen. Einzelne Taschen bleiben, wo das Spiel sie hinsetzt.", "Shift-drag. Single bags stay where the game puts them.")},
    })
    v:Button(p, tr("Position zurücksetzen", "Reset position"), 0, y, 200, function() NS.Inventory.ResetBagPosition() end, "secondary")
    y = y - 40
    section(v, p, tr("Erfahrung", "Experience"), y)
    y = checks(v, p, y - 28, {
        {"xpText", tr("Erfahrungszahlen dauerhaft auf der Leiste", "Keep experience numbers on the bar")},
        {"xpPercent", tr("Prozentwert anzeigen", "Show the percentage")},
    })
    section(v, p, tr("Post", "Mail"), y - 10)
    y = checks(v, p, y - 38, {
        {"mailAlts", tr("Eigene Charaktere als Empfänger anbieten", "Offer own characters as recipients"), tr("Gleicher Realm und gleiche Fraktion.", "Same realm and faction.")},
    })
    section(v, p, tr("Graue Gegenstände zerstören", "Destroy grey items"), y - 10)
    y = checks(v, p, y - 38, {
        {"destroyGray", tr("Zerstören per Klick erlauben", "Allow destroying by click"), tr("Shift-Klick auf „Billigster grauer Stapel“ der Infoleiste oder der Button hier. Nie im Kampf, nie automatisch.", "Shift-click the info bar's cheapest grey stack or the button here. Never in combat, never automatically.")},
        {"destroyConfirm", tr("Vorher nachfragen", "Ask first")},
    })
    v:Button(p, tr("Billigsten Stapel zerstören", "Destroy cheapest stack"), 0, y, 240, function()
        if not NS.Inventory.RequestDestroy() then v:SetMessage(tr("Gerade nichts zu zerstören oder nicht erlaubt.", "Nothing to destroy right now, or not allowed.")) end
    end, "secondary")
    return -y + 50
end

----------------------------------------------------------------------
-- Interface and small helpers
----------------------------------------------------------------------
----------------------------------------------------------------------
-- Action bars: outdated spell ranks and their exceptions
----------------------------------------------------------------------
local RANK_ROWS = 8

local function rankRow(v, p, y, buttons)
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(552, 28)
    row:SetPoint("TOPLEFT", 0, y)
    row.label = T.Text(row, "", "GameFontHighlightSmall", "text")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetWidth(552 - #buttons * 128)
    local right = 0
    for index = #buttons, 1, -1 do
        local spec = buttons[index]
        local button = T.Button(row, spec[1], 122, 24, function(self)
            spec[2](self:GetParent())
            v:Changed()
        end, "secondary")
        button:SetPoint("RIGHT", -right, 0)
        right = right + 128
    end
    row:Hide()
    return row
end

local function spellLabel(spell, rank)
    local name = A.SpellName(spell) or ("#" .. tostring(spell))
    return rank and rank > 0 and string.format(tr("%s (Rang %d)", "%s (Rank %d)"), name, rank) or name
end

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
    for index, row in ipairs(v.rankRows) do
        local mark = open[index]
        row.mark = mark
        if mark then
            row.label:SetText(string.format(tr("Slot %d: %s – verfügbar: Rang %d", "Slot %d: %s – available: Rank %d"),
                mark.slot, spellLabel(mark.spell, mark.rank), mark.bestRank or 0))
        end
        row:SetShown(mark ~= nil)
    end
    for index, row in ipairs(v.rankIgnoreRows) do
        local entry = ignored[index]
        row.entry = entry
        if entry and entry.spell then
            row.label:SetText(tr("Zauber: ", "Spell: ") .. spellLabel(entry.spell))
        elseif entry then
            local kind, id = A.Call(GetActionInfo, entry.slot)
            local held = kind == "spell" and type(id) == "number" and ("  ·  " .. spellLabel(id)) or ""
            row.label:SetText(string.format("Slot %d", entry.slot) .. held)
        end
        row:SetShown(entry ~= nil)
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

local function rankSection(v, p, y)
    local K = NS.ActionRanks
    section(v, p, tr("Aktionsleisten", "Action bars"), y - 10)
    y = checks(v, p, y - 38, {
        {"rankCheck", tr("Veraltete Zauberränge markieren", "Mark outdated spell ranks"),
            tr("Kleiner Punkt oben links am Button und ein Hinweis im Tooltip. Leisten und Makros bleiben unverändert.",
                "Small dot in the button's top-left corner and a note in the tooltip. Bars and macros stay unchanged.")},
        {"rankNotify", tr("Nach dem Erlernen kurz im Chat melden", "Short chat note after learning")},
    })
    hint(v, p, tr("Nur Blizzard-Aktionsleisten und direkt abgelegte Zauber, keine Makros. Gewolltes Downranking: Zauber oder Slot ignorieren.",
        "Only Blizzard action bars and spells placed directly, no macros. Deliberate downranking: ignore the spell or the slot."), y, 30)
    y = y - 34
    v.rankStatus = v:Label(p, "", 0, y, 552, 20, "GameFontHighlightSmall")
    y = y - 26
    v.rankRows = {}
    for index = 1, RANK_ROWS do
        v.rankRows[index] = rankRow(v, p, y, {
            {tr("Zauber ignorieren", "Ignore spell"), function(row) if row.mark then K.IgnoreSpell(row.mark.spell, true) end end},
            {tr("Slot ignorieren", "Ignore slot"), function(row) if row.mark then K.IgnoreSlot(row.mark.slot, true) end end},
        })
        y = y - 30
    end
    v.rankIgnoreTitle = v:Label(p, tr("Ausnahmen", "Exceptions"), 0, y - 6, 552, 20, "GameFontNormal", "gold")
    y = y - 30
    v.rankIgnoreRows = {}
    for index = 1, RANK_ROWS do
        v.rankIgnoreRows[index] = rankRow(v, p, y, {
            {tr("Wieder prüfen", "Check again"), function(row)
                local entry = row.entry
                if entry and entry.spell then K.IgnoreSpell(entry.spell, false) elseif entry then K.IgnoreSlot(entry.slot, false) end
            end},
        })
        y = y - 30
    end
    v:AddUpdate(function() U.RefreshRankRows(v) end)
    return y
end

function U.builders.interface(v, p)
    local F = NS.LootFeed
    section(v, p, "Quicker Loot", 0)
    local y = checks(v, p, -28, {
        {"fastLoot", tr("Schnelles Plündern", "Fast looting"), tr("Folgt deiner Einstellung für automatisches Plündern und der Modifikatortaste.", "Follows your auto loot setting and modifier key.")},
        {"lootConfirmSolo", tr("Bindungsfrage beim Plündern allein überspringen", "Skip the bind question when looting alone"), tr("Nur ohne Gruppe. In der Gruppe fragt das Spiel weiter.", "Only without a group. In a group the game still asks.")},
        {"lootGreed", tr("Bei grünen Gegenständen automatisch Gier würfeln", "Roll Greed on green items automatically"), tr("Nie bei Gegenständen, die beim Aufheben binden.", "Never on items that bind when picked up.")},
        {"lootFeed", tr("Loot-Anzeige", "Loot display"), tr("Zeigt erhaltene Gegenstände kurz an. Unabhängig vom schnellen Plündern.", "Briefly shows received items. Independent of fast looting.")},
        {"lootFeedQuality", tr("Nur ungewöhnliche und bessere (Questgegenstände immer)", "Only uncommon and better (quest items always)")},
        {"lootFeedTooltip", tr("Tooltip beim Hinzeigen", "Tooltip on hover"), tr("Die Einträge nehmen dann Mausklicks an.", "Entries then take mouse clicks.")},
    })
    v:Number(p, "lootFeedTime", tr("Anzeigedauer", "Display time"), y, 2, 5, 1, nil, nil, " s")
    y = y - 62
    v:Number(p, "lootFeedScale", tr("Größe", "Size"), y, .6, 1.6, .05)
    y = y - 66
    v:Button(p, tr("Verschieben", "Move"), 0, y, 150, function()
        F.SetMoving(not F.moving)
        v:SetMessage(F.moving and tr("Anzeige ziehen, erneut klicken zum Beenden.", "Drag the display, click again to finish.") or "")
    end, "secondary")
    v:Button(p, tr("Vorschau", "Preview"), 160, y, 130, function()
        if not F.Preview() then v:SetMessage(tr("Erst die Loot-Anzeige einschalten.", "Turn on the loot display first.")) end
    end, "secondary")
    v:Button(p, tr("Position zurücksetzen", "Reset position"), 300, y, 200, function() F.ResetPosition() end, "secondary")
    y = y - 40
    section(v, p, tr("Dialoge", "Dialogs"), y - 10)
    y = checks(v, p, y - 38, {
        {"skipGossip", tr("Eindeutige Dienst-Dialoge überspringen", "Skip clear service dialogs"), tr("Nur bei genau einem bekannten Dienst ohne Quest. Ruhestein binden nie. Shift pausiert.", "Only with exactly one known service and no quest. Never binds the hearthstone. Shift pauses.")},
        {"declineDuels", tr("Duellanfragen ablehnen", "Decline duel requests")},
        {"bgRelease", tr("Auf Schlachtfeldern den Geist freilassen", "Release your spirit in battlegrounds"), tr("Nicht mit Seelenstein. Shift pausiert.", "Not with a soulstone. Shift pauses.")},
    })
    section(v, p, tr("Fehlermeldungen", "Error messages"), y - 10)
    y = checks(v, p, y - 38, {
        {"errorFilter", tr("Wiederkehrende rote Meldungen filtern", "Filter repeating red messages"), tr("Gilt nur für die gewählten Arten. Andere Fehler kommen unverändert durch.", "Only for the chosen kinds. Other errors pass through unchanged.")},
        {"errShowText", tr("Gefilterte: rote Meldung trotzdem anzeigen", "Filtered: still show the red message")},
        {"errPlaySound", tr("Gefilterte: Fehlerton trotzdem abspielen", "Filtered: still play the error sound"), tr("Auch Sprachausgabe wie „Das ist noch nicht bereit“. Andere Sounds bleiben unberührt.", "Includes voice lines like \"That ability isn't ready yet\". Other sounds stay untouched.")},
        {"errResource", tr("Nicht genug Mana, Energie oder Wut", "Not enough mana, energy or rage")},
        {"errCooldown", tr("Fähigkeit nicht bereit", "Ability not ready")},
        {"errRange", tr("Ziel außer Reichweite", "Target out of range")},
        {"errTarget", tr("Kein oder ungültiges Ziel", "No or invalid target")},
        {"errAll", tr("Alle gewöhnlichen roten Fehlermeldungen filtern", "Filter all ordinary red error messages"), tr("Gelbe Hinweise und Systemmeldungen bleiben.", "Yellow notices and system messages stay.")},
    })
    section(v, p, tr("Oberfläche", "Interface"), y - 10)
    y = y - 38
    hint(v, p, tr("Ausgeblendetes ist nicht anklickbar.", "Hidden elements cannot be clicked."), y, 20)
    y = y - 26
    for _, row in ipairs({
        {"hideBags", tr("Taschenleiste", "Bag bar")}, {"hideMicro", tr("Mikromenü", "Micro menu")}, {"hideClock", tr("Uhr an der Minikarte", "Minimap clock")},
        {"hideCalendar", tr("Kalender an der Minikarte", "Minimap calendar")}, {"hideTracking", tr("Aufspüren an der Minikarte", "Minimap tracking")}, {"hideZoneText", tr("Gebietsname an der Minikarte", "Minimap zone name")},
    }) do
        visibility(v, p, row[1], row[2], y)
        y = y - 34
    end
    y = rankSection(v, p, y)
    return -y + 30
end

----------------------------------------------------------------------
-- Profiles
----------------------------------------------------------------------
function U.builders.profiles(v, p)
    local P = NS.Profiles
    section(v, p, tr("Profile", "Profiles"), 0)
    hint(v, p, tr("Alle Einstellungen, je Charakter gemerkt. Ohne Spielzeit, Gold, Makros, Einkaufslisten und Layout-Bibliothek.",
        "All settings, remembered per character. Without playtime, gold, macros, shopping lists and the layout library."), -28, 40)
    local status = v:Label(p, "", 0, -70, 552, 22)
    v:AddUpdate(function() status:SetText(tr("Aktiv: ", "Active: ") .. P.Active()) end)
    local y = -98
    v.profileRows = {}
    local function report(ok, reason, done)
        if ok then v:SetMessage(done or "") else v:SetMessage(P.ReasonText(reason)) end
        v:Changed()
    end
    for index = 1, 10 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(552, 28)
        row:SetPoint("TOPLEFT", 0, y)
        row.label = T.Text(row, "", "GameFontHighlight", "text")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(280)
        row.pick = T.Button(row, tr("Laden", "Load"), 90, 24, function(self)
            local ok, reason = P.Switch(self:GetParent().name)
            report(ok, reason)
        end, "secondary")
        row.pick:SetPoint("LEFT", 290, 0)
        row:Hide()
        v.profileRows[index] = row
        y = y - 30
    end
    v:AddUpdate(function()
        local names, active = P.Names(), P.Active()
        for index, row in ipairs(v.profileRows) do
            local name = names[index]
            row.name = name
            if name then
                row.label:SetText(name == active and ("|cffffd100" .. name .. "|r") or name)
                row.pick:SetEnabled(name ~= active)
            end
            row:SetShown(name ~= nil)
        end
    end)
    y = y - 6
    v:Label(p, tr("Name", "Name"), 0, y - 5, 60, 24)
    local name = W.Edit(p, 60, y, 260, nil)
    name:SetMaxLetters(40)
    v.profileName = name
    y = y - 34
    v:Button(p, tr("Neu aus aktivem", "New from active"), 0, y, 160, function()
        local ok, result = P.Create(name:GetText())
        report(ok, result, ok and string.format(tr("Profil „%s“ angelegt.", "Profile “%s” created."), result) or nil)
    end, "secondary")
    v:Button(p, tr("Umbenennen", "Rename"), 170, y, 120, function()
        local ok, result = P.Rename(P.Active(), name:GetText())
        report(ok, result)
    end, "secondary")
    v:Button(p, tr("Zurücksetzen", "Reset"), 300, y, 120, function()
        local ok, result = P.Reset(P.Active())
        report(ok, result, ok and tr("Profil auf Standardwerte gesetzt.", "Profile set to default values.") or nil)
    end, "secondary")
    v:Button(p, tr("Löschen", "Delete"), 430, y, 110, function()
        local ok, result = P.Delete(P.Active())
        report(ok, result)
    end, "danger")
    y = y - 44
    section(v, p, tr("Teilen", "Share"), y)
    y = y - 28
    hint(v, p, tr("Import legt immer ein neues Profil an. Beschädigter Text wird abgelehnt.",
        "Import always creates a new profile. Damaged text is refused."), y, 30)
    y = y - 36
    local box = W.Edit(p, 0, y, 552, nil)
    box:SetMaxLetters(0)
    v.profileText = box
    y = y - 34
    v:Button(p, tr("Exportieren", "Export"), 0, y, 150, function()
        box:SetText(P.Export() or "")
        box:SetFocus()
        box:HighlightText()
        v:SetMessage(tr("Mit Strg+C kopieren.", "Copy with Ctrl+C."))
    end, "secondary")
    v:Button(p, tr("Importieren", "Import"), 160, y, 150, function()
        local ok, result = P.Import(box:GetText())
        report(ok, result, ok and string.format(tr("Als „%s“ importiert.", "Imported as “%s”."), result) or nil)
    end, "secondary")
    return -y + 40
end
