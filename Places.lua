-- Where the player is. One place at a time, most specific first:
-- raid > dungeon > battleground > capital city > inn or town > the wilds.

local _, A = ...

-- Classic-era capital maps (uiMapID). Zone-name matching below also catches
-- any sub-map the client reports inside them.
local CAPITALS = {
    [1453] = true, -- Stormwind City
    [1455] = true, -- Ironforge
    [1457] = true, -- Darnassus
    [1454] = true, -- Orgrimmar
    [1456] = true, -- Thunder Bluff
    [1458] = true, -- Undercity
}

local function FactionIcon(alliance, horde)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return "Interface\\Icons\\" .. (faction == "Horde" and horde or alliance)
end

-- Labels shown in the window. Keys are saved; never rename them.
A.PLACE_INFO = {
    city = {
        label = "Cities", short = "Cities",
        note = "Capital cities, such as Stormwind and Orgrimmar.",
        icon = function() return FactionIcon("Spell_Arcane_TeleportStormWind", "Spell_Arcane_TeleportOrgrimmar") end,
    },
    inn = {
        label = "Inns & towns", short = "Inns",
        note = "Rested areas outside the capitals: inns and towns.",
        icon = "Interface\\Icons\\INV_Misc_Rune_01",
    },
    wilds = {
        label = "Outdoors", short = "Outdoors",
        note = "The open world, everywhere else.",
        icon = "Interface\\Icons\\INV_Misc_Map_01",
    },
    dungeon = {
        label = "Dungeons", short = "Dungeons",
        note = "5-player dungeons.",
        icon = "Interface\\Icons\\INV_Misc_Lantern_01",
    },
    raid = {
        label = "Raids", short = "Raids",
        note = "Raid instances.",
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    },
    battleground = {
        label = "Battlegrounds", short = "PvP",
        note = "Battlegrounds such as Warsong Gulch.",
        icon = function() return FactionIcon("INV_BannerPVP_02", "INV_BannerPVP_01") end,
    },
}

function A.PlaceInfo(place)
    return A.PLACE_INFO[place] or A.PLACE_INFO.wilds
end

function A.PlaceIcon(place)
    local icon = A.PlaceInfo(place).icon
    return type(icon) == "function" and icon() or icon
end

local capitalNames
local function CapitalNames()
    if capitalNames then return capitalNames end
    capitalNames = {}
    if C_Map and C_Map.GetMapInfo then
        for mapID in pairs(CAPITALS) do
            local ok, info = pcall(C_Map.GetMapInfo, mapID)
            if ok and type(info) == "table" and type(info.name) == "string" then capitalNames[info.name] = true end
        end
    end
    return capitalNames
end

local function InCapital()
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and mapID and not A.IsSecret(mapID) and CAPITALS[mapID] then return true end
    end
    local zone = GetRealZoneText and GetRealZoneText()
    return type(zone) == "string" and CapitalNames()[zone] == true
end

function A.GetPlace()
    local ok, inside, kind = pcall(IsInInstance)
    if ok and inside then
        if kind == "raid" then return "raid" end
        if kind == "party" or kind == "scenario" then return "dungeon" end
        if kind == "pvp" or kind == "arena" then return "battleground" end
    end
    if InCapital() then return "city" end
    if IsResting and IsResting() then return "inn" end
    return "wilds"
end

function A.ZoneText()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local sub = GetSubZoneText and GetSubZoneText() or ""
    if sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
    return zone
end
