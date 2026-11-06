local _, NS = ...
local M = {}
NS.Macros = M
local A, L, tr = NS.Adapter, NS.Logic, NS.Text

M.MAX_BODY = 255
M.MAX_NAME = 16
M.ICON = 134400 -- question mark: the client swaps it for the #showtooltip spell

M.Categories = {
    TARGETING = {"Zielwahl", "Targeting"}, CONTROL = {"PvP / Kontrolle", "PvP / Control"}, GROUP = {"Gruppe / Raid", "Group / Raid"},
    EQUIPMENT = {"Ausrüstung", "Equipment"}, TRAVEL = {"Reisen", "Travel"}, CONSUMABLES = {"Verbrauchsgüter", "Consumables"},
    PROFESSIONS = {"Berufe", "Professions"}, INTERFACE = {"Interface", "Interface"}, CHAT = {"Kommunikation", "Communication"},
    LEVELING = {"Leveling", "Leveling"}, COMBAT = {"Kampf", "Combat"}, TANK = {"Tank", "Tank"}, HEALING = {"Heilung", "Healing"},
    PETS = {"Begleiter", "Pets"}, TOTEMS = {"Totems", "Totems"}, FORMS = {"Gestalten", "Forms"},
}
M.CategoryOrder = {"TARGETING", "COMBAT", "CONTROL", "HEALING", "TANK", "GROUP", "PETS", "TOTEMS", "FORMS", "LEVELING",
    "EQUIPMENT", "CONSUMABLES", "TRAVEL", "PROFESSIONS", "INTERFACE", "CHAT"}
