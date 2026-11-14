local _, NS = ...
local C = {cards = {}, pool = {}, slots = {}, expanded = {}}
NS.LootRollCards = C
local T, A, M, tr = NS.Theme, NS.Adapter, NS.LootRollModel, NS.Text

-- The cards of the loot roll window. The state lives in NS.LootRoll; this file only draws it.
-- A card keeps its place while it exists: arriving decisions change its texts, never its size or
-- the position of its buttons. Gaps between cards close only while no card behind them is still open.

local WIDTH, LARGE_H, COMPACT_H, GAP = 340, 112, 26, 4
local LARGE_SLOTS, LIST_ROWS, ROW_H = 3, 8, 14
local LIST_H = LIST_ROWS * ROW_H + 8
local BAR_WIDTH = WIDTH - 64
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

local function db() return NS.App.db end
local function state() return NS.LootRoll.state end

----------------------------------------------------------------------
-- Texts and colours
----------------------------------------------------------------------
local function clientText(name, fallback)
    local value = _G[name]
    return type(value) == "string" and value ~= "" and value or fallback
end

local function kindLabel(kind)
    if kind == "NEED" then return clientText("NEED", tr("Bedarf", "Need")) end
    if kind == "GREED" then return clientText("GREED", tr("Gier", "Greed")) end
    if kind == "PASS" then return clientText("PASS", tr("Passen", "Pass")) end
    if kind == "TRANSMOG" then
        local text = clientText("TRANSMOGRIFICATION", "")
        return (text ~= "" and #text <= 12) and text or "Transmog"
    end
    if kind == "WAITING" then return tr("offen", "open") end
    return "?"
end

C.KindLabel = kindLabel

local function actionLabel(action) return kindLabel(M.ActionKind(action)) end

local function qualityColor(quality)
    local entry = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality or 1]
    if type(entry) == "table" and entry.r then return entry.r, entry.g, entry.b end
    return 1, 1, 1
end

-- "|cffrrggbbName|r" with the class colour, or the plain name.
local function playerName(player)
    local name = player.name or "?"
    local entry = player.class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[player.class]
    if type(entry) ~= "table" or not entry.r then return name end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(entry.r * 255 + .5), math.floor(entry.g * 255 + .5), math.floor(entry.b * 255 + .5), name)
end

local function playerDetail(player)
    local text = playerName(player) .. " (" .. kindLabel(player.kind)
    if player.roll then text = text .. " " .. player.roll end
    return text .. ")"
end

local function ownText(roll)
    local kind = roll.ownChoice or (roll.pendingChoice and M.ActionKind(roll.pendingChoice))
    if not kind then return nil end
    local text = tr("Du: ", "You: ") .. kindLabel(kind)
    if roll.ownChoice and roll.ownSource == "auto" then text = text .. tr(" (automatisch)", " (automatic)") end
    return text
end

-- Long status line and its colour key; short form for compact cards.
local function statusText(roll)
    if roll.status == "CANCELLED" then return tr("Ergebnis unbekannt", "Result unknown"), "muted", tr("unbekannt", "unknown") end
    if roll.status == "FINISHED" then
        if roll.winner then
            local key = roll.winner.isSelf and "online" or "gold"
            return tr("Gewinner: ", "Winner: ") .. playerDetail(roll.winner), key, tr("fertig", "done")
        end
        return tr("Alle haben gepasst", "Everyone passed"), "muted", tr("fertig", "done")
    end
    if roll.leader then
        local head = roll.isTied and tr("Gleichstand: ", "Tie: ") or tr("Führend: ", "Leading: ")
        return head .. playerDetail(roll.leader), "text", roll.isTied and tr("gleich", "tie") or ""
    end
    if roll.native and roll.status == "PENDING" then
        return tr("Wahl im Blizzard-Fenster", "Choose in the Blizzard window"), "muted", tr("nativ", "native")
    end
    if roll.status == "WAITING" then
        if roll.match == "ambiguous" then return tr("Nicht eindeutig zuordenbar", "Cannot be matched clearly"), "muted", "?" end
        return tr("Warte auf Ergebnis", "Waiting for the result"), "muted", tr("wartet", "wait")
    end
    return "", "muted", ""
