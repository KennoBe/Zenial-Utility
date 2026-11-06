local _, NS = ...
local Q = {}
NS.Quests = Q
local A, T, tr = NS.Adapter, NS.Theme, NS.Text

local function db() return NS.App.db end

----------------------------------------------------------------------
-- Reward values on the buttons of quest and quest log details. Purely a display.
----------------------------------------------------------------------
local function rewardLink(button, inLog)
    local kind, index = button.type, button:GetID()
    if inLog then return A.Call(GetQuestLogItemLink, kind, index) end
    return A.Call(GetQuestItemLink, kind, index)
end

function Q.UpdateRewardValues()
    local frame = _G.QuestInfoFrame
    local rewards = frame and frame.rewardsFrame
    local buttons = rewards and rewards.RewardButtons
    if type(buttons) ~= "table" then return end
    local on = db() and db().modComfort and db().questRewardValue
    local api = _G.C_Item
    for _, button in ipairs(buttons) do
        if button.zenialValue then button.zenialValue:Hide() end
        if on and api and button:IsShown() and button.objectType == "item" then
            local link = rewardLink(button, frame.questLog)
            local price = link and tonumber((select(11, A.Call(api.GetItemInfo, link))))
            if price and price > 0 then
                local count = math.max(1, tonumber(button.count) or 1)
                if not button.zenialValue then
                    button.zenialValue = T.Text(button, "", "GameFontHighlightSmall", "text")
                    button.zenialValue:SetPoint("BOTTOMRIGHT", -6, 4)
                    button.zenialValue:SetJustifyH("RIGHT")
                end
                button.zenialValue:SetText(A.Money(price * count))
                button.zenialValue:Show()
            end
        end
    end
end

----------------------------------------------------------------------
-- Zone checkbox in the quest log: track or untrack everything below one header.
-- Quests of a collapsed zone stay in the log's list, so collapsed zones work the same.
----------------------------------------------------------------------
function Q.ZoneQuests(headerIndex)
    local api = _G.C_QuestLog
    local out = {}
    if not api then return out end
    local total = tonumber(A.Call(api.GetNumQuestLogEntries)) or 0
    for index = headerIndex + 1, total do
        local info = A.Call(api.GetInfo, index)
        if type(info) ~= "table" or info.isHeader then break end
        if info.questID and not info.isHidden and not info.isTask and not info.isBounty then out[#out + 1] = info.questID end
    end
    return out
end

local function isWatched(questID)
    local api = _G.C_QuestLog
    return A.Call(api.GetQuestWatchType, questID) ~= nil
end

function Q.ZoneState(headerIndex)
    local quests, watched = Q.ZoneQuests(headerIndex), 0
    for _, questID in ipairs(quests) do
        if isWatched(questID) then watched = watched + 1 end
    end
    return #quests > 0 and watched == #quests, #quests
end

local function watchLimit()
    local consts = _G.Constants and _G.Constants.QuestWatchConsts
    return consts and tonumber(consts.MAX_QUEST_WATCHES) or 25
end

-- Stops at the tracker's limit and says so. Returns how many changed.
function Q.SetZoneTracked(headerIndex, tracked)
    local api = _G.C_QuestLog
    if not api then return 0 end
    local changed = 0
    for _, questID in ipairs(Q.ZoneQuests(headerIndex)) do
        local watching = isWatched(questID)
        if tracked and not watching then
            if (tonumber(A.Call(api.GetNumQuestWatches)) or 0) >= watchLimit() then
                A.Print(string.format(tr("Die Questverfolgung ist voll (%d).", "The quest tracker is full (%d)."), watchLimit()))
                break
            end
            A.Call(api.AddQuestWatch, questID)
            changed = changed + 1
        elseif not tracked and watching then
            A.Call(api.RemoveQuestWatch, questID)
            changed = changed + 1
        end
    end
    return changed
end

local function headerCheck(header)
    if header.zenialCheck then return header.zenialCheck end
    local check = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
    check:SetSize(18, 18)
    check:SetPoint("RIGHT", -2, 0)
    T.StyleCheckbox(check)
    check:SetScript("OnClick", function(self)
        Q.SetZoneTracked(header.questLogIndex, self:GetChecked() == true)
        Q.UpdateZoneChecks()
    end)
    NS.Widgets.Tooltip(check, tr("Gebiet verfolgen", "Track zone"),
        tr("Verfolgt alle Quests dieses Gebiets oder entfernt sie wieder.", "Tracks all quests of this zone or removes them again."))
    header.zenialCheck = check
    return check
end

function Q.UpdateZoneChecks()
    local scroll = _G.QuestScrollFrame
    local pool = scroll and scroll.headerFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return end
    local on = db() and db().modComfort and db().questZoneTrack
    for header in pool:EnumerateActive() do
        if on and header.questLogIndex then
            local check = headerCheck(header)
            local all, count = Q.ZoneState(header.questLogIndex)
            check:SetChecked(all)
            check:SetShown(count > 0)
        elseif header.zenialCheck then
            header.zenialCheck:Hide()
        end
    end
end

----------------------------------------------------------------------
function Q.SettingsChanged()
    local data = db()
    if type(hooksecurefunc) == "function" then
        if not Q.rewardHook and data.questRewardValue and type(_G.QuestInfo_Display) == "function" then
            Q.rewardHook = true
            hooksecurefunc("QuestInfo_Display", Q.UpdateRewardValues)
        end
        if not Q.zoneHook and data.questZoneTrack and type(_G.QuestLogQuests_Update) == "function" then
            Q.zoneHook = true
            hooksecurefunc("QuestLogQuests_Update", Q.UpdateZoneChecks)
        end
    end
    Q.UpdateZoneChecks()
end
