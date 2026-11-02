-- The account's companions.
--
-- Forever keeps companions account-wide in the Classic-style pet journal:
-- no battles, no levels, one of each. Petal therefore remembers companions by
-- species (key = tostring(speciesID)), not by the per-pet GUID, and resolves
-- the owned GUID only when it summons. Species keys also make shared codes
-- work between accounts.
--
-- Discovery order:
--   1. C_PetJournal.GetOwnedPetIDs()  (ignores the journal's filters)
--   2. C_PetJournal index walk         (filters widened, then restored)
--   3. GetCompanionInfo("CRITTER")     (older companion API; key "c<spellID>")

local _, A = ...

A.pets, A.petsByKey, A.petsByGUID = {}, {}, {}
A.collectionSource = nil

local J = C_PetJournal

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function Plain(value)
    if value == nil or A.IsSecret(value) then return nil end
    return value
end

local function Record(petID)
    local ok, speciesID, customName, _, _, _, displayID, favorite, name, icon, _, creatureID =
        Call(J and J.GetPetInfoByPetID, petID)
    speciesID = ok and Plain(speciesID)
    if not speciesID then return nil end
    name, customName = Plain(name), Plain(customName)
    if customName == "" then customName = nil end
    local pet = {
        key = tostring(speciesID),
        speciesID = speciesID,
        petID = petID,
        speciesName = name,
        customName = customName,
        name = customName or name or ("Companion " .. speciesID),
        icon = Plain(icon),
        displayID = Plain(displayID),
        creatureID = Plain(creatureID),
        favorite = Plain(favorite) == true,
    }
    local okFanfare, wrapped = Call(J.PetNeedsFanfare, petID)
    pet.wrapped = okFanfare and Plain(wrapped) == true
    local okInfo, _, err = Call(J.GetPetSummonInfo, petID)
    -- The other faction's companions can never come; hide them like Blizzard.
    pet.neverUsable = okInfo and Enum and Enum.PetJournalError
        and Plain(err) == Enum.PetJournalError.InvalidFaction or false
    return pet
end

local function OwnedIDs()
    local ok, owned = Call(J and J.GetOwnedPetIDs)
    if ok and type(owned) == "table" and not A.IsSecret(owned) and #owned > 0 then
        return owned, "owned"
    end
    return nil
end

-- Widen the journal's filters so the walk sees every owned companion, then put
-- the player's own filters back exactly as they were.
local suppressUntil = 0
local function IndexWalk()
    if not (J and J.GetNumPets and J.GetPetInfoByIndex) then return nil end
    local restore = {}
    local function Save(get, set, arg, want)
        local ok, value = Call(get, arg)
        if ok and value ~= want and type(set) == "function" then
            restore[#restore + 1] = function() pcall(set, arg, value) end
            pcall(set, arg, want)
        end
    end
    local okSearch, search = Call(J.GetSearchFilter)
    if okSearch and type(search) == "string" and search ~= "" and J.ClearSearchFilter then
        restore[#restore + 1] = function() pcall(J.SetSearchFilter, search) end
        pcall(J.ClearSearchFilter)
    end
    if LE_PET_JOURNAL_FILTER_COLLECTED then
        Save(J.IsFilterChecked, J.SetFilterChecked, LE_PET_JOURNAL_FILTER_COLLECTED, true)
    end
    local okTypes, types = Call(J.GetNumPetTypes)
    for i = 1, okTypes and tonumber(types) or 0 do Save(J.IsPetTypeChecked, J.SetPetTypeFilter, i, true) end
    local okSources, sources = Call(J.GetNumPetSources)
    for i = 1, okSources and tonumber(sources) or 0 do Save(J.IsPetSourceChecked, J.SetPetSourceChecked, i, true) end

    local ids = {}
    local okCount, count = Call(J.GetNumPets)
    for index = 1, okCount and math.min(tonumber(count) or 0, 5000) or 0 do
        local okPet, petID, _, owned = Call(J.GetPetInfoByIndex, index)
        if okPet and Plain(owned) and Plain(petID) then ids[#ids + 1] = petID end
    end
    for i = #restore, 1, -1 do restore[i]() end
    -- Our own filter changes fire PET_JOURNAL_LIST_UPDATE; don't rescan for them.
    if #restore > 0 then suppressUntil = A.Now() + 2 end
    return ids, "index"
end

local function LegacyCompanions()
    if type(GetNumCompanions) ~= "function" or type(GetCompanionInfo) ~= "function" then return nil end
    local list = {}
    local ok, count = pcall(GetNumCompanions, "CRITTER")
    for index = 1, ok and tonumber(count) or 0 do
        local okInfo, creatureID, name, spellID, icon = pcall(GetCompanionInfo, "CRITTER", index)
        spellID = okInfo and Plain(spellID)
        if spellID then
            list[#list + 1] = {
                key = "c" .. spellID, spellID = spellID, legacyIndex = index,
                name = Plain(name) or ("Companion " .. spellID), speciesName = Plain(name),
                icon = Plain(icon), creatureID = Plain(creatureID),
            }
        end
    end
    return list
end

local function Sort(list)
    table.sort(list, function(a, b)
        local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
        if an ~= bn then return an < bn end
        return a.key < b.key
    end)
end

function A.ScanCollection()
    local pets, byKey, byGUID, source = {}, {}, {}, nil
    if J then
        local ids
        ids, source = OwnedIDs()
        if not ids then ids, source = IndexWalk() end
        for _, petID in ipairs(ids or {}) do
            local pet = Record(petID)
            if pet and not pet.neverUsable then
                byGUID[petID] = pet
                local existing = byKey[pet.key]
                -- One per species in Forever; if not, prefer a favorite copy.
                if not existing then
                    byKey[pet.key] = pet
                    pets[#pets + 1] = pet
                elseif pet.favorite and not existing.favorite then
                    for i, other in ipairs(pets) do if other == existing then pets[i] = pet end end
                    byKey[pet.key] = pet
                end
            end
        end
    end
    if #pets == 0 then
        local legacy = LegacyCompanions()
        if legacy and #legacy > 0 then
            source = "companion"
            for _, pet in ipairs(legacy) do
                if not byKey[pet.key] then byKey[pet.key] = pet; pets[#pets + 1] = pet end
            end
        end
    end
    Sort(pets)
    -- Details already read for a species survive the rescan.
    for _, pet in ipairs(pets) do
        local old = A.petsByKey[pet.key]
        if old and old.details then pet.details = old.details end
    end
    A.pets, A.petsByKey, A.petsByGUID = pets, byKey, byGUID
    A.collectionSource = source
    A.scanned = true
    A.Fire("collection")
    return #pets
end

local scanSerial = 0
function A.RequestScan(force)
    if not force and A.Now() < suppressUntil then return end
    scanSerial = scanSerial + 1
    local serial = scanSerial
    C_Timer.After(0.5, function()
        if serial == scanSerial and A.db then A.ScanCollection() end
    end)
end

-- One companion ----------------------------------------------------------------

function A.GetPet(key)
    return key and A.petsByKey[key] or nil
end

-- Lore and model data, read on first view.
function A.PetDetails(pet)
    if not pet then return {} end
    if pet.details then return pet.details end
    local details = {}
    if pet.speciesID and J and J.GetPetInfoBySpeciesID then
        local ok, _, _, _, creatureID, sourceText, description, _, _, _, _, _, displayID =
            pcall(J.GetPetInfoBySpeciesID, pet.speciesID)
        if ok then
            details.creatureID = Plain(creatureID)
            details.source = Plain(sourceText)
            details.description = Plain(description)
            details.displayID = Plain(displayID)
        end
        local okScene, sceneID = Call(J.GetPetModelSceneInfoBySpeciesID, pet.speciesID)
        details.sceneID = okScene and Plain(sceneID) or nil
    end
    details.displayID = pet.displayID or details.displayID
    details.creatureID = details.creatureID or pet.creatureID
    pet.details = details
    return details
end

function A.IsSummonable(pet)
    if not pet then return false end
    if pet.legacyIndex then return true end
    if pet.wrapped then return false end
    local ok, result = Call(J and J.PetIsSummonable, pet.petID)
    return ok and Plain(result) == true
end

function A.CurrentPet()
    if J and J.GetSummonedPetGUID then
        local ok, guid = Call(J.GetSummonedPetGUID)
        guid = ok and Plain(guid)
        if not guid then return nil end
        local pet = A.petsByGUID[guid]
        if pet then return pet end
        -- A companion not in the last scan (just learned): identify it now.
        local record = Record(guid)
        return record and (A.petsByKey[record.key] or record) or nil
    end
    if type(GetNumCompanions) == "function" then
        local ok, count = pcall(GetNumCompanions, "CRITTER")
        for index = 1, ok and count or 0 do
            local okInfo, _, _, spellID, _, summoned = pcall(GetCompanionInfo, "CRITTER", index)
            if okInfo and Plain(summoned) and Plain(spellID) then
                return A.petsByKey["c" .. spellID]
            end
        end
    end
    return nil
end

function A.SummonPet(pet)
    if not pet then return false end
    if pet.legacyIndex then
        return pcall(CallCompanion, "CRITTER", pet.legacyIndex)
    end
    if not (J and J.SummonPetByGUID and pet.petID) then return false end
    local ok, err = pcall(J.SummonPetByGUID, pet.petID)
    if not ok then A.Debug("summon failed", err) end
    return ok
end

function A.DismissPet(pet)
    if not pet then return false end
    if pet.legacyIndex then return pcall(DismissCompanion, "CRITTER") end
    if J and J.DismissSummonedPet then return pcall(J.DismissSummonedPet, pet.petID) end
    -- Summoning the active companion again sends it away.
    return pcall(J.SummonPetByGUID, pet.petID)
end

function A.Unwrap(pet)
    if pet and pet.wrapped and J and J.ClearFanfare then
        pcall(J.ClearFanfare, pet.petID)
        pet.wrapped = false
        A.RequestScan(true)
        return true
    end
end

function A.SetFavorite(pet, favorite)
    if not (pet and pet.petID and J and J.SetFavorite) then return end
    pcall(J.SetFavorite, pet.petID, favorite and 1 or 0)
    pet.favorite = favorite
    A.Fire("collection")
end

function A.CanSetFavorite(pet)
    if not (pet and pet.petID and J and J.SetFavorite) then return false end
    local ok, unlocked = Call(J.IsJournalUnlocked)
    return not ok or Plain(unlocked) ~= false
end

-- /petal probe: records what this client's pet API returns, so a report from
-- the game can confirm the discovery path. Saved in PETALDB.probe.
function A.Probe()
    local probe = { time = date and date("%Y-%m-%d %H:%M:%S"), apis = {} }
    for _, name in ipairs({ "GetOwnedPetIDs", "GetNumPets", "GetPetInfoByIndex", "GetPetInfoByPetID",
        "GetPetInfoBySpeciesID", "SummonPetByGUID", "DismissSummonedPet", "GetSummonedPetGUID",
        "PetIsSummonable", "PetNeedsFanfare", "GetPetModelSceneInfoBySpeciesID", "SetFavorite" }) do
        probe.apis[name] = J and type(J[name]) == "function" or false
    end
    probe.legacyCompanionAPI = type(GetNumCompanions) == "function"
    local okCount, total, owned = Call(J and J.GetNumPets)
    probe.numPets, probe.numOwned = okCount and total, okCount and owned
    local ids = OwnedIDs()
    probe.ownedIDs = ids and #ids or 0
    probe.source = A.collectionSource
    probe.scanned = #A.pets
    probe.sample = {}
    for i = 1, math.min(3, #A.pets) do
        local pet = A.pets[i]
        local details = A.PetDetails(pet)
        probe.sample[i] = { key = pet.key, name = pet.name, petID = tostring(pet.petID),
            summonable = A.IsSummonable(pet), wrapped = pet.wrapped,
            displayID = details.displayID, sceneID = details.sceneID,
            hasDescription = details.description ~= nil and details.description ~= "" }
    end
    local current = A.CurrentPet()
    probe.current = current and current.key
    A.db.probe = probe
    A.Print(("Probe: %d pets found via %s (journal owns %s). Saved to PETALDB.probe.")
        :format(#A.pets, tostring(A.collectionSource), tostring(probe.numOwned)))
end