end

----------------------------------------------------------------------
-- Anchor
----------------------------------------------------------------------
local function place()
    local anchor, saved = C.anchor, db().lootRollPosition
    anchor:ClearAllPoints()
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
        anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
    else
        anchor:SetPoint("TOPLEFT", UIParent, "CENTER", 180, 200)
    end
end

local function createAnchor()
    if C.anchor then return C.anchor end
    local anchor = CreateFrame("Frame", "ZenialUtilityLootRoll", UIParent, BACKDROP)
    anchor:SetSize(WIDTH, 24)
    anchor:SetScale(db().lootRollScale)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) if C.moving then self:StartMoving() end end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        db().lootRollPosition = {x = self:GetLeft(), y = self:GetTop()}
        place()
    end)
    anchor.label = T.Text(anchor, tr("Loot-Würfe: ziehen zum Verschieben", "Loot rolls: drag to move"), "GameFontHighlightSmall", "gold")
    anchor.label:SetPoint("LEFT", 8, 0)
    anchor.label:Hide()
    C.anchor = anchor
    place()
    return anchor
end

----------------------------------------------------------------------
-- Cards
----------------------------------------------------------------------
local function showTip(owner, build)
    local tip = _G.GameTooltip
    if not tip or not tip.SetOwner then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    build(tip)
    tip:Show()
end

local function hideTip()
    local tip = _G.GameTooltip
    if tip and tip.Hide then tip:Hide() end
end

local function currentRoll(card) return card.rollID ~= nil and state().rolls[card.rollID] or nil end

local function createRows(card)
    if card.rows then return end
    card.rows = {}
    for index = 1, LIST_ROWS do
        local y = -(LARGE_H + 2 + (index - 1) * ROW_H)
        local row = {
            name = T.Text(card, "", "GameFontHighlightSmall", "text"),
            kind = T.Text(card, "", "GameFontHighlightSmall", "dim"),
            roll = T.Text(card, "", "GameFontHighlightSmall", "text"),
        }
        row.name:SetPoint("TOPLEFT", 10, y); row.name:SetWidth(170); row.name:SetWordWrap(false)
        row.kind:SetPoint("TOPLEFT", 186, y); row.kind:SetWidth(90); row.kind:SetWordWrap(false)
        row.roll:SetPoint("TOPRIGHT", -10, y); row.roll:SetWidth(50); row.roll:SetJustifyH("RIGHT")
        card.rows[index] = row
    end
end

