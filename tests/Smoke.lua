-- Run from the addon folder: lua5.1 tests/Smoke.lua
-- Loads every file against a mocked Forever client and checks the rules.
local assertions = 0
local function check(value, message) assertions = assertions + 1; assert(value, message) end

-- Clock and timers ------------------------------------------------------------
local now, timers = 1000, {}
function GetTime() return now end
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTimer = function(delay, fn)
        local t = { at = now + delay, fn = fn }
        function t:Cancel() self.cancelled = true end
        timers[#timers + 1] = t
        return t
    end,
    NewTicker = function(delay, fn)
        local t = { Cancel = function(self) self.cancelled = true end }
        return t
    end,
}
local function advance(seconds)
    now = now + seconds
    local ran = true
    while ran do
        ran = false
        for i, t in ipairs(timers) do
            if t.at <= now then
                table.remove(timers, i)
                if not t.cancelled then t.fn() end
                ran = true
                break
            end
        end
    end
end

-- Generic frame mock: any method exists and returns nil, a few return values.
local function Mock(kind)
    local obj = { scripts = {}, shown = kind ~= "hidden" }
    local methods = {
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        GetScript = function(self, name) return self.scripts[name] end,
        HookScript = function(self, name, fn) self.scripts[name] = fn end,
        CreateTexture = function() return Mock() end,
        CreateFontString = function() return Mock() end,
        CreateMaskTexture = function() return Mock() end,
        GetText = function(self) return rawget(self, "text") or "" end,
        SetText = function(self, text) self.text = text end,
        IsShown = function(self) return self.shown end,
        Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end,
        Hide = function(self) self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end,
        SetShown = function(self, v) self.shown = v and true or false end,
        GetChecked = function(self) return rawget(self, "checked") end,
        SetChecked = function(self, v) self.checked = v end,
        GetFontString = function(self) if not rawget(self, "fs") then rawset(self, "fs", Mock()) end; return rawget(self, "fs") end,
        GetSize = function() return 100, 100 end,
        GetWidth = function() return 100 end,
        GetHeight = function() return 20 end,
        GetStringHeight = function() return 12 end,
        GetFrameLevel = function() return 1 end,
        IsEnabled = function() return true end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        GetActorByTag = function() return Mock() end,
        GetVerticalScrollRange = function() return 0 end,
        
    }
    local fields = { Left = true, Middle = true, Right = true, LeftSeparator = true, RightSeparator = true, Text = true, text = true }
    return setmetatable(obj, { __index = function(_, key)
        if fields[key] then return nil end
        return methods[key] or function() end
    end })
end
local eventFrame
function CreateFrame(kind, name, parent, template)
    local frame = Mock()
    if kind == "Frame" and not name and not parent and not eventFrame then eventFrame = frame end
    if name then _G[name] = frame end
    if kind == "CheckButton" then frame.Text = Mock() end
    return frame
end
UIParent, GameTooltip, UIErrorsFrame = Mock(), Mock(), Mock()
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) chat[#chat + 1] = text end }
UISpecialFrames, SlashCmdList = {}, {}
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
function PlaySound() end
function hooksecurefunc() end
C_Texture = { GetAtlasInfo = function() return { width = 43, height = 60, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1, file = 1 } end }
NineSliceUtil = { ApplyLayoutByName = function() end }
Enum = { PetJournalError = { InvalidFaction = 3 }, ModelBlendOperation = { None = 0 } }
function date(fmt, t) return "27 Sep 2026" end
function time() return 1790000000 end
function GetBindingKey() return nil end
function InCombatLockdown() return false end

-- Player state ------------------------------------------------------------------
local player = { combat = false, mounted = false, instance = nil, resting = false, mapID = 1429, zone = "Elwynn Forest", auras = {} }
function UnitAffectingCombat() return player.combat end
function UnitIsDeadOrGhost() return false end
function UnitOnTaxi() return false end
function IsMounted() return player.mounted end
function IsStealthed() return false end
function GetShapeshiftFormID() return player.form end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function UnitClass() return "Druid", "DRUID" end
function UnitFactionGroup() return "Alliance" end
function IsInInstance() return player.instance ~= nil, player.instance or "none" end
function IsResting() return player.resting end
function GetRealZoneText() return player.zone end
function GetSubZoneText() return "" end
C_Map = {
    GetBestMapForUnit = function() return player.mapID end,
    GetMapInfo = function(id) return ({ [1453] = { name = "Stormwind City" } })[id] end,
}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id) return player.auras[id] end,
    GetAuraDataByIndex = function(_, i) return player.auraList and player.auraList[i] end,
}
C_Spell = { GetSpellName = function(id) return ({ [433] = "Food", [430] = "Drink" })[id] end }

