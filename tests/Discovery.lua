-- Run from the addon folder: lua5.1 tests/Discovery.lua
-- Without GetOwnedPetIDs, Petal walks the journal by index. It must see every
-- owned companion whatever the player's journal filters are, and put those
-- filters back exactly. Without C_PetJournal it uses the companion API.
local assertions = 0
local function check(value, message) assertions = assertions + 1; assert(value, message) end

function GetTime() return 0 end
C_Timer = { After = function() end }
function issecretvalue() return false end
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
LE_PET_JOURNAL_FILTER_COLLECTED = 1
SlashCmdList = {}

local pets = {
    { guid = "P1", species = 1, name = "Ancona Chicken", type = 1 },
    { guid = "P2", species = 2, name = "Black Kingsnake", type = 2 },
    { guid = "P3", species = 3, name = "Brown Snake", type = 2 },
}
local filter = { search = "king", collected = false, types = { true, false }, sources = { true, true } }
local function Visible()
    local list = {}
    if not filter.collected then return list end
    for _, p in ipairs(pets) do
        if filter.types[p.type] and (filter.search == "" or p.name:lower():find(filter.search, 1, true)) then
            list[#list + 1] = p
        end
    end
    return list
end
C_PetJournal = {
    GetSearchFilter = function() return filter.search end,
    ClearSearchFilter = function() filter.search = "" end,
    SetSearchFilter = function(text) filter.search = text end,
    IsFilterChecked = function() return filter.collected end,
    SetFilterChecked = function(_, v) filter.collected = v end,
    GetNumPetTypes = function() return 2 end,
    IsPetTypeChecked = function(i) return filter.types[i] end,
    SetPetTypeFilter = function(i, v) filter.types[i] = v end,
    GetNumPetSources = function() return 2 end,
    IsPetSourceChecked = function(i) return filter.sources[i] end,
    SetPetSourceChecked = function(i, v) filter.sources[i] = v end,
    GetNumPets = function() local n = #Visible(); return n, n end,
    GetPetInfoByIndex = function(i) local p = Visible()[i]; return p.guid, p.species, true end,
    GetPetInfoByPetID = function(guid)
        for _, p in ipairs(pets) do
            if p.guid == guid then return p.species, nil, 1, 0, 0, 10, false, p.name, 1, p.type, 100 end
        end
    end,
}

local A = {}
assert(loadfile("Core.lua"))("PETAL", A)
assert(loadfile("Collection.lua"))("PETAL", A)
A.db = {}

A.ScanCollection()
check(#A.pets == 3, "index walk sees every owned companion")
check(A.collectionSource == "index", "index walk used")
check(filter.search == "king" and filter.collected == false and filter.types[2] == false,
    "the player's journal filters are restored")

-- No pet journal at all: the companion API.
C_PetJournal = nil
local learned = { { 7560, "Tabby Cat", 10675, 132599, true }, { 7555, "Hawk Owl", 10706, 132599, false } }
function GetNumCompanions() return #learned end
function GetCompanionInfo(_, i) return unpack(learned[i]) end
local called
function CallCompanion(_, index) called = index end
assert(loadfile("Collection.lua"))("PETAL", A)
A.ScanCollection()
check(#A.pets == 2 and A.collectionSource == "companion", "companion API fallback")
check(A.CurrentPet() and A.CurrentPet().name == "Tabby Cat", "summoned companion found")
A.SummonPet(A.GetPet("c10706"))
check(called == 2, "CallCompanion uses the sorted companion's own index")

print(("PETAL discovery: %d assertions passed"):format(assertions))
