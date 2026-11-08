local _, NS = ...
local M = {textures = {}, used = 0}
NS.MapTools = M
local A, L, tr = NS.Adapter, NS.Logic, NS.Text

local function db() return NS.App and NS.App.db end
local function revealMode()
    local data = db()
    if not data or not data.modMap then return "off" end
    return data.mapReveal
end

-- Reads the data keys "w:h:x:y" that the client has not marked as explored yet.
function M.MissingPieces(data, explored)
    local seen, out = {}, {}
    for _, info in ipairs(explored or {}) do
        seen[info.textureWidth .. ":" .. info.textureHeight .. ":" .. info.offsetX .. ":" .. info.offsetY] = true
    end
    for key, files in pairs(data or {}) do
        if not seen[key] then
            local w, h, x, y = key:match("^(%d+):(%d+):(%d+):(%d+)$")
            if w then
                local ids = {}
                for id in files:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
                out[#out + 1] = {w = tonumber(w), h = tonumber(h), x = tonumber(x), y = tonumber(y), files = ids}
            end
        end
    end
    return out
end

local function hideOwn()
    for index = 1, M.used do M.textures[index]:Hide() end
    M.used = 0
end

local function ownTexture(pin, canvas)
    M.used = M.used + 1
    local texture = M.textures[M.used]
    if not texture then
        texture = pin:CreateTexture(nil, "ARTWORK")
        M.textures[M.used] = texture
        -- Same mask handling as the game's own explored pieces.
        if canvas and type(canvas.AddMaskableTexture) == "function" then pcall(canvas.AddMaskableTexture, canvas, texture) end
    end
    return texture
end

-- Lays out one piece exactly like the game's MapExplorationPinMixin does, one tile at a time.
local function drawPiece(pin, canvas, piece, tileW, tileH, alpha, shade)
    local wide, tall = math.ceil(piece.w / tileW), math.ceil(piece.h / tileH)
    for row = 1, tall do
        local pixelH, fileH = tileH, tileH
        if row == tall then
            pixelH = piece.h % tileH
            if pixelH == 0 then pixelH = tileH end
            fileH = 16
            while fileH < pixelH do fileH = fileH * 2 end
        end
        for column = 1, wide do
            local pixelW, fileW = tileW, tileW
            if column == wide then
                pixelW = piece.w % tileW
                if pixelW == 0 then pixelW = tileW end
                fileW = 16
                while fileW < pixelW do fileW = fileW * 2 end
            end
            local file = piece.files[(row - 1) * wide + column]
            if file then
                local texture = ownTexture(pin, canvas)
                texture:ClearAllPoints()
                texture:SetSize(pixelW, pixelH)
                texture:SetTexCoord(0, pixelW / fileW, 0, pixelH / fileH)
                texture:SetPoint("TOPLEFT", piece.x + tileW * (column - 1), -(piece.y + tileH * (row - 1)))
                texture:SetTexture(file, nil, nil, "TRILINEAR")
                texture:SetVertexColor(shade, shade, shade, alpha)
                texture:Show()
            end
        end
    end
end

-- Runs after the game has redrawn its explored pieces. Community's member pins sit on
-- their own higher pin level and are not affected. Never drawn in combat: the next
-- PLAYER_REGEN_ENABLED catches up.
function M.Draw(pin)
    pin = pin or M.pin
    if not pin then return end
    hideOwn()
    local mode = revealMode()
    if mode == "off" then return end
    if A.Combat() then M.dirty = true; return end
    M.dirty = false
    local canvas = pin:GetMap()
    local mapID = canvas and canvas:GetMapID()
    local api = _G.C_Map
    if not mapID or not api then return end
    local art = A.Call(api.GetMapArtID, mapID)
    local data = art and NS.MapReveal[art]
    local layers = A.Call(api.GetMapArtLayers, mapID)
    if not data or type(layers) ~= "table" then return end
    local container = canvas.GetCanvasContainer and canvas:GetCanvasContainer()
    local index = container and container.GetCurrentLayerIndex and container:GetCurrentLayerIndex() or 1
    local layer = layers[index] or layers[1]
    if not layer then return end
    local exploration = _G.C_MapExplorationInfo
    local explored = exploration and A.Call(exploration.GetExploredMapTextures, mapID)
    local alpha, shade = 1, 1
    if mode == "soft" then alpha, shade = db().revealAlpha, .8 end
    for _, piece in ipairs(M.MissingPieces(data, explored)) do
        drawPiece(pin, canvas, piece, layer.tileWidth, layer.tileHeight, alpha, shade)
    end
end

function M.ToggleReveal()
    local data = db()
    if not data then return end
    if data.mapReveal == "off" then
        data.mapReveal = M.lastReveal or "soft"
    else
        M.lastReveal = data.mapReveal
        data.mapReveal = "off"
    end
    NS.App:Changed()
end

function M.TryAttach()
    if not M.menuAttached and _G.Menu and type(_G.Menu.ModifyMenu) == "function" then
        -- Sits next to Community's own entries in the same tracking menu.
        local ok = pcall(_G.Menu.ModifyMenu, "MENU_WORLD_MAP_TRACKING", function(_, root)
            if not db() or not db().modMap then return end
            root:CreateCheckbox(tr("Karte aufdecken", "Reveal map"), function() return db().mapReveal ~= "off" end, M.ToggleReveal)
        end)
        M.menuAttached = ok
    end
    local map = _G.WorldMapFrame
    if map and M.AttachLevels then M.AttachLevels(map) end
    if M.pin or not map or type(map.EnumeratePinsByTemplate) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    local enumerate = A.Call(map.EnumeratePinsByTemplate, map, "MapExplorationPinTemplate")
    if type(enumerate) ~= "function" then return end
    for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        hooksecurefunc(pin, "RefreshOverlays", function(self) M.Draw(self) end)
        M.pin = pin
        M.Draw(pin)
        break
    end
end

function M.PlayerPosition(mapID)
    local api = _G.C_Map
    if not api or not mapID then return nil end
    local point = A.Call(api.GetPlayerMapPosition, mapID, "player")
    if type(point) ~= "table" or type(point.GetXY) ~= "function" then return nil end
    local x, y = A.Call(point.GetXY, point)
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return x, y
end

----------------------------------------------------------------------
-- Zone level ranges on continent maps (data: LevelData.lua). A map data provider places the
-- labels on the map's canvas, so they follow zoom and panning without a frame script. Only the
-- mouseover tooltip runs one, and only while a continent map with this option is open.
----------------------------------------------------------------------
local LEVEL_COLORS = {fit = {.25, 1, .25}, low = {.62, .62, .62}, high = {1, .3, .25}}
local CONTINENT_MAPS = {[0] = 1415, [1] = 1414} -- world-position continent -> its uiMap
local levels = {labels = {}, used = 0}
M.levels = levels

-- Another addon that already prints zone levels on the map: ours stays out of the way.
function M.LevelsElsewhere()
    local api = _G.C_AddOns
    local loaded = api and api.IsAddOnLoaded or _G.IsAddOnLoaded
    local function on(name) return A.Call(loaded, name) and true or false end
    if on("OpenMap") then
        -- OpenMap adds the range to the map's hover label unless its zone levels are off
        -- (default on; a missing table is still its defaults).
        local saved = type(_G.OpenMapDB) == "table" and _G.OpenMapDB.worldmap
        if type(saved) ~= "table" or (saved.enabled ~= false and saved.zoneLevels ~= false) then return "OpenMap" end
    end
    if on("Leatrix_Maps") and type(_G.LeaMapsDB) == "table" and _G.LeaMapsDB.ShowZoneLevels == "On" then return "Leatrix Maps" end
    return nil
end

function M.LevelMode()
    local data = db()
    if not data or not data.modMap or not data.mapLevels or M.LevelsElsewhere() then return nil end
    return data.mapLevelMode
end

function M.ZoneLevels(mapID)
    local range = NS.MapLevels and NS.MapLevels[mapID]
    if type(range) == "table" and type(range[1]) == "number" and type(range[2]) == "number" then return range[1], range[2] end
    return nil
end

local function playerLevel()
    return M.playerLevel or tonumber(A.Call(_G.UnitLevel, "player")) or 1
end

local function colorCode(low, high)
    local c = LEVEL_COLORS[L.LevelBand(playerLevel(), low, high)]
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function mapInfo(mapID)
    local api = _G.C_Map
    local info = api and mapID and A.Call(api.GetMapInfo, mapID)
    return type(info) == "table" and info or nil
end

local function continentOf(map)
    local mapID = map and A.Call(map.GetMapID, map)
    local info = mapInfo(mapID)
    local kinds = _G.Enum and _G.Enum.UIMapType
    if info and info.mapType == (kinds and kinds.Continent or 2) then return mapID end
    return nil
end

-- The level zones on a continent with their centre on its map, read once per continent.
local spots = {}
local function zoneSpots(continent)
    if spots[continent] then return spots[continent] end
    local api, list = _G.C_Map, {}
    local kinds = _G.Enum and _G.Enum.UIMapType
    local children = api and A.Call(api.GetMapChildrenInfo, continent, kinds and kinds.Zone or 3, false)
    for _, child in ipairs(type(children) == "table" and children or {}) do
        local low, high = M.ZoneLevels(child.mapID)
        if low then
            local left, right, top, bottom = A.Call(api.GetMapRectOnMap, child.mapID, continent)
            if type(left) == "number" and type(right) == "number" and type(top) == "number" and type(bottom) == "number" then
                list[#list + 1] = {id = child.mapID, name = child.name, x = (left + right) / 2, y = (top + bottom) / 2, low = low, high = high}
            end
        end
    end
    spots[continent] = list
    return list
end

-- World yards to a continent map's 0..1, the way OpenMap reads them: the corners from the game,
-- and the axis order settled once on Stormwind's flight master (Elwynn Forest or Stormwind).
local corners, swap = {}, nil
local function project(continent, wx, wy)
    local api, mapID = _G.C_Map, CONTINENT_MAPS[continent]
    if not mapID or not api or type(_G.CreateVector2D) ~= "function" then return nil end
    if corners[continent] == nil then
        corners[continent] = false
        local _, p0 = A.Call(api.GetWorldPosFromMapPos, mapID, _G.CreateVector2D(0, 0))
        local _, p1 = A.Call(api.GetWorldPosFromMapPos, mapID, _G.CreateVector2D(1, 1))
        local x0, y0, x1, y1
        if type(p0) == "table" then x0, y0 = A.Call(p0.GetXY, p0) end
        if type(p1) == "table" then x1, y1 = A.Call(p1.GetXY, p1) end
        if type(x0) == "number" and type(y0) == "number" and type(x1) == "number" and type(y1) == "number" and x1 ~= x0 and y1 ~= y0 then corners[continent] = {x0, y0, x1, y1} end
    end
    local c = corners[continent]
    if not c then return nil end
    local function at(x, y, order)
        if order then return (x - c[1]) / (c[3] - c[1]), (y - c[2]) / (c[4] - c[2]) end
        return (y - c[2]) / (c[4] - c[2]), (x - c[1]) / (c[3] - c[1])
    end
    if swap == nil and continent == 0 then
        for _, order in ipairs({false, true}) do
            local u, v = at(-8840.6, 489.7, order)
            local info = A.Call(api.GetMapInfoAtPosition, mapID, u, v)
            if type(info) == "table" and (info.mapID == 1429 or info.mapID == 1453) then swap = order; break end
        end
        if swap == nil then swap = false end
    end
    if swap == nil then project(0, -8840.6, 489.7) end
    return at(wx, wy, swap)
end

-- The level zone a uiMap belongs to: itself, or the nearest parent with a level range (a city).
local function levelZone(mapID)
    for _ = 1, 4 do
        if not mapID or mapID == 0 then return nil end
        if M.ZoneLevels(mapID) then return mapID end
        local info = mapInfo(mapID)
        mapID = info and info.parentMapID
    end
    return nil
end

local dungeonsByZone
local function dungeonName(row)
    local name = row[1] > 0 and A.Call(_G.GetRealZoneText, row[1])
    if type(name) ~= "string" or name == "" then name = row[2] end
    return name
end

-- Dungeon entrances per level zone, worked out on first use. Wings of one instance with the same
-- range are one line.
function M.ZoneDungeons(zoneID)
    if not dungeonsByZone then
        dungeonsByZone = {}
        local api = _G.C_Map
        for _, entry in ipairs(NS.MapDungeons or {}) do
            local zone
            if entry.map then
                zone = levelZone(entry.map)
            elseif api then
                local u, v = project(entry[1], entry[2], entry[3])
                local info = u and A.Call(api.GetMapInfoAtPosition, CONTINENT_MAPS[entry[1]], u, v)
                zone = type(info) == "table" and levelZone(info.mapID) or nil
            end
            if zone then
                local list, seen = dungeonsByZone[zone] or {}, {}
                for _, row in ipairs(list) do seen[row.key] = true end
                for _, row in ipairs(entry[4]) do
                    local key = row[1] .. ":" .. row[4] .. ":" .. row[5]
                    if row[1] == 0 then key = row[2] end
                    if not seen[key] then
                        seen[key] = true
                        list[#list + 1] = {key = key, name = dungeonName(row), raid = row[3], low = row[4], high = row[5]}
                    end
                end
                table.sort(list, function(a, b) if a.low ~= b.low then return a.low < b.low end return a.name < b.name end)
                dungeonsByZone[zone] = list
            end
        end
    end
    return dungeonsByZone[zoneID] or {}
end

local function hideLabels()
    for index = 1, levels.used do levels.labels[index]:Hide() end
    levels.used = 0
end

local function hideTip()
    local tip = _G.GameTooltip
    if levels.layer and tip and tip.IsOwned and tip:IsOwned(levels.layer) then tip:Hide() end
    levels.tipZone = nil
end

function M.ShowZoneTip(zoneID, name)
    local tip, low, high = _G.GameTooltip, M.ZoneLevels(zoneID)
    if not tip or not low or not levels.layer then return end
    tip:SetOwner(levels.layer, "ANCHOR_CURSOR")
    tip:AddLine(name or (mapInfo(zoneID) or {}).name or "", 1, .82, 0)
    local c = LEVEL_COLORS[L.LevelBand(playerLevel(), low, high)]
    tip:AddDoubleLine(tr("Mindeststufe", "Minimum level"), tostring(low), .8, .8, .8, c[1], c[2], c[3])
    tip:AddDoubleLine(tr("Höchststufe", "Maximum level"), tostring(high), .8, .8, .8, c[1], c[2], c[3])
    local data = db()
    if data and data.mapLevelDungeons then
        local list = M.ZoneDungeons(zoneID)
        if #list > 0 then
            tip:AddLine(" ")
            tip:AddLine(tr("Dungeons in diesem Gebiet", "Dungeons in this zone"), 1, .82, 0)
            for _, row in ipairs(list) do
                local d = LEVEL_COLORS[L.LevelBand(playerLevel(), row.low, row.high)]
                local title = row.raid and (row.name .. " " .. tr("(Schlachtzug)", "(raid)")) or row.name
                tip:AddDoubleLine(title, L.LevelRange(row.low, row.high), 1, 1, 1, d[1], d[2], d[3])
            end
        end
    end
    tip:Show()
    levels.tipZone = zoneID
end

-- The zone under the cursor, a few times a second while the layer is shown.
local function hover(layer, elapsed)
    levels.wait = (levels.wait or 0) - (elapsed or 0)
    if levels.wait > 0 then return end
    levels.wait = .1
    local map, continent = levels.map, levels.continent
    local api = _G.C_Map
    local zone
    if map and continent and api and A.Call(map.IsCanvasMouseFocus, map) then
        local x, y = A.Call(map.GetNormalizedCursorPosition, map)
        local info = type(x) == "number" and type(y) == "number" and A.Call(api.GetMapInfoAtPosition, continent, x, y)
        zone = type(info) == "table" and M.ZoneLevels(info.mapID) and info.mapID or nil
    end
    if zone == levels.tipZone then return end
    hideTip()
    if zone then M.ShowZoneTip(zone) end
end

local function ensureLayer(map)
    if levels.layer then return levels.layer end
    local canvas = map.GetCanvas and A.Call(map.GetCanvas, map)
    if not canvas or type(_G.CreateFrame) ~= "function" then return nil end
    local layer = _G.CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:SetScript("OnUpdate", hover)
    layer:SetScript("OnHide", hideTip)
    layer:Hide()
    levels.layer = layer
    return layer
end

-- Keeps the labels the same size on screen at every zoom.
function M.PlaceLevels()
    local layer, map = levels.layer, levels.map
    if not layer or not map or levels.used == 0 then return end
    local scale = tonumber(A.Call(map.GetCanvasScale, map)) or 1
    if scale <= 0 then scale = 1 end
    local width, height = layer:GetWidth() or 0, layer:GetHeight() or 0
    for index = 1, levels.used do
        local label = levels.labels[index]
        local own = 1 / scale
        if label.SetScale then label:SetScale(own) else own = 1 end
        label:ClearAllPoints()
        label:SetPoint("CENTER", layer, "TOPLEFT", label.spot.x * width / own, -label.spot.y * height / own)
    end
end

function M.DrawLevels()
    hideLabels()
    local map = levels.map
    local layer = levels.layer
    local mode = M.LevelMode()
    local continent = mode and continentOf(map)
    levels.continent = continent
    if not layer then return end
    if not continent then hideTip(); layer:Hide(); return end
    -- Above the explored overlays and OpenMap's stitched art; labels take no mouse input.
    local level = M.pin and M.pin.GetFrameLevel and M.pin:GetFrameLevel() or 0
    local art = _G.OpenMapAPI and A.Call(_G.OpenMapAPI.ArtTopLevel)
    if type(art) == "number" and art > level then level = art end
    if level > 0 then layer:SetFrameLevel(level + 1) end
    layer:Show()
    if mode == "labels" then
        for _, spot in ipairs(zoneSpots(continent)) do
            levels.used = levels.used + 1
            local label = levels.labels[levels.used]
            if not label then
                label = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                if label.SetShadowOffset then label:SetShadowOffset(1, -1) end
                levels.labels[levels.used] = label
            end
            label.spot = spot
            label:SetText(string.format("|cffffffff%s|r %s(%s)|r", spot.name or "", colorCode(spot.low, spot.high), L.LevelRange(spot.low, spot.high)))
            label:Show()
        end
        M.PlaceLevels()
    end
    if levels.tipZone then local zone = levels.tipZone; levels.tipZone = nil; M.ShowZoneTip(zone) end
end

-- New level from PLAYER_LEVEL_UP (UnitLevel can still answer the old one then).
function M.LevelChanged(level)
    M.playerLevel = tonumber(level)
    M.DrawLevels()
end

function M.AttachLevels(map)
    if not map or levels.provider or A.Combat() then return end
    local mixin = _G.MapCanvasDataProviderMixin
    if type(mixin) ~= "table" or type(_G.CreateFromMixins) ~= "function" or type(map.AddDataProvider) ~= "function" then return end
    if not ensureLayer(map) then return end
    local provider = _G.CreateFromMixins(mixin)
    function provider:RefreshAllData() M.DrawLevels() end
    function provider:RemoveAllData() hideLabels(); hideTip() end
    function provider:OnCanvasScaleChanged() M.PlaceLevels() end
    levels.map = map
    if pcall(map.AddDataProvider, map, provider) then levels.provider = provider end
end

function M.Refresh()
    M.TryAttach()
    if M.pin then M.Draw(M.pin) end
    M.DrawLevels()
end

function M.CombatEnded()
    if M.dirty and M.pin then M.Draw(M.pin) end
    if not levels.provider then M.AttachLevels(_G.WorldMapFrame) end
end

-- Sets the game's own user waypoint on the player's current zone map.
function M.Waypoint(text)
    local data = db()
    if not data or not data.modMap or not data.waypoints then return false end
    local api = _G.C_Map
    text = (text or ""):match("^%s*(.-)%s*$")
    if text:lower() == "clear" then
        if api and api.ClearUserWaypoint then A.Call(api.ClearUserWaypoint) end
        return true
    end
    local x, y = L.ParseWaypoint(text)
    if not x then
        A.Print(tr("Verwendung: /zway 45.2 67.8 oder /zway clear", "Usage: /zway 45.2 67.8 or /zway clear"))
        return false
    end
    local mapID = api and A.Call(api.GetBestMapForUnit, "player")
    if not mapID or A.Call(api.CanSetUserWaypointOnMap, mapID) == false or not _G.UiMapPoint then
        A.Print(tr("Auf dieser Karte kann kein Wegpunkt gesetzt werden.", "A waypoint cannot be set on this map."))
        return false
    end
    local point = A.Call(_G.UiMapPoint.CreateFromCoordinates, mapID, x, y)
    if not point or not pcall(api.SetUserWaypoint, point) then
        A.Print(tr("Das Spiel hat den Wegpunkt abgelehnt.", "The game rejected the waypoint."))
        return false
    end
    if _G.C_SuperTrack and _G.C_SuperTrack.SetSuperTrackedUserWaypoint then A.Call(_G.C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    A.Print(string.format(tr("Wegpunkt gesetzt: %.1f, %.1f", "Waypoint set: %.1f, %.1f"), x * 100, y * 100))
    return true
end
