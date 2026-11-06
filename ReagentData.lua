local _, NS = ...

-- What each class may want from a vendor. `spells`: the row counts once one of them is known.
-- `economy`: Forever's Reagent Economy makes this reagent unnecessary. Item IDs are the classic
-- ones and are not verified against a Forever table; a row only matters if the merchant really
-- sells that item, so a wrong or removed ID shows nothing instead of buying the wrong thing.
NS.ReagentData = {
    reagentEconomySpell = 1225503,
    classes = {
        MAGE = {
            {item = 17020, spells = {23028}, economy = true},
            {item = 17056, spells = {130}, economy = true},
            {item = 17031, spells = {3561, 3562, 3563, 3565, 3566, 3567}, economy = true},
            {item = 17032, spells = {10059, 11416, 11417, 11418, 11419, 11420}, economy = true},
        },
        PRIEST = {
            {item = 17029, spells = {21564}, economy = true},
            {item = 17028, spells = {21562}, economy = true},
            {item = 17056, spells = {1706}, economy = true},
        },
        PALADIN = {
            {item = 21177, spells = {25782, 25916, 25894, 25918, 25898}, economy = true},
            {item = 17033, spells = {19752}, economy = true},
        },
        SHAMAN = {{item = 17030, spells = {20608}, economy = true}},
        DRUID = {
            {item = 17021, spells = {21849}, economy = true},
            {item = 17026, spells = {21850}, economy = true},
            {item = 17034, spells = {20484}, economy = true},
            {item = 17035, spells = {20739}, economy = true},
            {item = 17036, spells = {20742}, economy = true},
            {item = 17037, spells = {20747}, economy = true},
            {item = 17038, spells = {20748}, economy = true},
        },
        WARLOCK = {
            {item = 5565, spells = {1122}, economy = true},
            {item = 16583, spells = {18540}, economy = true},
        },
        ROGUE = {
            {item = 5140, spells = {1856, 1857}, economy = true},
            {item = 2928, poison = true},
            {item = 8924, poison = true},
            {item = 2930, poison = true},
            {item = 8923, poison = true},
            {item = 5173, poison = true},
            {item = 3371, poison = true},
            {item = 3372, poison = true},
            {item = 8925, poison = true},
        },
    },
    -- Finished poisons: enough of them in the bags stops the ingredient purchase.
    finishedPoisons = {6947, 6949, 6950, 8926, 8927, 8928, 2892, 2893, 8984, 8985, 20844, 3775, 3776, 5237, 6951, 9186, 10918, 10920, 10921, 10922},
}
