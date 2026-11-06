local _, NS = ...
local G = {pending = {}, keepSeconds = 30}
NS.Graphics = G
local A = NS.Adapter

local function cvarApi() return _G.C_CVar end

-- The client's list decides: a name it does not know is simply not offered.
function G.Exists(name)
    local api = cvarApi()
    if not api then return false end
    return A.Call(api.GetCVar, name) ~= nil
end

function G.Current(name)
    local api = cvarApi()
    return api and A.Call(api.GetCVar, name) or nil
end

function G.Default(name)
    local api = cvarApi()
    return api and A.Call(api.GetCVarDefault, name) or nil
end

local function write(name, value)
    local api = cvarApi()
    if not api or type(api.SetCVar) ~= "function" then return false end
    local ok, result = pcall(api.SetCVar, name, tostring(value))
    return ok and result ~= false
end

local function same(a, b)
    if a == nil or b == nil then return a == b end
    local x, y = tonumber(a), tonumber(b)
    if x and y then return math.abs(x - y) < .0001 end
    return tostring(a) == tostring(b)
end
G.Same = same

function G.Rows()
    local out = {}
    for _, section in ipairs(NS.GraphicsCatalog) do
        local rows = {}
        for _, row in ipairs(section.rows) do
            if G.Exists(row.name) then rows[#rows + 1] = row end
        end
        if #rows > 0 then out[#out + 1] = {key = section.key, title = section.title, rows = rows} end
    end
    return out
end

function G.AllowedRow(name)
    for _, section in ipairs(NS.GraphicsCatalog) do
        for _, row in ipairs(section.rows) do
            if row.name == name then return row end
        end
    end
end

function G.Stage(name, value)
    if not G.AllowedRow(name) then return false end
    if same(G.Current(name), value) then G.pending[name] = nil else G.pending[name] = tostring(value) end
    return true
end

function G.StagePreset(key)
    for _, preset in ipairs(NS.GraphicsPresets) do
        if preset.key == key then
            for name, value in pairs(preset.values) do
                if G.Exists(name) then G.Stage(name, value) end
            end
            return true
        end
    end
    return false
end

function G.PendingCount()
    local count = 0
    for _ in pairs(G.pending) do count = count + 1 end
    return count
end

function G.Discard() G.pending = {} end

function G.ChangedCount(db)
    local count = 0
    for name in pairs(db.cvarBackup) do
        if not same(G.Current(name), db.cvarBackup[name]) then count = count + 1 end
    end
    return count
end

-- Writes `values`, remembering the state before ZENIAL Utility ever changed each setting
-- and arming the timed confirmation with the values from right before this change.
local function commit(db, values, keepBackup)
    if A.Combat() then return false, "combat" end
    -- An unanswered earlier change keeps its older starting value.
    local revert, refused, changed = db.pendingRevert, {}, 0
    for name, value in pairs(values) do
        local before = G.Current(name)
        if before ~= nil and not same(before, value) then
            if write(name, value) then
                if revert[name] == nil then revert[name] = before end
                changed = changed + 1
                if keepBackup and db.cvarBackup[name] == nil then db.cvarBackup[name] = before end
            else
                refused[#refused + 1] = name
            end
        end
    end
    table.sort(refused)
    if changed > 0 then
        db.pendingRevert = revert
        G.deadline = G.keepSeconds
        if NS.App then NS.App:GraphicsConfirm() end
    end
    return changed > 0 or #refused == 0, changed, refused
end

function G.Apply(db)
    local values = G.pending
    local ok, changed, refused = commit(db, values, true)
    if ok then G.pending = {} end
    return ok, changed, refused
end

function G.Keep(db)
    db.pendingRevert = {}
    G.deadline = nil
    -- A setting that is back at its original value needs no backup any more.
    for name, value in pairs(db.cvarBackup) do
        if same(G.Current(name), value) then db.cvarBackup[name] = nil end
    end
    if NS.App then NS.App:GraphicsConfirmDone() end
end

function G.Revert(db)
    local values = db.pendingRevert
    db.pendingRevert = {}
    G.deadline = nil
    for name, value in pairs(values) do write(name, value) end
    if NS.App then NS.App:GraphicsConfirmDone() end
end

function G.HasUnanswered(db) return next(db.pendingRevert) ~= nil end

-- Runs from the addon's timer. Combat postpones the write; the question stays open.
function G.Tick(db, elapsed)
    if not G.deadline then return end
    G.deadline = G.deadline - elapsed
    if G.deadline <= 0 and not A.Combat() then G.Revert(db) end
end

-- A /reload or logout before the answer counts as no answer; the next tick out of combat reverts.
function G.ResumeUnanswered(db)
    if G.HasUnanswered(db) then G.deadline = 0; return true end
    return false
end

-- Values from before ZENIAL Utility changed anything.
function G.RestoreBackup(db)
    return commit(db, db.cvarBackup, false)
end

-- The game's own defaults for every setting the catalog knows.
function G.RestoreDefaults(db)
    local values = {}
    for _, section in ipairs(G.Rows()) do
        for _, row in ipairs(section.rows) do
            local default = G.Default(row.name)
            if default ~= nil then values[row.name] = default end
        end
    end
    return commit(db, values, true)
end

function G.ResetOne(db, name)
    local default = G.Default(name)
    if default == nil or not G.AllowedRow(name) then return false end
    G.pending[name] = nil
    return commit(db, {[name] = default}, true)
end
