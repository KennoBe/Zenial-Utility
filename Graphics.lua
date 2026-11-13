local _, NS = ...
local G = {pending = {}, pendingFrom = {}, keepSeconds = 30}
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

-- Metadata where the client offers it: a locked or read-only setting is never written.
-- GetCVarInfo returns value, default, account, character, lockedFromUser, secure, readOnly.
function G.Writable(name)
    if not G.Exists(name) then return false end
    local api = cvarApi()
    if type(api.GetCVarInfo) ~= "function" then return true end
    local ok, value, _, _, _, locked, _, readOnly = pcall(api.GetCVarInfo, name)
    if not ok or value == nil then return true end
    return locked ~= true and readOnly ~= true
end

local function same(a, b)
    if a == nil or b == nil then return a == b end
    local x, y = tonumber(a), tonumber(b)
    if x and y then return math.abs(x - y) < .0001 end
    return tostring(a) == tostring(b)
end
G.Same = same

-- Writes one value and reads it back. The answer is what the client really holds now:
-- "ok", "clamped" (the client kept a different value) or "refused" (unchanged or error).
local function write(name, value)
    local api = cvarApi()
    if not api or type(api.SetCVar) ~= "function" then return "refused" end
    local before = G.Current(name)
    local ok, result = pcall(api.SetCVar, name, tostring(value))
    if not ok or result == false then return "refused" end
    local after = G.Current(name)
    if same(after, value) then return "ok", after end
    if same(after, before) then return "refused" end
    return "clamped", after
end

-- Game menu sliders reset their detail values when written, so they always go first.
-- Within each group the order is fixed, so the same input always gives the same result.
local function ordered(values)
    local names = {}
    for name in pairs(values) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        local menuA, menuB = a:sub(1, 8) == "graphics", b:sub(1, 8) == "graphics"
        if menuA ~= menuB then return menuA end
        return a < b
    end)
    return names
end
G.Ordered = ordered

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

-- A value outside the catalog's range is never written, whoever asks for it.
function G.InRange(name, value)
    local row, number = G.AllowedRow(name), tonumber(value)
    if not row or not number then return false end
    if row.minimum and number < row.minimum - .0001 then return false end
    if row.maximum and number > row.maximum + .0001 then return false end
    return true
end

function G.Stage(name, value)
    if not G.AllowedRow(name) or not G.InRange(name, value) then return false end
    G.pendingFrom[name] = nil
    if same(G.Current(name), value) then G.pending[name] = nil else G.pending[name] = tostring(value) end
    return true
end

function G.Preset(key)
    for _, preset in ipairs(NS.GraphicsPresets) do
        if preset.key == key then return preset end
    end
end

