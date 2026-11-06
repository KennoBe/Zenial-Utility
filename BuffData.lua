local _, NS = ...

-- Every spell ID here exists in the 1.60.1.70790 game tables. `ranks` lists rank chains in learning
-- order; several chains mean "any one of these" (armors, aspects, blessings). `also` are spells that
-- count as covering the buff without being a rank of it (the group version of a buff).
-- `def`: on without asking once the warning system is on. Consumables stay opt-in.
NS.BuffData = {
    classes = {
        PRIEST = {
            {key = "priest_fort", bar = "combat", def = true, group = true, ranks = {{1243, 1244, 1245, 2791, 10937, 10938}}, also = {21562, 21564}},
            {key = "priest_spirit", bar = "combat", def = true, group = true, ranks = {{14752, 14818, 14819, 27841}}, also = {27681}},
            {key = "priest_shadow", bar = "combat", group = true, ranks = {{976, 10957, 10958}}, also = {27683}},
            {key = "priest_inner", bar = "combat", def = true, ranks = {{588, 602, 1006, 7128, 10951, 10952}}},
        },
        MAGE = {
            {key = "mage_int", bar = "combat", def = true, group = true, ranks = {{1459, 1460, 1461, 10156, 10157}}, also = {23028}},
            {key = "mage_armor", bar = "combat", def = true, de = "Rüstungszauber", en = "Armor spell",
                ranks = {{168, 7300, 7301}, {7302, 7320, 10219, 10220}, {6117, 22782, 22783}}},
        },
        DRUID = {
            {key = "druid_wild", bar = "combat", def = true, group = true, ranks = {{1126, 5232, 5234, 6756, 8907, 9884, 9885}}, also = {21849, 21850}},
            {key = "druid_thorns", bar = "combat", ranks = {{467, 782, 1075, 8914, 9756, 9910}}},
        },
        PALADIN = {
            {key = "pala_blessing", bar = "combat", def = true, de = "Segen", en = "Blessing",
                ranks = {{19740, 19834, 19835, 19836, 19837, 19838, 25291}, {19742, 19850, 19852, 19853, 19854, 25290}, {20217}},
                also = {25782, 25916, 25894, 25918, 25898}},
            {key = "pala_fury", bar = "combat", ranks = {{25780}}},
        },
        WARRIOR = {
            {key = "war_shout", bar = "combat", def = true, ranks = {{6673, 5242, 6192, 11549, 11550, 11551, 25289}}},
        },
        HUNTER = {
            {key = "hunt_aspect", bar = "combat", def = true, de = "Aspekt", en = "Aspect",
                ranks = {{13165, 14318, 14319, 14320, 14321, 14322, 25296}, {5118}, {13163}, {13159}, {20043, 20190}, {13161}}},
            {key = "hunt_trueshot", bar = "combat", ranks = {{19506, 20905, 20906}}},
        },
        WARLOCK = {
            {key = "lock_armor", bar = "combat", def = true, de = "Dämonenrüstung", en = "Demon armor", ranks = {{687, 696}, {706, 1086, 11733, 11734, 11735}}},
            {key = "lock_stone", bar = "consumables", kind = "weapon", slot = "main", de = "Feuerstein oder Zauberstein", en = "Firestone or Spellstone",
                learn = {6366, 17951, 17952, 17953, 2362, 17727, 17728}},
        },
        SHAMAN = {
            {key = "sham_shield", bar = "combat", def = true, charges = true, de = "Blitz- oder Wasserschild", en = "Lightning or Water Shield",
                ranks = {{324, 325, 905, 945, 8134, 10431, 10432}, {408510}}},
            {key = "sham_main", bar = "combat", kind = "weapon", slot = "main", de = "Waffenverzauberung (Waffenhand)", en = "Weapon imbue (main hand)", learn = {8017, 8024, 8033, 8232}},
            {key = "sham_off", bar = "combat", kind = "weapon", slot = "off", de = "Waffenverzauberung (Schildhand)", en = "Weapon imbue (off hand)", learn = {8017, 8024, 8033, 8232}},
        },
        ROGUE = {
            {key = "rogue_main", bar = "combat", def = true, kind = "weapon", slot = "main", de = "Gift (Waffenhand)", en = "Poison (main hand)", learn = {2842}},
            {key = "rogue_off", bar = "combat", def = true, kind = "weapon", slot = "off", de = "Gift (Schildhand)", en = "Poison (off hand)", learn = {2842}},
        },
    },
    -- For every class. Gathering only asks for abilities the character has learned.
    general = {
        {key = "gather_nodes", bar = "general", kind = "tracking", de = "Kräuter oder Erze suchen", en = "Find Herbs or Minerals", tracking = {2383, 8387, 2580, 8388}},
        {key = "gather_treasure", bar = "general", kind = "tracking", de = "Schätze suchen", en = "Find Treasure", tracking = {2481}},
        {key = "camp", bar = "general", exact = true, de = "Lagerboni", en = "Camp Benefits", ranks = {{1229741}}},
    },
    -- Nothing here is on until chosen. Matched by exact spell ID, because many names are generic.
    consumables = {
        {key = "food", free = true, de = "Satt (Essen)", en = "Well Fed (food)", ranks = {{19705}}},
        {key = "flask_titans", exact = true, ranks = {{17626}}},
        {key = "flask_wisdom", exact = true, ranks = {{17627}}},
        {key = "flask_power", exact = true, ranks = {{17628}}},
        {key = "flask_chromatic", exact = true, ranks = {{17629}}},
        {key = "elixir_mongoose", exact = true, ranks = {{17538}}},
        {key = "elixir_giants", exact = true, de = "Elixier der Riesen", en = "Elixir of the Giants", ranks = {{11405}}},
        {key = "elixir_agility", exact = true, de = "Elixier der großen Beweglichkeit", en = "Elixir of Greater Agility", ranks = {{11334}}},
        {key = "elixir_fortitude", exact = true, de = "Elixier der Seelenstärke", en = "Elixir of Fortitude", ranks = {{3593}}},
        {key = "elixir_defense", exact = true, de = "Elixier der Verteidigung", en = "Defense elixir", ranks = {{11348, 11349}}},
        {key = "elixir_arcane", exact = true, ranks = {{11390, 17539}}},
        {key = "elixir_fire", exact = true, ranks = {{26276}}},
        {key = "elixir_shadow", exact = true, ranks = {{11474}}},
        {key = "elixir_frost", exact = true, ranks = {{21920}}},
        {key = "elixir_sages", exact = true, ranks = {{17535}}},
        {key = "weapon_main", kind = "weapon", slot = "main", de = "Öl oder Stein (Waffenhand)", en = "Oil or stone (main hand)"},
        {key = "weapon_off", kind = "weapon", slot = "off", de = "Öl oder Stein (Schildhand)", en = "Oil or stone (off hand)"},
    },
    icons = {
        weapon = "Interface\\Icons\\INV_Stone_SharpeningStone_05",
        durability = "Interface\\Icons\\Trade_BlackSmithing",
        bags = "Interface\\Icons\\INV_Misc_Bag_08",
        ammo = "Interface\\Icons\\INV_Ammo_Arrow_02",
        tracking = "Interface\\Icons\\INV_Misc_Spyglass_02",
    },
}
