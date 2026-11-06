local addonName, NS = ...
local A, L, G, H, MT = NS.Adapter, NS.Logic, NS.Graphics, NS.Helpers, NS.MapTools
local App = {missingEvents = {}}
NS.App = App

function App:Changed()
    self.db = L.Sanitize(self.db)
    ZenialUtilityDB = self.db
    MT.Refresh()
    NS.SettingsUI.Refresh()
    NS.RollWindow.SettingsChanged()
end

function App:GraphicsConfirm() NS.GraphicsConfirm.Show() end
function App:GraphicsConfirmDone()
    NS.GraphicsConfirm.Hide()
    NS.SettingsUI.Refresh()
end

function App:Initialize()
    if self.db then return end
    local fresh = type(ZenialUtilityDB) ~= "table" or next(ZenialUtilityDB) == nil
    self.db = L.Sanitize(ZenialUtilityDB)
    ZenialUtilityDB = self.db
    NS.Setup.Initialize(fresh)
end

local driver = CreateFrame("Frame")
NS.Driver = driver
local events = {"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "CVAR_UPDATE", "UPDATE_MACROS", "MERCHANT_SHOW", "MERCHANT_CLOSED", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_GREETING", "GOSSIP_SHOW", "UPDATE_INVENTORY_DURABILITY", "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED",
    "PLAYER_LEVEL_UP", "BOSS_KILL", "ENCOUNTER_END", "TIME_PLAYED_MSG", "CHAT_MSG_SYSTEM"}
for _, event in ipairs(events) do
    if not pcall(driver.RegisterEvent, driver, event) then App.missingEvents[#App.missingEvents + 1] = event end
end

driver:SetScript("OnEvent", function(_, event, ...)
    local first = ...
    if event == "ADDON_LOADED" then
        if first == addonName then App:Initialize() end
        if App.db then MT.TryAttach() end
        return
    end
    if event == "PLAYER_LOGIN" then
        App:Initialize()
        G.ResumeUnanswered(App.db)
        H.AttachTooltips()
        MT.Refresh()
        NS.Setup.Schedule()
        return
    end
    if not App.db then return end
    if event == "PLAYER_ENTERING_WORLD" then
        H.CheckAll()
    elseif event == "PLAYER_REGEN_ENABLED" then
        MT.CombatEnded()
        NS.SettingsUI.Refresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        NS.SettingsUI.Refresh()
    elseif event == "CVAR_UPDATE" or event == "UPDATE_MACROS" then
        NS.SettingsUI.Refresh()
    else
        H.Event(event, ...)
    end
end)

local attachTimer = 0
driver:SetScript("OnUpdate", function(_, dt)
    if not App.db then return end
    G.Tick(App.db, dt)
    NS.GraphicsConfirm.Update()
    H.Tick(dt)
    -- The world map can load late. Keep looking, as Community does, until the pin exists.
    if not MT.pin then
        attachTimer = attachTimer + dt
        if attachTimer >= 5 then attachTimer = 0; MT.TryAttach() end
    end
end)

SLASH_ZENIALUTILITY1 = "/zutil"
SLASH_ZENIALUTILITY2 = "/zenialutility"
SlashCmdList.ZENIALUTILITY = function(command)
    if not App.db then return end
    command = (command or ""):match("^%s*(.-)%s*$"):lower()
    if command == "config" then NS.Setup.Open()
    elseif NS.SettingsUI.Titles[command] then NS.SettingsUI.Open(command)
    else NS.SettingsUI.Toggle() end
end

SLASH_ZENIALUTILITYWAY1 = "/zway"
SlashCmdList.ZENIALUTILITYWAY = function(text) if App.db then MT.Waypoint(text) end end
SLASH_ZENIALUTILITYPULL1 = "/zpull"
SlashCmdList.ZENIALUTILITYPULL = function(text) if App.db then H.Pull(text) end end

_G.ZenialAddonPanels = _G.ZenialAddonPanels or {}
_G.ZenialAddonPanels.ZenialUtility = {apiVersion = 1, CreatePanel = function(parent)
    local view = NS.SettingsUI.Create(parent, true)
    return view.frame, function() view:Refresh() end
end}
