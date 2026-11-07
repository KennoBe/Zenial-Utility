local _, NS = ...
local V = {}
NS.Inventory = V
local A, L, T, tr = NS.Adapter, NS.Logic, NS.Theme, NS.Text

local function db() return NS.App.db end
local function on(key) return db().modInventory and db()[key] end

----------------------------------------------------------------------
-- Moving the combined bag window. Shift-drag, kept after the game re-anchors its bags.
-- Individual bag windows keep the game's own column layout.
----------------------------------------------------------------------
local function applyBagPosition()
    local bag, saved = _G.ContainerFrameCombinedBags, db().bagPosition
    if not bag or not on("bagMove") or type(saved.x) ~= "number" or type(saved.y) ~= "number" then return end
    bag:ClearAllPoints()
    bag:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
end
V.ApplyBagPosition = applyBagPosition

function V.ResetBagPosition()
    db().bagPosition = {}
    if type(_G.UpdateContainerFrameAnchors) == "function" then A.Call(_G.UpdateContainerFrameAnchors) end
end

local function hookBags()
    local bag = _G.ContainerFrameCombinedBags
    if V.bagHooked or not bag or type(hooksecurefunc) ~= "function" or type(_G.UpdateContainerFrameAnchors) ~= "function" then return end
    V.bagHooked = true
    hooksecurefunc("UpdateContainerFrameAnchors", applyBagPosition)
    bag:SetMovable(true)
    bag:SetClampedToScreen(true)
    bag:HookScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and on("bagMove") and A.Shift() and not A.Combat() then
            self:StartMoving()
            V.bagDragging = true
        end
    end)
    bag:HookScript("OnMouseUp", function(self)
        if not V.bagDragging then return end
        V.bagDragging = false
        self:StopMovingOrSizing()
        db().bagPosition = {x = self:GetLeft(), y = self:GetBottom()}
        applyBagPosition()
    end)
end

----------------------------------------------------------------------
-- XP numbers that stay visible on the bar.
----------------------------------------------------------------------
function V.XPText(xp, maximum, withPercent, numbers)
    xp, maximum = tonumber(xp) or 0, tonumber(maximum) or 0
    if maximum <= 0 then return "" end
    local percent = string.format("%.1f%%", xp / maximum * 100)
    if not numbers then return percent end
    local text = xp .. " / " .. maximum
    return withPercent and (text .. "  (" .. percent .. ")") or text
end

local function xpFrame()
    if V.xp then return V.xp end
    local parent = _G.MainStatusTrackingBarContainer or _G.StatusTrackingBarManager
    if not parent then return nil end
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 10)
    f.text = f:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    f.text:SetPoint("CENTER")
    V.xp = f
    return f
end

function V.UpdateXP()
    local wanted = on("xpText") or on("xpPercent")
    if not wanted then
        if V.xp then V.xp:Hide() end
        return
    end
    local f = xpFrame()
    if not f then return end
    local level, cap = tonumber(A.Call(UnitLevel, "player")) or 0, tonumber(A.Call(GetMaxPlayerLevel))
    if cap and level >= cap then f:Hide(); return end
    f.text:SetText(V.XPText(A.Call(UnitXP, "player"), A.Call(UnitXPMax, "player"), on("xpPercent"), on("xpText")))
    f:Show()
end

