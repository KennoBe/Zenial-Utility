local _, NS = ...
local F = {entries = {}, pool = {}}
NS.LootFeed = F
local A, L, T, tr = NS.Adapter, NS.Logic, NS.Theme, NS.Text

-- Short list of received items. The only source is the own CHAT_MSG_LOOT line: it comes after
-- the item reached the bags, once per item. ENCOUNTER_LOOT_RECEIVED repeats the same boss loot
-- and LOOT_READY lists what is only offered, so neither is used.
local MAX_ENTRIES, ROW_HEIGHT, WIDTH, FADE = 6, 22, 280, .6
local QUEST_CLASS = 12

local function db() return NS.App.db end
local function on(key) return db().modQoL and db()[key] end

local function formats()
    if not F.multiple then
        F.multiple = L.FormatPattern(_G.LOOT_ITEM_SELF_MULTIPLE)
        F.single = L.FormatPattern(_G.LOOT_ITEM_SELF)
    end
    return F.multiple, F.single
end

----------------------------------------------------------------------
-- Frames: one anchor and at most MAX_ENTRIES rows, reused after they fade.
----------------------------------------------------------------------
local function place()
    local anchor, saved = F.anchor, db().lootFeedPosition
    anchor:ClearAllPoints()
    if type(saved.x) == "number" and type(saved.y) == "number" then
        anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
    else
        anchor:SetPoint("TOPLEFT", UIParent, "CENTER", 180, 120)
    end
end

local function createAnchor()
    if F.anchor then return F.anchor end
    local anchor = CreateFrame("Frame", "ZenialUtilityLootFeed", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    anchor:SetSize(WIDTH, ROW_HEIGHT)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) if F.moving then self:StartMoving() end end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        db().lootFeedPosition = {x = self:GetLeft(), y = self:GetTop()}
        place()
    end)
    anchor.label = T.Text(anchor, tr("Loot-Anzeige: ziehen zum Verschieben", "Loot display: drag to move"), "GameFontHighlightSmall", "gold")
    anchor.label:SetPoint("LEFT", 8, 0)
    anchor.label:Hide()
    F.anchor = anchor
    place()
    return anchor
end

local function layout()
    local scale = db().lootFeedScale
    F.anchor:SetScale(scale)
    for index, entry in ipairs(F.entries) do
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", F.anchor, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    end
end

