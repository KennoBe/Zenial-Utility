local _, NS = ...
local S = {}
NS.Setup = S
local W, L, U, tr = NS.ConfigWizard, NS.Logic, NS.SettingsUI, NS.Text

-- Only these keys belong to the wizard; everything else in the settings stays as it is.
local KEYS = {"mapReveal", "vendorJunk", "vendorRepair", "questAccept", "questTurnIn",
    "warnDurability", "warnBags", "warnAmmo", "warnPoison", "warnReagents", "screenshotLevel", "screenshotBoss",
    "tooltipIDs", "rollTracker",
    "modBuffs", "modInfoBar", "questRewardValue", "fastLoot", "lootFeed"}

local function sanitize(raw, current)
    local combined = L.Copy(current)
    if type(raw) == "table" then
        for _, key in ipairs(KEYS) do if raw[key] ~= nil then combined[key] = raw[key] end end
    end
    combined = L.Sanitize(combined)
    local out = {}
    for _, key in ipairs(KEYS) do out[key] = combined[key] end
    local choice = type(raw) == "table" and raw.graphicsChoice
    out.graphicsChoice = (choice == "beauty" or choice == "fps") and choice or "keep"
    return out
end

function S.Initialize(fresh)
    if S.wizard then return end
    local db = NS.App.db
    db.setup = W.Store(db.setup, fresh)
    local pages = {}
    local function page(de, en, dde, den, height, build)
        pages[#pages + 1] = {title = tr(de, en), description = tr(dde, den), height = height, build = build}
    end
    page("Willkommen bei ZENIAL Utility", "Welcome to ZENIAL Utility",
        "Die wichtigsten Helfer einstellen. Alles Weitere unter /zutil.",
        "Set up the main helpers. Everything else is under /zutil.", 150, function(v, p)
        v:Label(p, tr("Was Gold ausgibt, verkauft oder NPCs antwortet, bleibt aus, bis du es einschaltest.",
            "Anything that spends gold, sells or answers NPCs stays off until you turn it on."), 0, 0, 552, 50)
        v:Label(p, tr("/zutil config öffnet diesen Assistenten erneut.", "/zutil config reopens this wizard."), 0, -60, 552, 40, "GameFontHighlightSmall", "muted")
    end)
    page("Grafik", "Graphics",
        "Eine Grafikvorlage über Einstellungen, die das Spielmenü nicht anbietet.",
        "A graphics preset through settings the game menu does not offer.", 170, function(v, p)
        v:Dropdown(p, "graphicsChoice", 0, 0, 400, {{"keep", tr("Grafik unverändert lassen", "Leave graphics unchanged")},
            {"beauty", tr("Vorlage „Schöne Weitsicht“ verwenden", "Use the “Beautiful views” preset")},
            {"fps", tr("Vorlage „Mehr FPS – gute Optik“ verwenden", "Use the “More FPS – good looks” preset")}})
        v:Label(p, tr("Schöne Weitsicht braucht einen kräftigen Rechner, Mehr FPS senkt teure Effekte. Deine Werte werden gesichert; ohne Bestätigung binnen 30 Sekunden kehrt alles zurück.",
            "Beautiful views needs a capable computer, More FPS lowers expensive effects. Your values are saved; without confirmation within 30 seconds everything reverts."), 0, -50, 552, 70, "GameFontHighlightSmall", "muted")
    end)
    page("Karte", "Map",
        "Aufdecken ändert nur die Anzeige. Erkundung, Erfahrung und Erfolge bleiben unberührt.",
        "Revealing only changes the display. Exploration, experience and achievements stay untouched.", 80, function(v, p)
        v:Dropdown(p, "mapReveal", 0, 0, 300, {{"off", tr("Karte nicht aufdecken", "Do not reveal the map")}, {"soft", tr("Halbtransparent aufdecken", "Reveal translucent")}, {"full", tr("Voll aufdecken", "Reveal fully")}})
    end)
    page("Komfort", "Comfort",
        "Shift hält jede Automatik beim Öffnen an.",
        "Shift holds back each automation when opening.", 150, function(v, p)
        v:Check(p, "vendorJunk", tr("Graue Gegenstände beim Händler verkaufen", "Sell grey items at vendors"), 0, 0)
        v:Check(p, "vendorRepair", tr("Beim Händler automatisch reparieren", "Repair automatically at vendors"), 0, -36)
        v:Check(p, "questAccept", tr("Quests automatisch annehmen", "Accept quests automatically"), 0, -72)
        v:Check(p, "questTurnIn", tr("Fertige Quests automatisch abgeben", "Turn in finished quests automatically"), 0, -108)
    end)
    page("Warnungen", "Warnings",
        "Jede Warnung erscheint einmal.",
        "Each warning appears once.", 190, function(v, p)
        v:Check(p, "warnDurability", tr("Niedrige Haltbarkeit", "Low durability"), 0, 0)
        v:Check(p, "warnBags", tr("Fast volle Taschen", "Nearly full bags"), 0, -36)
        v:Check(p, "warnAmmo", tr("Wenig Munition", "Low ammo"), 0, -72)
        v:Check(p, "warnPoison", tr("Abgelaufenes Waffengift", "Expired weapon poison"), 0, -108)
        v:Check(p, "warnReagents", tr("Reagenzien gehen aus", "Reagents running out"), 0, -144)
    end)
    page("Extras", "Extras",
        "Kleinigkeiten für zwischendurch.",
        "Small things for in between.", 150, function(v, p)
        v:Check(p, "tooltipIDs", tr("Item- und Zauber-IDs im Tooltip", "Item and spell IDs in tooltips"), 0, 0)
        v:Check(p, "screenshotLevel", tr("Screenshot beim Levelaufstieg", "Screenshot on level up"), 0, -36)
        v:Check(p, "screenshotBoss", tr("Screenshot beim Bosskill", "Screenshot on boss kill"), 0, -72)
        v:Check(p, "rollTracker", tr("Würfelfenster für /roll", "Roll window for /roll"), 0, -108)
    end)
    page("Neue Anzeigen", "New displays",
        "Diese Helfer zeigen etwas Neues an und bleiben aus, bis du sie wählst.",
        "These helpers show something new and stay off until you choose them.", 190, function(v, p)
        v:Check(p, "modBuffs", tr("Warnleisten für Buffs und Verbrauchsmaterial", "Warning bars for buffs and consumables"), 0, 0)
        v:Check(p, "modInfoBar", tr("Infoleiste mit Gold, Zeit, Ort und mehr", "Info bar with gold, time, location and more"), 0, -36)
        v:Check(p, "questRewardValue", tr("Händlerwert auf Questbelohnungen", "Vendor value on quest rewards"), 0, -72)
        v:Check(p, "fastLoot", tr("Schnelles Plündern", "Fast looting"), 0, -108)
        v:Check(p, "lootFeed", tr("Loot-Anzeige für erhaltene Gegenstände", "Loot display for received items"), 0, -144)
    end)
    page("Bereit", "Ready",
        "Deine Auswahl. Alles bleibt unter /zutil änderbar.",
        "Your choices. Everything stays changeable under /zutil.", 170, function(v, p)
        local summary = v:Label(p, "", 0, 0, 552, 160)
        v:AddUpdate(function()
            local function on(value) return value and tr("An", "On") or tr("Aus", "Off") end
            local reveal = v.draft.mapReveal
            summary:SetText(table.concat({
                tr("Grafik: ", "Graphics: ") .. ((v.draft.graphicsChoice == "beauty" and tr("Schöne Weitsicht", "Beautiful views"))
                    or (v.draft.graphicsChoice == "fps" and tr("Mehr FPS – gute Optik", "More FPS – good looks")) or tr("unverändert", "unchanged")),
                tr("Karte aufdecken: ", "Reveal map: ") .. ((reveal == "off" and tr("Aus", "Off")) or (reveal == "soft" and tr("Halbtransparent", "Translucent")) or tr("Voll", "Full")),
                tr("Müll verkaufen / Reparieren: ", "Sell junk / repair: ") .. on(v.draft.vendorJunk) .. " / " .. on(v.draft.vendorRepair),
                tr("Quests annehmen / abgeben: ", "Accept / turn in quests: ") .. on(v.draft.questAccept) .. " / " .. on(v.draft.questTurnIn),
                tr("Warnleisten / Infoleiste: ", "Warning bars / info bar: ") .. on(v.draft.modBuffs) .. " / " .. on(v.draft.modInfoBar),
            }, "\n\n"))
        end)
    end)
    S.wizard = W.New({
        title = "ZENIAL UTILITY", steps = pages, store = db.setup,
        capture = function() return sanitize(nil, NS.App.db) end,
        sanitize = sanitize,
        apply = function(draft)
            for _, key in ipairs(KEYS) do NS.App.db[key] = draft[key] end
            NS.App:Changed()
            if draft.graphicsChoice == "beauty" or draft.graphicsChoice == "fps" then
                NS.Graphics.StagePreset(draft.graphicsChoice)
                NS.Graphics.Apply(NS.App.db)
                U.Refresh()
            end
        end,
        beforeShow = U.HideAll,
    })
end

function S.Open() if S.wizard then return S.wizard:Open(false) end end
function S.Schedule() if S.wizard then S.wizard:Schedule() end end
