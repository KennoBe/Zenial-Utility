local _, NS = ...
local I = {segments = {}, session = {}}
NS.InfoBar = I
local A, L, T, tr = NS.Adapter, NS.Logic, NS.Theme, NS.Text

local TICK, PAD, HEARTHSTONE = .5, 8, 6948
local HONOR_IDS, FAVOR_ID = {1792, 392}, 3402
local STUDY_SPELLS = {1225469, 1261368, 1261373, 1261374, 1261375, 1261376, 1261377, 1261378}
-- Long profession cooldowns the game tables confirm. A character only sees what it has learned.
local PROFESSION_COOLDOWNS = {18560, 11479, 11480, 17187}

local function db() return NS.App.db end

local RED, YELLOW, GREEN = {1, .35, .25}, {1, .82, .2}, {.35, .9, .4}

local function tipLine(left, right, color)
    local tip = _G.GameTooltip
    if right and tip.AddDoubleLine then tip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
    else
        local c = color or {1, 1, 1}
        tip:AddLine(left, c[1], c[2], c[3], true)
    end
end

local function statusColor(value, warn, bad)
    if not db().infoColors then return nil end
    if value >= bad then return RED end
    if value >= warn then return YELLOW end
    return GREEN
end

local function formatGold(copper)
    return A.Money(copper)
end

----------------------------------------------------------------------
-- Readers shared with several segments
----------------------------------------------------------------------
local function currency(ids)
    local api = _G.C_CurrencyInfo
    if not api then return nil end
    for _, id in ipairs(ids) do
        local info = A.Call(api.GetCurrencyInfo, id)
        if type(info) == "table" and info.name and info.name ~= "" then return info end
    end
    return nil
end

local function bagSpace()
    local api = _G.C_Container
    if not api then return nil end
    local free, total = 0, 0
    for bag = 0, 4 do
        local count, family = A.Call(api.GetContainerNumFreeSlots, bag)
        if family == 0 or family == nil then
            free = free + (tonumber(count) or 0)
            total = total + (tonumber(A.Call(api.GetContainerNumSlots, bag)) or 0)
        end
    end
    return free, total
end

local function cooldown(spell)
    local api = _G.C_Spell
    if not api then return nil end
    local info = A.Call(api.GetSpellCooldown, spell)
    if type(info) ~= "table" then return nil end
    local start, duration = tonumber(info.startTime), tonumber(info.duration)
    if not start or not duration then return nil end
    -- Global cooldown and a free spell both read as ready.
    if duration <= 2 then return 0 end
    return math.max(0, start + duration - (tonumber(A.Call(GetTime)) or 0))
end

