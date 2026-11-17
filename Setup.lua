local _, NS = ...
local S = {}
NS.Setup = S
local W, L, U, tr = NS.ConfigWizard, NS.Logic, NS.SettingsUI, NS.Text

-- Only these keys belong to the wizard; everything else in the settings stays as it is.
local KEYS = {"mapReveal", "vendorJunk", "vendorRepair", "questAccept", "questTurnIn",
    "warnDurability", "warnBags", "warnAmmo", "warnPoison", "warnReagents", "screenshotLevel", "screenshotBoss",
    "tooltipIDs", "rollTracker",
    "modBuffs", "modInfoBar", "questRewardValue", "fastLoot", "lootFeed", "lootRoll"}

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
    local function page(de, en, dde, den, build)
        pages[#pages + 1] = {title = tr(de, en), description = tr(dde, den), build = build}
    end
    local function toggle(form, key, de, en) form:Toggle({key = key, label = tr(de, en)}) end
    page("Willkommen bei ZENIAL Utility", "Welcome to ZENIAL Utility",
        "Die wichtigsten Helfer einstellen. Alles Weitere unter /zutil.",
        "Set up the main helpers. Everything else is under /zutil.", function(form)
        form:Note({text = tr("Was Gold ausgibt, verkauft oder NPCs antwortet, bleibt aus, bis du es einschaltest.",
            "Anything that spends gold, sells or answers NPCs stays off until you turn it on.")})
        form:Note({text = tr("/zutil config öffnet diesen Assistenten erneut.", "/zutil config reopens this wizard.")})
    end)
    page("Grafik", "Graphics",
        "Eine Grafikvorlage über Einstellungen, die das Spielmenü nicht anbietet.",
        "A graphics preset through settings the game menu does not offer.", function(form)
        form:Select({key = "graphicsChoice", label = tr("Grafik", "Graphics"), default = "keep", options = {
            {"keep", tr("Grafik unverändert lassen", "Leave graphics unchanged")},
            {"beauty", tr("Vorlage „Schöne Weitsicht“ verwenden", "Use the “Beautiful views” preset")},
            {"fps", tr("Vorlage „Mehr FPS – gute Optik“ verwenden", "Use the “More FPS – good looks” preset")}}})
        form:Note({text = tr("Schöne Weitsicht braucht einen kräftigen Rechner und setzt 98 % Render-Skalierung mit Schärfe 0,5. Mehr FPS senkt teure Effekte. Deine Werte werden gesichert; ohne Bestätigung binnen 30 Sekunden kehrt alles zurück.",
            "Beautiful views needs a capable computer and sets 98% render scale with sharpness 0.5. More FPS lowers expensive effects. Your values are saved; without confirmation within 30 seconds everything reverts.")})
    end)
    page("Karte", "Map",
        "Aufdecken ändert nur die Anzeige. Erkundung, Erfahrung und Erfolge bleiben unberührt.",
        "Revealing only changes the display. Exploration, experience and achievements stay untouched.", function(form)
        form:Select({key = "mapReveal", label = tr("Karte aufdecken", "Reveal map"), options = {
            {"off", tr("Karte nicht aufdecken", "Do not reveal the map")}, {"soft", tr("Halbtransparent aufdecken", "Reveal translucent")},
            {"full", tr("Voll aufdecken", "Reveal fully")}}})
    end)
    page("Komfort", "Comfort",
        "Shift hält jede Automatik beim Öffnen an.",
        "Shift holds back each automation when opening.", function(form)
        toggle(form, "vendorJunk", "Graue Gegenstände beim Händler verkaufen", "Sell grey items at vendors")
        toggle(form, "vendorRepair", "Beim Händler automatisch reparieren", "Repair automatically at vendors")
        toggle(form, "questAccept", "Quests automatisch annehmen", "Accept quests automatically")
        toggle(form, "questTurnIn", "Fertige Quests automatisch abgeben", "Turn in finished quests automatically")
    end)
    page("Warnungen", "Warnings",
        "Jede Warnung erscheint einmal.",
        "Each warning appears once.", function(form)
        toggle(form, "warnDurability", "Niedrige Haltbarkeit", "Low durability")
        toggle(form, "warnBags", "Fast volle Taschen", "Nearly full bags")
        toggle(form, "warnAmmo", "Wenig Munition", "Low ammo")
        toggle(form, "warnPoison", "Abgelaufenes Waffengift", "Expired weapon poison")
        toggle(form, "warnReagents", "Reagenzien gehen aus", "Reagents running out")
    end)
    page("Extras", "Extras",
        "Kleinigkeiten für zwischendurch.",
        "Small things for in between.", function(form)
        toggle(form, "tooltipIDs", "Item- und Zauber-IDs im Tooltip", "Item and spell IDs in tooltips")
        toggle(form, "screenshotLevel", "Screenshot beim Levelaufstieg", "Screenshot on level up")
        toggle(form, "screenshotBoss", "Screenshot beim Bosskill", "Screenshot on boss kill")
        toggle(form, "rollTracker", "Würfelfenster für /roll", "Roll window for /roll")
    end)
    page("Neue Anzeigen", "New displays",
        "Diese Helfer zeigen etwas Neues an und bleiben aus, bis du sie wählst.",
        "These helpers show something new and stay off until you choose them.", function(form)
        toggle(form, "modBuffs", "Warnleisten für Buffs und Verbrauchsmaterial", "Warning bars for buffs and consumables")
        toggle(form, "modInfoBar", "Infoleiste mit Gold, Zeit, Ort und mehr", "Info bar with gold, time, location and more")
        toggle(form, "questRewardValue", "Händlerwert auf Questbelohnungen", "Vendor value on quest rewards")
        toggle(form, "fastLoot", "Schnelles Plündern", "Fast looting")
        toggle(form, "lootFeed", "Loot-Anzeige für erhaltene Gegenstände", "Loot display for received items")
        toggle(form, "lootRoll", "Eigenes Würfelfenster für Gruppenbeute", "Own roll window for group loot")
    end)
    page("Bereit", "Ready",
        "Deine Auswahl. Alles bleibt unter /zutil änderbar.",
        "Your choices. Everything stays changeable under /zutil.", function(form, v)
        form:Note({text = function()
            local function on(value) return value and tr("An", "On") or tr("Aus", "Off") end
            local reveal = v.draft.mapReveal
            return table.concat({
                tr("Grafik: ", "Graphics: ") .. ((v.draft.graphicsChoice == "beauty" and tr("Schöne Weitsicht", "Beautiful views"))
                    or (v.draft.graphicsChoice == "fps" and tr("Mehr FPS – gute Optik", "More FPS – good looks")) or tr("unverändert", "unchanged")),
                tr("Karte aufdecken: ", "Reveal map: ") .. ((reveal == "off" and tr("Aus", "Off")) or (reveal == "soft" and tr("Halbtransparent", "Translucent")) or tr("Voll", "Full")),
                tr("Müll verkaufen / Reparieren: ", "Sell junk / repair: ") .. on(v.draft.vendorJunk) .. " / " .. on(v.draft.vendorRepair),
                tr("Quests annehmen / abgeben: ", "Accept / turn in quests: ") .. on(v.draft.questAccept) .. " / " .. on(v.draft.questTurnIn),
                tr("Warnleisten / Infoleiste: ", "Warning bars / info bar: ") .. on(v.draft.modBuffs) .. " / " .. on(v.draft.modInfoBar),
            }, "\n\n")
        end})
    end)
    S.wizard = W.New({
        label = "Utility", steps = pages, store = db.setup,
        default = function(key) return L.Defaults[key] end,
        capture = function() return sanitize(nil, NS.App.db) end,
        sanitize = sanitize,
        apply = function(draft)
            for _, key in ipairs(KEYS) do NS.App.db[key] = draft[key] end
            NS.App:Changed()
            if draft.graphicsChoice == "beauty" or draft.graphicsChoice == "fps" then
                local G = NS.Graphics
                local missing = G.PresetPlan(draft.graphicsChoice).missing
                G.StagePreset(draft.graphicsChoice)
                local ok, changed, refused, clamped = G.Apply(NS.App.db)
                -- Partial application must not stay silent; combat keeps its existing behaviour.
                if not (ok == false and changed == "combat") then
                    local unavailable = {}
                    for _, name in ipairs(missing) do unavailable[#unavailable + 1] = name end
                    for _, name in ipairs(type(refused) == "table" and refused or {}) do unavailable[#unavailable + 1] = name end
                    local adjusted = type(clamped) == "table" and clamped or {}
                    if #unavailable > 0 or #adjusted > 0 then
                        local parts = {tr("Grafikvorlage nur teilweise angewendet.", "Graphics preset only partly applied.")}
                        if #unavailable > 0 then parts[#parts + 1] = tr("Nicht verfügbar oder abgelehnt: ", "Not available or refused: ") .. table.concat(unavailable, ", ") .. "." end
                        if #adjusted > 0 then parts[#parts + 1] = tr("Vom Spiel angepasst: ", "Adjusted by the game: ") .. table.concat(adjusted, ", ") .. "." end
                        NS.Adapter.Print(table.concat(parts, " "))
                    end
                end
                U.Refresh()
            end
        end,
        beforeShow = U.HideAll,
    })
end

function S.Open() if S.wizard then return S.wizard:Open(false) end end
function S.Schedule() if S.wizard then S.wizard:Schedule() end end
