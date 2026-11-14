local _, NS = ...
local Y = {}
NS.Layouts = Y
local A, L, tr = NS.Adapter, NS.Logic, NS.Text

-- Library of Blizzard layout strings. Two kinds that never mix:
--   ui  Edit Mode layouts ("5 0 59 0 ..."), read by C_EditMode.ConvertStringToLayoutInfo.
--   cdm Cooldown Manager layouts ("1|<base64>"): Deflate-compressed CBOR, as Blizzard_CooldownViewer writes it.
-- Utility never writes into the game's layouts. C_EditMode.SaveLayouts would bypass the cached copy in
-- EditModeManagerFrame, and C_CooldownViewer.SetLayoutData replaces every Cooldown Manager layout at once.
-- Import therefore always goes through Blizzard's own dialog. Strings are kept exactly as given.
Y.MaxEntries, Y.MaxText, Y.MaxName, Y.MaxDescription = 200, 100000, 40, 120
local KINDS = {ui = true, cdm = true}

local function db() return NS.App.db end

function Y.Clean(text) return type(text) == "string" and text:match("^%s*(.-)%s*$") or "" end

-- Kind by shape only. Whether the game accepts it is checked separately.
function Y.Detect(text)
    text = Y.Clean(text)
    if text:match("^%d+|[%w%+/=]+$") then return "cdm" end
    if text:match("^%d+ %-?%d+ ") then return "ui" end
    return nil
end

----------------------------------------------------------------------
-- Saved library: account wide, apart from the settings profiles.
----------------------------------------------------------------------
local repaired = setmetatable({}, {__mode = "k"})

local function text(value, limit)
    return type(value) == "string" and L.TrimUTF8(value, limit) or ""
end

function Y.Repair(raw)
    raw = type(raw) == "table" and raw or {}
    local out = {entries = {}, favorites = {}, nextId = 1}
    local seen = {}
    for _, entry in ipairs(type(raw.entries) == "table" and raw.entries or {}) do
        local id = type(entry) == "table" and tonumber(entry.id)
        if id and not seen[id] and KINDS[entry.kind] and type(entry.text) == "string" and entry.text ~= "" and #out.entries < Y.MaxEntries then
            seen[id] = true
            out.entries[#out.entries + 1] = {
                id = id, kind = entry.kind, text = entry.text,
                name = text(entry.name, Y.MaxName) ~= "" and text(entry.name, Y.MaxName) or ("Layout " .. id),
                desc = text(entry.desc, Y.MaxDescription),
                source = entry.source == "game" and "game" or "own",
                fav = entry.fav == true,
                added = tonumber(entry.added) or 0,
                origin = type(entry.origin) == "string" and entry.origin or nil,
            }
            out.nextId = math.max(out.nextId, id + 1)
        end
    end
    if type(raw.favorites) == "table" then
        for key, value in pairs(raw.favorites) do
            if type(key) == "string" and value == true then out.favorites[key] = true end
        end
    end
    out.nextId = math.max(out.nextId, math.floor(tonumber(raw.nextId) or 1))
    return out
end

function Y.Library()
    local lib = db().layoutLibrary
    if not repaired[lib] then
        lib = Y.Repair(lib)
        db().layoutLibrary = lib
        repaired[lib] = true
    end
    return lib
end

local function find(id)
    for index, entry in ipairs(Y.Library().entries) do
        if entry.id == id then return entry, index end
    end
end
Y.Find = find

