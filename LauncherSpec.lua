-- Entry points of the standalone Utility window (/zutil) and setup wizard (/zutil config).
local _, ns = ...
local function slash(argument)
    local handler = _G.SlashCmdList and _G.SlashCmdList.ZENIALUTILITY
    if type(handler) == "function" then handler(argument) end
end
ns.LauncherSpec = {
    minimapIcon = "Interface\\AddOns\\ZenialUtility\\Media\\ZenialIcon.tga",
    openSettings = function()
        -- /zutil toggles; never close a window that is already open.
        local frame = _G.ZenialUtilitySettings
        if frame and frame.IsShown and frame:IsShown() then return end
        slash("")
    end,
    openWizard = function() slash("config") end,
}
