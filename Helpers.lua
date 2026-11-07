local _, NS = ...
local H = {rolls = {}, sellQueue = nil, states = {}}
NS.Helpers = H
local A, L, tr = NS.Adapter, NS.Logic, NS.Text

local function db() return NS.App.db end
local function comfort(key) return db().modComfort and db()[key] end
local function warning(key) return db().modWarnings and db()[key] end
local function extra(key) return db().modExtras and db()[key] end
local function shiftHeld() return A.Call(IsShiftKeyDown) == true end

local function alert(message)
    A.Print(message)
    if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then pcall(_G.UIErrorsFrame.AddMessage, _G.UIErrorsFrame, message, 1, .82, .2) end
end

----------------------------------------------------------------------
-- Vendor: holding Shift when the window opens skips everything once.
----------------------------------------------------------------------
function H.JunkSlots()
    local api = _G.C_Container
    local out = {}
    if not api then return out end
    for bag = 0, 4 do
        for slot = 1, tonumber(A.Call(api.GetContainerNumSlots, bag)) or 0 do
            local info = A.Call(api.GetContainerItemInfo, bag, slot)
            -- Only grey items with a real sale value. Locked items stay untouched.
            if type(info) == "table" and info.quality == 0 and not info.hasNoValue and not info.isLocked then
                out[#out + 1] = {bag = bag, slot = slot, link = info.hyperlink, count = info.stackCount or 1}
            end
        end
    end
    return out
end

local function sellPrice(link)
    local api = _G.C_Item
    if not api or not link then return 0 end
    local price = select(11, A.Call(api.GetItemInfo, link))
    return tonumber(price) or 0
end

function H.Repair()
    H.repairWaiting = false
    if not comfort("vendorRepair") or A.Call(CanMerchantRepair) ~= true then return end
    local cost, needed = A.Call(GetRepairAllCost)
    cost = tonumber(cost) or 0
    if not needed or cost <= 0 then return end
    local guild = comfort("vendorGuildRepair") and A.Call(CanGuildBankRepair) == true
        and (tonumber(A.Call(GetGuildBankWithdrawMoney)) or 0) >= cost
    if guild then
        A.Call(RepairAllItems, true)
    elseif (tonumber(A.Call(GetMoney)) or 0) >= cost then
        A.Call(RepairAllItems)
    else
        -- Selling grey items often brings the missing gold, so the next gold change tries again.
        if db().vendorChat and not H.repairTold then A.Print(string.format(tr("Nicht genug Gold zum Reparieren (%s).", "Not enough gold to repair (%s)."), A.Money(cost))) end
        H.repairTold, H.repairWaiting = true, true
        return
    end
    if db().vendorChat then
        A.Print((guild and tr("Repariert aus der Gildenbank: ", "Repaired from the guild bank: ") or tr("Repariert: ", "Repaired: ")) .. A.Money(cost))
    end
end

function H.MerchantOpened()
    H.merchantOpen, H.repairTold = true, false
    if shiftHeld() then return end
    H.Repair()
    if comfort("vendorJunk") then
        local queue = H.JunkSlots()
        if #queue > 0 then
            H.sellQueue, H.sellTotal, H.sellCount, H.sellTimer, H.sellPass, H.sellSent = queue, 0, 0, 0, 1, {}
            NS.App:WakeTick()
        end
    end
end

function H.MerchantClosed()
    H.merchantOpen, H.repairWaiting = false, false
    H.FinishSale()
end

function H.MoneyChanged()
    if H.merchantOpen and H.repairWaiting then H.Repair() end
end

-- A sale counts once the slot no longer holds that stack, so a refused item is not reported as sold.
local function confirmSales()
    local api = _G.C_Container
    for _, row in ipairs(H.sellSent or {}) do
        local info = A.Call(api.GetContainerItemInfo, row.bag, row.slot)
        local still = type(info) == "table" and info.hyperlink == row.link and not info.isLocked
        if not still then
            H.sellCount = H.sellCount + 1
            H.sellTotal = H.sellTotal + row.value
        end
    end
    H.sellSent = {}
end

function H.FinishSale()
    if not H.sellQueue then return end
    H.sellQueue = nil
    confirmSales()
    if H.sellCount > 0 then
        local stats = db().sellStats
        stats.count = (tonumber(stats.count) or 0) + H.sellCount
        stats.total = (tonumber(stats.total) or 0) + H.sellTotal
        if db().vendorChat then
            A.Print(string.format(tr("%d graue Gegenstände verkauft: %s", "Sold %d grey items: %s"), H.sellCount, A.Money(H.sellTotal)))
        end
    end
end

-- One item per step, so the server keeps up and closing the window stops at once.
-- After the list is done the bags are read again: whatever is still there gets up to two more tries.
function H.SellStep(dt)
    if not H.sellQueue then return end
    H.sellTimer = H.sellTimer + dt
    if #H.sellQueue == 0 then
        if H.sellTimer < 1 then return end
        H.sellTimer = 0
        confirmSales()
        H.sellPass = H.sellPass + 1
        local again = H.sellPass <= 3 and H.JunkSlots() or {}
        if #again == 0 then H.FinishSale() else H.sellQueue = again end
        return
    end
    if H.sellTimer < .15 then return end
    H.sellTimer = 0
    local row = table.remove(H.sellQueue)
    local api = _G.C_Container
    local info = A.Call(api.GetContainerItemInfo, row.bag, row.slot)
    if type(info) == "table" and info.quality == 0 and info.hyperlink == row.link then
        H.sellSent[#H.sellSent + 1] = {bag = row.bag, slot = row.slot, link = row.link, value = sellPrice(row.link) * (info.stackCount or 1)}
        A.Call(api.UseContainerItem, row.bag, row.slot)
    end
end

----------------------------------------------------------------------
-- Quests: never picks between rewards and never pays gold for a quest.
----------------------------------------------------------------------

-- One conversation: each quest is answered once per step, whatever events the dialog repeats.
local function once(step, questID)
    local npc = A.Call(UnitGUID, "npc")
    local now = tonumber(A.Call(GetTime)) or 0
    if npc ~= H.questNpc or not H.questAt or now - H.questAt > 30 then H.questSeen = {} end
    H.questNpc, H.questAt = npc, now
    if not questID then return true end
    local key = step .. ":" .. questID
    if H.questSeen[key] then return false end
    H.questSeen[key] = true
    return true
end

local function bandAllowed(level, trivial)
    local playerLevel = A.Call(UnitLevel, "player")
    return L.QuestBandAllowed(db().questDifficulty, L.QuestBand(level, playerLevel, trivial))
end

local function detailAllowed(questID)
    local api = _G.C_QuestLog
    if not questID or not api then return true end
    return bandAllowed(A.Call(api.GetQuestDifficultyLevel, questID), A.Call(api.IsQuestTrivial, questID))
end

-- A confirmed turn-in ends the block for this quest, so a repeatable one can run again at once.
function H.QuestTurnedIn(questID)
    if not questID or not H.questSeen then return end
    local suffix = ":" .. questID
    for key in pairs(H.questSeen) do
        if key:sub(-#suffix) == suffix then H.questSeen[key] = nil end
    end
end

function H.QuestEvent(event)
    if shiftHeld() then return end
    local questID = A.Call(GetQuestID)
    if event == "QUEST_DETAIL" then
        if comfort("questAccept") and detailAllowed(questID) and once("accept", questID) then A.Call(AcceptQuest) end
    elseif event == "QUEST_PROGRESS" then
        if comfort("questTurnIn") and A.Call(IsQuestCompletable) == true and (tonumber(A.Call(GetQuestMoneyToGet)) or 0) == 0 and once("progress", questID) then A.Call(CompleteQuest) end
    elseif event == "QUEST_COMPLETE" then
        if comfort("questTurnIn") and (tonumber(A.Call(GetNumQuestChoices)) or 0) <= 1 and (tonumber(A.Call(GetQuestMoneyToGet)) or 0) == 0 and once("reward", questID) then A.Call(GetQuestReward, 1) end
    elseif event == "GOSSIP_SHOW" then
        H.GossipQuests()
    elseif event == "QUEST_GREETING" then
        H.GreetingQuests()
    end
end

function H.GossipQuests()
    local api = _G.C_GossipInfo
    if not api then return end
    if comfort("questTurnIn") then
        for _, quest in ipairs(A.Call(api.GetActiveQuests) or {}) do
            if quest.isComplete and once("select", quest.questID) then A.Call(api.SelectActiveQuest, quest.questID); return end
        end
    end
    if comfort("questAccept") then
        for _, quest in ipairs(A.Call(api.GetAvailableQuests) or {}) do
            local repeatOk = db().questRepeatable or not quest.repeatable
            if repeatOk and bandAllowed(quest.questLevel, quest.isTrivial) and once("offer", quest.questID) then
                A.Call(api.SelectAvailableQuest, quest.questID)
                return
            end
        end
    end
end

function H.GreetingQuests()
    if comfort("questTurnIn") then
        for index = 1, tonumber(A.Call(GetNumActiveQuests)) or 0 do
            local title, complete = A.Call(GetActiveTitle, index)
            -- By quest and not by line: the list moves up after each turn-in.
            local key = A.Call(GetActiveQuestID, index) or title or ("active" .. index)
            if complete and once("select", key) then A.Call(SelectActiveQuest, index); return end
        end
    end
    if comfort("questAccept") then
        for index = 1, tonumber(A.Call(GetNumAvailableQuests)) or 0 do
            local trivial, _, repeatable, _, questID = A.Call(GetAvailableQuestInfo, index)
            local repeatOk = db().questRepeatable or repeatable ~= true
            if repeatOk and bandAllowed(A.Call(GetAvailableLevel, index), trivial) and once("offer", questID or ("greeting" .. index)) then
                A.Call(SelectAvailableQuest, index)
                return
            end
        end
    end
end

----------------------------------------------------------------------
-- Warnings fire once when a value crosses its limit, and re-arm after it recovers.
----------------------------------------------------------------------
local function crossing(key, low, message)
    local was = H.states[key]
    H.states[key] = low
    if low and not was then
        alert(message)
        -- The game's raid warning sound, only if asked for.
        if db().warnSound then A.PlaySound(8959) end
    end
    if low ~= was and NS.Reminders then NS.Reminders.Invalidate() end
end

-- Lowest durability plus every damaged slot, lowest first.
function H.DurabilityInfo()
    local lowest, rows = nil, {}
    for slot = 1, 18 do
        local current, maximum = A.Call(GetInventoryItemDurability, slot)
        if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
            local percent = current / maximum * 100
            if not lowest or percent < lowest then lowest = percent end
            if percent < 100 then rows[#rows + 1] = {slot = slot, percent = percent} end
        end
    end
    table.sort(rows, function(a, b) return a.percent < b.percent end)
    return lowest, rows
end

function H.CheckDurability()
    if not warning("warnDurability") then H.states.durability = nil; return end
    local lowest, rows = H.DurabilityInfo()
    if not lowest then return end
    local name
    if rows[1] then
        local link = A.Call(GetInventoryItemLink, "player", rows[1].slot)
        if type(link) == "string" then name = link end
    end
    crossing("durability", lowest <= db().durabilityPercent,
        string.format(tr("Ausrüstung bei %d %% Haltbarkeit.", "Equipment at %d%% durability."), math.floor(lowest + .5)) .. (name and (" " .. name) or ""))
end

function H.CheckBags()
    if not warning("warnBags") then H.states.bags = nil; return end
    local api = _G.C_Container
    if not api then return end
    local free = 0
    for bag = 0, 4 do
        local count, family = A.Call(api.GetContainerNumFreeSlots, bag)
        if family == 0 or family == nil then free = free + (tonumber(count) or 0) end
    end
    crossing("bags", free <= db().bagSlots, string.format(tr("Nur noch %d freie Taschenplätze.", "Only %d free bag slots left."), free))
end

-- Item class 2 (weapon): bow, gun and crossbow fire ammo.
local AMMO_WEAPONS = {[2] = true, [3] = true, [18] = true}
local function firesAmmo()
    local api = _G.C_Item
    local weapon = A.Call(GetInventoryItemID, "player", 18)
    if not api or not weapon then return false end
    local _, _, _, _, _, classID, subclassID = A.Call(api.GetItemInfoInstant, weapon)
    return classID == 2 and AMMO_WEAPONS[subclassID] == true
end

function H.CheckAmmo()
    if not warning("warnAmmo") or not firesAmmo() then H.states.ammo = nil; H.ammoCount = nil; return end
    -- An empty ammo slot reports item 0 with a count of 1 on this client.
    local equipped = 0
    if (tonumber(A.Call(GetInventoryItemID, "player", 0)) or 0) > 0 then
        equipped = tonumber(A.Call(GetInventoryItemCount, "player", 0)) or 0
    end
    -- All matching ammo in the bags counts, not only the kind in the ammo slot.
    local count = math.max(equipped, NS.AutoBuy.AmmoInBags(NS.AutoBuy.ProjectileClass()))
    if count <= 0 then H.states.ammo = nil; H.ammoCount = nil; return end
    H.ammoCount = count
    crossing("ammo", count <= db().ammoThreshold, string.format(tr("Nur noch %d Schuss Munition.", "Only %d rounds of ammo left."), count))
end

-- Only warns about a poison that was on the weapon before, so nobody without poisons is nagged.
function H.CheckPoison()
    if not warning("warnPoison") or A.PlayerClass() ~= "ROGUE" then H.states.poison = nil; return end
    local main, off = A.WeaponEnchant(16), A.WeaponEnchant(17)
    -- Unreadable says nothing: the last known state stands.
    if main == nil and off == nil then return end
    local active = main == true or off == true
    if H.states.poisonActive and not active then alert(tr("Dein Waffengift ist abgelaufen.", "Your weapon poison has worn off.")) end
    H.states.poisonActive = active
end

-- Warns only when a stack you actually carried runs low, because Forever may not need every reagent.
H.Reagents = {
    MAGE = {17020, 17031, 17032}, PRIEST = {17056}, PALADIN = {21177}, SHAMAN = {17030}, WARLOCK = {6265}, DRUID = {17034},
}
function H.CheckReagents()
    if not warning("warnReagents") then H.states.reagents = nil; return end
    local api = _G.C_Item
    local list = H.Reagents[A.PlayerClass()]
    if not api or not list then return end
    H.states.reagents = H.states.reagents or {}
    for _, item in ipairs(list) do
        local count = tonumber(A.Call(api.GetItemCount, item)) or 0
        local before = H.states.reagents[item]
        H.states.reagents[item] = count
        if before and before > 5 and count <= 5 then
            local name = A.Call(api.GetItemNameByID, item) or tr("Reagenz", "Reagent")
            alert(string.format(tr("Nur noch %d × %s.", "Only %d × %s left."), count, name))
        end
    end
end

function H.CheckAll()
    H.CheckDurability(); H.CheckBags(); H.CheckAmmo(); H.CheckReagents()
end

----------------------------------------------------------------------
-- Screenshots
----------------------------------------------------------------------
function H.ScheduleScreenshot()
    local now = A.Call(GetTime) or 0
    if H.lastShot and now - H.lastShot < 5 then return end
    H.lastShot, H.shotTimer = now, 1.5
    NS.App:WakeTick()
end

function H.ShotStep(dt)
    if not H.shotTimer then return end
    H.shotTimer = H.shotTimer - dt
    if H.shotTimer <= 0 then
        H.shotTimer = nil
        A.Call(Screenshot)
    end
end

----------------------------------------------------------------------
-- /played per character. The value only updates when the game reports it.
----------------------------------------------------------------------
function H.TimePlayed(total, level)
    local scope = A.Scope()
    if not scope or type(total) ~= "number" then return end
    db().played[scope] = {total = total, level = tonumber(level) or 0, class = A.PlayerClass(), at = A.Call(GetServerTime)}
    if NS.SettingsUI then NS.SettingsUI.RefreshData() end
end

function H.PlayedRows()
    local rows, sum = {}, 0
    for scope, row in pairs(db().played) do
        rows[#rows + 1] = {scope = scope, total = row.total or 0, class = row.class}
        sum = sum + (row.total or 0)
    end
    table.sort(rows, function(a, b) return a.total > b.total end)
    return rows, sum
end

----------------------------------------------------------------------
-- Tooltips
----------------------------------------------------------------------
-- The game shows the sell price itself; Utility only adds the IDs.
local function addItemLines(tooltip, item)
    if not tooltip or not tooltip.AddLine then return end
    if extra("tooltipIDs") and item then tooltip:AddLine(tr("Item-ID: ", "Item ID: ") .. item, .65, .61, .52) end
end

function H.AttachTooltips()
    if H.tooltipsAttached then return end
    local processor = _G.TooltipDataProcessor
    local kinds = _G.Enum and _G.Enum.TooltipDataType
    if processor and kinds and kinds.Item and type(processor.AddTooltipPostCall) == "function" then
        H.tooltipsAttached = true
        processor.AddTooltipPostCall(kinds.Item, function(tooltip, data)
            if not A.Public(data) or type(data) ~= "table" or not A.Public(data.id) then return end
            pcall(addItemLines, tooltip, data.id)
        end)
        if kinds.Spell then
            processor.AddTooltipPostCall(kinds.Spell, function(tooltip, data)
                if not A.Public(data) or type(data) ~= "table" or not A.Public(data.id) or not extra("tooltipIDs") then return end
                pcall(tooltip.AddLine, tooltip, tr("Zauber-ID: ", "Spell ID: ") .. tostring(data.id), .65, .61, .52)
            end)
        end
    elseif _G.GameTooltip and _G.GameTooltip.HookScript then
        H.tooltipsAttached = true
        pcall(_G.GameTooltip.HookScript, _G.GameTooltip, "OnTooltipSetItem", function(tooltip)
            local _, link = A.Call(tooltip.GetItem, tooltip)
            local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
            pcall(addItemLines, tooltip, item)
        end)
    end
end

----------------------------------------------------------------------
local function groupChannel()
    if A.Call(IsInRaid) == true then return "RAID" end
    if A.Call(IsInGroup) == true then return "PARTY" end
end

----------------------------------------------------------------------
-- Roll tracker: reads /roll system lines through the client's own localized text.
----------------------------------------------------------------------
-- Need and Greed results arrive as loot messages and never pass through here.
local function baseName(name) return type(name) == "string" and (name:gsub("%-.*$", "")) or nil end

function H.IsOwnName(name)
    local own = A.Call(UnitName, "player")
    return type(own) == "string" and (name == own or baseName(name) == own)
end

-- Nearby players outside the group also produce roll lines; they are not part of the round.
function H.IsGroupMember(name)
    if A.Call(IsInGroup) ~= true then return false end
    for _, unit in ipairs(A.GroupUnits()) do
        local unitName, realm = A.Call(UnitName, unit)
        if type(unitName) == "string" then
            if name == unitName then return true end
            if type(realm) == "string" and realm ~= "" and name == unitName .. "-" .. realm then return true end
        end
    end
    return false
end

function H.SystemMessage(message)
    -- During an encounter lockdown the line is a protected value and cannot be read.
    if not extra("rollTracker") or type(message) ~= "string" or not A.Public(message) then return end
    H.rollPattern = H.rollPattern or L.RollPattern(_G.RANDOM_ROLL_RESULT)
    local row = L.ParseRoll(message, H.rollPattern)
    if not row then return end
    local own = H.IsOwnName(row.name)
    if not own and not H.IsGroupMember(row.name) then return end
    local now = tonumber(A.Call(GetTime)) or 0
    local fresh = #H.rolls == 0 or (H.rollLast and now - H.rollLast > L.RollRoundGap)
    if fresh then
        H.rolls = {}
        H.rollStart = A.Call(date, "%H:%M:%S")
    end
    H.rollLast = now
    row.own = own
    -- An own line may carry the realm; the round knows the player once.
    if own then row.name = A.Call(UnitName, "player") or row.name end
    L.AddRoll(H.rolls, row)
    if NS.SettingsUI then NS.SettingsUI.RefreshData() end
    -- Opens on an own roll and on the first roll of a round; later rolls update an open window.
    if NS.RollWindow then NS.RollWindow.Update(own or fresh) end
end

function H.ClearRolls()
    H.rolls = {}
    H.rollStart, H.rollLast = nil, nil
    if NS.SettingsUI then NS.SettingsUI.RefreshData() end
    if NS.RollWindow then NS.RollWindow.Update(false) end
end

function H.RollWinners() return L.RollWinners(H.rolls) end

-- All rolls, highest first, with the time of the round's first roll.
function H.AnnounceRolls()
    local channel = groupChannel()
    if #H.rolls == 0 or not channel then return false end
    local header = string.format(tr("Würfe (Start %s):", "Rolls (started %s):"), H.rollStart or "?")
    for _, line in ipairs(L.RollAnnouncement(H.rolls, header)) do
        A.Call(SendChatMessage, line, channel)
    end
    return true
end

function H.AnnounceWinner()
    local winners, channel = L.RollWinners(H.rolls), groupChannel()
    if #winners == 0 or not channel then return false end
    local names = {}
    for _, row in ipairs(winners) do names[#names + 1] = row.name end
    local text = #winners > 1
        and string.format(tr("Gleichstand mit %d: %s", "Tie at %d: %s"), winners[1].roll, table.concat(names, ", "))
        or string.format(tr("Höchster Wurf: %s mit %d", "Highest roll: %s with %d"), names[1], winners[1].roll)
    A.Call(SendChatMessage, text, channel)
    return true
end

----------------------------------------------------------------------
function H.Tick(dt)
    H.SellStep(dt); H.ShotStep(dt)
    if H.PollsPoison() then
        H.slow = (H.slow or 0) + dt
        if H.slow >= 5 then H.slow = 0; H.CheckPoison() end
    end
end

-- The weapon enchant has no dependable event, so only a rogue with the warning on keeps polling.
function H.PollsPoison() return warning("warnPoison") and A.PlayerClass() == "ROGUE" end

function H.Busy()
    return H.sellQueue ~= nil or H.shotTimer ~= nil or H.PollsPoison()
end

function H.Event(event, ...)
    if event == "MERCHANT_SHOW" then H.MerchantOpened()
    elseif event == "PLAYER_MONEY" then H.MoneyChanged()
    elseif event == "QUEST_TURNED_IN" then H.QuestTurnedIn(...)
    elseif event == "MERCHANT_CLOSED" then H.MerchantClosed()
    elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" or event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then H.QuestEvent(event)
    elseif event == "UPDATE_INVENTORY_DURABILITY" then H.CheckDurability()
    elseif event == "BAG_UPDATE_DELAYED" then H.CheckBags(); H.CheckReagents(); H.CheckAmmo()
    elseif event == "UNIT_INVENTORY_CHANGED" then if ... == "player" then H.CheckAmmo() end
    elseif event == "PLAYER_LEVEL_UP" then if extra("screenshotLevel") then H.ScheduleScreenshot() end
    elseif event == "BOSS_KILL" then if extra("screenshotBoss") then H.ScheduleScreenshot() end
    elseif event == "ENCOUNTER_END" then
        local success = select(5, ...)
        if success == 1 and extra("screenshotBoss") then H.ScheduleScreenshot() end
    elseif event == "TIME_PLAYED_MSG" then H.TimePlayed(...)
    elseif event == "CHAT_MSG_SYSTEM" then H.SystemMessage(...)
    end
end
