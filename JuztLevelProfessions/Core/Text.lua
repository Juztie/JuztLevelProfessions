local _, JLP = ...

local REPLACEMENTS = {
    { "→", "->" },
    { "↳", ">" },
    { "•", "-" },
    { "·", "-" },
    { "–", "-" },
    { "—", "-" },
    { "×", "x" },
    { "≈", "" },
    { "…", "..." },
}

function JLP:SafeText(value)
    local text = tostring(value or "")
    -- Most UI strings are ASCII. Avoid nine UTF-8 substitutions on every
    -- SetText call unless the value actually contains a non-ASCII byte.
    if not text:find("[\128-\255]") then return text end
    for _, pair in ipairs(REPLACEMENTS) do
        text = text:gsub(pair[1], pair[2])
    end
    return text
end
