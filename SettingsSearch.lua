local _, NS = ...
-- Settings search. The index is built from the page schema (SettingsPages.lua), not from the
-- frames, so searching never builds a page. Each entry is searched in German and English
-- plus its own keywords, so "Loot", "Beute" and "Plündern" all find the loot options.
local S = {entries = {}}
NS.SettingsSearch = S

local UPPER = {["Ä"] = "ä", ["Ö"] = "ö", ["Ü"] = "ü", ["É"] = "é"}

-- Lower case that also covers the umlauts Lua's lower() leaves alone.
local function lower(text)
    text = tostring(text or ""):lower()
    for upper, small in pairs(UPPER) do text = text:gsub(upper, small) end
    return text
end

-- Two spellings of every umlaut, so "plündern", "pluendern" and "plundern" all match.
function S.Fold(text)
    local low = lower(text)
    local long = low:gsub("ä", "ae"):gsub("ö", "oe"):gsub("ü", "ue"):gsub("ß", "ss"):gsub("é", "e")
    local short = low:gsub("ä", "a"):gsub("ö", "o"):gsub("ü", "u"):gsub("ß", "ss"):gsub("é", "e")
    if long == short then return long end
    return long .. " " .. short
end

local function both(value)
    if type(value) == "table" then return (value[1] or "") .. " " .. (value[2] or "") end
    return value or ""
end

function S.Clear() S.entries = {} end

-- entry: {page, id, title = {de, en} | text, desc, section, keywords}
function S.Add(entry)
    entry.titleHay = S.Fold(both(entry.title))
    entry.hay = S.Fold(table.concat({both(entry.title), both(entry.desc), both(entry.section), entry.keywords or ""}, " "))
    S.entries[#S.entries + 1] = entry
    return entry
end

local function words(query)
    local out = {}
    for word in lower(query):gmatch("%S+") do
        local folded = S.Fold(word)
        out[#out + 1] = folded:match("^%S+")
    end
    return out
end

-- Matches with every word of the query. Title hits rank before description hits;
-- otherwise the schema order (page order, then position on the page) stays.
function S.Find(query, order)
    local list = words(query)
    if #list == 0 then return {} end
    local rank = {}
    for index, id in ipairs(order or {}) do rank[id] = index end
    local hits = {}
    for index, entry in ipairs(S.entries) do
        local all, titleHits = true, 0
        for _, word in ipairs(list) do
            if not entry.hay:find(word, 1, true) then all = false; break end
            if entry.titleHay:find(word, 1, true) then titleHits = titleHits + 1 end
        end
        if all then
            local score = titleHits * 10 + (entry.kind == "page" and 5 or 0)
            if entry.titleHay:sub(1, #list[1]) == list[1] then score = score + 3 end
            hits[#hits + 1] = {entry = entry, score = score, index = index, page = rank[entry.page] or 99}
        end
    end
    table.sort(hits, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.page ~= b.page then return a.page < b.page end
        return a.index < b.index
    end)
    local out = {}
    for _, hit in ipairs(hits) do out[#out + 1] = hit.entry end
    return out
end
