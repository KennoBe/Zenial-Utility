local _, NS = ...
-- What the shared Form and Window do not offer: a text field at a free position, for the list pages (macros, UI
-- profiles). Tooltips, close button, scroll bar, sections and dialogs come from the shared Form, Window and Kit.
local W = {}
NS.Widgets = W
local T = NS.Theme

function W.Edit(parent, x, y, width, changed)
    local edit = CreateFrame("EditBox", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    edit:SetSize(width, 28)
    edit:SetPoint("TOPLEFT", x, y)
    edit:SetFontObject("GameFontHighlight")
    edit:EnableMouse(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(120)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    T.StyleEditBox(edit)
    if changed then
        edit:SetScript("OnTextChanged", function(self, user) if user then changed(self:GetText()) end end)
    end
    return edit
end
