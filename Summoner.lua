-- Which companion to call, and when to leave the player alone.
--
-- Rules, in order:
--   * Never interrupt: no summon while fighting, dead, riding, flying, eating
--     or drinking, sitting at a campfire, stealthed, shapeshifted or casting.
--   * A companion who loves the current place stays out (no churn).
--   * A companion the player called themselves stays until they move on to a
--     different kind of place (option).
--   * After the player sends a companion away, Petal rests for a while (option).
--   * A companion hidden by travel (mount, flight, loading screen, death)
--     comes back as the same companion.
--   * If nobody is chosen for a place, any companion who travels with you may come.

local _, A = ...

local S = { lastOwnActionAt = -100, worldAt = 0 }
A.state = S

local CAMPFIRE_AURA = 1229739 -- "Welcoming Campfire": sitting at a Forever campfire

-- Roster and places ------------------------------------------------------------

function A.IsTravelling(key)
    return key ~= nil and A.db.roster[key] == true
end

function A.SetTravelling(key, on)
    if not key then return end
    if on then
        A.db.roster[key] = true
    else
        A.db.roster[key] = nil
        for _, place in ipairs(A.PLACES) do A.db.places[place][key] = nil end
    end
    A.Fire("roster", key)
    A.RequestEvaluation(0.3, "roster changed")
end

function A.LikesPlace(key, place)
    return key ~= nil and A.db.places[place] ~= nil and A.db.places[place][key] == true
end

function A.SetLikesPlace(key, place, on)
    if not (key and A.db.places[place]) then return end
    A.db.places[place][key] = on and true or nil
    if on then A.db.roster[key] = true end
    A.Fire("roster", key)
    A.RequestEvaluation(0.3, "places changed")
end

function A.LikesEverywhere(key)
    for _, place in ipairs(A.PLACES) do
        if not A.LikesPlace(key, place) then return false end
    end
    return true
end

function A.SetAllPlaces(key, on)
    if not key then return end
    for _, place in ipairs(A.PLACES) do A.db.places[place][key] = on and true or nil end
    if on then A.db.roster[key] = true end
    A.Fire("roster", key)
    A.RequestEvaluation(0.3, "places changed")
end

function A.TravellingCount()
    local count = 0
    for _, pet in ipairs(A.pets) do if A.IsTravelling(pet.key) then count = count + 1 end end
    return count
end

function A.PlaceCount(place)
    local count = 0
    for _, pet in ipairs(A.pets) do if A.LikesPlace(pet.key, place) then count = count + 1 end end
    return count
end