local function createCard()
    local card = table.remove(C.pool)
    if card then return card end
    card = CreateFrame("Frame", nil, C.anchor, BACKDROP)
    card:SetSize(WIDTH, LARGE_H)
    card:EnableMouse(true)
    T.Panel(card, "surface")

    local icon = CreateFrame("Button", nil, card, BACKDROP)
    icon:SetPoint("TOPLEFT", 8, -8)
    icon:SetSize(40, 40)
    T.Panel(icon, "inset")
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetPoint("TOPLEFT", 3, -3)
    icon.tex:SetPoint("BOTTOMRIGHT", -3, 3)
    icon.count = T.Text(icon, "", "GameFontHighlightSmall", "text")
    icon.count:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetScript("OnEnter", function(self)
        local roll = currentRoll(card)
        if not roll then return end
        showTip(self, function(tip)
            -- Only a roll that is still open can be read through its id.
            if roll.status == "PENDING" and not roll.demo and tip.SetLootRollItem and pcall(tip.SetLootRollItem, tip, roll.rollID) then return end
            if roll.link and tip.SetHyperlink then pcall(tip.SetHyperlink, tip, roll.link) end
        end)
    end)
    icon:SetScript("OnLeave", hideTip)
    icon:SetScript("OnClick", function()
        local roll = currentRoll(card)
        if roll and roll.link then A.Call(_G.HandleModifiedItemClick, roll.link) end
    end)
    card.icon = icon

    card.name = T.Text(card, "", "GameFontNormal", "text")
    card.name:SetWordWrap(false)
    card.sub = T.Text(card, "", "GameFontHighlightSmall", "gold")
    card.sub:SetWordWrap(false)
    card.barBack = card:CreateTexture(nil, "BACKGROUND")
    card.barBack:SetColorTexture(.04, .035, .03, .9)
    card.barFill = card:CreateTexture(nil, "ARTWORK")
    T.Tint(card.barFill, "SetColorTexture", "goldDim")
    card.seconds = T.Text(card, "", "GameFontHighlightSmall", "dim")
    card.seconds:SetJustifyH("RIGHT")
    card.status = T.Text(card, "", "GameFontHighlightSmall", "muted")
    card.status:SetWordWrap(false)

    card.buttons = {}
    for index = 1, 3 do
        local button = T.Button(card, "", 104, 22, nil, "secondary")
        button:SetScript("OnClick", function(self)
            if card.rollID ~= nil and self.action ~= nil then NS.LootRoll.Choose(card.rollID, self.action) end
        end)
        button:HookScript("OnEnter", function(self)
            local roll = currentRoll(card)
            if not roll or self.action == nil or self:IsEnabled() then return end
            local reason = roll.native and tr("Wahl im Blizzard-Fenster", "Choose in the Blizzard window") or roll.reasons[self.action]
            if reason then showTip(self, function(tip) tip:SetText(reason, 1, 1, 1, 1, true) end) end
        end)
        button:HookScript("OnLeave", hideTip)
        card.buttons[index] = button
    end

    card.toggle = T.Button(card, "+", 44, 16, function()
        if card.rollID == nil then return end
        C.expanded[card.rollID] = not C.expanded[card.rollID] or nil
        C.Refresh()
    end, "secondary")
    card.toggle:HookScript("OnEnter", function(self)
        showTip(self, function(tip) tip:SetText(tr("Gruppenliste ein- oder ausklappen", "Show or hide the group list"), 1, 1, 1, 1, true) end)
    end)
    card.toggle:HookScript("OnLeave", hideTip)

    -- Only an open list takes the wheel; otherwise the card would block the camera zoom.
    card:EnableMouseWheel(false)
    card:SetScript("OnMouseWheel", function(self, delta)
        if not C.expanded[self.rollID] then return end
        self.listOffset = math.max(0, (self.listOffset or 0) - delta)
        C.Refresh()
    end)
    return card
end

-- Large and compact cards share one frame; the mode moves the parts.
local function applyMode(card, large)
    if card.large == large then return end
    card.large = large
    card.icon:ClearAllPoints(); card.name:ClearAllPoints(); card.sub:ClearAllPoints()
    card.barBack:ClearAllPoints(); card.barFill:ClearAllPoints(); card.seconds:ClearAllPoints()
    card.status:ClearAllPoints(); card.toggle:ClearAllPoints()
    if large then
        card.icon:SetPoint("TOPLEFT", 8, -8); card.icon:SetSize(40, 40)
        card.name:SetPoint("TOPLEFT", 56, -9); card.name:SetWidth(WIDTH - 66)
        card.sub:SetPoint("TOPLEFT", 56, -28); card.sub:SetWidth(WIDTH - 66)
        card.barBack:SetPoint("TOPLEFT", 8, -54); card.barBack:SetSize(BAR_WIDTH, 6)
        card.barFill:SetPoint("TOPLEFT", 8, -54); card.barFill:SetSize(BAR_WIDTH, 6)
        card.seconds:SetPoint("TOPRIGHT", -8, -51); card.seconds:SetWidth(44)
        card.status:SetPoint("TOPLEFT", 8, -94); card.status:SetWidth(WIDTH - 66)
        card.toggle:SetPoint("TOPRIGHT", -8, -92)
        for index, button in ipairs(card.buttons) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 8 + (index - 1) * 110, -66)
            button:SetSize(104, 22)
        end
    else
        card.icon:SetPoint("TOPLEFT", 4, -3); card.icon:SetSize(20, 20)
        card.name:SetPoint("TOPLEFT", 28, -7); card.name:SetWidth(80)
        -- One field: time left while open, the short status afterwards.
        card.seconds:SetPoint("TOPLEFT", 112, -8); card.seconds:SetWidth(44); card.seconds:SetJustifyH("CENTER")
        for index, button in ipairs(card.buttons) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 160 + (index - 1) * 60, -2)
            button:SetSize(58, 22)
        end
    end
    card.sub:SetShown(large)
    card.status:SetShown(large)
    card.seconds:SetJustifyH(large and "RIGHT" or "CENTER")
    card.barBack:SetShown(large)
    card.barFill:SetShown(large)
    card.toggle:SetShown(large)
    card.icon.count:SetShown(large)