-- What a preset would do on this client, without staging anything.
function G.PresetPlan(key)
    local preset = G.Preset(key)
    if not preset then return nil end
    local plan = {changes = 0, same = 0, missing = {}, restart = {}}
    for _, name in ipairs(ordered(preset.values)) do
        local value = preset.values[name]
        local row = G.AllowedRow(name)
        if not row or not G.Writable(name) or not G.InRange(name, value) then
            plan.missing[#plan.missing + 1] = name
        elseif same(G.Current(name), value) then
            plan.same = plan.same + 1
        else
            plan.changes = plan.changes + 1
            if row.restart then plan.restart[#plan.restart + 1] = row.title end
        end
    end
    return plan
end

-- The preset's summary lines as plain strings. An entry with `needs` only counts when this client
-- offers every named setting and takes the preset's value for it, so no line describes a change
-- that cannot happen here.
function G.PresetSummary(key)
    local preset = G.Preset(key)
    local out = {}
    if not preset or not preset.summary then return out end
    for _, entry in ipairs(preset.summary) do
        if type(entry) == "string" then
            out[#out + 1] = entry
        else
            local usable = true
            for _, name in ipairs(entry.needs or {}) do
                if not G.AllowedRow(name) or not G.Writable(name) or not G.InRange(name, preset.values[name]) then usable = false end
            end
            if usable then out[#out + 1] = entry.text end
        end
    end
    return out
end

-- Choosing another preset replaces what an earlier, unapplied preset staged.
-- Values the player moved by hand stay staged.
function G.StagePreset(key)
    local preset = G.Preset(key)
    if not preset then return false end
    for name in pairs(G.pendingFrom) do G.pending[name] = nil end
    G.pendingFrom = {}
    for _, name in ipairs(ordered(preset.values)) do
        local value = preset.values[name]
        if G.Writable(name) and G.Stage(name, value) and G.pending[name] then G.pendingFrom[name] = key end
    end
    G.stagedPreset = key
    return true
end

function G.PendingCount()
    local count = 0
    for _ in pairs(G.pending) do count = count + 1 end
    return count
end

function G.Discard()
    G.pending, G.pendingFrom, G.stagedPreset = {}, {}, nil
end

function G.ChangedCount(db)
    local count = 0
    for name in pairs(db.cvarBackup) do
        if not same(G.Current(name), db.cvarBackup[name]) then count = count + 1 end
    end
    return count
end

-- Writes `values`, remembering the state before ZENIAL Utility ever changed each setting
-- and arming the timed confirmation with the values from right before this change.
-- Returns ok, changed, refused (names), clamped (names) and restart (row titles).
local function commit(db, values, keepBackup)
    if A.Combat() then return false, "combat" end
    -- An unanswered earlier change keeps its older starting value.
    local revert, refused, clamped, restart, changed = db.pendingRevert, {}, {}, {}, 0
    -- Game menu sliders also move other catalog settings; those are remembered too.
    local snapshot = {}
    for _, section in ipairs(NS.GraphicsCatalog) do
        for _, row in ipairs(section.rows) do snapshot[row.name] = G.Current(row.name) end
    end
    local written = {}
    for _, name in ipairs(ordered(values)) do
        local value = values[name]
        local before = G.Current(name)
        if before ~= nil and not same(before, value) then
            local result = G.Writable(name) and write(name, value) or "refused"
            if result == "refused" then
                refused[#refused + 1] = name
            else
                written[#written + 1] = name
                -- A slider written earlier in this run may already have moved it; the value
                -- from before this change is the one to go back to.
                local original = snapshot[name] ~= nil and snapshot[name] or before
                if revert[name] == nil then revert[name] = original end
                changed = changed + 1
                if keepBackup and db.cvarBackup[name] == nil then db.cvarBackup[name] = original end
                if result == "clamped" then clamped[#clamped + 1] = name end
                local row = G.AllowedRow(name)
                if row and row.restart then restart[#restart + 1] = row.title end
            end
        end
    end
    -- A later write can move an earlier one, so read every written value once more: the report
    -- has to describe what the client really holds, not what each single write returned.
    local isClamped = {}
    for _, name in ipairs(clamped) do isClamped[name] = true end
    for _, name in ipairs(written) do
        if not isClamped[name] and not same(G.Current(name), values[name]) then
            clamped[#clamped + 1] = name
            isClamped[name] = true
        end
    end
    if changed > 0 then
        for name, before in pairs(snapshot) do
            if not same(G.Current(name), before) then
                if revert[name] == nil then revert[name] = before end
                if keepBackup and db.cvarBackup[name] == nil then db.cvarBackup[name] = before end
            end
        end
    end
    table.sort(refused)
    table.sort(clamped)
    if changed > 0 then
        db.pendingRevert = revert
        G.deadline = G.keepSeconds
        if NS.App then NS.App:GraphicsConfirm() end
    end
    return changed > 0 or #refused == 0, changed, refused, clamped, restart
end

function G.Apply(db)
    local values = G.pending
    local ok, changed, refused, clamped, restart = commit(db, values, true)
    if ok then G.pending, G.pendingFrom, G.stagedPreset = {}, {}, nil end
    return ok, changed, refused, clamped, restart
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

-- Puts back the values from before the unanswered change, in the same safe order.
-- Anything the client does not take back stays listed for the next attempt.
function G.Revert(db)
    local values = db.pendingRevert
    local left = {}
    for _, name in ipairs(ordered(values)) do
        local value = values[name]
        if not same(G.Current(name), value) and write(name, value) == "refused" then left[name] = value end
    end
    db.pendingRevert = {}
    G.deadline = nil
    G.revertFailed = next(left) and left or nil
    if G.revertFailed then
        A.Print(NS.Text("Diese Grafikwerte konnten nicht zurückgesetzt werden: ", "These graphics values could not be restored: ") .. table.concat(ordered(left), ", "))
    end
    if NS.App then NS.App:GraphicsConfirmDone() end
    return G.revertFailed == nil
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
    G.pendingFrom[name] = nil
    return commit(db, {[name] = default}, true)
end
