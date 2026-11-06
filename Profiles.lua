local _, NS = ...
local P = {}
NS.Profiles = P
local A, L, tr = NS.Adapter, NS.Logic, NS.Text

P.DefaultName = "Default"

local function db() return NS.App.db end

-- A save from before profiles keeps its values: they become the default profile.
function P.Initialize()
    local data = db()
    if not data.profiles[P.DefaultName] then data.profiles[P.DefaultName] = L.ProfileSnapshot(data) end
end

function P.Active()
    local data, scope = db(), A.Scope()
    local name = scope and data.charProfiles[scope]
    if name and data.profiles[name] then return name end
    return P.DefaultName
end

function P.Names()
    local names = {}
    for name in pairs(db().profiles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- Called by every settings change: the active profile follows the live values.
function P.Store()
    local data = db()
    if P.loading or not P.ready then return end
    data.profiles[P.Active()] = L.ProfileSnapshot(data)
end

local function load(name)
    local app = NS.App
    P.loading = true
    app.db = L.ApplySnapshot(app.db, app.db.profiles[name])
    ZenialUtilityDB = app.db
    P.loading = false
end

-- Each character remembers its profile. A character seen for the first time takes the default.
function P.Login()
    local data, scope = db(), A.Scope()
    if scope and not data.charProfiles[scope] then data.charProfiles[scope] = P.DefaultName end
    load(P.Active())
    P.ready = true
end

-- Switching touches frames that may be protected in combat, so it waits for the end of combat.
function P.Switch(name)
    local data, scope = db(), A.Scope()
    if not scope or not data.profiles[name] then return false, "missing" end
    if A.Combat() then P.pending = name; return false, "combat" end
    P.Store()
    data.charProfiles[scope] = name
    load(name)
    NS.App:Changed()
    return true
end

function P.CombatEnded()
    if not P.pending then return end
    local name = P.pending
    P.pending = nil
    P.Switch(name)
end

local function validName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return L.TrimUTF8(name, 40)
end

-- A new profile starts as a copy of the given one, or of the active one.
function P.Create(name, from)
    local data = db()
    name = validName(name)
    if not name then return false, "name" end
    if data.profiles[name] then return false, "exists" end
    P.Store()
    data.profiles[name] = L.Copy(data.profiles[from or P.Active()])
    return true, name
end

function P.Rename(old, new)
    local data = db()
    new = validName(new)
    if not new then return false, "name" end
    if old == P.DefaultName then return false, "default" end
    if not data.profiles[old] then return false, "missing" end
    if data.profiles[new] then return false, "exists" end
    data.profiles[new], data.profiles[old] = data.profiles[old], nil
    for scope, name in pairs(data.charProfiles) do
        if name == old then data.charProfiles[scope] = new end
    end
    return true, new
end

-- Characters on a deleted profile fall back to the default one.
function P.Delete(name)
    local data = db()
    if name == P.DefaultName then return false, "default" end
    if not data.profiles[name] then return false, "missing" end
    if name == P.Active() then
        local ok, reason = P.Switch(P.DefaultName)
        if not ok then return false, reason end
        data = db()
    end
    data.profiles[name] = nil
    for scope, value in pairs(data.charProfiles) do
        if value == name then data.charProfiles[scope] = P.DefaultName end
    end
    return true
end

-- Back to the shipped values for this profile. Account data stays untouched.
function P.Reset(name)
    local data = db()
    if not data.profiles[name] then return false, "missing" end
    if A.Combat() then return false, "combat" end
    data.profiles[name] = L.ProfileSnapshot(L.Sanitize({}))
    if name == P.Active() then load(name); NS.App:Changed() end
    return true
end

function P.Export(name)
    P.Store()
    name = name or P.Active()
    local profile = db().profiles[name]
    return profile and L.ExportText(name, profile) or nil
end

-- An import always becomes a new profile: an existing name gets a number.
function P.Import(text)
    local name, snapshot = L.ImportText(text)
    if not name then return false, snapshot end
    local data, target, number = db(), name, 2
    while data.profiles[target] do
        target = L.TrimUTF8(name, 36) .. " " .. number
        number = number + 1
    end
    data.profiles[target] = snapshot
    return true, target
end

function P.ReasonText(reason)
    local texts = {
        name = tr("Bitte einen Namen eingeben.", "Please enter a name."),
        exists = tr("Diesen Namen gibt es schon.", "This name already exists."),
        default = tr("Das Standardprofil bleibt bestehen.", "The default profile stays."),
        missing = tr("Dieses Profil gibt es nicht.", "This profile does not exist."),
        combat = tr("Wird nach dem Kampf ausgeführt.", "This happens after combat."),
        format = tr("Das ist kein ZENIAL-Utility-Profiltext.", "This is not a ZENIAL Utility profile text."),
        damaged = tr("Der Profiltext ist beschädigt und wurde nicht übernommen.", "The profile text is damaged and was not imported."),
    }
    return texts[reason] or tostring(reason)
end
