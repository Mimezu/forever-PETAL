-- Petal for WoW Forever: saved settings, events, timers and slash commands.
--
-- Files by responsibility:
--   Core.lua        settings, events, timers, slash commands
--   Collection.lua  the account's companions (C_PetJournal, legacy fallback)
--   Places.lua      where the player is (capital, inn, wilds, dungeon...)
--   Summoner.lua    which companion to call, and when not to disturb
--   Keepsakes.lua   saved arrangements, import and export codes
--   Skin.lua        Legacy window art (no dependency on other addons)
--   UI.lua          the companion journal window

local ADDON, A = ...
_G.PETAL = A
A.name = ADDON
A.version = "2.0.1"

BINDING_HEADER_PETAL = "Petal"
BINDING_NAME_PETAL_CHANGE_PET = "Summon another pet"
BINDING_NAME_PETAL_TOGGLE_JOURNAL = "Open Petal"

-- Places, in the order the journal shows them. Keys are saved; never rename.
A.PLACES = { "city", "inn", "wilds", "dungeon", "raid", "battleground" }

A.DEFAULTS = {
    enabled = true,
    respectOwnChoice = true,  -- a companion you call yourself stays out
    graceEnabled = true,      -- rest after you send a companion away
    graceMinutes = 10,
    shuffle = false,          -- change companions now and then
    shuffleMin = 20,
    shuffleMax = 40,
    whispers = false,         -- a short line in chat when a companion joins
    page = 1,
    filter = "all",
}

