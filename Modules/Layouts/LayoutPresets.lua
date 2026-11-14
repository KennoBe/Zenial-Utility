local _, NS = ...

-- Ready-made layouts for the library. Adding one only means adding an entry to this list.
-- Only strings that were imported and checked in the Forever client belong here; none are verified yet.
--
--   id      unique and fixed forever: favourites are stored by it
--   kind    "ui" (Edit Mode) or "cdm" (Cooldown Manager)
--   name    {German, English}
--   desc    {German, English}, one short line
--   text    the complete import string, unchanged
--   author  optional
--   image   optional texture below Interface\AddOns\ZenialUtility\Media\Layouts\ (a screenshot of the layout)
--
-- Example shape (not a real layout):
--   {id = "zenial-heal", kind = "ui", name = {"Heiler", "Healer"}, desc = {"Gruppenrahmen mittig", "Group frames centred"},
--    text = "...", author = "ZENIAL", image = "Interface\\AddOns\\ZenialUtility\\Media\\Layouts\\zenial-heal"},
NS.LayoutPresets = {
}