end

local function renderList(card, roll)
    createRows(card)
    local players = roll.players
    card.listOffset = math.min(card.listOffset or 0, math.max(0, #players - LIST_ROWS))
    for index, row in ipairs(card.rows) do
        local player = players[card.listOffset + index]
        if player then
            row.name:SetText((player.isWinner and "> " or "") .. playerName(player))
            row.kind:SetText(kindLabel(player.kind))
            row.roll:SetText(player.roll and tostring(player.roll) or "")
            T.Tint(row.name, "SetTextColor", player.isWinner and "gold" or "text")
        elseif index == 1 and #players == 0 then
            row.name:SetText(roll.match == "ambiguous" and tr("Nicht eindeutig zuordenbar", "Cannot be matched clearly")
                or tr("Noch keine Entscheidungen bekannt", "No decisions known yet"))
            row.kind:SetText(""); row.roll:SetText("")
            T.Tint(row.name, "SetTextColor", "muted")
        else
            row.name:SetText(""); row.kind:SetText(""); row.roll:SetText("")
        end
    end
end

local function showList(card, on)
    if not card.rows then return end
    for _, row in ipairs(card.rows) do
        row.name:SetShown(on); row.kind:SetShown(on); row.roll:SetShown(on)
    end
end

local function render(card, roll, large, now)
    applyMode(card, large)
    card.icon.tex:SetTexture(roll.icon or T.assets.neutralIcon)
    local r, g, b = qualityColor(roll.quality)
    if card.icon.SetBackdropBorderColor then card.icon:SetBackdropBorderColor(r, g, b, 1) end
    card.name:SetText(roll.name or "?")
    card.name:SetTextColor(r, g, b)
    card.icon.count:SetText((roll.count or 1) > 1 and tostring(roll.count) or "")

    local pending = roll.status == "PENDING"
    local left = math.max(0, roll.endsAt - now)
    card.seconds:SetText(pending and string.format("%d", math.ceil(left)) or "")
    if large then
        T.Tint(card.seconds, "SetTextColor", "dim")
        local fraction = (pending and roll.duration and roll.duration > 0) and math.min(1, left / roll.duration) or 0
        card.barFill:SetWidth(math.max(1, BAR_WIDTH * fraction))
        card.barFill:SetShown(pending)
        local parts = {ownText(roll)}
        if roll.bop then parts[#parts + 1] = clientText("ITEM_BIND_ON_PICKUP", tr("Beim Aufheben gebunden", "Binds when picked up")) end
        card.sub:SetText(table.concat(parts, "  |  "))
    end

    for index, button in ipairs(card.buttons) do
        local action = roll.offers[index]
        button.action = action
        button:SetShown(action ~= nil)
        if action ~= nil then
            button:SetText(actionLabel(action))
            if pending and roll.allowed[action] == true and not roll.native then button:Enable() else button:Disable() end
            local chosen = roll.ownChoice or (roll.pendingChoice and M.ActionKind(roll.pendingChoice))
            T.StyleButton(button, chosen == M.ActionKind(action) and "primary" or "secondary")
        end
    end

    local text, key, short = statusText(roll)
    card.status:SetText(large and text or "")
    T.Tint(card.status, "SetTextColor", key)
    if not large then
        card.seconds:SetText(pending and string.format("%d", math.ceil(left)) or short)
        T.Tint(card.seconds, "SetTextColor", pending and "dim" or key)
    end

    local expanded = large and C.expanded[roll.rollID] == true
    if large then
        card.toggle:SetText((expanded and "- " or "+ ") .. #roll.players)
        card.toggle:SetShown(#roll.players > 0 or expanded)
    end
    card:EnableMouseWheel(expanded)
    if expanded then renderList(card, roll) end
    showList(card, expanded)
    card:SetHeight(large and (LARGE_H + (expanded and LIST_H or 0)) or COMPACT_H)
end

----------------------------------------------------------------------
-- Places
----------------------------------------------------------------------
local function release(rollID)
    local card = C.cards[rollID]
    C.cards[rollID] = nil
    C.slots[rollID], C.expanded[rollID] = nil, nil
    if not card then return end
    card.rollID, card.listOffset = nil, nil
    card:Hide()
    C.pool[#C.pool + 1] = card
end

local function releaseAll()
    for rollID in pairs(C.cards) do release(rollID) end
    C.slots, C.expanded = {}, {}
end

local function assignSlots(current)
    local live = {}
    for _, rollID in ipairs(current.order) do live[rollID] = true end
    for rollID in pairs(C.slots) do
        if not live[rollID] then C.slots[rollID], C.expanded[rollID] = nil, nil end
    end
    local taken, maxSlot = {}, 0
    for _, slot in pairs(C.slots) do taken[slot] = true; maxSlot = math.max(maxSlot, slot) end
    -- A new card takes the first free place.
    for _, rollID in ipairs(current.order) do
        if not C.slots[rollID] then
            local slot = 1
            while taken[slot] do slot = slot + 1 end
            C.slots[rollID], taken[slot], maxSlot = slot, true, math.max(maxSlot, slot)
        end
    end
    local gap
    for slot = 1, maxSlot do
        if not taken[slot] then gap = slot; break end
    end
    if not gap then return end
    for rollID, slot in pairs(C.slots) do
        if slot > gap and current.rolls[rollID].status == "PENDING" then return end
    end
    local ordered = {}
    for rollID in pairs(C.slots) do ordered[#ordered + 1] = rollID end
    table.sort(ordered, function(a, b) return C.slots[a] < C.slots[b] end)
    for index, rollID in ipairs(ordered) do C.slots[rollID] = index end
end

function C.Refresh()
    local current = state()
    if #current.order == 0 then
        releaseAll()
        if C.anchor and not C.moving then C.anchor:Hide() end
        return
    end
    local anchor = createAnchor()
    anchor:Show()
    assignSlots(current)
    for rollID in pairs(C.cards) do
        if not current.rolls[rollID] then release(rollID) end
    end
    local now = NS.LootRollNative.Now()
    local compactAll = db().lootRollCompact == true
    local up = db().lootRollGrow == "up"
    local bySlot, maxSlot = {}, 0
    for _, rollID in ipairs(current.order) do
        local card = C.cards[rollID]
        if not card then
            card = createCard()
            card.rollID = rollID
            C.cards[rollID] = card
            card:Show()
        end
        local slot = C.slots[rollID]
        bySlot[slot], maxSlot = card, math.max(maxSlot, slot)
        render(card, current.rolls[rollID], slot <= LARGE_SLOTS and not compactAll, now)
    end
    -- An empty place keeps its height so the cards behind it do not move.
    local y = 0
    for slot = 1, maxSlot do
        local card = bySlot[slot]
        local height = card and card:GetHeight() or ((slot <= LARGE_SLOTS and not compactAll) and LARGE_H or COMPACT_H)
        if card then
            card:ClearAllPoints()
            if up then card:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, y)
            else card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -y) end
        end
        y = y + height + GAP
    end
end

function C.SetMoving(active)
    local anchor = createAnchor()
    C.moving = active == true
    anchor:EnableMouse(C.moving)
    anchor.label:SetShown(C.moving)
    if C.moving then
        T.Panel(anchor, "inset")
        anchor:Show()
    else
        if anchor.SetBackdrop then anchor:SetBackdrop(nil) end
        if #state().order == 0 then anchor:Hide() end
    end
end

function C.ResetPosition()
    db().lootRollPosition = {}
    if C.anchor then place() end
end

function C.SettingsChanged()
    if not C.anchor then return end
    C.anchor:SetScale(db().lootRollScale)
    place()
    C.Refresh()
end

function C.HideAll()
    releaseAll()
    if C.anchor then C.anchor:Hide() end
end
