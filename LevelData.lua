-- Zone level ranges and dungeon entrances, taken from OpenMap (MIT, see NOTICE.txt):
--   MapLevels    OpenMap Data/Forever/Levels.lua. OpenMap lists the Warcraft Wiki's "Zones by level
--                (original)" page plus each WoW Forever zone's own wiki page. [uiMapID] = {min, max}.
--   MapDungeons  OpenMap Data/Forever/Places.lua (instances), built from the game tables of build
--                1.60.1.70245: {continent, worldX, worldY, {{instanceID, name, raid, min, max}, ...}}, or
--                {nil, x, y, {...}, map = uiMapID} for a spot on that zone's map.
-- Zones and instances without a level range in the source are left out, not estimated.
-- Nothing is read from OpenMap at runtime.

local _, NS = ...

NS.MapLevels = {
    -- Eastern Kingdoms
    [1416] = {30, 40}, -- Alterac Mountains
    [1417] = {30, 40}, -- Arathi Highlands
    [1418] = {35, 45}, -- Badlands
    [1419] = {45, 55}, -- Blasted Lands
    [1420] = {1, 10}, -- Tirisfal Glades
    [1421] = {10, 20}, -- Silverpine Forest
    [1422] = {51, 58}, -- Western Plaguelands
    [1423] = {53, 60}, -- Eastern Plaguelands
    [1424] = {20, 30}, -- Hillsbrad Foothills
    [1425] = {40, 50}, -- The Hinterlands
    [1426] = {1, 10}, -- Dun Morogh
    [1427] = {45, 50}, -- Searing Gorge
    [1428] = {50, 58}, -- Burning Steppes
    [1429] = {1, 10}, -- Elwynn Forest
    [1430] = {55, 60}, -- Deadwind Pass
    [1431] = {18, 30}, -- Duskwood
    [1432] = {10, 20}, -- Loch Modan
    [1433] = {15, 25}, -- Redridge Mountains
    [1434] = {30, 45}, -- Stranglethorn Vale
    [1435] = {35, 45}, -- Swamp of Sorrows
    [1436] = {10, 20}, -- Westfall
    [1437] = {20, 30}, -- Wetlands
    -- Kalimdor
    [1411] = {1, 10}, -- Durotar
    [1412] = {1, 10}, -- Mulgore
    [1413] = {10, 25}, -- The Barrens
    [1438] = {1, 10}, -- Teldrassil
    [1439] = {10, 20}, -- Darkshore
    [1440] = {18, 30}, -- Ashenvale
    [1441] = {25, 35}, -- Thousand Needles
    [1442] = {15, 27}, -- Stonetalon Mountains
    [1443] = {30, 40}, -- Desolace
    [1444] = {40, 50}, -- Feralas
    [1445] = {35, 45}, -- Dustwallow Marsh
    [1446] = {40, 50}, -- Tanaris
    [1447] = {45, 55}, -- Azshara
    [1448] = {48, 55}, -- Felwood
    [1449] = {48, 55}, -- Un'Goro Crater
    [1450] = {55, 60}, -- Moonglade
    [1451] = {55, 60}, -- Silithus
    [1452] = {55, 60}, -- Winterspring
    -- WoW Forever's own (OpenMap: from each zone's Warcraft Wiki page)
    [2548] = {35, 45}, -- Riverglades
    [2521] = {1, 12}, -- Zephras Isle
}

-- Ruins of Ahn'Qiraj and Ahn'Qiraj Temple carry no level range in the source and are left out,
-- as are the four instances OpenMap has no entrance for yet.
NS.MapDungeons = {
    {nil, 0.213, 0.278, {{0, "The Drowned City", false, 35, 40}}, map = 1434},
    {0, -231.0, 1571.6, {{33, "Shadowfang Keep", false, 18, 23}}},
    {0, -8762.4, 848.0, {{34, "Stormwind Stockade", false, 23, 28}}},
    {0, -11207.8, 1681.2, {{36, "Deadmines", false, 16, 21}}},
    {1, -751.1, -2209.2, {{43, "Wailing Caverns", false, 17, 22}}},
    {1, -4459.4, -1660.2, {{47, "Razorfen Kraul", false, 24, 29}}},
    {1, 4249.1, 748.4, {{48, "Blackfathom Deeps", false, 22, 27}}},
    {0, -6060.2, -2955.0, {{70, "Uldaman", false, 35, 40}}},
    {0, -5162.7, 931.6, {{90, "Gnomeregan", false, 25, 30}}},
    {0, -10170.1, -3996.0, {{109, "Sunken Temple", false, 45, 50}}},
    {1, -4662.9, -2535.9, {{129, "Razorfen Downs", false, 34, 39}}},
    {0, 2892.2, -811.3, {{189, "Scarlet Monastery - Graveyard", false, 30, 35}, {189, "Scarlet Monastery - Library", false, 30, 35},
        {189, "Scarlet Monastery - Armory", false, 30, 35}, {189, "Scarlet Monastery - Cathedral", false, 30, 35}}},
    {1, -6790.6, -2891.3, {{209, "Zul'Farrak", false, 42, 47}}},
    {0, -7522.5, -1233.0, {{229, "Lower Blackrock Spire", false, 53, 58}, {229, "Upper Blackrock Spire", false, 53, 58},
        {409, "Molten Core", true, 60, 60}, {469, "Blackwing Lair", true, 60, 60}}},
    {0, -7178.1, -928.6, {{230, "Blackrock Depths", false, 48, 53}}},
    {1, -4753.3, -3752.4, {{249, "Onyxia's Lair", true, 60, 60}}},
    {0, 1274.8, -2552.6, {{289, "Scholomance", false, 57, 60}}},
    {0, -11916.1, -1224.6, {{309, "Zul'Gurub", true, 60, 60}}},
    {0, 3392.3, -3378.5, {{329, "Stratholme", false, 55, 60}}},
    {1, -1432.7, 2925.0, {{349, "Maraudon", false, 42, 47}}},
    {1, 1816.8, -4423.4, {{389, "Ragefire Chasm", false, 13, 18}}},
    {1, -3908.0, 1130.0, {{429, "Dire Maul - East", false, 54, 59}, {429, "Dire Maul - West", false, 54, 59}, {429, "Dire Maul - North", false, 54, 59}}},
    {nil, 0.085, 0.593, {{2959, "City of Dalaran", false, 28, 33}}, map = 1416},
    {nil, 0.478, 0.562, {{2998, "Excavation Site: Wetlands", false, 24, 29}}, map = 1437},
    {nil, 0.725, 0.114, {{2999, "Ruins of Lordaeron", false, 15, 20}}, map = 1458},
    {nil, 0.277, 0.479, {{3065, "The Hall of Thanes", false, 13, 18}}, map = 1455},
}
