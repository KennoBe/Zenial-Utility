local _, NS = ...
local B = {}
NS.AutoBuy = B
local A, L, T, tr, D = NS.Adapter, NS.Logic, NS.Theme, NS.Text, NS.ReagentData

local STEP, ROWS, SETTLE = .25, 8, 2
local BOW_SUBCLASSES = {[2] = 2, [18] = 2, [3] = 3} -- weapon subclass to projectile subclass: arrows 2, bullets 3
local PROJECTILE_CLASS = 6

function B.Settings() return NS.Characters.Data("autoBuy") end

local function targets()
    local data = B.Settings()
    data.targets = type(data.targets) == "table" and data.targets or {}
    return data.targets
end

function B.GetTarget(item) return tonumber(targets()[item]) or 0 end

function B.SetTarget(item, value)
    value = math.max(0, math.min(5000, math.floor(tonumber(value) or 0)))
    targets()[item] = value > 0 and value or nil
end

local function isKnown(row)
    if row.poison then return A.SpellKnown(2842) end
    if not row.spells then return true end
    for _, spell in ipairs(row.spells) do
        if A.SpellKnown(spell) then return true end
    end
    return false
end

-- True when Forever's Reagent Economy talent is learned. Only read through IsPlayerSpell;
-- whether the client reports a Legacy talent that way still has to be confirmed in game.
function B.HasReagentEconomy()
    return A.Call(IsPlayerSpell, D.reagentEconomySpell) == true
end

