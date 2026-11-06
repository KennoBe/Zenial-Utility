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
    if M.pin or not map or type(map.EnumeratePinsByTemplate) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    local enumerate = A.Call(map.EnumeratePinsByTemplate, map, "MapExplorationPinTemplate")
    if type(enumerate) ~= "function" then return end
    for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        hooksecurefunc(pin, "RefreshOverlays", function(self) M.Draw(self) end)
        M.pin = pin
        M.Draw(pin)
        break
    end
    M.AttachCoords(map)
end

-- Coordinates line along the lower edge of the world map.
function M.AttachCoords(map)
    if M.coords then return end
    local parent = map.ScrollContainer or map
    local frame = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(280, 22)
    frame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 4)
    frame:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 40)
    NS.Theme.Panel(frame, "inset")
    local text = NS.Theme.Text(frame, "", "GameFontHighlightSmall", "text")
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    frame.text = text
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < .1 then return end
        elapsed = 0
        self.text:SetText(M.CoordText(map))
    end)
    M.coords = frame
    M.RefreshCoords()
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

function M.CoordText(map)
    local parts = {}
    local mapID = map.GetMapID and map:GetMapID()
    local x, y = M.PlayerPosition(mapID)
    parts[1] = tr("Spieler ", "Player ") .. (x and L.FormatPercent(x, y) or "–")
    local scroll = map.ScrollContainer
    if scroll and scroll.GetNormalizedCursorPosition and scroll:IsMouseOver() then
        local cx, cy = A.Call(scroll.GetNormalizedCursorPosition, scroll)
        if type(cx) == "number" and type(cy) == "number" and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
            parts[2] = tr("Maus ", "Cursor ") .. L.FormatPercent(cx, cy)
        end
    end
    return table.concat(parts, "   ·   ")
end

function M.RefreshCoords()
    if M.coords then M.coords:SetShown(db() and db().modMap and db().mapCoords or false) end
end

function M.Refresh()
    M.TryAttach()
    M.RefreshCoords()
    if M.pin then M.Draw(M.pin) end
end

function M.CombatEnded()
    if M.dirty and M.pin then M.Draw(M.pin) end
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
