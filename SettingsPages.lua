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
    W.Tooltip(bar, tr("Leiste", "Bar"), tr("Klick wechselt zur nächsten Warnleiste.", "Click switches to the next warning bar."))
    v:AddUpdate(function() bar:SetText(barName(R.BarOf(entry))) end)
    if entry.kind ~= "tracking" then
        local edit = W.Edit(p, 464, y, 62, function(text)
            R.SetWarn(entry.key, tonumber(text))
            NS.Profiles.Store()
        end)
        W.Tooltip(edit, tr("Warnzeit (Sekunden)", "Warning time (seconds)"),
            tr("Leer: automatisch nach Dauer (10 s, 3 min oder 5 min vor dem Ablauf).", "Empty: automatic by duration (10 s, 3 min or 5 min before it ends)."))
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
            tr("Zeigt Symbole nur, wenn etwas fehlt, bald ausläuft oder ein höherer Rang erlernt ist. Bei Tod und auf Flugrouten bleibt es still.", "Shows icons only when something is missing, about to end, or a higher rank is learned. Quiet while dead and on flight paths.")},
        {"buffGroup", tr("Gruppenbuffs zählen", "Count group buffs"),
            tr("Zählt Gruppenmitglieder in Reichweite ohne deine Buffs. Die Reichweite kommt vom Spiel und ist grob.", "Counts group members in range without your buffs. Range comes from the game and is rough.")},
        {"buffMounted", tr("Auch beritten warnen", "Also warn while mounted")},
        {"buffResting", tr("Auch in Gasthäusern und Städten warnen", "Also warn in inns and cities")},
        {"warnOnBars", tr("Haltbarkeit, Taschen und Munition auch auf der Leiste zeigen", "Also show durability, bags and ammo on the bar")},
    })
    hint(v, p, tr("Im Kampf hält das Spiel Buffdaten zurück: Dort bleibt der letzte Stand stehen, die nächste Prüfung folgt nach dem Kampf.",
        "In combat the game withholds buff data: the last state stands until the next check after combat."), y, 30)
    y = y - 36

    section(v, p, tr("Leisten", "Bars"), y)
    y = y - 28
    local pick = T.Button(p, "", 240, 26, function()
        v.barIndex = (v.barIndex or 1) % #db().warnBars + 1
        v:Changed()
    end, "secondary")
    pick:SetPoint("TOPLEFT", 0, y)
    W.Tooltip(pick, tr("Leiste wählen", "Choose a bar"), tr("Klick zeigt die nächste Leiste zum Bearbeiten.", "Click shows the next bar to edit."))
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
        v:SetMessage(B.moving and tr("Ziehe die Leisten an ihren Platz. Noch ein Klick beendet das.", "Drag the bars into place. Another click ends this.") or "")
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
    hint(v, p, tr("Häkchen, Leiste und Warnzeit gelten für dieses Profil. Nur Erlerntes und Gewähltes warnt.", "Check, bar and warning time belong to this profile. Only what is learned and chosen warns."), y, 18)
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
        {"infoLocked", tr("Position sperren", "Lock the position"), tr("Entsperrt lässt sie sich mit der Maus an ihren Platz ziehen.", "Unlocked, it can be dragged into place with the mouse.")},
        {"infoCompact", tr("Kompakte Darstellung", "Compact view"), tr("Kurze Texte ohne Symbole.", "Short texts without icons.")},
        {"infoIcons", tr("Symbole anzeigen", "Show icons")},
        {"infoColors", tr("Statusfarben", "Status colors"), tr("Färbt zum Beispiel Latenz, Haltbarkeit und Munition nach Zustand.", "For example colors latency, durability and ammo by state.")},
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
    hint(v, p, tr("Die Reihenfolge hier ist die Reihenfolge auf der Leiste.", "The order here is the order on the bar."), y, 18)
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
    hint(v, p, tr("Bleibt aus, bis du sie einschaltest. Beide Grenzen unten gelten immer, auch für die Buttons. 0 heißt: kein eigenes Limit, das vorhandene Gold begrenzt dann.",
        "Stays off until you turn it on. Both limits below always apply, also for the buttons. 0 means no limit of your own; your gold limits it then."), y, 40)
    y = y - 42
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
        hint(v, p, tr("Reagent Economy ist erlernt: Reagenzien, die dadurch entfallen, fehlen in dieser Liste.", "Reagent Economy is learned: reagents it removes are not in this list."), y, 18)
        y = y - 22
    end
    local catalog = B.Catalog()
    if #catalog == 0 then
        hint(v, p, tr("Für deinen aktuellen Stand gibt es hier nichts einzustellen. Gelernte Zauber, die Reagenzien brauchen, erscheinen automatisch.",
            "Nothing to set for your current state. Learned spells that need reagents appear automatically."), y, 30)
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
        {"ttUnit", tr("Charakter-Tooltips anpassen", "Adjust character tooltips"), tr("Ändert vorhandene Zeilen statt sie zu verdoppeln.", "Changes existing lines instead of doubling them.")},
    })
    v:Label(p, tr("Aufbau", "Layout"), 0, y - 5, 200, 24)
    v:Dropdown(p, "ttLayout", 210, y, 240, {{"compact", tr("Kompakt", "Compact")}, {"lines", tr("Eine Angabe pro Zeile", "One per line")}, {"blizz", tr("Wie im Spiel", "As in the game")}})
    y = checks(v, p, y - 36, {
        {"ttLevel", tr("Stufe", "Level")}, {"ttClass", tr("Klasse", "Class")}, {"ttRace", tr("Volk", "Race")},
        {"ttFaction", tr("Fraktion", "Faction")}, {"ttGuild", tr("Gilde", "Guild")}, {"ttGuildRank", tr("Gildenrang", "Guild rank")},
        {"ttTarget", tr("Aktuelles Ziel", "Current target")},
        {"ttItemLevel", tr("Durchschnittliche Gegenstandsstufe", "Average item level"), tr("Andere Spieler brauchen dafür eine Betrachtung außerhalb des Kampfes in deren Nähe. Der Wert erscheint beim nächsten Hinzeigen.", "Other players need an inspect for this, out of combat and nearby. The value appears on the next hover.")},
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
        {"ttGathering", tr("Nötige Fertigkeit bei Kräutern, Erzen und Kürschnern", "Skill needed for herbs, ores and skinning"), tr("Klassische Werte. Neue Vorkommen in Forever-Startgebieten sind noch nicht erfasst.", "Classic values. New nodes in Forever's starting zones are not covered yet.")},
    })
    hint(v, p, tr("Verkaufspreis und IDs stellst du unter „Extras“ ein.", "Sell price and IDs are set under Extras."), y - 4, 20)
    return -y + 30