----------------------------------------------------------------------
-- Alts as mail recipients: same realm and faction, class colour and level.
----------------------------------------------------------------------
function V.MailRows()
    local rows = {}
    local own, scope = NS.Characters.Own()
    for key, row in pairs(db().characters) do
        if key ~= scope and own and row.name and row.realm == own.realm and row.faction == own.faction then
            rows[#rows + 1] = {key = key, name = row.name, level = row.level, class = row.class}
        end
    end
    table.sort(rows, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return a.name < b.name
    end)
    return rows
end

local function classColor(class)
    local colors = _G.RAID_CLASS_COLORS
    local c = colors and colors[class]
    return c and string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "ffffff"
end

local function buildMail()
    local parent = _G.SendMailFrame
    if V.mail or not parent then return V.mail end
    local mail = {rows = {}}
    mail.open = T.Button(parent, tr("Twinks", "Alts"), 60, 22, function()
        V.UpdateMailList()
        mail.popup:SetShown(not mail.popup:IsShown())
    end, "secondary")
    if _G.SendMailNameEditBox then mail.open:SetPoint("LEFT", _G.SendMailNameEditBox, "RIGHT", 4, 0)
    else mail.open:SetPoint("TOPRIGHT", -8, -40) end
    local popup = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    popup:SetSize(240, 40)
    popup:SetPoint("TOPLEFT", mail.open, "BOTTOMLEFT", 0, -2)
    popup:SetFrameStrata("DIALOG")
    T.Panel(popup, "surface")
    popup:EnableMouse(true)
    popup:Hide()
    mail.popup = popup
    for index = 1, 12 do
        local row = T.Button(popup, "", 196, 20, function(self)
            if _G.SendMailNameEditBox then _G.SendMailNameEditBox:SetText(self.name or "") end
            popup:Hide()
        end, "secondary")
        row:SetPoint("TOPLEFT", 6, -6 - (index - 1) * 21)
        row.remove = T.Button(popup, "×", 26, 20, function(self)
            if self.key and NS.Characters.Forget(self.key) then V.UpdateMailList() end
        end, "secondary")
        row.remove:SetPoint("LEFT", row, "RIGHT", 2, 0)
        NS.Widgets.Tooltip(row.remove, tr("Entfernen", "Remove"), tr("Nimmt diesen Charakter aus den Listen von Utility.", "Takes this character off Utility's lists."))
        row:Hide(); row.remove:Hide()
        mail.rows[index] = row
    end
    V.mail = mail
    return mail
end

function V.UpdateMailList()
    local mail = V.mail
    if not mail then return end
    local rows = V.MailRows()
    for index, button in ipairs(mail.rows) do
        local row = rows[index]
        button.name, button.remove.key = row and row.name, row and row.key
        if row then
            button:SetText(string.format("|cff%s%s|r  %s", classColor(row.class), row.name, row.level or "?"))
        end
        button:SetShown(row ~= nil)
        button.remove:SetShown(row ~= nil)
    end
    mail.popup:SetHeight(math.max(30, math.min(#rows, 12) * 21 + 12))
end

function V.UpdateMailButton()
    if not on("mailAlts") then
        if V.mail then V.mail.open:Hide(); V.mail.popup:Hide() end
        return
    end
    local mail = buildMail()
    if mail then mail.open:Show() end
end

----------------------------------------------------------------------
-- Destroying the cheapest grey stack: only from an explicit click, never automatically.
----------------------------------------------------------------------
function V.CheapestGray()
    local api, items = _G.C_Container, _G.C_Item
    if not api or not items then return nil end
    local rows = {}
    for bag = 0, 4 do
        for slot = 1, tonumber(A.Call(api.GetContainerNumSlots, bag)) or 0 do
            local info = A.Call(api.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.quality == 0 and info.hyperlink then
                local quest = A.Call(api.GetContainerItemQuestInfo, bag, slot)
                local isQuest = type(quest) == "table" and (quest.isQuestItem == true or quest.questID ~= nil)
                local price = info.hasNoValue and 0 or tonumber((select(11, A.Call(items.GetItemInfo, info.hyperlink)))) or 0
                rows[#rows + 1] = {bag = bag, slot = slot, link = info.hyperlink, item = info.itemID, count = info.stackCount or 1,
                    value = price * (info.stackCount or 1), locked = info.isLocked == true, quest = isQuest}
            end
        end
    end
    return L.CheapestGray(rows)
end

function V.Destroy(row)
    local api = _G.C_Container
    if not api or not row or A.Combat() then return false end
    if A.Call(GetCursorInfo) ~= nil then return false end
    -- The stack must still be the one that was shown.
    local info = A.Call(api.GetContainerItemInfo, row.bag, row.slot)
    if type(info) ~= "table" or info.hyperlink ~= row.link or info.isLocked or (info.stackCount or 1) ~= row.count then return false end
    A.Call(api.PickupContainerItem, row.bag, row.slot)
    local kind, id = A.Call(GetCursorInfo)
    if kind ~= "item" or (row.item and id ~= row.item) then
        A.Call(ClearCursor)
        return false
    end
    A.Call(DeleteCursorItem)
    A.Print(string.format(tr("Zerstört: %s (%s)", "Destroyed: %s (%s)"), row.link, A.Money(row.value)))
    return true
end

local function confirmFrame()
    if V.confirm then return V.confirm end
    local f = CreateFrame("Frame", "ZenialUtilityDestroyConfirm", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(380, 120)
    f:SetPoint("TOP", 0, -180)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    T.Panel(f, "surface")
    f.text = T.Text(f, "", "GameFontHighlight", "text")
    f.text:SetPoint("TOPLEFT", 16, -16)
    f.text:SetWidth(348)
    f.yes = T.Button(f, tr("Zerstören", "Destroy"), 140, 28, function()
        V.Destroy(f.row)
        f:Hide()
    end, "danger")
    f.yes:SetPoint("BOTTOMLEFT", 16, 14)
    f.no = T.Button(f, tr("Abbrechen", "Cancel"), 140, 28, function() f:Hide() end, "secondary")
    f.no:SetPoint("BOTTOMRIGHT", -16, 14)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "ZenialUtilityDestroyConfirm" end
    f:Hide()
    V.confirm = f
    return f
end

-- Called from a click only. Shows the question unless the player turned it off.
function V.RequestDestroy()
    if not on("destroyGray") or A.Combat() then return false end
    local row = V.CheapestGray()
    if not row then return false end
    if not db().destroyConfirm then return V.Destroy(row) end
    local f = confirmFrame()
    f.row = row
    f.text:SetText(string.format(tr("%s zerstören? Wert: %s", "Destroy %s? Value: %s"), row.link, A.Money(row.value)))
    f:Show()
    return true
end

----------------------------------------------------------------------
local listener = A.Listener({
    PLAYER_ENTERING_WORLD = function() V.UpdateXP() end,
    PLAYER_XP_UPDATE = V.UpdateXP,
    PLAYER_LEVEL_UP = V.UpdateXP,
    MAIL_SHOW = V.UpdateMailButton,
})

function V.SettingsChanged()
    local data = db()
    local any = data.modInventory and (data.xpText or data.xpPercent or data.mailAlts)
    listener:Set(any == true)
    if on("bagMove") then hookBags(); applyBagPosition() end
    V.UpdateXP()
    V.UpdateMailButton()
end