local function release(entry)
    for index, item in ipairs(F.entries) do
        if item == entry then table.remove(F.entries, index); break end
    end
    entry:Hide()
    entry.key, entry.link = nil, nil
    F.pool[#F.pool + 1] = entry
    layout()
end

local function showTooltip(entry)
    local tip = _G.GameTooltip
    if not entry.link or not tip or not tip.SetOwner then return end
    tip:SetOwner(entry, "ANCHOR_RIGHT")
    pcall(tip.SetHyperlink, tip, entry.link)
    tip:Show()
end

local function createEntry()
    local entry = table.remove(F.pool)
    if entry then return entry end
    entry = CreateFrame("Frame", nil, F.anchor)
    entry:SetSize(WIDTH, ROW_HEIGHT)
    entry.icon = entry:CreateTexture(nil, "ARTWORK")
    entry.icon:SetSize(18, 18)
    entry.icon:SetPoint("LEFT", 0, 0)
    entry.text = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    entry.text:SetPoint("LEFT", entry.icon, "RIGHT", 6, 0)
    entry.text:SetWidth(WIDTH - 26)
    entry.text:SetJustifyH("LEFT")
    entry.text:SetWordWrap(false)
    if entry.text.SetShadowOffset then entry.text:SetShadowOffset(1, -1) end
    -- The fade runs in the engine: no Lua runs per frame while entries are visible.
    if entry.CreateAnimationGroup then
        local group = entry:CreateAnimationGroup()
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetFromAlpha(1)
        alpha:SetToAlpha(0)
        alpha:SetDuration(FADE)
        group:SetScript("OnFinished", function() release(entry) end)
        entry.fade, entry.fadeAnim = group, alpha
    end
    entry:SetScript("OnEnter", function(self)
        if self.fade then self.fade:Stop() end
        self:SetAlpha(1)
        showTooltip(self)
    end)
    entry:SetScript("OnLeave", function(self)
        local tip = _G.GameTooltip
        if tip and tip.Hide then tip:Hide() end
        F.StartFade(self)
    end)
    return entry
end

function F.StartFade(entry)
    local seconds = db().lootFeedTime
    entry:SetAlpha(1)
    if entry.fade then
        entry.fade:Stop()
        entry.fadeAnim:SetStartDelay(math.max(0, seconds - FADE))
        entry.fade:Play()
    elseif _G.C_Timer and _G.C_Timer.After then
        -- Without animations the entry simply disappears after its time.
        local token = {}
        entry.token = token
        _G.C_Timer.After(seconds, function() if entry.token == token then release(entry) end end)
    end
end

local function render(entry)
    local name, prefix = L.LinkParts(entry.link)
    local text = (prefix or "") .. "[" .. (name or "?") .. "]" .. (prefix and "|r" or "")
    if entry.count > 1 then text = text .. " ×" .. entry.count end
    if entry.quest then text = text .. "  |cffffd100" .. tr("Quest", "Quest") .. "|r" end
    entry.text:SetText(text)
    entry.icon:SetTexture(entry.iconFile or 134400)
    -- Only with tooltips on does an entry take the mouse; otherwise clicks pass through.
    entry:EnableMouse(on("lootFeedTooltip") == true)
end

----------------------------------------------------------------------
-- Adding items
----------------------------------------------------------------------
local function itemDetails(link)
    local api = _G.C_Item
    local itemID = L.LinkItemID(link)
    local icon, classID
    if api and itemID then
        local _, _, _, _, instantIcon, instantClass = A.Call(api.GetItemInfoInstant, itemID)
        icon, classID = instantIcon, instantClass
    end
    local quality = L.LinkQuality(link, _G.ITEM_QUALITY_COLORS)
    if not quality and api and itemID then quality = tonumber(A.Call(api.GetItemQualityByID, itemID)) end
    return itemID, icon, quality, classID == QUEST_CLASS
end

-- A matching entry still on screen grows instead of adding a second row.
function F.Add(link, count)
    if not on("lootFeed") or type(link) ~= "string" then return false end
    local itemID, icon, quality, quest = itemDetails(link)
    if on("lootFeedQuality") and not quest and (quality or 0) < 2 then return false end
    createAnchor()
    local key = itemID or link
    for _, entry in ipairs(F.entries) do
        if entry.key == key then
            entry.count = entry.count + count
            render(entry)
            F.StartFade(entry)
            return true
        end
    end
    -- A full list gives its oldest row to the new item.
    if #F.entries >= MAX_ENTRIES then
        local oldest = F.entries[1]
        if oldest.fade then oldest.fade:Stop() end
        release(oldest)
    end
    local entry = createEntry()
    entry.key, entry.link, entry.count, entry.iconFile, entry.quest = key, link, count, icon, quest
    F.entries[#F.entries + 1] = entry
    render(entry)
    layout()
    entry:Show()
    F.anchor:Show()
    F.StartFade(entry)
    return true
end

function F.LootMessage(message)
    -- In an encounter lockdown the line is protected and cannot be read.
    if type(message) ~= "string" or not A.Public(message) then return end
    local link, count = L.ParseOwnLoot(message, formats())
    if link then F.Add(link, count) end
end

----------------------------------------------------------------------
-- Moving and previewing
----------------------------------------------------------------------
local SAMPLE = "|cff1eff00|Hitem:2589::::::::1:::::::|h[" .. tr("Beispiel", "Sample") .. "]|h|r"

function F.SetMoving(active)
    createAnchor()
    F.moving = active == true
    local anchor = F.anchor
    anchor:EnableMouse(F.moving)
    anchor.label:SetShown(F.moving)
    if F.moving then
        T.Panel(anchor, "inset")
        layout()
        anchor:Show()
    elseif anchor.SetBackdrop then
        anchor:SetBackdrop(nil)
    end
end

function F.Preview()
    if not on("lootFeed") then return false end
    F.Add(SAMPLE, 3)
    return true
end

function F.ResetPosition()
    db().lootFeedPosition = {}
    if F.anchor then place() end
end

----------------------------------------------------------------------
-- Bind-on-pickup question while solo: the item is yours either way.
----------------------------------------------------------------------
function F.BindConfirm(slot)
    if not on("lootConfirmSolo") or not slot or A.Call(IsInGroup) == true then return end
    A.Call(ConfirmLootSlot, slot)
    A.Call(StaticPopup_Hide, "LOOT_BIND")
    -- The game may open its question right after this handler.
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, function() A.Call(StaticPopup_Hide, "LOOT_BIND") end) end
end

----------------------------------------------------------------------
local feedListener = A.Listener({CHAT_MSG_LOOT = F.LootMessage})
local bindListener = A.Listener({LOOT_BIND_CONFIRM = F.BindConfirm})

function F.SettingsChanged()
    feedListener:Set(on("lootFeed") == true)
    bindListener:Set(on("lootConfirmSolo") == true)
    if not on("lootFeed") then
        for index = #F.entries, 1, -1 do
            local entry = F.entries[index]
            if entry.fade then entry.fade:Stop() end
            release(entry)
        end
        if F.moving then F.SetMoving(false) end
    elseif F.anchor then
        layout()
        for _, entry in ipairs(F.entries) do render(entry) end
    end
end
