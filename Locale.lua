local _, NS = ...

-- German text only on German clients; every other language reads the English text.
function NS.IsGerman()
    return type(GetLocale) == "function" and GetLocale() == "deDE"
end

function NS.Text(de, en)
    if NS.IsGerman() then return de end
    return en
end