end

----------------------------------------------------------------------
-- Inventory
----------------------------------------------------------------------
function U.builders.inventory(v, p)
    section(v, p, tr("Taschen und Munition", "Bags and ammo"), 0)
    local y = checks(v, p, -28, {
        {"bagFreeSlots", tr("Freie Plätze auf den Taschenbuttons", "Free slots on the bag buttons"), tr("Spezialtaschen zeigen ihre eigenen Zahlen, Köcher die Munition.", "Special bags show their own numbers, quivers the ammo.")},
        {"bagMove", tr("Kombiniertes Taschenfenster verschiebbar", "Combined bag window movable"), tr("Mit Shift ziehen. Einzelne Taschenfenster folgen weiter dem Spiel.", "Shift-drag. Single bag windows keep following the game.")},
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
        {"mailAlts", tr("Eigene Charaktere als Empfänger anbieten", "Offer own characters as recipients"), tr("Gleicher Realm und gleiche Fraktion. Einen eigenen Regelsatz liest Utility nicht aus, weil der Client dafür keine belegte Schnittstelle bietet.", "Same realm and faction. Utility does not read a separate ruleset, because the client offers no confirmed way to do so.")},
    })
    section(v, p, tr("Graue Gegenstände zerstören", "Destroy grey items"), y - 10)
    y = checks(v, p, y - 38, {
        {"destroyGray", tr("Zerstören auf ausdrücklichen Klick erlauben", "Allow destroying on an explicit click"), tr("Über die Anzeige „Billigster grauer Stapel“ der Infoleiste mit Shift-Klick oder den Button hier. Nie im Kampf, nie automatisch.", "Through the info bar's cheapest grey stack display with Shift-click or the button here. Never in combat, never automatically.")},
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
function U.builders.interface(v, p)
    section(v, p, tr("Plündern", "Looting"), 0)
    local y = checks(v, p, -28, {
        {"fastLoot", tr("Automatisches Plündern beschleunigen", "Speed up auto loot"), tr("Folgt deiner Spieleinstellung und Modifikatortaste.", "Follows your game setting and modifier key.")},
        {"lootGreed", tr("Bei grünen Gegenständen automatisch Gier würfeln", "Roll Greed on green items automatically"), tr("Nie bei Gegenständen, die beim Aufheben binden.", "Never on items that bind when picked up.")},
    })
    section(v, p, tr("Dialoge", "Dialogs"), y - 10)
    y = checks(v, p, y - 38, {
        {"skipGossip", tr("Eindeutige Dienst-Dialoge überspringen", "Skip clear service dialogs"), tr("Nur wenn ein bekannter Dienst die einzige Option ist und keine Quest dabei ist. Shift pausiert. Ruhestein binden bleibt deine Entscheidung.", "Only when one known service is the sole option and no quest is attached. Shift pauses. Binding your hearthstone stays your decision.")},
        {"declineDuels", tr("Duellanfragen ablehnen", "Decline duel requests")},
        {"bgRelease", tr("Auf Schlachtfeldern den Geist freilassen", "Release your spirit in battlegrounds"), tr("Nicht mit Seelenstein. Shift pausiert.", "Not with a soulstone. Shift pauses.")},
    })
    section(v, p, tr("Fehlermeldungen", "Error messages"), y - 10)
    y = checks(v, p, y - 38, {
        {"errorFilter", tr("Wiederkehrende rote Meldungen ausblenden", "Hide repeating red messages")},
        {"errResource", tr("Nicht genug Mana, Energie oder Wut", "Not enough mana, energy or rage")},
        {"errCooldown", tr("Fähigkeit nicht bereit", "Ability not ready")},
        {"errRange", tr("Ziel außer Reichweite", "Target out of range")},
        {"errTarget", tr("Kein oder ungültiges Ziel", "No or invalid target")},
    })
    section(v, p, tr("Oberfläche", "Interface"), y - 10)
    y = y - 38
    hint(v, p, tr("Ausgeblendetes ist auch nicht anklickbar, bis es wieder sichtbar ist.", "Hidden elements cannot be clicked either until they show again."), y, 20)
    y = y - 26
    for _, row in ipairs({
        {"hideBags", tr("Taschenleiste", "Bag bar")}, {"hideMicro", tr("Mikromenü", "Micro menu")}, {"hideClock", tr("Uhr an der Minikarte", "Minimap clock")},
        {"hideCalendar", tr("Kalender an der Minikarte", "Minimap calendar")}, {"hideTracking", tr("Aufspüren an der Minikarte", "Minimap tracking")}, {"hideZoneText", tr("Gebietsname an der Minikarte", "Minimap zone name")},
    }) do
        visibility(v, p, row[1], row[2], y)
        y = y - 34
    end
    return -y + 30
end

----------------------------------------------------------------------
-- Profiles
----------------------------------------------------------------------
function U.builders.profiles(v, p)
    local P = NS.Profiles
    section(v, p, tr("Profile", "Profiles"), 0)
    hint(v, p, tr("Ein Profil enthält alle Einstellungen. Jeder Charakter merkt sich seines. Spielzeit, Gold, Makros und die Einkaufslisten pro Charakter gehören nicht dazu.",
        "A profile holds all settings. Each character remembers its own. Playtime, gold, macros and per-character shopping lists are not part of it."), -28, 40)
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
    hint(v, p, tr("Exportieren schreibt das aktive Profil als Text in das Feld. Importieren legt immer ein neues Profil an, beschädigter Text wird abgelehnt.",
        "Export writes the active profile into the field as text. Import always creates a new profile; damaged text is refused."), y, 30)
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