M.Classes = {
    GENERAL = {"Allgemein", "General"}, WARRIOR = {"Krieger", "Warrior"}, PALADIN = {"Paladin", "Paladin"}, HUNTER = {"Jäger", "Hunter"},
    ROGUE = {"Schurke", "Rogue"}, PRIEST = {"Priester", "Priest"}, SHAMAN = {"Schamane", "Shaman"}, MAGE = {"Magier", "Mage"},
    WARLOCK = {"Hexenmeister", "Warlock"}, DRUID = {"Druide", "Druid"},
}
M.ClassOrder = {"GENERAL", "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}

-- Things only the player can name: their own items and equipment sets.
M.Inputs = {
    NAME_DES_HEILTRANKS = {"Heiltrank", "Healing potion"}, NAME_DES_MANATRANKS = {"Manatrank", "Mana potion"},
    NAME_DES_VERBANDS = {"Verband", "Bandage"}, NAME_DER_WAFFE = {"Waffe", "Weapon"}, NAME_DES_SCHILDS = {"Schild", "Shield"},
    NAME_DER_ANGEL = {"Angel", "Fishing pole"}, NAME_EINHANDWAFFE = {"Einhandwaffe", "One-handed weapon"},
    NAME_SCHILD = {"Schild", "Shield"}, NAME_ZWEIHANDWAFFE = {"Zweihandwaffe", "Two-handed weapon"},
    NAME_DES_GIFTS = {"Gift", "Poison"}, NAME_DES_MANAJUWELS = {"Mana-Juwel", "Mana gem"},
    NAME_DES_SEELENSTEINS = {"Seelenstein", "Soulstone"}, NAME_DES_GESUNDHEITSSTEINS = {"Gesundheitsstein", "Healthstone"},
    NAME_SET_DEFAULT = {"Ausrüstungsset ohne Shift", "Equipment set without Shift"},
    NAME_SET_SHIFT = {"Ausrüstungsset mit Shift", "Equipment set with Shift"},
}
local TEXT = {pull = {"Pull in Kürze – bitte bereit machen.", "Pull incoming, please get ready."}}

local function pick(pair) return tr(pair[1], pair[2]) end
function M.CategoryName(key) return M.Categories[key] and pick(M.Categories[key]) or key end
function M.ClassName(key) return M.Classes[key] and pick(M.Classes[key]) or key end
function M.InputName(key) return M.Inputs[key] and pick(M.Inputs[key]) or key end
function M.Name(entry) return tr(entry.nameDE, entry.nameEN) end
function M.Description(entry) return tr(entry.descDE, entry.descEN) end
function M.Note(entry) return entry.noteDE and tr(entry.noteDE, entry.noteEN) or "" end
function M.ShortName(entry)
    return L.TrimUTF8(tr(entry.shortDE, entry.shortEN), M.MAX_NAME)
end

function M.Find(id)
    for _, entry in ipairs(NS.MacroData) do
        if entry.id == id then return entry end
    end
end

-- Input keys of a macro in the order they appear, each once.
function M.InputKeys(entry)
    local keys, seen = {}, {}
    for key in entry.body:gmatch("{p:([%w_]+)}") do
        if not seen[key] then seen[key] = true; keys[#keys + 1] = key end
    end
    return keys
end

-- Builds the real macro text in the client's language. Returns the body, or nil and a reason.
function M.Expand(entry, inputs)
    inputs = inputs or {}
    local failure
    local body = entry.body:gsub("{s:(%d+)}", function(id)
        local name = A.SpellName(tonumber(id))
        if not name then failure = failure or {kind = "spell", value = tonumber(id)} end
        return name or ""
    end)
    body = body:gsub("{t:(%w+)}", function(key) return TEXT[key] and pick(TEXT[key]) or "" end)
    body = body:gsub("{p:([%w_]+)}", function(key)
        local value = inputs[key]
        value = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
        if value == "" then failure = failure or {kind = "input", value = key} end
        return value
    end)
    if failure then return nil, failure end
    if #body > M.MAX_BODY then return nil, {kind = "length", value = #body} end
    return body
end

-- Readable text for the preview: unresolved parts stay visible as <placeholder>.
function M.Preview(entry, inputs)
    inputs = inputs or {}
    local body = entry.body:gsub("{s:(%d+)}", function(id) return A.SpellName(tonumber(id)) or ("spell:" .. id) end)
    body = body:gsub("{t:(%w+)}", function(key) return TEXT[key] and pick(TEXT[key]) or "" end)
    body = body:gsub("{p:([%w_]+)}", function(key)
        local value = type(inputs[key]) == "string" and inputs[key]:match("^%s*(.-)%s*$") or ""
        return value ~= "" and value or ("<" .. M.InputName(key) .. ">")
    end)
    return body
end

-- "known" = all spells learned, "partial" = some, "unknown" = none, "free" = needs no spell.
function M.Knowledge(entry)
    if not entry.spells then return "free", {} end
    local missing = {}
    for _, spell in ipairs(entry.spells) do
        if not A.SpellKnown(spell) then missing[#missing + 1] = spell end
    end
    if #missing == 0 then return "known", missing end
    if #missing == #entry.spells then return "unknown", missing end
    return "partial", missing
end

function M.Filter(query)
    query = query or {}
    local out = {}
    local text = (query.text or ""):lower()
    for _, entry in ipairs(NS.MacroData) do
        local keep = (not query.class or query.class == "ALL" or entry.class == query.class)
            and (not query.cat or query.cat == "ALL" or entry.cat == query.cat)
        if keep and text ~= "" then
            keep = M.Name(entry):lower():find(text, 1, true) ~= nil or M.Description(entry):lower():find(text, 1, true) ~= nil
        end
        if keep and query.knownOnly then keep = M.Knowledge(entry) ~= "unknown" end
        if keep then out[#out + 1] = entry end
    end
    return out
end

function M.Slots()
    local account, character = A.Call(GetNumMacros)
    local constants = _G.Constants and _G.Constants.MacroConsts
    local accountMax = constants and constants.MAX_ACCOUNT_MACROS or 120
    local characterMax = constants and constants.MAX_CHARACTER_MACROS or 30
    return {account = tonumber(account) or 0, character = tonumber(character) or 0, accountMax = accountMax, characterMax = characterMax}
end

-- Where a macro of this name already lives, and whether it already has this text.
function M.Existing(name, body)
    local index = A.Call(GetMacroIndexByName, name)
    if type(index) ~= "number" or index <= 0 then return nil end
    local current = A.Call(GetMacroBody, index)
    return {index = index, same = current == body or (type(current) == "string" and current:gsub("%s+$", "") == body)}
end

-- Creates a macro. An existing macro of the same name is only replaced when `replace` says so.
function M.Import(entry, inputs, perCharacter, replace)
    if A.Combat() then return false, "combat" end
    local body, failure = M.Expand(entry, inputs)
    if not body then return false, failure.kind, failure.value end
    local name = M.ShortName(entry)
    local existing = M.Existing(name, body)
    if existing and existing.same then return true, "same", existing.index end
    if existing then
        if not replace then return false, "exists", existing.index end
        local ok = pcall(EditMacro, existing.index, name, nil, body)
        if not ok then return false, "failed" end
        return true, "replaced", existing.index
    end
    local slots = M.Slots()
    if perCharacter and slots.character >= slots.characterMax then return false, "full" end
    if not perCharacter and slots.account >= slots.accountMax then return false, "full" end
    local ok, index = pcall(CreateMacro, name, M.ICON, body, perCharacter == true)
    if not ok or type(index) ~= "number" then return false, "failed" end
    return true, "created", index
end

function M.Reason(reason, value)
    if reason == "combat" then return tr("Im Kampf können keine Makros angelegt werden.", "Macros cannot be created in combat.") end
    if reason == "input" then return string.format(tr("Bitte zuerst „%s“ eintragen.", "Please enter “%s” first."), M.InputName(value)) end
    if reason == "spell" then return tr("Der Spielclient kennt einen Zauber dieses Makros nicht.", "The game client does not know a spell of this macro.") end
    if reason == "length" then return string.format(tr("Das Makro wäre mit %d Zeichen zu lang (maximal 255).", "With %d characters the macro would be too long (maximum 255)."), value) end
    if reason == "exists" then return tr("Es gibt schon ein anderes Makro mit diesem Namen. Noch einmal klicken ersetzt es.", "A different macro with this name already exists. Click again to replace it.") end
    if reason == "full" then return tr("Keine freien Makroplätze mehr in dieser Liste.", "No free macro slots left in this list.") end
    if reason == "same" then return tr("Dieses Makro ist bereits vorhanden.", "This macro already exists.") end
    if reason == "created" then return tr("Makro angelegt. Du findest es unter /macro.", "Macro created. You can find it under /macro.") end
    if reason == "replaced" then return tr("Vorhandenes Makro ersetzt.", "Existing macro replaced.") end
    return tr("Das Spiel hat das Makro abgelehnt.", "The game rejected the macro.")
end

-- Keeps a copy of this character's own macros so another character can import them.
function M.SaveCharacterSet(db)
    local scope = A.Scope()
    if not scope or A.Combat() then return false end
    local _, count = A.Call(GetNumMacros)
    local slots = M.Slots()
    local rows = {}
    for slot = 1, tonumber(count) or 0 do
        local name, _, body = A.Call(GetMacroInfo, slots.accountMax + slot)
        if type(name) == "string" and type(body) == "string" then rows[#rows + 1] = {name = name, body = body} end
    end
    db.macroSets[scope] = rows
    return true, #rows
end

function M.LoadCharacterSet(db, scope)
    if A.Combat() then return false, 0, 0 end
    local rows = db.macroSets[scope]
    if type(rows) ~= "table" then return false, 0, 0 end
    local created, skipped = 0, 0
    for _, row in ipairs(rows) do
        local slots = M.Slots()
        local index = A.Call(GetMacroIndexByName, row.name)
        if (type(index) == "number" and index > 0) or slots.character >= slots.characterMax then
            skipped = skipped + 1
        elseif pcall(CreateMacro, row.name, M.ICON, row.body, true) then
            created = created + 1
        else
            skipped = skipped + 1
        end
    end
    return true, created, skipped
end