local function knownCooldowns(list)
    local rows = {}
    for _, spell in ipairs(list) do
        if A.Call(IsPlayerSpell, spell) == true then
            rows[#rows + 1] = {spell = spell, name = A.SpellName(spell) or tostring(spell), left = cooldown(spell)}
        end
    end
    return rows
end

local function xpSample()
    local s = I.session
    local xp = tonumber(A.Call(UnitXP, "player")) or 0
    if not s.xpAt then s.xpAt, s.xpGained, s.xpLast = A.Call(GetTime) or 0, 0, xp end
    if xp > s.xpLast then s.xpGained = s.xpGained + (xp - s.xpLast) end
    if xp < s.xpLast then
        -- A level was gained: what was missing to the old cap plus the new value.
        s.xpGained = s.xpGained + xp + math.max(0, (s.xpMax or s.xpLast) - s.xpLast)
    end
    s.xpLast, s.xpMax = xp, tonumber(A.Call(UnitXPMax, "player")) or s.xpMax
end

local function xpPerHour()
    local s = I.session
    if not s.xpAt then return nil end
    return L.XPRate(s.xpGained, (A.Call(GetTime) or 0) - s.xpAt)
end

local function atMaxLevel()
    local level = tonumber(A.Call(UnitLevel, "player")) or 0
    local cap = tonumber(A.Call(GetMaxPlayerLevel))
    return cap ~= nil and level >= cap
end

local function grouped(number)
    number = math.floor(number + .5)
    if number >= 1000 then return string.format("%.1fk", number / 1000) end
    return tostring(number)
end

local function repairEstimate()
    local api = _G.C_TooltipInfo
    if not api or type(api.GetInventoryItem) ~= "function" then return nil end
    local total, read = 0, false
    for slot = 1, 18 do
        local data = A.Call(api.GetInventoryItem, "player", slot)
        if type(data) == "table" and type(data.repairCost) == "number" then
            total, read = total + data.repairCost, true
        end
    end
    return read and total or nil
end

----------------------------------------------------------------------
-- Segments. `get` returns text and an optional colour. It runs only for its events
-- or its interval, never per frame, and never at all while the segment is off.
----------------------------------------------------------------------
I.Modules = {
    {key = "gold", icon = "Interface\\Icons\\INV_Misc_Coin_02", de = "Gold", en = "Gold", events = {"PLAYER_MONEY"},
        get = function() return formatGold(A.Call(GetMoney) or 0) end},
    {key = "goldalts", icon = "Interface\\Icons\\INV_Misc_Coin_17", de = "Gold aller Charaktere", en = "Gold of all characters", events = {"PLAYER_MONEY"},
        get = function()
            local own, scope = NS.Characters.Own()
            return formatGold(L.GoldTotal(db().characters, db().goldScope, scope, own and own.faction))
        end,
        tip = function()
            local rows = {}
            for key, row in pairs(db().characters) do rows[#rows + 1] = {key = key, money = tonumber(row.money) or 0} end
            table.sort(rows, function(a, b) return a.money > b.money end)
            for index, row in ipairs(rows) do
                if index > 15 then break end
                tipLine(row.key, formatGold(row.money))
            end
        end},
    {key = "session", icon = "Interface\\Icons\\INV_Misc_Coin_06", de = "Gold dieser Sitzung", en = "Gold this session", events = {"PLAYER_MONEY"},
        get = function()
            local money = tonumber(A.Call(GetMoney)) or 0
            I.session.goldStart = I.session.goldStart or money
            local diff = money - I.session.goldStart
            if diff < 0 then return "-" .. formatGold(-diff), db().infoColors and RED or nil end
            return "+" .. formatGold(diff), db().infoColors and diff > 0 and GREEN or nil
        end},
    {key = "time", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", de = "Uhrzeit", en = "Time", interval = 5,
        get = function(compact)
            local hour, minute = A.Call(GetGameTime)
            local here = A.Call(date, "%H:%M") or "?"
            if compact or not hour then return here end
            return string.format("%s  %s %02d:%02d", here, tr("Server", "Server"), hour, minute or 0)
        end},
    {key = "zone", icon = "Interface\\Icons\\INV_Misc_Map_01", de = "Gebiet", en = "Zone", events = {"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA"},
        get = function(compact)
            local zone, sub = A.Call(GetZoneText) or "", A.Call(GetSubZoneText) or ""
            if compact or sub == "" or sub == zone then return zone ~= "" and zone or sub end
            return zone .. " · " .. sub
        end},
    {key = "coords", icon = "Interface\\Icons\\INV_Misc_Spyglass_02", de = "Koordinaten", en = "Coordinates", interval = .5,
        get = function()
            local api = _G.C_Map
            local map = api and A.Call(api.GetBestMapForUnit, "player")
            local x, y = NS.MapTools.PlayerPosition(map)
            if not x then return "–" end
            return string.format("%.1f, %.1f", x * 100, y * 100)
        end},
    {key = "hearth", icon = "Interface\\Icons\\INV_Misc_Rune_01", de = "Ruhestein", en = "Hearthstone", secure = true, interval = 5, events = {"HEARTHSTONE_BOUND"},
        get = function(compact)
            local api = _G.C_Container
            local bound = A.Call(GetBindLocation) or "?"
            local start, duration = nil, nil
            if api then start, duration = A.Call(api.GetItemCooldown, HEARTHSTONE) end
            local left = (tonumber(start) or 0) > 0 and (start + (tonumber(duration) or 0) - (A.Call(GetTime) or 0)) or 0
            if left > 0 then return (compact and "" or (bound .. " ")) .. L.ShortTime(left), db().infoColors and YELLOW or nil end
            return bound
        end},
    {key = "bags", icon = "Interface\\Icons\\INV_Misc_Bag_08", de = "Taschenplätze", en = "Bag slots", events = {"BAG_UPDATE_DELAYED"},
        get = function()
            local free, total = bagSpace()
            if not free then return "–" end
            return free .. "/" .. total, statusColor(total - free, math.max(0, total - 10), math.max(0, total - 3))
        end,
        click = function() A.Call(_G.ToggleAllBags) end},
    {key = "ammo", icon = "Interface\\Icons\\INV_Ammo_Arrow_02", de = "Munition", en = "Ammunition", events = {"BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED"},
        get = function()
            local projectile = NS.AutoBuy.ProjectileClass()
            if not projectile then return "–" end
            local count = NS.AutoBuy.AmmoInBags(projectile)
            return tostring(count), db().infoColors and count <= db().ammoThreshold and RED or nil
        end},
    {key = "durability", icon = "Interface\\Icons\\Trade_BlackSmithing", de = "Haltbarkeit", en = "Durability", events = {"UPDATE_INVENTORY_DURABILITY"},
        get = function()
            local lowest = NS.Helpers.DurabilityInfo()
            if not lowest then return "–" end
            return math.floor(lowest + .5) .. "%", statusColor(100 - lowest, 50, 100 - db().durabilityPercent)
        end,
        tip = function()
            local _, rows = NS.Helpers.DurabilityInfo()
            for index, row in ipairs(rows) do
                if index > 10 then break end
                local link = A.Call(GetInventoryItemLink, "player", row.slot)
                tipLine(type(link) == "string" and link or tostring(row.slot), math.floor(row.percent + .5) .. "%")
            end
        end,
        click = function() if not A.Combat() then A.Call(_G.ToggleCharacter, "PaperDollFrame") end end},
    {key = "repair", icon = "Interface\\Icons\\Trade_BlackSmithing", de = "Reparaturkosten", en = "Repair cost", events = {"UPDATE_INVENTORY_DURABILITY"},
        get = function()
            local cost = repairEstimate()
            if not cost then return "–" end
            return formatGold(cost)
        end},
    {key = "latency", icon = "Interface\\Icons\\Spell_Nature_Lightning", de = "Latenz", en = "Latency", interval = 10,
        get = function()
            local _, _, home, world = A.Call(GetNetStats)
            local value = math.max(tonumber(home) or 0, tonumber(world) or 0)
            return value .. " ms", statusColor(value, 150, 300)
        end},
    {key = "fps", icon = "Interface\\Icons\\Spell_Nature_Haste", de = "FPS", en = "FPS", interval = 1,
        get = function()
            local fps = math.floor((tonumber(A.Call(GetFramerate)) or 0) + .5)
            return fps .. " fps", db().infoColors and fps < 20 and RED or nil
        end},
    {key = "addons", icon = "Interface\\Icons\\Trade_Engineering", de = "Addons (Speicher, CPU)", en = "Addons (memory, CPU)",
        get = function() return tr("Addons", "Addons") end,
        -- Measuring every addon is expensive, so it only happens while the tooltip opens.
        tip = function()
            local api = _G.C_AddOns
            if not api or type(api.GetNumAddOns) ~= "function" then return end
            A.Call(_G.UpdateAddOnMemoryUsage)
            local profiling = A.Call(GetCVarBool, "scriptProfile") == true
            if profiling then A.Call(_G.UpdateAddOnCPUUsage) end
            local rows = {}
            for index = 1, tonumber(A.Call(api.GetNumAddOns)) or 0 do
                local memory = tonumber(A.Call(_G.GetAddOnMemoryUsage, index))
                if memory and memory > 0 then
                    rows[#rows + 1] = {name = (A.Call(api.GetAddOnInfo, index)) or "?", memory = memory,
                        cpu = profiling and tonumber(A.Call(_G.GetAddOnCPUUsage, index)) or nil}
                end
            end
            table.sort(rows, function(a, b) return a.memory > b.memory end)
            for index, row in ipairs(rows) do
                if index > 12 then break end
                local right = string.format("%.1f MB", row.memory / 1024)
                if row.cpu then right = right .. string.format("  %.0f ms", row.cpu) end
                tipLine(row.name, right)
            end
            if not profiling then tipLine(tr("CPU-Werte brauchen die Einstellung scriptProfile.", "CPU values need the scriptProfile setting."), nil, YELLOW) end
        end},
    {key = "volume", icon = "Interface\\Icons\\INV_Misc_Bell_01", de = "Lautstärke", en = "Volume", events = {"CVAR_UPDATE"},
        get = function()
            local api = _G.C_CVar
            local value = api and tonumber(A.Call(api.GetCVar, "Sound_MasterVolume")) or 0
            local enabled = api and A.Call(api.GetCVar, "Sound_EnableAllSound") ~= "0"
            return math.floor(value * 100 + .5) .. "%", not enabled and db().infoColors and RED or nil
        end,
        hint = {"Klick: Ton an oder aus. Mausrad: lauter oder leiser.", "Click: sound on or off. Mouse wheel: louder or quieter."},
        click = function()
            local api = _G.C_CVar
            if api then A.Call(api.SetCVar, "Sound_EnableAllSound", A.Call(api.GetCVar, "Sound_EnableAllSound") == "0" and "1" or "0") end
        end,
        wheel = function(delta)
            local api = _G.C_CVar
            if not api then return end
            local value = tonumber(A.Call(api.GetCVar, "Sound_MasterVolume")) or 0
            A.Call(api.SetCVar, "Sound_MasterVolume", tostring(math.max(0, math.min(1, value + delta * .05))))
        end},
    {key = "honor", icon = "Interface\\Icons\\Achievement_PVP_H_H", de = "Ehrenpunkte", en = "Honor points", events = {"CURRENCY_DISPLAY_UPDATE"},
        get = function()
            local info = currency(HONOR_IDS)
            if not info then return "–" end
            return tostring(info.quantity or 0), db().infoColors and (info.maxQuantity or 0) > 0 and (info.quantity or 0) >= info.maxQuantity and RED or nil
        end},
    {key = "favor", icon = "Interface\\Icons\\INV_Misc_Note_02", de = "Händlergunst", en = "Merchant's Favor", events = {"CURRENCY_DISPLAY_UPDATE"},
        get = function()
            local info = currency({FAVOR_ID})
            if not info then return "–" end
            return tostring(info.quantity or 0), db().infoColors and (info.maxQuantity or 0) > 0 and (info.quantity or 0) >= info.maxQuantity and RED or nil
        end},
    {key = "cooldowns", icon = "Interface\\Icons\\Trade_Alchemy", de = "Berufsabklingzeiten", en = "Profession cooldowns", interval = 30, events = {"SPELLS_CHANGED"},
        get = function()
            local rows, ready = knownCooldowns(PROFESSION_COOLDOWNS), 0
            if #rows == 0 then return "–" end
            for _, row in ipairs(rows) do
                if row.left == 0 then ready = ready + 1 end
            end
            return ready .. "/" .. #rows, db().infoColors and ready > 0 and GREEN or nil
        end,
        tip = function()
            local rows = knownCooldowns(PROFESSION_COOLDOWNS)
            for _, row in ipairs(rows) do
                tipLine(row.name, row.left and (row.left == 0 and tr("bereit", "ready") or L.ShortTime(row.left)) or "?")
            end
            if #rows == 0 then tipLine(tr("Keine bekannten Abklingzeiten erlernt.", "No known cooldowns learned.")) end
        end},
    {key = "study", icon = "Interface\\Icons\\INV_Misc_Book_09", de = "Dedicated Study", en = "Dedicated Study", interval = 30, events = {"SPELLS_CHANGED"},
        get = function()
            local rows = knownCooldowns(STUDY_SPELLS)
            local row = rows[1]
            if not row then return "–" end
            if row.left == nil then return "?" end
            if row.left == 0 then return tr("bereit", "ready"), db().infoColors and GREEN or nil end
            return L.ShortTime(row.left)
        end},
    {key = "xprate", icon = "Interface\\Icons\\INV_Misc_Book_11", de = "EP pro Stunde", en = "XP per hour", events = {"PLAYER_XP_UPDATE"}, interval = 30,
        get = function()
            if atMaxLevel() then return "–" end
            xpSample()
            local rate = xpPerHour()
            return rate and (grouped(rate) .. tr(" EP/h", " XP/h")) or tr("– EP/h", "– XP/h")
        end},
    {key = "xptime", icon = "Interface\\Icons\\INV_Misc_PocketWatch_02", de = "Zeit bis Level", en = "Time to level", events = {"PLAYER_XP_UPDATE"}, interval = 30,
        get = function()
            if atMaxLevel() then return "–" end
            xpSample()
            local rate = xpPerHour()
            if not rate or rate <= 0 then return "–" end
            local missing = (tonumber(A.Call(UnitXPMax, "player")) or 0) - (tonumber(A.Call(UnitXP, "player")) or 0)
            return L.ShortTime(missing / rate * 3600)
        end},
    {key = "gray", icon = "Interface\\Icons\\INV_Misc_Bone_01", de = "Billigster grauer Stapel", en = "Cheapest grey stack", events = {"BAG_UPDATE_DELAYED"},
        get = function()
            local best = NS.Inventory.CheapestGray()
            if not best then return "–" end
            return formatGold(best.value)
        end,
        tip = function()
            local best = NS.Inventory.CheapestGray()
            if not best then tipLine(tr("Kein passender grauer Gegenstand.", "No matching grey item.")); return end
            tipLine(best.link or "?", formatGold(best.value))
            if db().destroyGray then tipLine(tr("Shift-Klick zerstört diesen Stapel.", "Shift-click destroys this stack."), nil, YELLOW) end
        end,
        click = function()
            if A.Shift() and db().destroyGray then NS.Inventory.RequestDestroy() end
        end},
}

I.ByKey = {}
for _, module in ipairs(I.Modules) do I.ByKey[module.key] = module end
I.DefaultOn = {gold = true, time = true, zone = true, bags = true, durability = true, fps = true, latency = true}

function I.Title(module) return tr(module.de, module.en) end

function I.IsOn(key)
    local on = db().infoBar.on[key]
    if on ~= nil then return on end
    return I.DefaultOn[key] == true
end

-- Saved order first, then anything new from the list. Unknown keys from an old save drop out.
function I.Order()
    local out, seen = {}, {}
    for _, key in ipairs(db().infoBar.order) do
        if I.ByKey[key] and not seen[key] then seen[key] = true; out[#out + 1] = key end
    end
    for _, module in ipairs(I.Modules) do
        if not seen[module.key] then out[#out + 1] = module.key end
    end
    return out
end

function I.Move(key, delta)
    local order = I.Order()
    for index, value in ipairs(order) do
        if value == key then
            local other = index + delta
            if other < 1 or other > #order then return false end
            order[index], order[other] = order[other], order[index]
            db().infoBar.order = order
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------
local function fontFor(segment)
    local size = db().infoFont
    segment.text:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    segment.icon:SetSize(size + 3, size + 3)
end

local function showTooltip(segment)
    local tip, module = _G.GameTooltip, segment.module
    if not tip or not tip.SetOwner then return end
    tip:SetOwner(segment, "ANCHOR_BOTTOM")
    tip:SetText(I.Title(module))
    if module.tip then pcall(module.tip) end
    if module.hint then tip:AddLine(tr(module.hint[1], module.hint[2]), .8, .8, .8, true) end
    if module.key == "hearth" then tip:AddLine(tr("Klick benutzt den Ruhestein.", "Click uses the Hearthstone."), .8, .8, .8, true) end
    tip:Show()
end

local function createSegment(module)
    local template = module.secure and "SecureActionButtonTemplate" or nil
    local ok, segment = pcall(CreateFrame, "Button", nil, I.frame, template)
    if not ok then segment = CreateFrame("Button", nil, I.frame) end
    segment.module = module
    segment.icon = segment:CreateTexture(nil, "ARTWORK")
    segment.icon:SetPoint("LEFT", 0, 0)
    segment.icon:SetTexture(module.icon)
    segment.text = segment:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    segment.text:SetJustifyH("LEFT")
    segment:EnableMouse(true)
    if module.secure and segment.SetAttribute then
        -- Using an item needs the client's secure button: it works on a plain click, also while
        -- other addon code is tainted, and its attributes are only ever set out of combat.
        segment:RegisterForClicks("AnyUp", "AnyDown")
        segment:SetAttribute("type", "item")
        segment:SetAttribute("item", "item:" .. HEARTHSTONE)
    elseif module.click then
        segment:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        segment:SetScript("OnClick", function() pcall(module.click) end)
    end
    if module.wheel then
        segment:EnableMouseWheel(true)
        segment:SetScript("OnMouseWheel", function(_, delta) pcall(module.wheel, delta) end)
    end
    segment:SetScript("OnEnter", showTooltip)
    segment:SetScript("OnLeave", function()
        if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
    end)
    return segment
end

local function createFrame()
    local f = CreateFrame("Frame", "ZenialUtilityInfoBar", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetHeight(24)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not db().infoLocked and not A.Combat() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        db().infoBar.x, db().infoBar.y = self:GetLeft(), self:GetTop()
        NS.Profiles.Store()
    end)
    T.Panel(f, "surface")
    I.frame = f
end

local function drawSegment(segment)
    local module = segment.module
    local got, text, color = pcall(module.get, db().infoCompact)
    if not got or type(text) ~= "string" then text, color = "–", nil end
    if not A.Public(text) then text, color = "–", nil end
    segment.text:SetText(text)
    local c = color or {1, 1, 1}
    segment.text:SetTextColor(c[1], c[2], c[3])
    local width = (segment.text:GetStringWidth() or 0)
    if width ~= segment.lastWidth then
        segment.lastWidth = width
        I.layoutDirty = true
    end
end

-- Moving a secure child is not allowed in combat, so a width change waits until combat ends.
function I.Layout()
    local f = I.frame
    if not f then return end
    if A.Combat() then I.layoutDirty = true; return end
    I.layoutDirty = false
    local x = PAD
    local data = db()
    for _, key in ipairs(I.Order()) do
        local segment = I.segments[key]
        if segment and segment:IsShown() then
            local icon = data.infoIcons and not data.infoCompact
            segment.icon:SetShown(icon)
            local iconWidth = icon and (data.infoFont + 6) or 0
            segment.text:ClearAllPoints()
            segment.text:SetPoint("LEFT", iconWidth, 0)
            local width = iconWidth + (segment.text:GetStringWidth() or 0) + 2
            segment:SetSize(width, 20)
            segment:ClearAllPoints()
            segment:SetPoint("LEFT", f, "LEFT", x, 0)
            x = x + width + PAD
        end
    end
    f:SetWidth(math.max(40, x))
    f:SetScale(data.infoScale)
    if f.SetBackdropColor then
        local r, g, b = T.PaletteColor("panel")
        f:SetBackdropColor(r, g, b, data.infoAlpha)
        local er, eg, eb = T.PaletteColor("line")
        f:SetBackdropBorderColor(er, eg, eb, data.infoAlpha)
    end
    f:ClearAllPoints()
    if data.infoBar.x then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", data.infoBar.x, data.infoBar.y)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -2) end
    f:EnableMouse(not data.infoLocked)
end

----------------------------------------------------------------------
-- Updates: only events the visible segments use are registered.
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local clock = CreateFrame("Frame")
local elapsed = 0

local function update(key)
    local segment = I.segments[key]
    if segment and segment:IsShown() then drawSegment(segment) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if I.layoutDirty then I.Layout() end
        return
    end
    if event == "UNIT_INVENTORY_CHANGED" and ... ~= "player" then return end
    for _, key in ipairs(I.listeners[event] or {}) do update(key) end
    if I.layoutDirty then I.Layout() end
end)

local function onClock(_, dt)
    elapsed = elapsed + dt
    if elapsed < TICK then return end
    local passed = elapsed
    elapsed = 0
    for key, row in pairs(I.timers) do
        row.waited = row.waited + passed
        if row.waited >= row.interval then
            row.waited = 0
            update(key)
        end
    end
    if I.layoutDirty then I.Layout() end
end

function I.Rebuild()
    local data = db()
    eventFrame:UnregisterAllEvents()
    clock:SetScript("OnUpdate", nil)
    if data.modInfoBar ~= true then
        if I.frame and not A.Combat() then I.frame:Hide() end
        return
    end
    if A.Combat() then I.rebuildAfterCombat = true; return end
    if not I.frame then createFrame() end
    I.listeners, I.timers = {}, {}
    local anyTimer = false
    for _, module in ipairs(I.Modules) do
        local key = module.key
        local on = I.IsOn(key)
        local segment = I.segments[key]
        if on and not segment then
            segment = createSegment(module)
            I.segments[key] = segment
        end
        if segment then
            segment:SetShown(on)
            if on then fontFor(segment) end
        end
        if on then
            for _, event in ipairs(module.events or {}) do
                I.listeners[event] = I.listeners[event] or {}
                table.insert(I.listeners[event], key)
                pcall(eventFrame.RegisterEvent, eventFrame, event)
            end
            if module.interval then
                I.timers[key] = {interval = module.interval, waited = 0}
                anyTimer = true
            end
            drawSegment(segment)
        end
    end
    pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_REGEN_ENABLED")
    I.frame:Show()
    I.Layout()
    if anyTimer then clock:SetScript("OnUpdate", onClock) end
end

local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_ENABLED")
combat:SetScript("OnEvent", function()
    if I.rebuildAfterCombat then
        I.rebuildAfterCombat = false
        I.Rebuild()
    end
end)

function I.SettingsChanged() I.Rebuild() end