local function CopyDefaults(db)
    for key, value in pairs(A.DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    db.roster = type(db.roster) == "table" and db.roster or {}
    db.places = type(db.places) == "table" and db.places or {}
    for _, place in ipairs(A.PLACES) do
        if type(db.places[place]) ~= "table" then db.places[place] = {} end
    end
    db.called = type(db.called) == "table" and db.called or {}
    db.together = type(db.together) == "table" and db.together or {}
    db.keepsakes = type(db.keepsakes) == "table" and db.keepsakes or {}
    db.graceMinutes = math.max(1, math.min(60, tonumber(db.graceMinutes) or 10))
    db.shuffleMin = math.max(5, math.min(180, tonumber(db.shuffleMin) or 20))
    db.shuffleMax = math.max(db.shuffleMin, math.min(240, tonumber(db.shuffleMax) or 40))
    db.version = 1
end

function A.InitDB()
    if type(PETALDB) ~= "table" then PETALDB = {} end
    A.db = PETALDB
    CopyDefaults(A.db)
    return A.db
end

-- Utilities ------------------------------------------------------------------

function A.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

function A.Now()
    return GetTime and GetTime() or 0
end

function A.Print(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffe8c37aPetal:|r " .. tostring(text))
    end
end

function A.Debug(...)
    if not (A.db and A.db.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    A.Print("|cff888888" .. table.concat(parts, " ") .. "|r")
end

-- Listeners let the window refresh without the logic knowing about it.
local listeners = {}
function A.On(kind, callback)
    listeners[kind] = listeners[kind] or {}
    table.insert(listeners[kind], callback)
end
function A.Fire(kind, ...)
    for _, callback in ipairs(listeners[kind] or {}) do
        local ok, err = pcall(callback, ...)
        if not ok then A.Debug("listener", kind, err) end
    end
end

-- Timers ---------------------------------------------------------------------
-- One debounced evaluation, a slow safety check, and a one-shot shuffle timer.
-- No OnUpdate: everything else is driven by events.

local evalSerial, evalReason = 0, nil
function A.RequestEvaluation(delay, reason)
    evalSerial = evalSerial + 1
    local serial = evalSerial
    evalReason = reason or evalReason or "state changed"
    C_Timer.After(math.max(0, delay or 0), function()
        if serial ~= evalSerial or not A.db then return end
        local why = evalReason
        evalReason = nil
        A.Evaluate(why)
    end)
end

-- Some blockers clear a moment after their event fires (landing, loading
-- screens, resurrection). Evaluate promptly and once more after settling.
function A.RequestSettledEvaluation(delay, reason, settle)
    A.RequestEvaluation(delay, reason)
    C_Timer.After((delay or 0) + (settle or 1.2), function()
        if A.db then A.RequestEvaluation(0, (reason or "state") .. " settled") end
    end)
end

local ticker
function A.ResetTicker()
    if ticker then ticker:Cancel(); ticker = nil end
    if not (A.db and A.db.enabled) then return end
    ticker = C_Timer.NewTicker(90, function()
        if A.db.enabled then A.Evaluate("safety check") end
    end)
end

local shuffleTimer
A.shuffleDueAt = nil
function A.ResetShuffle(retry)
    if shuffleTimer then shuffleTimer:Cancel(); shuffleTimer = nil end
    A.shuffleDueAt = nil
    local db = A.db
    if not (db and db.enabled and db.shuffle) then return end
    local delay = retry or (math.random(db.shuffleMin * 60, db.shuffleMax * 60))
    A.shuffleDueAt = A.Now() + delay
    shuffleTimer = C_Timer.NewTimer(delay, function()
        shuffleTimer = nil
        local changed, reason = A.CallAnother("shuffle")
        -- Busy right now (riding, fighting, eating): try again soon.
        if not changed and A.IsBusyReason(reason) then A.ResetShuffle(30) else A.ResetShuffle() end
    end)
end

-- Settings -------------------------------------------------------------------

function A.SetOption(key, value)
    A.db[key] = value
    if key == "enabled" then
        A.ResetTicker(); A.ResetShuffle()
        if value then A.RequestEvaluation(0.1, "enabled") end
    elseif key == "shuffle" or key == "shuffleMin" or key == "shuffleMax" then
        A.ResetShuffle()
    elseif key == "graceEnabled" and not value then
        A.ClearGrace()
        A.RequestEvaluation(0.1, "rest period off")
    end
    A.Fire("options")
end

-- Events ---------------------------------------------------------------------

local frame = CreateFrame("Frame")
A.eventFrame = frame

-- Events that may change the place or clear a blocker, with (delay, settle).
local PLACE_EVENTS = {
    PLAYER_ENTERING_WORLD = { 2.0, 1.5 },
    ZONE_CHANGED_NEW_AREA = { 0.3, 1.0 },
    ZONE_CHANGED = { 0.3, 1.0 },
    ZONE_CHANGED_INDOORS = { 0.3, 1.0 },
    PLAYER_UPDATE_RESTING = { 0.3, 1.0 },
    PLAYER_REGEN_ENABLED = { 0.3, 1.0 },
    PLAYER_ALIVE = { 0.5, 1.5 },
    PLAYER_UNGHOST = { 0.5, 1.5 },
    PLAYER_CONTROL_GAINED = { 0.4, 1.2 },
    PLAYER_MOUNT_DISPLAY_CHANGED = { 0.4, 1.2 },
    UPDATE_STEALTH = { 0.4, 1.0 },
    UPDATE_SHAPESHIFT_FORM = { 0.4, 1.0 },
}
local CAST_END = {
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_FAILED = true,
}

local function Register(event, unit)
    if unit then
        pcall(frame.RegisterUnitEvent, frame, event, unit)
    else
        pcall(frame.RegisterEvent, frame, event)
    end
end

Register("ADDON_LOADED")
Register("PLAYER_LOGIN")
Register("PLAYER_LOGOUT")
for event in pairs(PLACE_EVENTS) do Register(event) end
for event in pairs(CAST_END) do Register(event, "player") end
Register("UNIT_AURA", "player")
Register("COMPANION_UPDATE")
Register("COMPANION_LEARNED")
Register("COMPANION_UNLEARNED")
Register("PET_JOURNAL_LIST_UPDATE")
Register("NEW_PET_ADDED")
Register("PLAYER_DEAD")

local lastAuraCheck = 0
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then A.InitDB() end
        return
    end
    if not A.db then return end
    if event == "PLAYER_LOGIN" then
        A.ScanCollection(true)
        A.ObservePet("login")
        A.ResetTicker()
        A.ResetShuffle()
        return
    elseif event == "PLAYER_LOGOUT" then
        A.ObservePet("logout")
        return
    end

    if event == "COMPANION_UPDATE" then
        -- Nil or "CRITTER": a companion came or went. "MOUNT" is irrelevant.
        if arg1 == nil or arg1 == "CRITTER" then
            A.ObservePet(event)
            A.RequestEvaluation(0.6, event)
        end
    elseif event == "PET_JOURNAL_LIST_UPDATE" or event == "COMPANION_LEARNED"
        or event == "COMPANION_UNLEARNED" or event == "NEW_PET_ADDED" then
        A.RequestScan(event ~= "PET_JOURNAL_LIST_UPDATE")
    elseif event == "PLAYER_DEAD" then
        A.ObservePet(event)
    elseif event == "UNIT_AURA" then
        -- Only matters while Petal is waiting on food, drink or a campfire.
        if A.waitingOnAura and A.Now() - lastAuraCheck > 1 then
            lastAuraCheck = A.Now()
            A.RequestEvaluation(0.5, "aura changed")
        end
    elseif CAST_END[event] then
        if A.waitingOnCast then A.RequestEvaluation(0.4, "cast ended") end
    else
        local timing = PLACE_EVENTS[event]
        if event == "PLAYER_ENTERING_WORLD" then A.ObservePet(event) end
        if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "UPDATE_STEALTH"
            or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_CONTROL_GAINED" then
            A.ObservePet(event)
        end
        A.RequestSettledEvaluation(timing[1], event, timing[2])
    end
end)

-- Keybindings and slash commands ----------------------------------------------

function PETAL_KeybindChangePet()
    local changed, reason = A.CallAnother("key")
    if not changed then A.Fire("feedback", reason) end
end

function PETAL_ToggleJournal()
    if A.ToggleJournal then A.ToggleJournal() end
end

local function Status()
    local place = A.GetPlace()
    local current = A.CurrentPet()
    A.Print(("Place: %s. Pet: %s."):format(A.PlaceInfo(place).label, current and current.name or "none"))
    local reason = A.lastBlock
    if reason then A.Print(A.BlockText(reason)) end
end

SLASH_PETAL1 = "/petal"
SlashCmdList.PETAL = function(message)
    message = (message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message == "" or message == "journal" or message == "options" then
        PETAL_ToggleJournal()
    elseif message == "next" or message == "another" then
        PETAL_KeybindChangePet()
    elseif message == "summon" or message == "call" then
        local ok, reason = A.Evaluate("manual", true)
        if not ok and reason then A.Print(A.BlockText(reason)) end
    elseif message == "dismiss" then
        A.DismissCurrent()
    elseif message == "on" or message == "resume" then
        A.SetOption("enabled", true); A.Print("Automatic summoning on.")
    elseif message == "off" or message == "pause" then
        A.SetOption("enabled", false); A.Print("Automatic summoning off.")
    elseif message == "status" then
        Status()
    elseif message == "probe" then
        A.Probe()
    elseif message == "debug" then
        A.db.debug = not A.db.debug
        A.Print("Debug " .. (A.db.debug and "on" or "off"))
    else
        A.Print("/petal - window, /petal next, /petal summon, /petal dismiss, /petal on|off, /petal status, /petal probe")
    end
end