-- Companions who may come to this place. The second result is true when
-- nobody is chosen for it and every travelling companion is allowed instead.
function A.PoolFor(place, includeUnsummonable)
    local pool = {}
    for _, pet in ipairs(A.pets) do
        if A.LikesPlace(pet.key, place) and (includeUnsummonable or A.IsSummonable(pet)) then
            pool[#pool + 1] = pet
        end
    end
    if #pool > 0 then return pool, false end
    for _, pet in ipairs(A.pets) do
        if A.IsTravelling(pet.key) and (includeUnsummonable or A.IsSummonable(pet)) then
            pool[#pool + 1] = pet
        end
    end
    return pool, true
end

local function Contains(pool, key)
    for _, pet in ipairs(pool) do if pet.key == key then return true end end
    return false
end

-- Never interrupt ------------------------------------------------------------------

local foodNames
local function FoodNames()
    if foodNames then return foodNames end
    foodNames = { Food = true, Drink = true, ["Food & Drink"] = true, Refreshment = true }
    local getName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    for _, spellID in ipairs({ 433, 430, 1131, 22734, 24005 }) do
        local ok, name = pcall(getName, spellID)
        if ok and type(name) == "string" then foodNames[name] = true end
    end
    return foodNames
end

-- Reads the player's own buffs; returns "campfire", "eating" or nil.
local function RestingAura()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, CAMPFIRE_AURA)
        if ok and aura then return "campfire" end
    end
    local names = FoodNames()
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for index = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
            if not ok or not aura then break end
            local name = aura.name
            if name and not A.IsSecret(name) and names[name] then return "eating" end
        end
    end
    return nil
end

local function Check(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    return ok and not A.IsSecret(value) and value and true or false
end

-- Cat, travel, aquatic, bear, dire bear, flight and Ghost Wolf. Moonkin and
-- Tree of Life can still call a companion.
local BLOCKING_FORMS = { [1] = true, [3] = true, [4] = true, [5] = true, [8] = true,
    [16] = true, [27] = true, [29] = true }
local function InBlockingForm()
    if type(GetShapeshiftFormID) ~= "function" then return false end
    local ok, form = pcall(GetShapeshiftFormID)
    return ok and form ~= nil and not A.IsSecret(form) and BLOCKING_FORMS[form] == true
end

function A.BlockReason()
    A.waitingOnAura, A.waitingOnCast = false, false
    if Check(InCombatLockdown) or Check(UnitAffectingCombat, "player") then return "combat" end
    if Check(UnitIsDeadOrGhost, "player") then return "dead" end
    if Check(UnitIsFeignDeath, "player") then return "feign" end
    if Check(UnitOnTaxi, "player") then return "taxi" end
    if Check(IsMounted) then return "mounted" end
    if Check(UnitInVehicle, "player") or Check(UnitHasVehicleUI, "player") then return "vehicle" end
    if Check(IsStealthed) then return "stealth" end
    if InBlockingForm() then return "form" end
    if Check(UnitCastingInfo, "player") or Check(UnitChannelInfo, "player") then
        A.waitingOnCast = true
        return "casting"
    end
    local aura = RestingAura()
    if aura then
        A.waitingOnAura = true
        return aura
    end
    return nil
end

local BLOCK_TEXT = {
    combat = "in combat",
    dead = "you are dead",
    feign = "feigning death",
    taxi = "on a flight path",
    mounted = "mounted",
    vehicle = "in a vehicle",
    stealth = "stealthed",
    form = "shapeshifted",
    casting = "casting",
    campfire = "sitting at a campfire",
    eating = "eating or drinking",
    nopets = "No pets ticked.",
    resting = "Waiting after you dismissed your pet.",
    off = "Automatic summoning is off.",
    pending = "A pet is being summoned.",
    only = "No other pet for this place.",
    kept = "Your pet already fits this place.",
}
local BUSY_TEXT = {}
-- Busy reasons read "Waiting: mounted."; the others are full sentences.
function A.BlockText(reason)
    local text = BLOCK_TEXT[reason] or tostring(reason)
    if BUSY_TEXT[reason] then return "Waiting: " .. text .. "." end
    return text
end

local BUSY = { combat = true, dead = true, feign = true, taxi = true, mounted = true, vehicle = true,
    stealth = true, form = true, casting = true, campfire = true, eating = true, pending = true }
function A.IsBusyReason(reason) return BUSY[reason] == true end
for reason in pairs(BUSY) do if reason ~= "pending" then BUSY_TEXT[reason] = true end end

-- Rest after a dismissal ------------------------------------------------------------

local graceSerial = 0
function A.ClearGrace() S.graceUntil = nil; graceSerial = graceSerial + 1 end
function A.GraceRemaining()
    if not S.graceUntil then return 0 end
    local left = S.graceUntil - A.Now()
    if left <= 0 then S.graceUntil = nil; return 0 end
    return left
end

local function StartGrace()
    if not A.db.graceEnabled then return end
    local seconds = A.db.graceMinutes * 60
    S.graceUntil = A.Now() + seconds
    graceSerial = graceSerial + 1
    local serial = graceSerial
    C_Timer.After(seconds + 0.2, function()
        if serial == graceSerial then S.graceUntil = nil; A.RequestEvaluation(0, "rest over") end
    end)
end

-- Watching the companion --------------------------------------------------------------

local TRAVEL_EVENTS = {
    PLAYER_ENTERING_WORLD = true, PLAYER_MOUNT_DISPLAY_CHANGED = true, PLAYER_CONTROL_GAINED = true,
    UPDATE_STEALTH = true, UPDATE_SHAPESHIFT_FORM = true, PLAYER_DEAD = true, login = true,
}

local function Hidden(reason)
    if TRAVEL_EVENTS[reason] then return true end
    if A.Now() - S.worldAt < 6 then return true end
    local block = A.BlockReason()
    return block == "dead" or block == "taxi" or block == "mounted" or block == "vehicle"
        or block == "stealth" or block == "form" or block == "feign"
end

local function AddTogether(key, since)
    if key and since then
        local seconds = math.max(0, A.Now() - since)
        A.db.together[key] = (A.db.together[key] or 0) + math.floor(seconds + 0.5)
    end
end

function A.ObservePet(reason)
    if reason == "PLAYER_ENTERING_WORLD" or reason == "login" then S.worldAt = A.Now() end
    if reason == "logout" then
        AddTogether(S.currentKey, S.currentSince)
        S.currentSince = A.Now()
        return
    end
    local current = A.CurrentPet()
    local key = current and current.key
    if key == S.currentKey then return current end
    local previous = S.currentKey
    AddTogether(previous, S.currentSince)
    S.currentKey = key
    S.currentSince = key and A.Now() or nil
    if key then
        S.hiddenKey, S.judging = nil, false
        if S.pendingKey == key or A.Now() - S.lastOwnActionAt < 4 then
            S.pendingKey = nil
        elseif reason ~= "login" and reason ~= "PLAYER_ENTERING_WORLD" then
            -- The player called this one themselves.
            S.ownChoice = { key = key, place = A.GetPlace() }
            A.ClearGrace()
        end
    elseif previous then
        if A.Now() - S.lastOwnActionAt < 4 then
            -- Petal's own swap.
        elseif Hidden(reason) then
            S.hiddenKey = previous
        else
            -- A mount or loading screen can hide the companion a moment before
            -- the game reports it. Judge once things have settled.
            local serial = (S.goneSerial or 0) + 1
            S.goneSerial, S.judging = serial, true
            C_Timer.After(1.5, function()
                if S.goneSerial ~= serial then return end
                S.judging = false
                if S.currentKey ~= nil then return end
                if Hidden(nil) then
                    S.hiddenKey = previous
                else
                    S.ownChoice = nil
                    StartGrace()
                end
                A.RequestEvaluation(0.2, "companion gone")
            end)
        end
    end
    A.Fire("pet", current)
    return current
end

-- Calling ------------------------------------------------------------------------------

local WHISPERS = {
    any = { "%s pads along at your side.", "%s catches up with you.", "%s is glad to be with you again.",
        "%s trots after you." },
    city = { "%s stares wide-eyed at the crowds.", "%s stays close in the busy streets." },
    inn = { "%s settles in by the hearth.", "%s sniffs at the smell of stew." },
    wilds = { "%s sniffs the wind and follows you.", "%s bounds ahead down the road." },
    dungeon = { "%s creeps in behind you, keeping close.", "%s peers into the dark with you." },
    raid = { "%s bravely follows you in.", "%s keeps well behind the tank." },
    battleground = { "%s follows you into the fray.", "%s keeps its head down." },
}

local function Whisper(pet, place)
    if not A.db.whispers then return end
    local lines = WHISPERS[place]
    if not lines or math.random(1, 3) == 1 then lines = WHISPERS.any end
    local who = pet.customName or ("Your " .. (pet.speciesName or pet.name))
    local line = lines[math.random(1, #lines)]:format(who)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd8c09a" .. line .. "|r") end
end
A.Whisper = Whisper

local function Choose(pool, avoidKey)
    local candidates = {}
    for _, pet in ipairs(pool) do
        if pet.key ~= avoidKey then candidates[#candidates + 1] = pet end
    end
    if #candidates == 0 then return nil end
    return candidates[math.random(1, #candidates)]
end

local function Summon(pet, place, quiet)
    local now = A.Now()
    S.pendingKey, S.pendingAt, S.lastOwnActionAt = pet.key, now, now
    local ok = A.SummonPet(pet)
    if not ok then S.pendingKey = nil; return false end
    A.db.called[pet.key] = (A.db.called[pet.key] or 0) + 1
    A.lastCalled = pet.key
    if not quiet then Whisper(pet, place) end
    A.Fire("pet")
    return true
end

local function Pending()
    return S.judging or (S.pendingKey and A.Now() - (S.pendingAt or 0) < 3)
end

function A.Evaluate(reason, force)
    if not A.db then return false end
    local place = A.GetPlace()
    if place ~= S.lastPlace then
        S.lastPlace = place
        if S.ownChoice and S.ownChoice.place ~= place then S.ownChoice = nil end
        A.Fire("place", place)
    end
    local function Finish(ok, why)
        A.lastBlock = not ok and why or nil
        A.lastResult = why
        A.Fire("state", why)
        return ok, why
    end
    if not A.db.enabled and not force then return Finish(false, "off") end
    local block = A.BlockReason()
    if block then return Finish(false, block) end
    if Pending() then return Finish(false, "pending") end

    local pool = A.PoolFor(place)
    if #pool == 0 then return Finish(false, "nopets") end
    local current = A.ObservePet(reason)
    if current then
        if Contains(pool, current.key) then return Finish(false, "kept") end
        if A.db.respectOwnChoice and S.ownChoice and S.ownChoice.key == current.key then
            return Finish(false, "own choice")
        end
    elseif not force and A.GraceRemaining() > 0 then
        return Finish(false, "resting")
    end

    local pet, quiet
    if not current and S.hiddenKey and Contains(pool, S.hiddenKey) then
        pet, quiet = A.GetPet(S.hiddenKey), true
    end
    pet = pet or Choose(pool, current and current.key)
    if not pet then return Finish(false, "only") end
    if force then A.ClearGrace() end
    if not Summon(pet, place, quiet) then return Finish(false, "failed") end
    S.hiddenKey = nil
    A.Debug("called", pet.name, "for", place, "-", reason)
    return Finish(true, "called")
end

-- "Call another companion": a different one who loves this place.
function A.CallAnother(source)
    if not A.db then return false end
    local block = A.BlockReason()
    if block then return false, block end
    if Pending() then return false, "pending" end
    local place = A.GetPlace()
    local pool = A.PoolFor(place)
    if #pool == 0 then return false, "nopets" end
    local current = A.CurrentPet()
    local pet = Choose(pool, current and current.key)
    if not pet then return false, "only" end
    A.ClearGrace()
    S.ownChoice = nil
    local ok = Summon(pet, place)
    return ok, ok and "called" or "failed"
end

-- Summon a specific companion from the journal. Counts as the player's choice.
function A.CallPet(pet)
    if not pet then return false end
    local block = A.BlockReason()
    if block and block ~= "casting" then return false, block end
    A.ClearGrace()
    local ok = A.SummonPet(pet)
    if ok then S.ownChoice = { key = pet.key, place = A.GetPlace() } end
    return ok
end

function A.DismissCurrent()
    local current = A.CurrentPet()
    if current then A.DismissPet(current) end
end

function A.OwnChoiceKey() return S.ownChoice and S.ownChoice.key or nil end
