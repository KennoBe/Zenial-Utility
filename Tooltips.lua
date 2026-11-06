local _, NS = ...
local P = {inspect = {}}
NS.Tooltips = P
local A, L, tr = NS.Adapter, NS.Logic, NS.Text

local INSPECT_KEEP = 300

local function db() return NS.App.db end
local function on(key) return db().modTooltip and db()[key] end

-- Skill each gathering node needs. English and German client names. Forever's added nodes in its
-- starting zones are not in the data sources used here, so they simply show nothing extra.
P.Nodes = {
    ["Peacebloom"] = 1, ["Friedensblume"] = 1, ["Silverleaf"] = 1, ["Silberblatt"] = 1, ["Earthroot"] = 15, ["Erdwurzel"] = 15,
    ["Mageroyal"] = 50, ["Maguskönigskraut"] = 50, ["Briarthorn"] = 70, ["Wilddornrose"] = 70, ["Stranglekelp"] = 85, ["Würgetang"] = 85,
    ["Bruiseweed"] = 100, ["Beulengras"] = 100, ["Wild Steelbloom"] = 115, ["Wildstahlblume"] = 115, ["Grave Moss"] = 120, ["Grabmoos"] = 120,
    ["Kingsblood"] = 125, ["Königsblut"] = 125, ["Liferoot"] = 150, ["Lebenswurz"] = 150, ["Fadeleaf"] = 160, ["Blassblatt"] = 160,
    ["Goldthorn"] = 170, ["Golddorn"] = 170, ["Khadgar's Whisker"] = 185, ["Khadgars Schnurrbart"] = 185, ["Wintersbite"] = 195, ["Winterbiss"] = 195,
    ["Firebloom"] = 205, ["Feuerblüte"] = 205, ["Purple Lotus"] = 210, ["Lila Lotus"] = 210, ["Arthas' Tears"] = 220, ["Arthas' Tränen"] = 220,
    ["Sungrass"] = 230, ["Sonnengras"] = 230, ["Blindweed"] = 235, ["Blindkraut"] = 235, ["Ghost Mushroom"] = 245, ["Geisterpilz"] = 245,
    ["Gromsblood"] = 250, ["Gromsblut"] = 250, ["Golden Sansam"] = 260, ["Goldener Sansam"] = 260, ["Dreamfoil"] = 270, ["Traumblatt"] = 270,
    ["Mountain Silversage"] = 280, ["Bergsilbersalbei"] = 280, ["Plaguebloom"] = 285, ["Pestblüte"] = 285, ["Icecap"] = 290, ["Eiskappe"] = 290,
    ["Black Lotus"] = 300, ["Schwarzer Lotus"] = 300,
    ["Copper Vein"] = 1, ["Kupfervorkommen"] = 1, ["Tin Vein"] = 65, ["Zinnvorkommen"] = 65, ["Silver Vein"] = 75, ["Silbervorkommen"] = 75,
    ["Iron Deposit"] = 125, ["Eisenvorkommen"] = 125, ["Gold Vein"] = 155, ["Goldvorkommen"] = 155, ["Mithril Deposit"] = 175, ["Mithrilablagerung"] = 175,
    ["Truesilver Deposit"] = 230, ["Echtsilberablagerung"] = 230, ["Small Thorium Vein"] = 245, ["Kleines Thoriumvorkommen"] = 245,
    ["Rich Thorium Vein"] = 275, ["Reiches Thoriumvorkommen"] = 275,
}

function P.NodeSkill(name) return type(name) == "string" and P.Nodes[name] or nil end

----------------------------------------------------------------------
-- Character tooltips. Blizzard already writes name, guild and level. So existing lines are changed
-- in place instead of adding second copies, and only what is really missing gets a new line.
----------------------------------------------------------------------
local function classColor(class)
    local colors = _G.RAID_CLASS_COLORS
    local c = colors and colors[class]
    return c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
end

