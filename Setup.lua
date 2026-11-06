local _, NS = ...
local S = {}
NS.Setup = S
local W, L, U, tr = NS.ConfigWizard, NS.Logic, NS.SettingsUI, NS.Text

-- Only these keys belong to the wizard; everything else in the settings stays as it is.
local KEYS = {"mapReveal", "mapCoords", "vendorJunk", "vendorRepair", "questAccept", "questTurnIn",
    "warnDurability", "warnBags", "warnAmmo", "warnPoison", "warnReagents", "screenshotLevel", "screenshotBoss",
    "tooltipPrice", "tooltipIDs", "pullEnabled", "rollTracker"}

local function sanitize(raw, current)
    local combined = L.Copy(current)
    if type(raw) == "table" then
        for _, key in ipairs(KEYS) do if raw[key] ~= nil then combined[key] = raw[key] end end
    end
    combined = L.Sanitize(combined)
    local out = {}
    for _, key in ipairs(KEYS) do out[key] = combined[key] end
    out.graphicsChoice = type(raw) == "table" and raw.graphicsChoice == "beauty" and "beauty" or "keep"
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
        "Viele kleine Helfer in einem Addon. Hier stellst du die wichtigsten ein, alles Weitere findest du unter /zutil.",
        "Many small helpers in one addon. Set up the most important ones here, everything else is under /zutil.", 150, function(v, p)
        v:Label(p, tr("Automatik, die Gold ausgibt, Gegenstände verkauft oder NPCs antwortet, bleibt aus, bis du sie einschaltest. Der Makro-Browser braucht keine Einrichtung und wartet in den Einstellungen auf dich.",
            "Automation that spends gold, sells items or answers NPCs stays off until you turn it on. The macro browser needs no setup and is waiting in the settings."), 0, 0, 552, 70)
        v:Label(p, tr("„Fertig“ übernimmt deine Auswahl. /zutil config öffnet diesen Assistenten erneut.", "Finish applies your choices. /zutil config reopens this wizard."), 0, -84, 552, 40, "GameFontHighlightSmall", "muted")
    end)
    page("Grafik", "Graphics",
        "Die Vorlage nutzt Einstellungen, die das Spielmenü nicht anbietet: dichtes Gras, weite Sicht und scharfe Schatten.",
        "The preset uses settings the game menu does not offer: dense grass, long view distance and sharp shadows.", 170, function(v, p)
        v:Dropdown(p, "graphicsChoice", 0, 0, 400, {{"keep", tr("Grafik unverändert lassen", "Leave graphics unchanged")}, {"beauty", tr("Vorlage „Schöne Weitsicht“ verwenden", "Use the “Beautiful views” preset")}})
        v:Label(p, tr("Das braucht einen kräftigen Rechner. Deine bisherigen Werte werden gesichert. Nach „Fertig“ hast du 30 Sekunden Zeit zu bestätigen, sonst kehrt alles von selbst zurück.",
            "This needs a capable computer. Your current values are saved. After Finish you have 30 seconds to confirm, otherwise everything returns on its own."), 0, -50, 552, 70, "GameFontHighlightSmall", "muted")
    end)
    page("Karte", "Map",
        "Aufdecken ändert nur die Anzeige. Erkundung, Erfahrung und Erfolge bleiben unberührt.",
        "Revealing only changes the display. Exploration, experience and achievements stay untouched.", 110, function(v, p)
        v:Dropdown(p, "mapReveal", 0, 0, 300, {{"off", tr("Karte nicht aufdecken", "Do not reveal the map")}, {"soft", tr("Halbtransparent aufdecken", "Reveal translucent")}, {"full", tr("Voll aufdecken", "Reveal fully")}})
        v:Check(p, "mapCoords", tr("Koordinaten auf der Weltkarte anzeigen", "Show coordinates on the world map"), 0, -48)
    end)
    page("Komfort", "Comfort",
        "Shift hält jede dieser Automatiken beim nächsten Öffnen an.",
        "Shift holds back each of these automations on the next window.", 150, function(v, p)
        v:Check(p, "vendorJunk", tr("Graue Gegenstände beim Händler verkaufen", "Sell grey items at vendors"), 0, 0)
        v:Check(p, "vendorRepair", tr("Beim Händler automatisch reparieren", "Repair automatically at vendors"), 0, -36)
        v:Check(p, "questAccept", tr("Quests automatisch annehmen", "Accept quests automatically"), 0, -72)
        v:Check(p, "questTurnIn", tr("Fertige Quests automatisch abgeben", "Turn in finished quests automatically"), 0, -108)
    end)
    page("Warnungen", "Warnings",
        "Jede Warnung erscheint einmal, wenn es so weit ist.",
        "Each warning appears once when the time comes.", 190, function(v, p)
        v:Check(p, "warnDurability", tr("Niedrige Haltbarkeit", "Low durability"), 0, 0)
        v:Check(p, "warnBags", tr("Fast volle Taschen", "Nearly full bags"), 0, -36)
        v:Check(p, "warnAmmo", tr("Wenig Munition", "Low ammo"), 0, -72)
        v:Check(p, "warnPoison", tr("Abgelaufenes Waffengift", "Expired weapon poison"), 0, -108)
        v:Check(p, "warnReagents", tr("Reagenzien gehen aus", "Reagents running out"), 0, -144)
    end)
    page("Extras", "Extras",
        "Kleinigkeiten für zwischendurch. /zpull startet den Pull-Countdown.",
        "Small things for in between. /zpull starts the pull countdown.", 190, function(v, p)
        v:Check(p, "tooltipPrice", tr("Verkaufspreis im Tooltip", "Sell price in tooltips"), 0, 0)
        v:Check(p, "tooltipIDs", tr("Item- und Zauber-IDs im Tooltip", "Item and spell IDs in tooltips"), 0, -36)
        v:Check(p, "screenshotLevel", tr("Screenshot beim Levelaufstieg", "Screenshot on level up"), 0, -72)
        v:Check(p, "screenshotBoss", tr("Screenshot beim Bosskill", "Screenshot on boss kill"), 0, -108)
        v:Check(p, "rollTracker", tr("Würfe von /roll mitschreiben", "Track /roll results"), 0, -144)
    end)
    page("Bereit", "Ready",
        "Prüfe deine Auswahl. Alles lässt sich jederzeit unter /zutil ändern.",
        "Check your choices. Everything can be changed at any time under /zutil.", 170, function(v, p)
        local summary = v:Label(p, "", 0, 0, 552, 160)
        v:AddUpdate(function()
            local function on(value) return value and tr("An", "On") or tr("Aus", "Off") end
            local reveal = v.draft.mapReveal
            summary:SetText(table.concat({
                tr("Grafik: ", "Graphics: ") .. (v.draft.graphicsChoice == "beauty" and tr("Schöne Weitsicht", "Beautiful views") or tr("unverändert", "unchanged")),
                tr("Karte aufdecken: ", "Reveal map: ") .. ((reveal == "off" and tr("Aus", "Off")) or (reveal == "soft" and tr("Halbtransparent", "Translucent")) or tr("Voll", "Full")),
                tr("Müll verkaufen / Reparieren: ", "Sell junk / repair: ") .. on(v.draft.vendorJunk) .. " / " .. on(v.draft.vendorRepair),
                tr("Quests annehmen / abgeben: ", "Accept / turn in quests: ") .. on(v.draft.questAccept) .. " / " .. on(v.draft.questTurnIn),
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
            if draft.graphicsChoice == "beauty" then
                NS.Graphics.StagePreset("beauty")
                NS.Graphics.Apply(NS.App.db)
                U.Refresh()
            end
        end,
        beforeShow = U.HideAll,
    })
end

function S.Open() if S.wizard then return S.wizard:Open(false) end end
function S.Schedule() if S.wizard then S.wizard:Schedule() end end