-- The class rows that matter to this character right now.
function B.Catalog()
    local out, economy = {}, B.HasReagentEconomy()
    for _, row in ipairs(D.classes[A.PlayerClass()] or {}) do
        if isKnown(row) and not (economy and row.economy) then out[#out + 1] = row end
    end
    return out
end

function B.ProjectileClass()
    local api = _G.C_Item
    local weapon = A.Call(GetInventoryItemID, "player", 18)
    if not api or not weapon then return nil end
    local _, _, _, _, _, classID, subclassID = A.Call(api.GetItemInfoInstant, weapon)
    return classID == 2 and BOW_SUBCLASSES[subclassID] or nil
end

-- Reads the merchant's list once per window or list update.
function B.Scan()
    local stock, ammo = {}, {}
    local info = _G.C_MerchantFrame
    if not info then return stock, ammo end
    local projectile = B.ProjectileClass()
    for index = 1, tonumber(A.Call(GetMerchantNumItems)) or 0 do
        local item = A.Call(GetMerchantItemID, index)
        local row = A.Call(info.GetItemInfo, index)
        if item and type(row) == "table" and row.isPurchasable ~= false then
            local offer = {index = index, item = item, name = row.name, icon = row.texture, price = row.price or 0,
                stack = row.stackCount or 1, available = row.numAvailable,
                hasCost = row.hasExtendedCost == true or (row.currencyID or 0) > 0, usable = row.isUsable ~= false}
            stock[item] = offer
            if projectile and _G.C_Item then
                local _, _, _, _, _, classID, subclassID = A.Call(_G.C_Item.GetItemInfoInstant, item)
                if classID == PROJECTILE_CLASS and subclassID == projectile and offer.usable then ammo[#ammo + 1] = offer end
            end
        end
    end
    table.sort(ammo, function(a, b) return (a.price / a.stack) > (b.price / b.stack) end)
    return stock, ammo
end

-- Ammo of the right kind across all bags, because one fight can use any of it.
function B.AmmoInBags(projectile)
    local api, items = _G.C_Container, _G.C_Item
    if not api or not items or not projectile then return 0 end
    local total = 0
    for bag = 0, 4 do
        for slot = 1, tonumber(A.Call(api.GetContainerNumSlots, bag)) or 0 do
            local info = A.Call(api.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID then
                local _, _, _, _, _, classID, subclassID = A.Call(items.GetItemInfoInstant, info.itemID)
                if classID == PROJECTILE_CLASS and subclassID == projectile then total = total + (info.stackCount or 1) end
            end
        end
    end
    return total
end

local function finishedPoisons()
    local total = 0
    for _, item in ipairs(D.finishedPoisons) do total = total + A.ItemCount(item) end
    return total
end

-- The plan for this merchant: only rows with a target, sold here and not already covered.
function B.BuildPlan(stock, ammo)
    local data = B.Settings()
    local wanted, have = {}, {}
    local enough = (tonumber(data.poisonStop) or 0) > 0 and finishedPoisons() >= data.poisonStop
    for _, row in ipairs(B.Catalog()) do
        local target = B.GetTarget(row.item)
        if target > 0 and not (row.poison and enough) then
            wanted[#wanted + 1] = {item = row.item, target = target}
            have[row.item] = A.ItemCount(row.item)
        end
    end
    local ammoTarget = tonumber(data.ammoTarget) or 0
    if ammoTarget > 0 and ammo and ammo[1] then
        wanted[#wanted + 1] = {item = ammo[1].item, target = ammoTarget}
        have[ammo[1].item] = B.AmmoInBags(B.ProjectileClass())
    end
    return L.PurchasePlan(wanted, stock, have, B.Budget(), 0)
end

-- What may still be spent: the gold there is, and what the limit per visit leaves of it.
function B.Budget()
    local money = tonumber(A.Call(GetMoney)) or 0
    local limit = (tonumber(B.Settings().maxCost) or 0) * 10000
    if limit <= 0 then return money end
    return math.min(money, math.max(0, limit - (B.visitSpent or 0)))
end

----------------------------------------------------------------------
-- Buying: one vendor stack step at a time, and it stops the moment the window closes.
----------------------------------------------------------------------
local runner = CreateFrame("Frame")
B.runner = runner

local function stop(report)
    runner:SetScript("OnUpdate", nil)
    local job = B.job
    B.job = nil
    B.settleUntil = (tonumber(A.Call(GetTime)) or 0) + SETTLE
    if report and job and job.spent > 0 then
        A.Print(string.format(tr("Eingekauft für %s.", "Bought for %s."), A.Money(job.spent)))
    end
    B.Refresh()
end

local function step()
    local job = B.job
    local row = job and job.rows[1]
    if not row then stop(true); return end
    -- The list can change while buying: the same line must still be the same item.
    if A.Call(GetMerchantItemID, row.index) ~= row.item then
        table.remove(job.rows, 1)
        return
    end
    local maxStack = tonumber(A.Call(GetMerchantItemMaxStack, row.index)) or row.quantity
    local quantity = math.min(row.quantity, math.max(row.stack, maxStack - maxStack % row.stack))
    local price = row.cost * quantity / math.max(1, row.fullQuantity)
    if (tonumber(A.Call(GetMoney)) or 0) < price then stop(true); return end
    A.Call(BuyMerchantItem, row.index, quantity)
    job.spent = job.spent + price
    B.visitSpent = (B.visitSpent or 0) + price
    row.quantity = row.quantity - quantity
    if row.quantity <= 0 then table.remove(job.rows, 1) end
end

function B.Execute(plan)
    if B.job or not plan or #plan == 0 then return false end
    if B.settleUntil and (tonumber(A.Call(GetTime)) or 0) < B.settleUntil then return false end
    local rows = {}
    for _, row in ipairs(plan) do
        rows[#rows + 1] = {item = row.item, index = row.index, quantity = row.quantity, fullQuantity = row.quantity, stack = row.stack, cost = row.cost}
    end
    B.job = {rows = rows, spent = 0}
    local elapsed = STEP
    runner:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < STEP then return end
        elapsed = 0
        step()
    end)
    return true
end

----------------------------------------------------------------------
-- Panel beside the merchant window. Prices are shown before anything is bought.
----------------------------------------------------------------------
local function createPanel()
    local parent = _G.MerchantFrame
    if not parent then return nil end
    local f = CreateFrame("Frame", "ZenialUtilityAutoBuy", parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(250, 120)
    f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
    f:EnableMouse(true)
    T.Panel(f, "surface")
    local title = T.Text(f, tr("Nachkaufen", "Restock"), "GameFontNormal", "gold")
    title:SetPoint("TOPLEFT", 12, -10)
    f.rows = {}
    for index = 1, ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(226, 20)
        row:SetPoint("TOPLEFT", 12, -30 - (index - 1) * 21)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT")
        row.name = T.Text(row, "", "GameFontHighlightSmall", "text")
        row.name:SetPoint("LEFT", 24, 0)
        row.name:SetWidth(112)
        row.name:SetWordWrap(false)
        row.cost = T.Text(row, "", "GameFontHighlightSmall", "text")
        row.cost:SetPoint("RIGHT")
        row.cost:SetJustifyH("RIGHT")
        row:Hide()
        f.rows[index] = row
    end
    f.total = T.Text(f, "", "GameFontHighlightSmall", "text")
    f.total:SetWidth(226)
    f.buy = T.Button(f, tr("Alles kaufen", "Buy all"), 226, 26, function() B.BuyNow() end, "primary")
    f.fill = T.Button(f, "", 226, 24, function() B.FillQuiver() end, "secondary")
    f.note = T.Text(f, "", "GameFontHighlightSmall", "muted")
    f.note:SetWidth(226)
    f:Hide()
    return f
end

-- Stacks that fit into the free slots of a quiver or ammo pouch.
function B.QuiverSpace(stackSize, projectile)
    local api = _G.C_Container
    if not api then return 0 end
    -- Bag family: 1 = quiver for arrows, 2 = ammo pouch for bullets.
    local wanted = projectile == 2 and 1 or projectile == 3 and 2 or nil
    local free = 0
    for bag = 1, 4 do
        local count, family = A.Call(api.GetContainerNumFreeSlots, bag)
        if wanted and family == wanted then free = free + (tonumber(count) or 0) end
    end
    return free * (tonumber(stackSize) or 0)
end

function B.FillQuiver()
    local offer = B.ammo and B.ammo[1]
    if not offer then return false end
    local itemStack = 200
    if _G.C_Item then itemStack = tonumber((select(8, A.Call(_G.C_Item.GetItemInfo, offer.item)))) or itemStack end
    local space = B.QuiverSpace(itemStack, B.ProjectileClass())
    if space <= 0 then
        A.Print(tr("Köcher oder Munitionsbeutel haben keinen freien Platz.", "Your quiver or ammo pouch has no free space."))
        return false
    end
    local plan = L.PurchasePlan({{item = offer.item, target = space}}, {[offer.item] = offer}, {}, B.Budget(), 0)
    if #plan == 0 then
        A.Print(tr("Das Gold oder dein Limit reicht dafür nicht.", "Your gold or your limit does not cover this."))
        return false
    end
    return B.Execute(plan)
end

function B.BuyNow()
    local plan = B.plan
    if not plan or #plan == 0 then return false end
    return B.Execute(plan)
end

function B.Refresh()
    if not B.merchantOpen or B.Settings().enabled ~= true then
        if B.panel then B.panel:Hide() end
        return
    end
    B.stock, B.ammo = B.Scan()
    B.plan, B.total, B.skipped = B.BuildPlan(B.stock, B.ammo)
    if #B.plan == 0 and #B.skipped == 0 and not (B.ammo and B.ammo[1]) then
        if B.panel then B.panel:Hide() end
        return
    end
    B.panel = B.panel or createPanel()
    local f = B.panel
    if not f then return end
    local shown = 0
    for index, row in ipairs(f.rows) do
        local data = B.plan[index]
        if data then
            shown = index
            row.icon:SetTexture(data.icon)
            row.name:SetText(data.quantity .. " × " .. (data.name or data.item))
            row.cost:SetText(A.Money(data.cost))
            row:Show()
        else
            row:Hide()
        end
    end
    local y = -34 - shown * 21
    f.total:ClearAllPoints()
    f.total:SetPoint("TOPLEFT", 12, y)
    f.total:SetText(#B.plan > 0 and (tr("Gesamt: ", "Total: ") .. A.Money(B.total)) or tr("Vorrat reicht.", "Stock is sufficient."))
    y = y - 22
    f.buy:ClearAllPoints()
    f.buy:SetPoint("TOPLEFT", 12, y)
    f.buy:SetShown(#B.plan > 0)
    f.buy:SetEnabled(not B.job)
    if #B.plan > 0 then y = y - 30 end
    local offer = B.ammo and B.ammo[1]
    f.fill:ClearAllPoints()
    f.fill:SetPoint("TOPLEFT", 12, y)
    f.fill:SetShown(offer ~= nil)
    if offer then
        f.fill:SetText(string.format(tr("Köcher füllen: %s", "Fill quiver: %s"), offer.name or offer.item))
        f.fill:SetEnabled(not B.job)
        y = y - 28
    end
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", 12, y)
    f.note:SetText(#B.skipped > 0 and string.format(tr("%d Posten über deinem Limit ausgelassen.", "%d items left out, over your limit."), #B.skipped) or "")
    f:SetHeight(-y + (#B.skipped > 0 and 34 or 12))
    f:Show()
end

function B.MerchantOpened()
    B.merchantOpen, B.visitSpent = true, 0
    local data = B.Settings()
    if data.enabled ~= true then return end
    B.Refresh()
    -- Without the confirmation setting the plan runs by itself, but only if automation is on,
    -- and every limit still applied when the plan was made.
    if data.auto == true and data.confirm == false and not A.Shift() and B.plan and #B.plan > 0 then B.Execute(B.plan) end
end

function B.MerchantClosed()
    B.merchantOpen = false
    if B.job then stop(true) end
    if B.panel then B.panel:Hide() end
end

local listener = A.Listener({
    MERCHANT_SHOW = B.MerchantOpened,
    MERCHANT_CLOSED = B.MerchantClosed,
    MERCHANT_UPDATE = function() if B.merchantOpen and not B.job then B.Refresh() end end,
    BAG_UPDATE_DELAYED = function() if B.merchantOpen and not B.job then B.Refresh() end end,
})

function B.SettingsChanged()
    listener:Set(B.Settings().enabled == true)
    if B.merchantOpen then B.Refresh() end
end
