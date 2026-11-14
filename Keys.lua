-- Petal's two keys (Bindings.xml), set from its own windows: the key as a
-- button; click, then press a key. Escape cancels, right-click clears.
-- A key that already did something else is asked about first.
-- A.Keys.Setter(parent, action, width, plain) builds one; the rest is the logic,
-- for the tests.

local _, A = ...
local K = {}
A.Keys = K

-- Order shown in the windows.
K.ACTIONS = {
    { action = "PETAL_TOGGLE_JOURNAL", label = "Open Petal" },
    { action = "PETAL_CHANGE_PET", label = "Summon another" },
}

local MODIFIERS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true,
}
-- Never bound: chat's Enter and Backspace, and the left and right clicks.
local NEVER = { ENTER = true, BACKSPACE = true, BUTTON1 = true, BUTTON2 = true }
local BUTTONS = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3" }

function K.IsModifier(key) return MODIFIERS[key] == true end
function K.Refused(key) return NEVER[key] == true end
function K.Button(mouse) return BUTTONS[mouse] or tostring(mouse):upper() end

-- The key pressed with its modifiers, as the bindings write it.
function K.Combo(key)
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

-- The key `action` is on, for showing, or nil.
function K.Text(action)
    local key = GetBindingKey and GetBindingKey(action)
    if not key then return nil end
    return GetBindingText and GetBindingText(key) or key
end

-- What `key` does now, in the bindings' words; nil when nothing, or `action`.
function K.Taken(action, key)
    local before = GetBindingAction and GetBindingAction(key)
    if not before or before == "" or before == action then return nil end
    return _G["BINDING_NAME_" .. before] or before
end

local function Save()
    if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
end

-- Binds `key` to `action`, in place of the action's old key and of whatever
-- had the key. Out of combat only.
function K.Bind(action, key)
    if InCombatLockdown() then return false, "Not in combat." end
    for _, old in ipairs({ GetBindingKey(action) }) do SetBinding(old) end
    SetBinding(key, action)
    Save()
    A.Fire("options")
    return true
end

function K.Clear(action)
    if InCombatLockdown() then return false, "Not in combat." end
    for _, old in ipairs({ GetBindingKey(action) }) do SetBinding(old) end
    Save()
    A.Fire("options")
    return true
end

local function Say(text)
    if text and UIErrorsFrame then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end

-- Asks before taking a key from another action; binds on yes.
local function Offer(action, key)
    local taken = K.Taken(action, key)
    if not taken or not (StaticPopupDialogs and StaticPopup_Show) then
        local ok, err = K.Bind(action, key)
        if not ok then Say(err) end
        return
    end
    StaticPopupDialogs.PETAL_REPLACE_KEY = StaticPopupDialogs.PETAL_REPLACE_KEY or {
        text = "%s is set to %s.\n\nUse it for %s?",
        button1 = "Use it",
        button2 = CANCEL or "Cancel",
        OnAccept = function(_, data)
            local ok, err = K.Bind(data.action, data.key)
            if not ok then Say(err) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local shown = GetBindingText and GetBindingText(key) or key
    local name = _G["BINDING_NAME_" .. action] or action
    StaticPopup_Show("PETAL_REPLACE_KEY", shown, taken, name, { action = action, key = key })
end
K.Offer = Offer

-- One at a time: starting another setter stops the one listening.
local listening
local setters = {}

-- `plain` keeps Blizzard's button look (for the Settings page).
function K.Setter(parent, action, width, plain)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 150, 22)
    if A.Skin and not plain then A.Skin.Button(button) end
    button.action = action
    button:RegisterForClicks("AnyUp")
    setters[#setters + 1] = button

    function button:Refresh()
        if listening == self then
            self:SetText("|cffffd100Press a key|r")
        else
            self:SetText(K.Text(action) or "|cff808080Not set|r")
        end
    end

    function button:Stop()
        if listening ~= self then return end
        listening = nil
        self:EnableKeyboard(false)
        self:SetScript("OnKeyDown", nil)
        self:Refresh()
    end

    local function Take(key)
        button:Stop()
        if K.Refused(key) then Say("That key stays with the game."); return end
        Offer(action, K.Combo(key))
    end

    function button:Listen()
        if InCombatLockdown() then Say("Not in combat."); return end
        if listening then listening:Stop() end
        listening = self
        self:EnableKeyboard(true)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        self:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then button:Stop(); return end
            if K.IsModifier(key) then return end
            Take(key)
        end)
        self:Refresh()
    end

    button:SetScript("OnClick", function(self, mouse)
        if listening == self then
            -- Left or right click cancels; other mouse buttons bind.
            if mouse == "LeftButton" or mouse == "RightButton" then self:Stop() else Take(K.Button(mouse)) end
            return
        end
        if mouse == "RightButton" then
            local ok, err = K.Clear(action)
            if not ok then Say(err) end
            self:Refresh()
        elseif mouse == "LeftButton" then
            self:Listen()
        end
    end)
    button:HookScript("OnHide", function(self) self:Stop() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(_G["BINDING_NAME_" .. action] or action, 1, 0.82, 0)
        GameTooltip:AddLine("Click to set. Right-click to clear.", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Refresh()
    return button
end

-- Every setter shows the current keys (after a bind from either window).
function K.RefreshAll()
    for _, setter in ipairs(setters) do setter:Refresh() end
end
A.On("options", K.RefreshAll)
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UPDATE_BINDINGS")
watcher:SetScript("OnEvent", K.RefreshAll)
