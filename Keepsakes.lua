-- Keepsakes: saved arrangements of who travels with you and where they like
-- to be. Loading one replaces the current arrangement; settings, keybindings
-- and history are never touched.
--
-- Share codes (species IDs, so they work between accounts):
--   PETALF1|name|roster|city|inn|wilds|dungeon|raid|battleground|checksum
-- Retail PETAL1 codes import too: open world becomes the wilds, and the
-- neighborhood tag is dropped (Forever has no neighborhoods).

local _, A = ...

local FORMAT = "PETALF1"
local RETAIL = "PETAL1"
local RETAIL_TAGS = { "city", "dungeon", "raid", "wilds", false } -- city, dungeon, raid, openworld, neighborhood
local MAX_NAME = 32

local function CleanName(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, MAX_NAME)
    return value ~= "" and value or nil
end

local function Checksum(text)
    local a, b = 1, 0
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return ("%08X"):format(b * 65536 + a)
end

local function Encode(value)
    return (tostring(value):gsub("([^%w%-%._~])", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function Decode(value)
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function Keys(map)
    local list = {}
    for key, on in pairs(map or {}) do if on then list[#list + 1] = key end end
    table.sort(list)
    return list
end
local function Map(list)
    local map = {}
    for _, key in ipairs(list or {}) do map[key] = true end
    return map
end

local function Snapshot()
    local snap = { roster = Keys(A.db.roster), places = {} }
    for _, place in ipairs(A.PLACES) do snap.places[place] = Keys(A.db.places[place]) end
    return snap
end

function A.KeepsakeNames()
    local names = {}
    for name in pairs(A.db.keepsakes) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function A.GetKeepsake(name) return name and A.db.keepsakes[name] end

function A.SaveKeepsake(name)
    name = CleanName(name)
    if not name then return nil, "Enter a name first." end
    local snap = Snapshot()
    snap.saved = time and time() or 0
    A.db.keepsakes[name] = snap
    A.Fire("keepsakes")
    return name
end

function A.LoadKeepsake(name)
    local snap = A.db.keepsakes[name]
    if not snap then return false end
    A.db.roster = Map(snap.roster)
    for _, place in ipairs(A.PLACES) do
        A.db.places[place] = Map(snap.places and snap.places[place])
        for key in pairs(A.db.places[place]) do A.db.roster[key] = true end
    end
    A.Fire("roster")
    A.RequestEvaluation(0.3, "keepsake loaded")
    return true
end

function A.DeleteKeepsake(name)
    A.db.keepsakes[name] = nil
    A.Fire("keepsakes")
end

-- Companions in a keepsake that this account owns.
function A.KeepsakeCounts(snap)
    local total, owned = 0, 0
    for _, key in ipairs(snap and snap.roster or {}) do
        total = total + 1
        if A.petsByKey[key] then owned = owned + 1 end
    end
    return total, owned
end

local function Species(list)
    local out = {}
    for _, key in ipairs(list or {}) do
        if tostring(key):match("^%d+$") then out[#out + 1] = key end
    end
    table.sort(out, function(a, b) return tonumber(a) < tonumber(b) end)
    return table.concat(out, ",")
end

function A.ExportCode(name)
    local snap = name and A.db.keepsakes[name] or Snapshot()
    local fields = { FORMAT, Encode(CleanName(name) or "My pets"), Species(snap.roster) }
    for _, place in ipairs(A.PLACES) do fields[#fields + 1] = Species(snap.places and snap.places[place]) end
    local payload = table.concat(fields, "|")
    return payload .. "|" .. Checksum(payload)
end

local function Split(text)
    local out, start = {}, 1
    while true do
        local at = text:find("|", start, true)
        if not at then out[#out + 1] = text:sub(start); return out end
        out[#out + 1] = text:sub(start, at - 1)
        start = at + 1
    end
end

local function ParseList(text)
    local list = {}
    if text == "" then return list end
    for token in text:gmatch("[^,]+") do
        if not token:match("^%d+$") then return nil end
        list[#list + 1] = token
    end
    return list
end

local function UniqueName(wanted)
    if not A.db.keepsakes[wanted] then return wanted end
    for i = 2, 99 do
        local candidate = (wanted:sub(1, MAX_NAME - 5) .. " (" .. i .. ")")
        if not A.db.keepsakes[candidate] then return candidate end
    end
end

-- Import never changes the current arrangement: it adds a keepsake.
function A.ImportCode(text)
    if type(text) ~= "string" then return nil, "That is not a Petal code." end
    text = text:gsub("^\239\187\191", ""):gsub("%s", "")
    -- Chat edit boxes double pipes when pasting; undo it only for our formats.
    if text:sub(1, #FORMAT + 2) == FORMAT .. "||" or text:sub(1, #RETAIL + 2) == RETAIL .. "||" then
        text = text:gsub("||", "|")
    end
    local fields = Split(text)
    local format = fields[1]
    local expected = format == FORMAT and (4 + #A.PLACES) or format == RETAIL and (4 + #RETAIL_TAGS) or nil
    if not expected then return nil, "That is not a Petal code." end
    if #fields ~= expected then return nil, "The code is incomplete." end
    local sum = table.remove(fields)
    if Checksum(table.concat(fields, "|")) ~= sum then return nil, "The code is damaged. Copy it again." end
    local roster = ParseList(fields[3])
    if not roster then return nil, "The code is not valid." end
    local inRoster = Map(roster)
    local snap = { roster = roster, places = {}, saved = time and time() or 0, imported = true }
    for _, place in ipairs(A.PLACES) do snap.places[place] = {} end
    local columns = format == FORMAT and A.PLACES or RETAIL_TAGS
    for index, place in ipairs(columns) do
        local list = ParseList(fields[3 + index])
        if not list then return nil, "The code is not valid." end
        if place then
            for _, key in ipairs(list) do
                if inRoster[key] then table.insert(snap.places[place], key) end
            end
        end
    end
    local name = UniqueName(CleanName(Decode(fields[2])) or "Imported set")
    if not name then return nil, "Too many sets with that name." end
    A.db.keepsakes[name] = snap
    A.Fire("keepsakes")
    return name
end