-- Pet journal: five companions, one wrapped, one of the other faction ----------------
local journal = {
    { guid = "BattlePet-0-1", species = 40, name = "Tabby Cat", favorite = true },
    { guid = "BattlePet-0-2", species = 68, name = "Prairie Dog" },
    { guid = "BattlePet-0-3", species = 55, name = "Cockroach", custom = "Skitters" },
    { guid = "BattlePet-0-4", species = 90, name = "Sprite Darter Hatchling", wrapped = true },
    { guid = "BattlePet-0-5", species = 77, name = "Horde Pup", faction = true },
}
local byGUID = {}
for _, p in ipairs(journal) do byGUID[p.guid] = p end
local summoned, summonCalls = nil, 0
C_PetJournal = {
    GetOwnedPetIDs = function() local t = {}; for _, p in ipairs(journal) do t[#t + 1] = p.guid end; return t end,
    GetPetInfoByPetID = function(guid)
        local p = byGUID[guid]
        if not p then return nil end
        return p.species, p.custom, 1, 0, 0, 1000 + p.species, p.favorite, p.name, 132000 + p.species, 1, 5000 + p.species
    end,
    GetPetInfoBySpeciesID = function(species)
        return "x", 1, 1, 5000 + species, "|cFFFFD200Vendor:|r Donni Anthania", "A loyal friend.", false, false, true, false, true, 1000 + species
    end,
    GetPetModelSceneInfoBySpeciesID = function() return 42, 43 end,
    PetNeedsFanfare = function(guid) return byGUID[guid].wrapped == true end,
    GetPetSummonInfo = function(guid) return true, byGUID[guid].faction and 3 or 0, "" end,
    PetIsSummonable = function(guid) return not byGUID[guid].wrapped end,
    GetSummonedPetGUID = function() return summoned end,
    SummonPetByGUID = function(guid) summonCalls = summonCalls + 1; summoned = (summoned ~= guid) and guid or nil end,
    DismissSummonedPet = function() summoned = nil end,
    ClearFanfare = function(guid) byGUID[guid].wrapped = false end,
    GetNumPets = function() return #journal, #journal end,
}

-- Load the addon ----------------------------------------------------------------------
local A = {}
for _, file in ipairs({ "Core.lua", "Collection.lua", "Places.lua", "Summoner.lua", "Keepsakes.lua", "Skin.lua", "UI.lua" }) do
    assert(loadfile(file))("PETAL", A)
end
local function fire(event, ...) eventFrame.scripts.OnEvent(eventFrame, event, ...) end
fire("ADDON_LOADED", "PETAL")
fire("PLAYER_LOGIN")

check(#A.pets == 4, "other-faction companion hidden, four remain")
check(A.collectionSource == "owned", "GetOwnedPetIDs path used")
check(A.GetPet("55").name == "Skitters", "custom name shown")
check(A.GetPet("90").wrapped, "wrapped gift detected")
check(not A.IsSummonable(A.GetPet("90")), "wrapped gift cannot be summoned")

-- Places ------------------------------------------------------------------------------
check(A.GetPlace() == "wilds", "outdoors is the wilds")
player.resting = true
check(A.GetPlace() == "inn", "resting outside a capital is an inn")
player.mapID, player.zone = 1453, "Stormwind City"
check(A.GetPlace() == "city", "Stormwind is a capital")
player.mapID, player.zone, player.resting = 1429, "Elwynn Forest", false
player.instance = "party"
check(A.GetPlace() == "dungeon", "party instance is a dungeon")
player.instance = "raid"
check(A.GetPlace() == "raid", "raid instance")
player.instance = nil

-- Nothing travels: nothing is called ---------------------------------------------------
local ok, why = A.Evaluate("test")
check(not ok and why == "nopets", "no roster, no summon")

-- Roster: Tabby Cat and Prairie Dog travel; the Prairie Dog loves dungeons ---------------
A.SetTravelling("40", true)
A.SetLikesPlace("68", "dungeon", true)
check(A.IsTravelling("68"), "a place implies travelling")
check(#A.PoolFor("wilds") == 2, "no one chosen for wilds: every traveller")
advance(1) -- the roster change schedules an evaluation
check(summoned ~= nil and summonCalls == 1, "a traveller is called in the wilds")
fire("COMPANION_UPDATE", "CRITTER")
advance(1)
local first = summoned
ok, why = A.Evaluate("test")
check(not ok and why == "kept" and summoned == first, "no churn while the companion fits")

-- Dungeon: only the Prairie Dog loves it -----------------------------------------------
player.instance = "party"
advance(5)
ok, why = A.Evaluate("zone")
check(summoned == "BattlePet-0-2", "dungeon lover is called in a dungeon")
fire("COMPANION_UPDATE", "CRITTER"); advance(1)
player.instance = nil

-- Never interrupt: combat, campfire, food, blocking form ----------------------------------
player.combat = true
check(A.BlockReason() == "combat", "combat blocks")
player.combat = false
player.auras[1229739] = {}
check(A.BlockReason() == "campfire", "campfire sitting blocks")
player.auras[1229739] = nil
player.auraList = { { name = "Drink" } }
check(A.BlockReason() == "eating", "drinking blocks")
player.auraList = nil
player.form = 1
check(A.BlockReason() == "form", "cat form blocks")
player.form = 31
check(A.BlockReason() == nil, "moonkin does not block")
player.form = nil

-- Mounting hides the companion; it comes back as the same one ------------------------------
advance(10)
local before = summoned
summoned = nil
player.mounted = true
fire("COMPANION_UPDATE", "CRITTER")
advance(3)
check(A.state.hiddenKey ~= nil and A.GraceRemaining() == 0, "mount hides, no rest period")
player.mounted = false
fire("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(5)
check(summoned == before, "same companion comes back after dismounting")
fire("COMPANION_UPDATE", "CRITTER"); advance(1)

-- The player sends it away: rest period, then it returns ------------------------------------
advance(10)
summoned = nil
fire("COMPANION_UPDATE", "CRITTER")
advance(3)
check(summoned == nil and A.GraceRemaining() > 0, "dismissal starts a rest period")
advance(A.db.graceMinutes * 60 + 5)
check(summoned ~= nil, "a companion returns after the rest")
fire("COMPANION_UPDATE", "CRITTER"); advance(1)

-- A companion you call yourself stays until you change place ---------------------------------
advance(10)
summoned = "BattlePet-0-3" -- Skitters, not travelling
fire("COMPANION_UPDATE", "CRITTER")
advance(2)
ok, why = A.Evaluate("safety check")
check(summoned == "BattlePet-0-3" and why == "own choice", "own choice respected")
player.resting = true -- walk into an inn
advance(5)
fire("PLAYER_UPDATE_RESTING")
advance(5)
check(summoned ~= "BattlePet-0-3", "own choice ends at a new place")
fire("COMPANION_UPDATE", "CRITTER"); advance(1)
player.resting = false

-- Call another -----------------------------------------------------------------------------
advance(10)
local was = summoned
local changed = A.CallAnother("key")
check(changed and summoned ~= was, "call another picks someone new")

-- Whispers off by default, on when chosen ------------------------------------------------------
check(#chat == 0, "no whispers by default")
A.db.whispers = true
advance(10); fire("COMPANION_UPDATE", "CRITTER"); advance(1)
A.CallAnother("key")
check(#chat == 1 and chat[1]:find("Your ") or chat[1]:find("Skitters"), "a whisper when enabled")

-- Keepsakes and codes ------------------------------------------------------------------------
local name = A.SaveKeepsake("Road trip")
check(name == "Road trip", "keepsake saved")
local code = A.ExportCode(name)
check(code:match("^PETALF1|Road%%20trip|40,68|"), "export format: " .. code)
local imported = A.ImportCode(code)
check(imported == "Road trip (2)", "import adds a copy, never overwrites")
check(A.ImportCode(code:sub(1, -2) .. "0") == nil, "damaged code refused")
-- Retail PETAL1: city, dungeon, raid, openworld, neighborhood.
local function Checksum(text)
    local a, b = 1, 0
    for i = 1, #text do a = (a + text:byte(i)) % 65521; b = (b + a) % 65521 end
    return ("%08X"):format(b * 65536 + a)
end
local retail = "PETAL1|Retail%20set|40,55|40||55|55|40"
retail = retail .. "|" .. Checksum(retail)
local fromRetail = A.ImportCode(retail)
check(fromRetail == "Retail set", "retail code imports")
local snap = A.GetKeepsake(fromRetail)
check(snap.places.city[1] == "40" and snap.places.raid[1] == "55" and snap.places.wilds[1] == "55", "retail tags mapped")
A.SetTravelling("40", false)
check(A.LoadKeepsake("Road trip") and A.IsTravelling("40"), "loading restores the arrangement")

-- The journal builds and every page refreshes -----------------------------------------------------
A.ToggleJournal()
for page = 1, 4 do A.ToggleJournal(page) end
check(_G.PetalJournal and _G.PetalJournal:IsShown(), "journal opens")

-- Together time is recorded ---------------------------------------------------------------------
fire("PLAYER_LOGOUT")
local total = 0
for _, seconds in pairs(A.db.together) do total = total + seconds end
check(total > 0, "time together recorded")

print(("PETAL smoke: %d assertions passed"):format(assertions))