-- Builds what one unit should show. Returns nil for anything unreadable: nothing is guessed.
function P.UnitLines(unit, layout, flags)
    local name = A.Call(UnitName, unit)
    if type(name) ~= "string" then return nil end
    local info = {guild = nil, rank = nil, level = nil}
    local level = A.Call(UnitLevel, unit)
    if flags.ttLevel and type(level) == "number" then info.level = level > 0 and tostring(level) or "??" end
    if flags.ttRace then info.race = (A.Call(UnitRace, unit)) end
    local className, classFile = A.Call(UnitClass, unit)
    if flags.ttClass and type(className) == "string" then info.class = classColor(classFile) .. className .. "|r" end
    local guild, rank = A.Call(GetGuildInfo, unit)
    if flags.ttGuild and type(guild) == "string" then info.guild = guild end
    if flags.ttGuildRank and type(rank) == "string" then info.rank = rank end
    local _, faction = A.Call(UnitFactionGroup, unit)
    if flags.ttFaction and type(faction) == "string" then info.faction = faction end
    local target = A.Call(UnitName, unit .. "target")
    if flags.ttTarget and type(target) == "string" then info.target = target end
    return info
end

local function levelLine(info)
    local parts = {}
    if info.level then parts[#parts + 1] = tr("Stufe ", "Level ") .. info.level end
    if info.race then parts[#parts + 1] = info.race end
    if info.class then parts[#parts + 1] = info.class end
    return table.concat(parts, " ")
end

local function lineString(tooltip, index)
    local name = tooltip.GetName and tooltip:GetName()
    return name and _G[name .. "TextLeft" .. index] or nil
end

-- Finds Blizzard's level line by the level text it always starts with.
local function findLine(tooltip, test)
    for index = 2, tonumber(A.Call(tooltip.NumLines, tooltip)) or 0 do
        local region = lineString(tooltip, index)
        local text = region and A.Call(region.GetText, region)
        if type(text) == "string" and test(text) then return region, text end
    end
end

function P.AddUnit(tooltip, unit)
    local info = P.UnitLines(unit, db().ttLayout, db())
    if not info then return end
    local isPlayer = A.Call(UnitIsPlayer, unit) == true
    local layout = db().ttLayout
    if isPlayer and layout ~= "blizz" then
        -- Compact: one line for level, race and class. One per line: separate lines for race and class.
        local levelWord = _G.LEVEL or tr("Stufe", "Level")
        local region = findLine(tooltip, function(text) return text:find(levelWord, 1, true) ~= nil end)
        if region then
            if layout == "compact" then
                region:SetText(levelLine(info))
            else
                region:SetText(info.level and (tr("Stufe ", "Level ") .. info.level) or "")
                if info.race then tooltip:AddLine(info.race, 1, 1, 1) end
                if info.class then tooltip:AddLine(info.class, 1, 1, 1) end
            end
        end
    end
    if isPlayer and info.guild and info.rank then
        local region = findLine(tooltip, function(text) return text:find(info.guild, 1, true) ~= nil end)
        if region then region:SetText("<" .. info.guild .. "> " .. info.rank) end
    end
    if info.target then tooltip:AddLine(tr("Ziel: ", "Target: ") .. info.target, .82, .79, .71) end
    if isPlayer and on("ttItemLevel") then
        local level = P.ItemLevel(unit)
        if level then tooltip:AddLine(string.format(tr("Gegenstandsstufe: %d", "Item level: %d"), level), .82, .79, .71) end
    end
end

----------------------------------------------------------------------
-- Item level of others needs an inspect, so it is asked for once per player and kept for a while.
----------------------------------------------------------------------
function P.ItemLevel(unit)
    if A.Call(UnitIsUnit, unit, "player") == true then
        local _, equipped = A.Call(GetAverageItemLevel)
        return tonumber(equipped) and math.floor(equipped + .5) or nil
    end
    local guid = A.Call(UnitGUID, unit)
    if type(guid) ~= "string" then return nil end
    local now = tonumber(A.Call(GetTime)) or 0
    local cached = P.inspect[guid]
    if cached and now - cached.at < INSPECT_KEEP then return cached.level end
    if A.Combat() or (_G.InspectFrame and _G.InspectFrame.IsShown and _G.InspectFrame:IsShown()) then return nil end
    if P.inspectGuid or A.Call(CanInspect, unit) ~= true then return nil end
    P.inspectGuid, P.inspectUnit = guid, unit
    P.inspectListener:Set(true)
    A.Call(NotifyInspect, unit)
    return nil
end

P.inspectListener = A.Listener({INSPECT_READY = function(guid)
    P.inspectListener:Set(false)
    local unit, wanted = P.inspectUnit, P.inspectGuid
    P.inspectGuid, P.inspectUnit = nil, nil
    if not unit or guid ~= wanted or A.Call(UnitGUID, unit) ~= wanted then return end
    local paper = _G.C_PaperDollInfo
    local level = paper and tonumber(A.Call(paper.GetInspectItemLevel, unit))
    if level and level > 0 then
        P.inspect[wanted] = {level = math.floor(level + .5), at = tonumber(A.Call(GetTime)) or 0}
    end
    A.Call(ClearInspectPlayer)
end})

----------------------------------------------------------------------
-- Gathering
----------------------------------------------------------------------
local function addRequired(tooltip, skill, de, en)
    tooltip:AddLine(string.format(tr(de, en), skill), .82, .79, .71)
end

function P.AddSkinning(tooltip, unit)
    local word = _G.UNIT_SKINNABLE_LEATHER
    if type(word) ~= "string" or not on("ttGathering") then return end
    if not findLine(tooltip, function(text) return text == word end) then return end
    local skill = L.SkinningSkill(A.Call(UnitLevel, unit))
    if skill then addRequired(tooltip, skill, "Kürschnerei: %d", "Skinning: %d") end
end

function P.AddObject(tooltip)
    if not on("ttGathering") then return end
    local region = lineString(tooltip, 1)
    local name = region and A.Call(region.GetText, region)
    local skill = P.NodeSkill(name)
    if skill then addRequired(tooltip, skill, "Benötigte Fertigkeit: %d", "Skill needed: %d") end
end

----------------------------------------------------------------------
-- Position and health bar
----------------------------------------------------------------------
function P.Anchor(tooltip, parent)
    local corner = db().modTooltip and db().ttAnchor
    if not corner or corner == "default" or not tooltip or not tooltip.SetOwner then return end
    tooltip:SetOwner(parent or UIParent, "ANCHOR_NONE")
    tooltip:ClearAllPoints()
    local x = corner:find("LEFT") and 20 or -20
    local y = corner:find("TOP") and -20 or 60
    tooltip:SetPoint(corner, UIParent, corner, x, y)
end

function P.StyleHealthBar()
    local bar = _G.GameTooltipStatusBar
    if not bar or not bar.SetStatusBarTexture then return end
    local style = db().modTooltip and db().ttHealthBar or "default"
    if style == "default" and not P.barStyled then return end
    if style == "default" then
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        return
    end
    P.barStyled = true
    bar:SetStatusBarTexture(style == "flat" and "Interface\\Buttons\\WHITE8X8" or "Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
end

----------------------------------------------------------------------
function P.Attach()
    if P.attached then return end
    local processor = _G.TooltipDataProcessor
    local kinds = _G.Enum and _G.Enum.TooltipDataType
    if not processor or not kinds or type(processor.AddTooltipPostCall) ~= "function" then return end
    P.attached = true
    if kinds.Unit then
        processor.AddTooltipPostCall(kinds.Unit, function(tooltip)
            if tooltip ~= _G.GameTooltip then return end
            local _, unit = A.Call(tooltip.GetUnit, tooltip)
            if type(unit) ~= "string" then return end
            if on("ttUnit") then pcall(P.AddUnit, tooltip, unit) end
            pcall(P.AddSkinning, tooltip, unit)
        end)
    end
    if kinds.Object then
        processor.AddTooltipPostCall(kinds.Object, function(tooltip)
            if tooltip == _G.GameTooltip then pcall(P.AddObject, tooltip) end
        end)
    end
end

function P.SettingsChanged()
    local data = db()
    if data.modTooltip then
        if data.ttUnit or data.ttGathering then P.Attach() end
        if data.ttAnchor ~= "default" and not P.anchorHook and type(_G.GameTooltip_SetDefaultAnchor) == "function" and type(hooksecurefunc) == "function" then
            P.anchorHook = true
            hooksecurefunc("GameTooltip_SetDefaultAnchor", P.Anchor)
        end
    end
    P.StyleHealthBar()
end
