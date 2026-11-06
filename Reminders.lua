local _, NS = ...
local R = {auras = {byID = {}, byName = {}}, groupCounts = {}, items = {}}
NS.Reminders = R
local A, L, tr, D = NS.Adapter, NS.Logic, NS.Text, NS.BuffData

local DEBOUNCE, GROUP_INTERVAL, GROUP_REFRESH, WEAPON_POLL, MAX_AURAS, CHARGE_WARN = .2, 3, 10, 5, 40, 1

local function db() return NS.App.db end

function R.Enabled() return db().modBuffs == true end

----------------------------------------------------------------------
-- Catalog: every entry that applies to this character, with its settings.
----------------------------------------------------------------------
local function allEntries()
    local out = {}
    for _, entry in ipairs(D.classes[A.PlayerClass()] or {}) do out[#out + 1] = entry end
    for _, entry in ipairs(D.general) do out[#out + 1] = entry end
    for _, entry in ipairs(D.consumables) do
        entry.bar = entry.bar or "consumables"
        out[#out + 1] = entry
    end
    return out
end
R.AllEntries = allEntries

function R.Title(entry)
    if entry.de then return tr(entry.de, entry.en) end
    local first = entry.ranks and entry.ranks[1] and entry.ranks[1][1]
    return first and A.SpellName(first) or entry.key
end

local function firstSpell(entry)
    if entry.ranks then return entry.ranks[1][1] end
    if entry.tracking then return entry.tracking[1] end
    if entry.learn then return entry.learn[1] end
end

function R.Icon(entry)
    local spell = firstSpell(entry)
    if entry.kind == "weapon" and not spell then return D.icons.weapon end
    return (spell and A.SpellIcon(spell)) or D.icons.tracking
end

function R.IsOn(entry)
    local row = db().reminders[entry.key]
    if row and row.on ~= nil then return row.on end
    return entry.def == true
end

function R.SetOn(key, value)
    local row = db().reminders[key] or {}
    row.on = value == true
    db().reminders[key] = row
end

function R.BarOf(entry)
    local row = db().reminders[entry.key]
    local wanted = row and row.bar or entry.bar or L.GeneralBar
    for _, bar in ipairs(db().warnBars) do
        if bar.id == wanted then return wanted end
    end
    return L.GeneralBar
end

function R.SetBar(key, bar)
    local row = db().reminders[key] or {}
    row.bar = bar
    db().reminders[key] = row
end

-- Deleted bars hand their entries to the general bar, which can't be deleted.
function R.DeleteBar(id)
    if id == L.GeneralBar then return false end
    local data = db()
    for index, bar in ipairs(data.warnBars) do
        if bar.id == id then
            table.remove(data.warnBars, index)
            for _, row in pairs(data.reminders) do
                if row.bar == id then row.bar = L.GeneralBar end
            end
            return true
        end
    end
    return false
end

function R.AddBar(name)
    local data = db()
    if #data.warnBars >= L.MaxBars then return nil end
    local serial = #data.warnBars + 1
    local id = "bar" .. serial
    while true do
        local taken = false
        for _, bar in ipairs(data.warnBars) do taken = taken or bar.id == id end
        if not taken then break end
        serial = serial + 1
        id = "bar" .. serial
    end
    local bar = {id = id, name = name ~= "" and name or id, size = 36, grow = "RIGHT", countdown = true, x = false, y = 120 + #data.warnBars * 44}
    data.warnBars[#data.warnBars + 1] = bar
    return bar
end

local function isKnownAny(list)
    if not list then return true end
    for _, spell in ipairs(list) do
        if A.Call(IsPlayerSpell, spell) == true or A.SpellKnown(spell) then return true end
    end
    return false
end

-- Rank chains are known through the highest learned rank, so a low rank ID alone never decides.
local function learnedRankIndex(chain)
    local best
    for index, spell in ipairs(chain) do
        if A.Call(IsPlayerSpell, spell) == true then best = index end
    end
    return best
end

local function isLearned(entry)
    if entry.tracking then return isKnownAny(entry.tracking) end
    if entry.learn then return isKnownAny(entry.learn) end
    -- Consumables and camp benefits are not spells the player learns.
    if entry.exact or entry.kind == "weapon" then return true end
    for _, chain in ipairs(entry.ranks or {}) do
        if learnedRankIndex(chain) then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Aura cache. Reading a secret aura throws in this client, so scans run only while auras are
-- not secret, usually out of combat. Until the next scan the last known state stands.
----------------------------------------------------------------------
local function aurasSecret()
    local api = _G.C_Secrets
    return api ~= nil and A.Call(api.ShouldAurasBeSecret) == true
end

local function readAura(aura)
    return aura.spellId, aura.name, aura.expirationTime, aura.duration, aura.applications, aura.icon
end

function R.ScanPlayer()
    local api = _G.C_UnitAuras
    if not api or type(api.GetBuffDataByIndex) ~= "function" or aurasSecret() then return false end
    local byID, byName = {}, {}
    for index = 1, MAX_AURAS do
        local got, aura = pcall(api.GetBuffDataByIndex, "player", index, "HELPFUL")
        if not got or not A.Public(aura) then return false end
        if not aura then break end
        local ok, spell, name, expires, duration, stacks = pcall(readAura, aura)
        if not ok then return false end
        if A.Public(spell) and A.Public(name) and A.Public(expires) and A.Public(duration) and A.Public(stacks) then
            local row = {spell = spell, name = name, expires = tonumber(expires) or 0, duration = tonumber(duration) or 0, stacks = tonumber(stacks) or 0}
            if spell then byID[spell] = row end
            if name then byName[name] = row end
        end
    end
    R.auras = {byID = byID, byName = byName}
    return true
end

local function findAura(entry)
    local auras = R.auras
    for chainIndex, chain in ipairs(entry.ranks or {}) do
        for rank, spell in ipairs(chain) do
            local row = auras.byID[spell]
            if row then return row, chainIndex, rank end
        end
    end
    for _, spell in ipairs(entry.also or {}) do
        local row = auras.byID[spell]
        if row then return row end
    end
    if entry.exact then return nil end
    -- Names catch ranks the table does not list, also in other client languages.
    for chainIndex, chain in ipairs(entry.ranks or {}) do
        local name = A.SpellName(chain[1])
        local row = name and auras.byName[name]
        if row then return row, chainIndex end
    end
    for _, spell in ipairs(entry.also or {}) do
        local name = A.SpellName(spell)
        local row = name and auras.byName[name]
        if row then return row end
    end
    return nil
end

----------------------------------------------------------------------
-- Other sources
----------------------------------------------------------------------
local function weaponState(slot)
    local main, mainLeft, _, _, off, offLeft = A.Call(GetWeaponEnchantInfo)
    if slot == "main" then
        if not A.Call(GetInventoryItemID, "player", 16) then return nil end
        return main == true, main == true and (tonumber(mainLeft) or 0) / 1000 or 0
    end
    -- Weapon enchants only exist on a real off-hand weapon, not on a shield or book.
    local paper = _G.C_PaperDollInfo
    if not paper or A.Call(paper.OffhandHasWeapon) ~= true then return nil end
    return off == true, off == true and (tonumber(offLeft) or 0) / 1000 or 0
end

local function activeTracking()
    local api = _G.C_Minimap
    local active = {}
    if not api then return active, false end
    local count = tonumber(A.Call(api.GetNumTrackingTypes)) or 0
    for index = 1, count do
        local info = A.Call(api.GetTrackingInfo, index)
        if type(info) == "table" and info.active and info.spellID then active[info.spellID] = true end
    end
    return active, count > 0
end

-- Dead, on a flight path or in a vehicle there is nothing to do about a missing buff.
function R.Suppressed()
    if A.Call(UnitIsDeadOrGhost, "player") == true then return true end
    if A.Call(UnitOnTaxi, "player") == true or A.Call(UnitInVehicle, "player") == true then return true end
    if not db().buffMounted and A.Call(IsMounted) == true then return true end
    if not db().buffResting and A.Call(IsResting) == true then return true end
    return false
end

-- How many group members near the player lack this buff. Aura checks stay out of combat.
function R.CountMissing(entry)
    local api = _G.C_UnitAuras
    if not api or type(api.GetAuraDataBySpellName) ~= "function" or aurasSecret() then return nil end
    local names = {}
    for _, chain in ipairs(entry.ranks or {}) do names[#names + 1] = A.SpellName(chain[1]) end
    for _, spell in ipairs(entry.also or {}) do names[#names + 1] = A.SpellName(spell) end
    local missing = 0
    for _, unit in ipairs(A.GroupUnits()) do
        local reachable = A.Call(UnitIsConnected, unit) == true and A.Call(UnitIsDeadOrGhost, unit) ~= true
        -- UnitInRange answers "was checked" second: an unchecked unit counts as reachable.
        if reachable then
            local inRange, checked = A.Call(UnitInRange, unit)
            if checked == true and inRange ~= true then reachable = false end
        end
        if reachable then
            local has = false
            for _, name in ipairs(names) do
                local got, aura = pcall(api.GetAuraDataBySpellName, unit, name, "HELPFUL")
                if got and aura then has = true; break end
            end
            if not has then missing = missing + 1 end
        end
    end
    return missing
end

function R.RefreshGroup()
    R.groupCounts = {}
    if not R.Enabled() or not db().buffGroup or A.Combat() then return end
    for _, entry in ipairs(allEntries()) do
        if entry.group and R.IsOn(entry) and isLearned(entry) then
            R.groupCounts[entry.key] = R.CountMissing(entry)
        end
    end
end

----------------------------------------------------------------------
-- Evaluation: one list of what to show right now. Pure reading, no drawing.
----------------------------------------------------------------------
local function evaluateAura(entry, now)
    local row, chainIndex, rank = findAura(entry)
    local warnRow = db().reminders[entry.key]
    local override = warnRow and warnRow.warn
    if not row then
        return {state = "missing"}
    end
    local left = row.expires > 0 and row.expires - now or nil
    if entry.charges and row.stacks > 0 and row.stacks <= CHARGE_WARN then
        return {state = "expiring", text = tostring(row.stacks), left = left}
    end
    if left then
        local warn = L.WarnSeconds(row.duration, override)
        if left <= warn then return {state = "expiring", left = left, expires = row.expires} end
        R.NoteWake(row.expires - warn)
    end
    if chainIndex and rank then
        local learned = learnedRankIndex(entry.ranks[chainIndex])
        if learned and learned > rank then return {state = "rank", nextSpell = entry.ranks[chainIndex][learned]} end
    end
    return nil
end

local function evaluateWeapon(entry, now)
    local has, left = weaponState(entry.slot)
    if has == nil then return nil end
    R.pollWeapons = true
    if not has then return {state = "missing"} end
    local warnRow = db().reminders[entry.key]
    local warn = warnRow and warnRow.warn or 180
    if left <= warn then return {state = "expiring", left = left, expires = now + left} end
    return nil
end

local function evaluateTracking(entry, active)
    for _, spell in ipairs(entry.tracking) do
        if active[spell] then return nil end
    end
    return {state = "missing"}
end

function R.NoteWake(at)
    if not R.nextWake or at < R.nextWake then R.nextWake = at end
end

local function legacyItems(out)
    if not db().warnOnBars then return end
    local states, H = NS.Helpers.states, NS.Helpers
    local function add(key, on, de, en, icon)
        if on then
            out[#out + 1] = {key = key, title = tr(de, en), icon = icon, state = "missing", bar = R.BarOf({key = key, bar = L.GeneralBar})}
        end
    end
    if db().modWarnings then
        add("legacy_durability", states.durability, "Haltbarkeit niedrig", "Low durability", D.icons.durability)
        add("legacy_bags", states.bags, "Taschen fast voll", "Bags nearly full", D.icons.bags)
        add("legacy_ammo", states.ammo, "Wenig Munition", "Low ammo", D.icons.ammo)
        if states.ammo and H.ammoCount then out[#out].text = tostring(H.ammoCount) end
    end
end

function R.Evaluate()
    local out = {}
    R.pollWeapons, R.nextWake = false, nil
    if not R.Enabled() then return out end
    legacyItems(out)
    if R.Suppressed() then return out end
    local now = tonumber(A.Call(GetTime)) or 0
    local active, trackingKnown = activeTracking()
    for _, entry in ipairs(allEntries()) do
        if R.IsOn(entry) and isLearned(entry) then
            local item
            if entry.kind == "weapon" then item = evaluateWeapon(entry, now)
            elseif entry.kind == "tracking" then
                if trackingKnown then item = evaluateTracking(entry, active) end
            else item = evaluateAura(entry, now) end
            local count = entry.group and db().buffGroup and R.groupCounts[entry.key] or 0
            if not item and count > 0 then item = {state = "group"} end
            if item then
                item.key, item.title, item.icon, item.bar = entry.key, R.Title(entry), R.Icon(entry), R.BarOf(entry)
                if count > 0 then item.count = count end
                out[#out + 1] = item
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Scheduling. No per-frame reading: events mark the state dirty, a timer wakes only for the next
-- moment something can change, and countdowns tick once a second while they are visible.
----------------------------------------------------------------------
local clock = CreateFrame("Frame")
local waited = 0

local function stopClock() clock:SetScript("OnUpdate", nil) end

function R.Update()
    R.dirty = false
    if not R.Enabled() then
        R.items = {}
        NS.WarnBars.Render(R.items)
        stopClock()
        return
    end
    if not A.Combat() then
        R.ScanPlayer()
        if R.groupDirty then R.groupDirty = false; R.RefreshGroup(); R.groupAt = A.Call(GetTime) end
    end
    R.items = R.Evaluate()
    NS.WarnBars.Render(R.items)
    R.Schedule()
end

local function onClock(_, dt)
    waited = waited + dt
    if R.dirty then
        if waited >= DEBOUNCE then waited = 0; R.Update() end
        return
    end
    local now = tonumber(A.Call(GetTime)) or 0
    if R.tickAt and now >= R.tickAt then waited = 0; R.Update() end
end

function R.Schedule()
    local now = tonumber(A.Call(GetTime)) or 0
    local at = R.nextWake
    -- A countdown on screen needs one redraw per second, nothing more.
    for _, item in ipairs(R.items) do
        if item.left then at = math.min(at or now + 1, now + 1); break end
    end
    if R.pollWeapons then at = math.min(at or now + WEAPON_POLL, now + WEAPON_POLL) end
    -- Range changes have no event, so a group gets a fresh count every so often.
    if #A.GroupUnits() > 0 and db().buffGroup then
        local due = (tonumber(R.groupAt) or now) + GROUP_REFRESH
        if now >= due then R.groupDirty = true end
        due = math.max(due, now + 1)
        at = math.min(at or due, due)
    end
    R.tickAt = at
    if at then clock:SetScript("OnUpdate", onClock) else stopClock() end
end

function R.Invalidate()
    if not R.Enabled() then return end
    R.dirty = true
    clock:SetScript("OnUpdate", onClock)
end

local function markGroup()
    R.groupDirty = true
    R.Invalidate()
end

local listener = A.Listener({
    UNIT_AURA = function() if not A.Combat() then R.Invalidate() end end,
}, {UNIT_AURA = "player"})

local general = A.Listener({
    PLAYER_ENTERING_WORLD = markGroup, SPELLS_CHANGED = R.Invalidate, PLAYER_DEAD = R.Invalidate, PLAYER_ALIVE = R.Invalidate, PLAYER_UNGHOST = R.Invalidate,
    PLAYER_REGEN_ENABLED = markGroup, PLAYER_MOUNT_DISPLAY_CHANGED = R.Invalidate, PLAYER_UPDATE_RESTING = R.Invalidate, MINIMAP_UPDATE_TRACKING = R.Invalidate,
    PLAYER_EQUIPMENT_CHANGED = R.Invalidate, UNIT_ENTERED_VEHICLE = R.Invalidate, UNIT_EXITED_VEHICLE = R.Invalidate, PLAYER_CONTROL_LOST = R.Invalidate, PLAYER_CONTROL_GAINED = R.Invalidate,
})

-- Only a group-buff user with a group listens to the group's auras, and only out of combat.
local group = A.Listener({GROUP_ROSTER_UPDATE = markGroup, UNIT_AURA = function() end})
group.frame:SetScript("OnEvent", function(_, event, unit)
    if A.Combat() then return end
    if event == "UNIT_AURA" then
        if type(unit) == "string" and (unit:find("^party") or unit:find("^raid")) then
            local now = tonumber(A.Call(GetTime)) or 0
            if not R.groupAt or now - R.groupAt >= GROUP_INTERVAL then markGroup() end
        end
    else
        markGroup()
    end
end)

function R.SettingsChanged()
    local on = R.Enabled()
    listener:Set(on)
    general:Set(on)
    local wantsGroup = false
    if on and db().buffGroup then
        for _, entry in ipairs(allEntries()) do
            if entry.group and R.IsOn(entry) then wantsGroup = true; break end
        end
    end
    group:Set(wantsGroup)
    R.groupDirty = true
    R.Update()
end