-- Presets come from LayoutPresets.lua. An entry there needs no code change anywhere else.
function Y.Presets(kind)
    local out = {}
    for _, preset in ipairs(NS.LayoutPresets or {}) do
        if type(preset) == "table" and preset.kind == kind and type(preset.id) == "string" and type(preset.text) == "string" then
            out[#out + 1] = preset
        end
    end
    return out
end

local function localized(value)
    if type(value) == "table" then return tr(value[1] or value.de or "", value[2] or value.en or value[1] or "") end
    return type(value) == "string" and value or ""
end

-- One list for the page: presets first, then own entries; favourites only when asked.
function Y.Rows(kind, favoritesOnly)
    local lib, rows = Y.Library(), {}
    for _, preset in ipairs(Y.Presets(kind)) do
        local key = "preset:" .. preset.id
        local fav = lib.favorites[key] == true
        if not favoritesOnly or fav then
            rows[#rows + 1] = {key = key, preset = true, kind = kind, name = localized(preset.name), desc = localized(preset.desc),
                text = preset.text, fav = fav, image = preset.image, author = preset.author}
        end
    end
    local own = {}
    for _, entry in ipairs(lib.entries) do
        if entry.kind == kind and (not favoritesOnly or entry.fav) then own[#own + 1] = entry end
    end
    table.sort(own, function(a, b)
        if a.fav ~= b.fav then return a.fav end
        return a.name:lower() < b.name:lower()
    end)
    for _, entry in ipairs(own) do
        rows[#rows + 1] = {key = "own:" .. entry.id, id = entry.id, kind = kind, name = entry.name, desc = entry.desc,
            text = entry.text, fav = entry.fav, source = entry.source}
    end
    return rows
end

-- Returns the new entry, or nil and a reason: empty, long, kind, exists, full.
function Y.Add(kind, name, desc, value, source, origin)
    value = Y.Clean(value)
    if value == "" then return nil, "empty" end
    if #value > Y.MaxText then return nil, "long" end
    local detected = Y.Detect(value)
    if not detected or (kind and detected ~= kind) then return nil, "kind" end
    local lib = Y.Library()
    for _, entry in ipairs(lib.entries) do
        if entry.kind == detected and (entry.text == value or (origin and entry.origin == origin)) then return nil, "exists", entry end
    end
    if #lib.entries >= Y.MaxEntries then return nil, "full" end
    local id = lib.nextId
    lib.nextId = id + 1
    name = text(Y.Clean(name), Y.MaxName)
    local entry = {id = id, kind = detected, text = value, name = name ~= "" and name or ("Layout " .. id),
        desc = text(Y.Clean(desc), Y.MaxDescription), source = source == "game" and "game" or "own", fav = false,
        added = tonumber(A.Call(GetServerTime)) or 0, origin = origin}
    lib.entries[#lib.entries + 1] = entry
    return entry
end

function Y.Rename(id, name)
    local entry = find(id)
    name = text(Y.Clean(name), Y.MaxName)
    if not entry or name == "" then return false end
    entry.name = name
    return true
end

function Y.Describe(id, desc)
    local entry = find(id)
    if not entry then return false end
    entry.desc = text(Y.Clean(desc), Y.MaxDescription)
    return true
end

function Y.Delete(id)
    local entry, index = find(id)
    if not entry then return false end
    table.remove(Y.Library().entries, index)
    return true
end

function Y.ToggleFavorite(key)
    local lib = Y.Library()
    local id = tonumber(key:match("^own:(%d+)$"))
    if id then
        local entry = find(id)
        if not entry then return false end
        entry.fav = not entry.fav
        return true
    end
    if key:match("^preset:") then
        lib.favorites[key] = not lib.favorites[key] or nil
        return true
    end
    return false
end

function Y.ReasonText(reason)
    return ({
        empty = tr("Kein Text eingefügt.", "No text pasted."),
        long = tr("Der Text ist zu lang.", "The text is too long."),
        kind = tr("Das ist kein Layout dieser Kategorie.", "This is not a layout of this category."),
        exists = tr("Dieses Layout ist schon gespeichert.", "This layout is already saved."),
        full = tr("Die Bibliothek ist voll.", "The library is full."),
        api = tr("Der Client bietet dafür keine Schnittstelle.", "The client offers no interface for this."),
        invalid = tr("Das Spiel kann diesen Text nicht lesen.", "The game cannot read this text."),
        none = tr("Im Spiel sind keine eigenen Layouts gespeichert.", "There are no own layouts saved in the game."),
    })[reason] or tr("Nicht möglich.", "Not possible.")
end

----------------------------------------------------------------------
-- Edit Mode: decoding and a simplified preview from the decoded anchors.
----------------------------------------------------------------------
function Y.DecodeUI(value)
    local api = _G.C_EditMode
    if not api or type(api.ConvertStringToLayoutInfo) ~= "function" then return nil, "api" end
    local info = A.Call(api.ConvertStringToLayoutInfo, Y.Clean(value))
    if type(info) ~= "table" or type(info.systems) ~= "table" then return nil, "invalid" end
    return info
end

-- FramePoint may arrive as a name or as the enum number.
local POINTS = {[0] = "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"}
local function pointName(value)
    if type(value) == "number" then return POINTS[value] or "CENTER" end
    return type(value) == "string" and value or "CENTER"
end

local function pointOffset(point, width, height)
    point = pointName(point)
    local x = point:find("LEFT") and 0 or (point:find("RIGHT") and width or width / 2)
    local y = point:find("TOP") and height or (point:find("BOTTOM") and 0 or height / 2)
    return x, y
end

-- Positions in screen units (origin bottom left). `live(system)` describes the matching frame of the
-- running interface ({name, width, height, scale, frameName}); `rectOf(frameName)` gives left, bottom,
-- width, height of any other frame. Sizes come from the current interface, positions from the string.
function Y.PreviewBoxes(systems, live, rectOf, screenWidth, screenHeight)
    local boxes, byFrame, busy = {}, {}, {}
    for index, system in ipairs(systems or {}) do
        local info = live and live(system) or nil
        info = type(info) == "table" and info or {}
        local box = {system = system, index = index, name = info.name, frameName = info.frameName, scale = tonumber(info.scale) or 1,
            width = math.max(8, tonumber(info.width) or 60), height = math.max(8, tonumber(info.height) or 24), known = info.width ~= nil}
        boxes[index] = box
        if box.frameName then byFrame[box.frameName] = box end
    end
    local function resolve(box, depth)
        if box.left then return end
        if depth > 16 or busy[box] then
            box.left, box.bottom = (screenWidth - box.width) / 2, (screenHeight - box.height) / 2
            return
        end
        busy[box] = true
        local anchor = type(box.system.anchorInfo) == "table" and box.system.anchorInfo or {}
        local left, bottom, width, height = 0, 0, screenWidth, screenHeight
        local relative = anchor.relativeTo
        if type(relative) == "string" and relative ~= "UIParent" then
            local other = byFrame[relative]
            if other then
                resolve(other, depth + 1)
                left, bottom, width, height = other.left, other.bottom, other.width, other.height
            elseif rectOf then
                local l, b, w, h = rectOf(relative)
                if l and b and w and h then left, bottom, width, height = l, b, w, h end
            end
        end
        local targetX, targetY = pointOffset(anchor.relativePoint or anchor.point, width, height)
        local ownX, ownY = pointOffset(anchor.point, box.width, box.height)
        box.left = left + targetX + (tonumber(anchor.offsetX) or 0) * box.scale - ownX
        box.bottom = bottom + targetY + (tonumber(anchor.offsetY) or 0) * box.scale - ownY
        busy[box] = nil
    end
    for _, box in ipairs(boxes) do resolve(box, 0) end
    return boxes
end

local function systemKey(system)
    local names = _G.Enum and _G.Enum.EditModeSystem
    if type(names) == "table" then
        for key, value in pairs(names) do if value == system then return key end end
    end
    return tostring(system)
end
Y.SystemKey = systemKey

-- Reads the running interface. Only reading: nothing is moved, shown or saved.
local function uiScale()
    local scale = UIParent and A.Call(UIParent.GetEffectiveScale, UIParent)
    return tonumber(scale) or 1
end

local function sameIndex(a, b)
    a, b = tonumber(a) or -1, tonumber(b) or -1
    return a == b or (a <= 0 and b <= 0)
end

function Y.LiveSystem(system)
    local manager = _G.EditModeManagerFrame
    local frames = manager and manager.registeredSystemFrames
    if type(frames) ~= "table" then return nil end
    for _, frame in ipairs(frames) do
        if type(frame) == "table" and frame.system == system.system and sameIndex(frame.systemIndex, system.systemIndex) then
            local relative = (tonumber(A.Call(frame.GetEffectiveScale, frame)) or uiScale()) / uiScale()
            local name = type(frame.GetSystemName) == "function" and A.Call(frame.GetSystemName, frame) or nil
            return {
                name = type(name) == "string" and name or nil,
                frameName = A.Call(frame.GetName, frame),
                width = (tonumber(A.Call(frame.GetWidth, frame)) or 0) * relative,
                height = (tonumber(A.Call(frame.GetHeight, frame)) or 0) * relative,
                scale = relative,
            }
        end
    end
end

function Y.FrameRect(name)
    local frame = _G[name]
    if type(frame) ~= "table" or type(frame.GetLeft) ~= "function" then return nil end
    local relative = (tonumber(A.Call(frame.GetEffectiveScale, frame)) or uiScale()) / uiScale()
    local left, bottom = A.Call(frame.GetLeft, frame), A.Call(frame.GetBottom, frame)
    local width, height = A.Call(frame.GetWidth, frame), A.Call(frame.GetHeight, frame)
    if not (tonumber(left) and tonumber(bottom) and tonumber(width) and tonumber(height)) then return nil end
    return left * relative, bottom * relative, width * relative, height * relative
end

function Y.ScreenSize()
    local width = UIParent and tonumber(A.Call(UIParent.GetWidth, UIParent)) or 1920
    local height = UIParent and tonumber(A.Call(UIParent.GetHeight, UIParent)) or 1080
    return math.max(1, width), math.max(1, height)
end

function Y.UIPreview(value)
    local info, reason = Y.DecodeUI(value)
    if not info then return nil, reason end
    local width, height = Y.ScreenSize()
    return Y.PreviewBoxes(info.systems, Y.LiveSystem, Y.FrameRect, width, height), info
end

----------------------------------------------------------------------
-- Cooldown Manager: "<encoding version>|<payload>", version 1 = Base64(Deflate(CBOR)).
-- Field numbers as in Blizzard_CooldownViewer's CooldownViewerSettingsDataStoreSerialization.lua.
----------------------------------------------------------------------
local FIELD_VERSION, FIELD_ACTIVE, FIELD_LAYOUTS, FIELD_NAMES = 1, 2, 3, 4
local FIELD_ORDER, FIELD_CATEGORIES, FIELD_ALERTS = 1, 2, 3

local function deflate()
    local methods = _G.Enum and _G.Enum.CompressionMethod
    return methods and methods.Deflate
end

function Y.DecodeCooldown(value)
    local api = _G.C_EncodingUtil
    if not api or not deflate() then return nil, "api" end
    local version, payload = Y.Clean(value):match("^(%d+)|(.+)$")
    if version ~= "1" then return nil, "invalid" end
    local decoded = A.Call(api.DecodeBase64, payload)
    local inflated = decoded and A.Call(api.DecompressString, decoded, deflate())
    local data = inflated and A.Call(api.DeserializeCBOR, inflated)
    if type(data) ~= "table" or type(data[FIELD_VERSION]) ~= "number" then return nil, "invalid" end
    return data
end

local function count(list)
    local n = 0
    if type(list) == "table" then for _ in pairs(list) do n = n + 1 end end
    return n
end

-- One row per contained layout: name, class and specialization tag, cooldown order, category moves, alerts.
function Y.CooldownSummary(data)
    local out = {}
    local layouts, names = type(data) == "table" and data[FIELD_LAYOUTS], type(data) == "table" and data[FIELD_NAMES] or {}
    if type(layouts) ~= "table" then return out end
    for tag, group in pairs(layouts) do
        if type(group) == "table" then
            for layoutID, layout in pairs(group) do
                if type(layout) == "table" then
                    local categories = {}
                    for category, ids in pairs(type(layout[FIELD_CATEGORIES]) == "table" and layout[FIELD_CATEGORIES] or {}) do
                        categories[category] = count(ids)
                    end
                    local alerts = 0
                    for _, list in pairs(type(layout[FIELD_ALERTS]) == "table" and layout[FIELD_ALERTS] or {}) do alerts = alerts + count(list) end
                    out[#out + 1] = {
                        id = layoutID, tag = tonumber(tag), name = type(names) == "table" and type(names[layoutID]) == "string" and names[layoutID] or nil,
                        classID = tonumber(tag) and math.floor(tonumber(tag) / 10), spec = tonumber(tag) and tonumber(tag) % 10,
                        order = type(layout[FIELD_ORDER]) == "table" and layout[FIELD_ORDER] or {}, categories = categories, alerts = alerts,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
    return out
end

-- The same structure Blizzard writes when it exports a single layout: no active layouts, one layout.
function Y.SingleCooldownTable(data, tag, layoutID)
    local version = data[FIELD_VERSION]
    local layout = data[FIELD_LAYOUTS][tag][layoutID]
    local names = type(data[FIELD_NAMES]) == "table" and data[FIELD_NAMES] or {}
    return {
        [FIELD_VERSION] = version,
        [FIELD_ACTIVE] = {},
        [FIELD_LAYOUTS] = {[tag] = {[layoutID] = layout}},
        [FIELD_NAMES] = {[layoutID] = names[layoutID]},
    }
end

function Y.EncodeCooldown(data)
    local api = _G.C_EncodingUtil
    if not api or not deflate() then return nil end
    local serialized = A.Call(api.SerializeCBOR, data)
    local compressed = serialized and A.Call(api.CompressString, serialized, deflate())
    local encoded = compressed and A.Call(api.EncodeBase64, compressed)
    return type(encoded) == "string" and ("1|" .. encoded) or nil
end

local CATEGORY_NAMES = {
    Essential = {"Wichtig", "Essential"}, Utility = {"Nützlich", "Utility"}, TrackedBuff = {"Buffs", "Buffs"},
    TrackedBar = {"Leisten", "Bars"}, HiddenSpell = {"Ausgeblendet", "Hidden"}, HiddenAura = {"Ausgeblendet", "Hidden"},
}
function Y.CategoryName(category)
    local enum = _G.Enum and _G.Enum.CooldownViewerCategory
    if type(enum) == "table" then
        for key, value in pairs(enum) do
            if value == category then
                local name = CATEGORY_NAMES[key]
                return name and tr(name[1], name[2]) or key
            end
        end
    end
    return tostring(category)
end

function Y.SpecText(classID, spec)
    local className = classID and A.Call(GetClassInfo, classID)
    local api = _G.C_SpecializationInfo
    local specName
    if api and classID and spec then specName = select(2, A.Call(api.GetSpecializationInfo, spec, false, false, nil, nil, nil, classID)) end
    if type(className) == "string" and type(specName) == "string" then return specName .. " " .. className end
    if type(className) == "string" then return className .. " (" .. tostring(spec) .. ")" end
    return classID and string.format(tr("Klasse %d, Spezialisierung %d", "Class %d, specialization %d"), classID, spec or 0) or "?"
end

function Y.CooldownIcon(cooldownID)
    local api = _G.C_CooldownViewer
    local info = api and A.Call(api.GetCooldownViewerCooldownInfo, cooldownID)
    local spell = type(info) == "table" and (info.overrideSpellID or info.spellID)
    return spell and A.SpellIcon(spell) or nil
end

----------------------------------------------------------------------
-- Taking over the game's own layouts. Read only: the game's data stays as it is.
----------------------------------------------------------------------
function Y.ReadGame(kind)
    local added, skipped = 0, 0
    if kind == "ui" then
        local api = _G.C_EditMode
        if not api or type(api.GetLayouts) ~= "function" or type(api.ConvertLayoutInfoToString) ~= "function" then return nil, "api" end
        local data = A.Call(api.GetLayouts)
        local preset = _G.Enum and _G.Enum.EditModeLayoutType and _G.Enum.EditModeLayoutType.Preset
        local found = 0
        for _, info in ipairs(type(data) == "table" and type(data.layouts) == "table" and data.layouts or {}) do
            if type(info) == "table" and info.layoutType ~= preset then
                found = found + 1
                local value = A.Call(api.ConvertLayoutInfoToString, info)
                if type(value) == "string" and Y.Add("ui", info.layoutName, tr("Aus dem Spiel übernommen", "Taken from the game"), value, "game") then
                    added = added + 1
                else
                    skipped = skipped + 1
                end
            end
        end
        if found == 0 then return nil, "none" end
        return added, skipped
    end
    local api = _G.C_CooldownViewer
    if not api or type(api.GetLayoutData) ~= "function" then return nil, "api" end
    local value = A.Call(api.GetLayoutData)
    if type(value) ~= "string" or value == "" then return nil, "none" end
    local data, reason = Y.DecodeCooldown(value)
    if not data then return nil, reason end
    local rows = Y.CooldownSummary(data)
    if #rows == 0 then return nil, "none" end
    for _, row in ipairs(rows) do
        local single = Y.EncodeCooldown(Y.SingleCooldownTable(data, row.tag, row.id))
        local name = row.name or Y.SpecText(row.classID, row.spec)
        -- A re-encoded string can differ byte for byte, so the origin marks a layout already taken over.
        local origin = "cdm:" .. tostring(row.tag) .. ":" .. tostring(row.id) .. ":" .. tostring(row.name)
        if single and Y.Add("cdm", name, Y.SpecText(row.classID, row.spec), single, "game", origin) then
            added = added + 1
        else
            skipped = skipped + 1
        end
    end
    return added, skipped
end

-- The Blizzard steps for a manual import. The Cooldown Manager command comes from the client.
function Y.ImportSteps(kind)
    if kind == "ui" then
        return tr("Import im Spiel: Esc > Bearbeitungsmodus > Layout-Auswahl > Importieren, Text einfügen, neuen Namen wählen.",
            "Import in the game: Esc > Edit Mode > layout menu > Import, paste the text, choose a new name.")
    end
    local command = type(_G.SLASH_COOLDOWNMANAGER1) == "string" and _G.SLASH_COOLDOWNMANAGER1 or nil
    local open = command and string.format(tr("%s öffnen", "open %s"), command) or tr("Cooldown-Manager-Einstellungen öffnen", "open the Cooldown Manager settings")
    return string.format(tr("Import im Spiel: %s > Layout-Menü > Importieren, Text einfügen. Gilt nur für die passende Spezialisierung.",
        "Import in the game: %s > layout menu > Import, paste the text. Only applies to the matching specialization."), open)
end
