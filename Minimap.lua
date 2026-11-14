-- The minimap button (click opens Petal, drag moves it round the edge) and
-- Petal's page in Blizzard's Settings (Esc > Options > AddOns).
-- Saved: PETALDB.minimapButton (shown), PETALDB.minimapAngle (degrees).
-- Hand-rolled, no library, under a global name for minimap collectors.

local _, A = ...
local M = {}
A.Minimap = M

local ICON = "Interface\\AddOns\\PETAL\\Media\\PetalIcon"
local SIZE, RING, GROUND, LOGO = 31, 50, 24, 20
local OUTSIDE = 5

-- Which quarters are round: bottom right, bottom left, top right, top left.
local SHAPES = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- The button's middle from the minimap's, for an angle (0 east, 90 north).
function M.Offset(angle)
    local rad = math.rad(angle)
    local x, y = math.cos(rad), math.sin(rad)
    local quarter = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0)
    local shape = SHAPES[GetMinimapShape and GetMinimapShape() or "ROUND"] or SHAPES.ROUND
    local reach = Minimap:GetWidth() / 2 + OUTSIDE
    if shape[quarter] then return x * reach, y * reach end
    local corner = math.sqrt(2 * reach * reach) - 10
    return math.max(-reach, math.min(x * corner, reach)), math.max(-reach, math.min(y * corner, reach))
end

local button

local function Place(angle)
    local x, y = M.Offset(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CursorAngle()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local midX, midY = Minimap:GetCenter()
    return math.deg(math.atan2(y / scale - midY, x / scale - midX)) % 360
end

local function Press(down)
    local sink = down and 1 or 0
    button.logo:ClearAllPoints()
    button.logo:SetPoint("CENTER", button, "CENTER", sink, -sink)
    local shade = down and 0.8 or 1
    button.logo:SetVertexColor(shade, shade, shade)
end

local function Build()
    button = CreateFrame("Button", "PetalMinimapButton", Minimap)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    if button.SetFixedFrameStrata then button:SetFixedFrameStrata(true) end
    button:SetFrameLevel(8)
    if button.SetFixedFrameLevel then button:SetFixedFrameLevel(true) end
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local ground = button:CreateTexture(nil, "BACKGROUND")
    ground:SetSize(GROUND, GROUND)
    ground:SetPoint("CENTER")
    ground:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    button.logo = button:CreateTexture(nil, "ARTWORK")
    button.logo:SetSize(LOGO, LOGO)
    button.logo:SetTexture(ICON)
    if button.CreateMaskTexture and button.logo.AddMaskTexture then
        local mask = button:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(button.logo)
        button.logo:AddMaskTexture(mask)
    end
    Press(false)

    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetSize(RING, RING)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Petal", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function() PETAL_ToggleJournal() end)
    button:SetScript("OnMouseDown", function() Press(true) end)
    button:SetScript("OnMouseUp", function() Press(false) end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        Press(true)
        self:SetScript("OnUpdate", function() Place(CursorAngle()) end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        Press(false)
        A.db.minimapAngle = CursorAngle()
        Place(A.db.minimapAngle)
    end)
end

-- Made the first time it is wanted.
function M.Refresh()
    if not A.db or not Minimap then return end
    local on = A.db.minimapButton == true
    if not button then
        if not on then return end
        Build()
    end
    Place(A.db.minimapAngle)
    button:SetShown(on)
end
function M.Button() return button end

-- Blizzard Settings page -----------------------------------------------------------

local function RegisterSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -16)
    heading:SetText("Petal")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(140, 26)
    open:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -14)
    open:SetText("Open Petal")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        A.ToggleJournal(nil, true)
    end)
    local slash = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    slash:SetPoint("LEFT", open, "RIGHT", 12, 0)
    slash:SetText("/petal")

    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -2, -14)
    local label = check.Text or check.text or check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:ClearAllPoints()
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetFontObject("GameFontHighlight")
    label:SetText("Minimap icon")
    check:SetScript("OnClick", function(self)
        A.SetOption("minimapButton", self:GetChecked() == true)
    end)

    local keysTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    keysTitle:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 2, -18)
    keysTitle:SetText("Keys")
    local anchor = keysTitle
    for _, entry in ipairs(A.Keys.ACTIONS) do
        local name = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        name:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
        name:SetWidth(130); name:SetJustifyH("LEFT")
        name:SetText(entry.label)
        local setter = A.Keys.Setter(panel, entry.action, 160, true)
        setter:SetPoint("LEFT", name, "RIGHT", 10, 0)
        anchor = name
    end

    panel:SetScript("OnShow", function()
        check:SetChecked(A.db.minimapButton == true)
        A.Keys.RefreshAll()
    end)
    A.On("options", function() if panel:IsShown() then check:SetChecked(A.db.minimapButton == true) end end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Petal")
    Settings.RegisterAddOnCategory(category)
    M.settingsCategory = category
end

A.On("options", function() M.Refresh() end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    M.Refresh()
    local ok, err = pcall(RegisterSettings)
    if not ok then A.Debug("settings page", err) end
end)
