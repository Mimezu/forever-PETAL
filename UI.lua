-- The Petal window: a Legacy frame with side tabs, like Forever's own panels.
-- Pages: Pets, Places, Options, Saved sets. Built on first open.

local _, A = ...

local W, H = 760, 500
local PW, PH = W - 48, H - 122 -- page area (inside header and footer)
local GAP = 10
local GOLD, NOTE, DIM = { 1, 0.82, 0 }, { 0.80, 0.77, 0.70 }, { 0.5, 0.5, 0.5 }
local CHAT = { 0.85, 0.75, 0.60 }
local GIFT_ICON = "Interface\\Icons\\INV_Misc_Gift_01"
local MODEL_FACING = 0.45

-- Name, tab icon, tab tooltip.
local PAGES = {
    { "Pets", "Interface\\Icons\\Spell_Magic_PolymorphChicken",
        "Tick the pets Petal can summon, and choose where each one appears." },
    { "Places", "Interface\\Icons\\INV_Misc_Map_01",
        "All ticked pets by place. A place with no pets uses all ticked pets." },
    { "Options", "Interface\\Icons\\INV_Misc_PocketWatch_01",
        "When and how Petal summons your pets." },
    { "Saved sets", "Interface\\Icons\\INV_Scroll_03",
        "Save your pets and places as a set, load it later, or share it as a code." },
}

local frame
local pageFrames, tabs, pageRefresh = {}, {}, {}
local skin

-- Building blocks (same as Forever Names) ------------------------------------------

local function Text(parent, text, x, y, template, width, color)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    if width then label:SetWidth(width); label:SetWordWrap(true) end
    if color then label:SetTextColor(unpack(color)) end
    return label
end
local function Note(parent, text, x, y, width)
    return Text(parent, text, x, y, "GameFontHighlightSmall", width, NOTE)
end
local function Line(parent, x, y, width, height, alpha)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", x, y)
    line:SetSize(width, height)
    line:SetColorTexture(0.68, 0.50, 0.26, alpha or 0.45)
    return line
end
local function Card(parent, title, x, y, width, height)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", x, y)
    card:SetSize(width, height)
    local wash = card:CreateTexture(nil, "BACKGROUND", nil, -2)
    wash:SetAllPoints()
    wash:SetColorTexture(0.25, 0.17, 0.085, 0.16)
    Line(card, 0, 0, width, 1, 0.55); Line(card, 0, -height + 1, width, 1, 0.3)
    Line(card, 0, 0, 1, height, 0.3); Line(card, width - 1, 0, 1, height, 0.3)
    if title then
        card.title = Text(card, title, 12, -10, "GameFontNormal")
        Line(card, 8, -28, width - 16, 1, 0.25)
    end
    return card
end
local function Tooltip(owner, title, body)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title(self) or title, 1, 0.82, 0)
        local text = type(body) == "function" and body(self) or body
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function Button(parent, text, x, y, width, onClick, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, height or 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    if skin then skin.Button(button) end
    return button
end
local checks = {}
local function Check(parent, key, text, x, y, width)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", x, y)
    check:SetSize(26, 26)
    local label = check.Text or check.text
    label:SetFontObject("GameFontHighlight")
    label:SetText(text)
    label:SetWidth(width or 300)
    label:SetJustifyH("LEFT")
    check.label = label
    if key then
        check:SetScript("OnClick", function(self)
            PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            A.SetOption(key, self:GetChecked() == true)
        end)
        checks[#checks + 1] = { key = key, check = check }
    end
    return check
end
local function SetCheckEnabled(check, enabled)
    check:SetEnabled(enabled)
    check.label:SetTextColor(unpack(enabled and { 1, 1, 1 } or DIM))
end
-- [-] value [+]
local function Stepper(parent, x, y, valueWidth, onStep)
    local stepper = {}
    stepper.minus = Button(parent, "-", x, y, 24, function() onStep(-1) end)
    stepper.value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    stepper.value:SetPoint("TOPLEFT", x + 24, y - 4)
    stepper.value:SetWidth(valueWidth)
    stepper.value:SetJustifyH("CENTER")
    stepper.plus = Button(parent, "+", x + 24 + valueWidth, y, 24, function() onStep(1) end)
    function stepper:SetEnabled(enabled)
        self.minus:SetEnabled(enabled); self.plus:SetEnabled(enabled)
        self.value:SetTextColor(unpack(enabled and { 1, 1, 1 } or DIM))
    end
    return stepper
end
-- One-of-several buttons: the selected one is washed gold.
local function Segmented(parent, x, y, width, choices, get, set)
    local buttons, left = {}, x
    for i, choice in ipairs(choices) do
        local button = Button(parent, choice[1], left, y, width, function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON); set(choice[2])
        end)
        left = left + width + 4
        button.wash = button:CreateTexture(nil, "ARTWORK")
        button.wash:SetPoint("TOPLEFT", 4, -4); button.wash:SetPoint("BOTTOMRIGHT", -4, 4)
        button.wash:SetColorTexture(1, 0.72, 0.2, 0.2)
        buttons[i] = button
    end
    function buttons:Update()
        local current = get()
        for i, choice in ipairs(choices) do
            local selected = choice[2] == current
            self[i].wash:SetShown(selected)
            self[i]:GetFontString():SetTextColor(unpack(selected and GOLD or { 0.9, 0.9, 0.9 }))
        end
    end
    return buttons
end
-- A place icon that is on (full color, gold rim) or off (faded).
local function PlaceToggle(parent, place, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2); button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.icon:SetTexture(A.PlaceIcon(place))
    button.rim = {}
    for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
        local rim = button:CreateTexture(nil, "OVERLAY")
        rim:SetPoint(spec[1]); rim:SetPoint(spec[2])
        if spec[3] == 1 then rim:SetWidth(2) else rim:SetHeight(2) end
        button.rim[i] = rim
    end
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(button.icon)
    hover:SetColorTexture(1, 1, 1, 0.15)
    function button:SetOn(on)
        self.icon:SetDesaturated(not on)
        self.icon:SetAlpha(on and 1 or 0.4)
        for _, rim in ipairs(self.rim) do
            if on then rim:SetColorTexture(1, 0.78, 0.25, 0.95) else rim:SetColorTexture(0.35, 0.28, 0.2, 0.8) end
        end
    end
    button.place = place
    return button
end
-- A scroll list of pooled rows: rows(i) creates or reuses row i.
local function ScrollList(parent, x, y, width, bottom, rowHeight, makeRow)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", x, y)
    scroll:SetPoint("BOTTOMRIGHT", -26, bottom)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 10)
    scroll:SetScrollChild(child)
    local empty = Note(child, "", 16, -24, width - 32)
    empty:SetJustifyH("CENTER")
    local rows, list = {}, {}
    function list:Row(index)
        if not rows[index] then
            local row = makeRow(child, index)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
            rows[index] = row
        end
        return rows[index]
    end
    function list:Finish(count, emptyText)
        for i = count + 1, #rows do rows[i]:Hide() end
        child:SetHeight(math.max(10, count * rowHeight))
        empty:SetShown(count == 0)
        empty:SetText(emptyText or "")
    end
    return list
end
-- The Blizzard pet-list row look: background, selection and hover.
local function ListRowArt(row, alpha)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("PetList-ButtonBackground"); bg:SetAllPoints(); bg:SetAlpha(alpha or 0.8)
    row.selected = row:CreateTexture(nil, "BORDER")
    row.selected:SetAtlas("PetList-ButtonSelect"); row.selected:SetAllPoints()
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAtlas("PetList-ButtonHighlight"); hover:SetAllPoints()
end

local function PetIcon(pet)
    return pet.wrapped and GIFT_ICON or pet.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Duration(seconds)
    seconds = math.floor(seconds or 0)
    if seconds < 60 then return nil end
    local hours, minutes = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
    if hours > 0 then return minutes > 0 and ("%d h %d min"):format(hours, minutes) or ("%d h"):format(hours) end
    return ("%d min"):format(minutes)
end

local function Plural(count, one, many)
    return ("%d %s"):format(count, count == 1 and one or many)
end

-- "Outdoors, Inns", "All places", "Any place" or "Not used".
local function PlacesSummary(key)
    if not A.IsTravelling(key) then return "Not used", DIM end
    if A.LikesEverywhere(key) then return "All places", NOTE end
    local list = {}
    for _, place in ipairs(A.PLACES) do
        if A.LikesPlace(key, place) then list[#list + 1] = A.PlaceInfo(place).short end
    end
    if #list == 0 then return "Any place", NOTE end
    return table.concat(list, ", "), NOTE
end

local function StripCodes(text)
    if not text or text == "" then return nil end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "  "))
end

-- A player model: drag to turn, mouse wheel to zoom. OnUpdate only while dragging.
local function PetModel(parent)
    local model = CreateFrame("PlayerModel", nil, parent)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    local facing, zoom = MODEL_FACING, 1
    local lastX
    local request, loaded = 0, false
    local function Drag()
        local x = GetCursorPosition()
        facing = facing + (x - (lastX or x)) * 0.012
        lastX = x
        model:SetFacing(facing)
    end
    local function Stop()
        lastX = nil
        model:SetScript("OnUpdate", nil)
    end
    model:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        lastX = GetCursorPosition()
        model:SetScript("OnUpdate", Drag)
    end)
    model:SetScript("OnMouseUp", Stop)
    model:SetScript("OnHide", Stop)
    model:SetScript("OnMouseWheel", function(self, delta)
        zoom = math.max(0.4, math.min(2, zoom - delta * 0.1))
        self:SetCamDistanceScale(zoom)
    end)
    model:SetScript("OnModelLoaded", function(self)
        loaded = true
        self:SetFacing(facing)
        self:SetCamDistanceScale(zoom)
    end)
    function model:IsPetLoaded() return loaded end
    -- Some displays need a second request (retail PETAL found the same).
    function model:ShowPet(displayID, creatureID)
        request = request + 1
        local mine = request
        loaded, facing, zoom = false, MODEL_FACING, 1
        self:ClearModel()
        if displayID then self:SetDisplayInfo(displayID) elseif creatureID then self:SetCreature(creatureID) end
        self:SetFacing(facing)
        C_Timer.After(0.4, function()
            if request ~= mine or loaded then return end
            self:ClearModel()
            if creatureID then self:SetCreature(creatureID) elseif displayID then self:SetDisplayInfo(displayID) end
            self:SetFacing(facing)
        end)
    end
    return model
end

-- Page 1: Pets ---------------------------------------------------------------------------

local selectedKey
local function BuildPets(page)
    local db = A.db
    local LIST_W = 290
    local DW = PW - LIST_W - GAP -- detail width
    local list = Card(page, nil, 0, 0, LIST_W, PH)

    local search = CreateFrame("EditBox", nil, list, "SearchBoxTemplate")
    search:SetPoint("TOPLEFT", 16, -8)
    search:SetSize(LIST_W - 28, 22)
    search:HookScript("OnTextChanged", function() pageRefresh[1]() end)

    local filters = Segmented(list, 8, -36, (LIST_W - 24) / 3, {
        { "All", "all" }, { "Ticked", "travel" }, { "Favorites", "fav" },
    }, function() return db.filter end, function(value) db.filter = value; pageRefresh[1]() end)
    Tooltip(filters[2], "Ticked", "Only the pets Petal can summon.")
    Line(list, 8, -64, LIST_W - 16, 1, 0.25)

    local ROW = 38
    local ROW_W = LIST_W - 32
    local rows = ScrollList(list, 4, -68, ROW_W, 4, ROW, function(child)
        local row = CreateFrame("Button", nil, child)
        row:SetSize(ROW_W, ROW - 2)
        ListRowArt(row)
        local frameBg = row:CreateTexture(nil, "ARTWORK", nil, 0)
        frameBg:SetPoint("LEFT", 4, 0); frameBg:SetSize(30, 30)
        frameBg:SetColorTexture(0, 0, 0, 0.8)
        row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.icon:SetPoint("CENTER", frameBg); row.icon:SetSize(28, 28)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.active = row:CreateTexture(nil, "OVERLAY")
        row.active:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        row.active:SetBlendMode("ADD")
        row.active:SetPoint("TOPLEFT", row.icon, -3, 3); row.active:SetPoint("BOTTOMRIGHT", row.icon, 3, -3)
        row.fav = row:CreateTexture(nil, "OVERLAY", nil, 2)
        row.fav:SetAtlas("PetJournal-FavoritesIcon", true)
        row.fav:SetPoint("TOPLEFT", row.icon, -8, 8)
        row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 40, -5); row.name:SetPoint("RIGHT", -30, 0)
        row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3); row.sub:SetPoint("RIGHT", -30, 0)
        row.sub:SetJustifyH("LEFT"); row.sub:SetWordWrap(false)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(24, 24)
        row.check:SetPoint("RIGHT", -3, 0)
        row.check:SetScript("OnClick", function(self)
            PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            A.SetTravelling(row.pet.key, self:GetChecked())
        end)
        Tooltip(row.check, "Use this pet", "Ticked pets can be summoned by Petal.")
        row:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            selectedKey = self.pet.key
            pageRefresh[1]()
        end)
        row:SetScript("OnDoubleClick", function(self)
            if A.IsSummonable(self.pet) then A.CallPet(self.pet) end
        end)
        return row
    end)

    -- Detail: a wide model stage, then name, facts and places. ---------------------
    local detail = Card(page, nil, LIST_W + GAP, 0, DW, PH)
    local STAGE_H = 212
    local stage = CreateFrame("Frame", nil, detail)
    stage:SetPoint("TOPLEFT", 1, -1); stage:SetPoint("TOPRIGHT", -1, -1)
    stage:SetHeight(STAGE_H)
    -- Plain dark stage with the vignette Forever's character panel puts over
    -- its model (UI-Character-Info-RaceBG-Overlay).
    local backdrop = stage:CreateTexture(nil, "BACKGROUND")
    backdrop:SetColorTexture(0.035, 0.03, 0.025, 1)
    backdrop:SetAllPoints()
    local vignette = stage:CreateTexture(nil, "BORDER")
    vignette:SetAtlas("UI-Character-Info-RaceBG-Overlay")
    vignette:SetAllPoints()
    Line(detail, 0, -STAGE_H - 1, DW, 1, 0.55)

    local model = PetModel(stage)
    model:SetPoint("TOPLEFT", 2, -2); model:SetPoint("BOTTOMRIGHT", -2, 2)
    local gift = stage:CreateTexture(nil, "ARTWORK")
    gift:SetSize(64, 64); gift:SetPoint("CENTER")
    gift:SetTexture(GIFT_ICON)
    -- Overlays sit above the model so they stay clickable.
    local overlay = CreateFrame("Frame", nil, stage)
    overlay:SetAllPoints(); overlay:SetFrameLevel(model:GetFrameLevel() + 2)
    local summonedTag = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summonedTag:SetPoint("TOPLEFT", 10, -9)
    summonedTag:SetText("Summoned")
    local fav = CreateFrame("Button", nil, overlay)
    fav:SetSize(22, 22); fav:SetPoint("TOPRIGHT", -8, -6)
    fav.icon = fav:CreateTexture(nil, "ARTWORK")
    fav.icon:SetAtlas("PetJournal-FavoritesIcon")
    fav.icon:SetAllPoints()
    fav:SetScript("OnClick", function()
        local pet = A.GetPet(selectedKey)
        if pet and A.CanSetFavorite(pet) then A.SetFavorite(pet, not pet.favorite) end
    end)
    Tooltip(fav, function() local pet = A.GetPet(selectedKey); return pet and pet.favorite and "Favorite" or "Not a favorite" end,
        "Click to change. Same favorites as the Collections window.")
    local call = Button(overlay, "Summon", 0, 0, 100, function()
        local pet = A.GetPet(selectedKey)
        if not pet then return end
        if pet.wrapped then A.Unwrap(pet); return end
        local current = A.CurrentPet()
        if current and current.key == pet.key then
            A.DismissPet(pet)
        else
            local ok, reason = A.CallPet(pet)
            if not ok and reason then UIErrorsFrame:AddMessage(A.BlockText(reason), 1, 0.82, 0) end
        end
    end, 24)
    call:ClearAllPoints(); call:SetPoint("BOTTOMRIGHT", -8, 8)
    -- The model owns the mouse; its tooltip carries the description, if any.
    model:SetScript("OnEnter", function(self)
        local pet = A.GetPet(selectedKey)
        if not pet then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 12, 0)
        GameTooltip:SetText(pet.name, 1, 0.82, 0)
        local description = A.PetDetails(pet).description
        if description and description ~= "" then GameTooltip:AddLine(description, 1, 1, 1, true) end
        GameTooltip:AddLine("Drag to turn. Scroll to zoom.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    model:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local nameText = Text(detail, "", 12, -STAGE_H - 10, "GameFontNormalLarge", DW - 150)
    nameText:SetWordWrap(false)
    local travels = Check(detail, nil, "Use this pet", DW - 128, -STAGE_H - 8, 96)
    travels:SetScript("OnClick", function(self)
        local pet = A.GetPet(selectedKey)
        if pet then A.SetTravelling(pet.key, self:GetChecked()) end
    end)
    Tooltip(travels, "Use this pet", "Ticked pets can be summoned by Petal.")
    local facts = Note(detail, "", 12, -STAGE_H - 34, DW - 24)
    local source = Note(detail, "", 12, -STAGE_H - 50, DW - 24)
    source:SetTextColor(0.6, 0.6, 0.6)
    if source.SetMaxLines then source:SetMaxLines(2) end

    local PLACES_Y = -PH + 52
    Line(detail, 8, PLACES_Y + 8, DW - 16, 1, 0.25)
    Text(detail, "Appears in", 12, PLACES_Y, "GameFontNormalSmall")
    local placeButtons = {}
    for i, place in ipairs(A.PLACES) do
        local button = PlaceToggle(detail, place, 28)
        button:SetPoint("TOPLEFT", 12 + (i - 1) * 33, PLACES_Y - 16)
        button:SetScript("OnClick", function()
            local pet = A.GetPet(selectedKey)
            if not pet then return end
            local on = not A.LikesPlace(pet.key, place)
            PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            A.SetLikesPlace(pet.key, place, on)
        end)
        Tooltip(button, A.PlaceInfo(place).label, function()
            local pet = A.GetPet(selectedKey)
            local on = pet and A.LikesPlace(pet.key, place)
            return A.PlaceInfo(place).note .. "\n\n" .. (on and "|cff80ff80On.|r Click to turn off." or "Click to turn on.")
        end)
        placeButtons[place] = button
    end
    local everywhere = Button(detail, "All places", DW - 112, PLACES_Y - 19, 100, function()
        local pet = A.GetPet(selectedKey)
        if pet then A.SetAllPlaces(pet.key, not A.LikesEverywhere(pet.key)) end
    end)
    Tooltip(everywhere, "All places", "Turns every place on. Click again to turn them all off.\n\n"
        .. "A pet with no places can still appear where no other pet is set.")

    local noPets = Note(detail, "", 20, -STAGE_H - 40, DW - 40)
    noPets:SetJustifyH("CENTER")

    local shownKey
    local function ShowModel(pet)
        local details = A.PetDetails(pet)
        gift:SetShown(pet.wrapped)
        model:SetShown(not pet.wrapped)
        if pet.wrapped then return end
        local key = pet.key .. ":" .. tostring(details.displayID)
        if key == shownKey and model:IsPetLoaded() then return end
        shownKey = key
        model:ShowPet(details.displayID, details.creatureID)
    end

    local function ShowDetail()
        local pet = A.GetPet(selectedKey)
        local has = pet ~= nil
        for _, region in ipairs({ overlay, model, gift, travels, everywhere, nameText, facts, source }) do region:SetShown(has) end
        for _, button in pairs(placeButtons) do button:SetShown(has) end
        noPets:SetShown(not has)
        if not has then
            noPets:SetText(#A.pets == 0 and "No pets found.\n\nPets you collect appear here, for all your characters."
                or "Select a pet on the left.")
            return
        end
        ShowModel(pet)
        nameText:SetText(pet.name)
        local current = A.CurrentPet()
        local here = current and current.key == pet.key
        summonedTag:SetShown(here)
        fav.icon:SetDesaturated(not pet.favorite)
        fav.icon:SetAlpha(pet.favorite and 1 or 0.45)
        fav:SetShown(pet.petID ~= nil)

        local parts = {}
        if pet.customName and pet.speciesName then parts[#parts + 1] = pet.speciesName end
        if pet.wrapped then parts[#parts + 1] = "New pet, not unwrapped yet" end
        local called = db.called[pet.key] or 0
        parts[#parts + 1] = called > 0 and ("Summoned by Petal " .. Plural(called, "time", "times")) or "Not summoned by Petal yet"
        local together = Duration((db.together[pet.key] or 0) + (here and A.state.currentSince and (A.Now() - A.state.currentSince) or 0))
        if together then parts[#parts + 1] = "Out for " .. together end
        facts:SetText(table.concat(parts, "  -  "))
        source:SetText(StripCodes(A.PetDetails(pet).source) or "")

        for place, button in pairs(placeButtons) do button:SetOn(A.LikesPlace(pet.key, place)) end
        everywhere:SetText(A.LikesEverywhere(pet.key) and "Clear places" or "All places")
        travels:SetChecked(A.IsTravelling(pet.key))
        if pet.wrapped then
            call:SetText("Unwrap"); call:Enable()
        elseif here then
            call:SetText("Dismiss"); call:Enable()
        else
            call:SetText("Summon"); call:SetEnabled(A.IsSummonable(pet))
        end
    end

    pageRefresh[1] = function()
        local query = (search:GetText() or ""):lower()
        local current = A.CurrentPet()
        local shown = {}
        for _, pet in ipairs(A.pets) do
            local match = query == "" or pet.name:lower():find(query, 1, true)
                or (pet.speciesName and pet.speciesName:lower():find(query, 1, true))
            if match and (db.filter == "all" or (db.filter == "travel" and A.IsTravelling(pet.key))
                or (db.filter == "fav" and pet.favorite)) then
                shown[#shown + 1] = pet
            end
        end
        if not A.GetPet(selectedKey) then
            selectedKey = (current and current.key) or (shown[1] and shown[1].key) or (A.pets[1] and A.pets[1].key)
        end
        for i, pet in ipairs(shown) do
            local row = rows:Row(i)
            row.pet = pet
            row.icon:SetTexture(PetIcon(pet))
            row.icon:SetDesaturated(not pet.wrapped and not A.IsSummonable(pet))
            row.name:SetText(pet.name)
            local summary, color = PlacesSummary(pet.key)
            if pet.wrapped then summary, color = "New pet, not unwrapped yet", GOLD end
            row.sub:SetText(summary)
            row.sub:SetTextColor(unpack(color))
            row.check:SetChecked(A.IsTravelling(pet.key))
            row.fav:SetShown(pet.favorite)
            row.active:SetShown(current ~= nil and current.key == pet.key)
            row.selected:SetShown(pet.key == selectedKey)
            row:Show()
        end
        rows:Finish(#shown, #A.pets == 0 and "No pets found." or db.filter == "travel" and query == ""
            and "No pets ticked yet.\nTick pets in All." or "No pets match.")
        filters:Update()
        ShowDetail()
    end
end

-- Page 2: Places -------------------------------------------------------------------------

local function BuildPlaces(page)
    local TOP_H = 56
    local now = Card(page, nil, 0, 0, PW, TOP_H)
    local placeIcon = now:CreateTexture(nil, "ARTWORK")
    placeIcon:SetSize(36, 36); placeIcon:SetPoint("TOPLEFT", 10, -10)
    placeIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local where = Text(now, "", 56, -10, "GameFontNormal", PW - 230)
    where:SetWordWrap(false)
    local status = Note(now, "", 56, -30, PW - 230)
    local another = Button(now, "Summon another", PW - 152, -16, 140, function()
        local ok, reason = A.CallAnother("window")
        if not ok and reason then UIErrorsFrame:AddMessage(A.BlockText(reason), 1, 0.82, 0) end
    end, 24)
    Tooltip(another, "Summon another pet", "Summons a different pet for this place. You can set a key for it in Options.")

    local GRID_H = PH - TOP_H - GAP
    local grid = Card(page, nil, 0, -TOP_H - GAP, PW, GRID_H)
    local FIRST, COL, ALL = 226, 68, 40
    local headers, washes = {}, {}
    for i, place in ipairs(A.PLACES) do
        local center = FIRST + (i - 1) * COL + COL / 2
        local wash = grid:CreateTexture(nil, "BACKGROUND", nil, -1)
        wash:SetPoint("TOPLEFT", center - COL / 2 + 2, -2); wash:SetSize(COL - 4, GRID_H - 4)
        wash:SetColorTexture(1, 0.75, 0.25, 0.10)
        washes[place] = wash
        local header = PlaceToggle(grid, place, 26)
        header:SetPoint("TOP", grid, "TOPLEFT", center, -6)
        header:SetOn(true)
        local label = grid:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("TOP", header, "BOTTOM", 0, -2)
        label:SetText(A.PlaceInfo(place).short)
        header.count = grid:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        header.count:SetPoint("TOP", label, "BOTTOM", 0, -1)
        header.count:SetTextColor(unpack(NOTE))
        Tooltip(header, A.PlaceInfo(place).label, function()
            local count = A.PlaceCount(place)
            return A.PlaceInfo(place).note .. "\n\n" .. (count == 0 and "No pets set: any ticked pet can appear here."
                or (Plural(count, "pet", "pets") .. " set for this place."))
        end)
        headers[place] = header
    end
    local allLabel = grid:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    allLabel:SetPoint("TOP", grid, "TOPLEFT", FIRST + 6 * COL + ALL / 2, -20)
    allLabel:SetText("All")
    Text(grid, "Ticked pets", 12, -20, "GameFontNormal")
    Line(grid, 8, -58, PW - 16, 1, 0.3)

    local ROW = 28
    local rows = ScrollList(grid, 6, -62, PW - 36, 4, ROW, function(child, index)
        local row = CreateFrame("Frame", nil, child)
        row:SetSize(PW - 36, ROW)
        if index % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.03)
        end
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.name:SetPoint("LEFT", 34, 0); row.name:SetWidth(FIRST - 44)
        row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.cells = {}
        local function Cell(x)
            local cell = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cell:SetSize(24, 24)
            cell:SetPoint("CENTER", row, "LEFT", x, 0)
            return cell
        end
        for i, place in ipairs(A.PLACES) do
            local cell = Cell(FIRST - 6 + (i - 1) * COL + COL / 2)
            cell:SetScript("OnClick", function(self)
                PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                A.SetLikesPlace(row.pet.key, place, self:GetChecked())
            end)
            row.cells[place] = cell
        end
        row.all = Cell(FIRST - 6 + 6 * COL + ALL / 2)
        row.all:SetScript("OnClick", function(self) A.SetAllPlaces(row.pet.key, self:GetChecked()) end)
        Tooltip(row.all, "All places", "Turns every place on or off for this pet.")
        return row
    end)

    pageRefresh[2] = function()
        local place = A.GetPlace()
        placeIcon:SetTexture(A.PlaceIcon(place))
        local zone = A.ZoneText()
        where:SetText(A.PlaceInfo(place).label .. (zone ~= "" and ("  |cffb0a890" .. zone .. "|r") or ""))
        local current = A.CurrentPet()
        if current then
            status:SetText("Summoned: " .. current.name)
        elseif A.lastBlock and A.lastBlock ~= "off" then
            status:SetText(A.BlockText(A.lastBlock))
        else
            status:SetText("No pet summoned.")
        end
        for p, wash in pairs(washes) do wash:SetShown(p == place) end
        for p, header in pairs(headers) do
            local count = A.PlaceCount(p)
            header.count:SetText(count == 0 and "any" or tostring(count))
        end

        local list = {}
        for _, pet in ipairs(A.pets) do if A.IsTravelling(pet.key) then list[#list + 1] = pet end end
        for i, pet in ipairs(list) do
            local row = rows:Row(i)
            row.pet = pet
            row.icon:SetTexture(PetIcon(pet))
            local here = current and current.key == pet.key
            row.name:SetText(here and (pet.name .. "  |cffffd100(summoned)|r") or pet.name)
            for p, cell in pairs(row.cells) do cell:SetChecked(A.LikesPlace(pet.key, p)) end
            row.all:SetChecked(A.LikesEverywhere(pet.key))
            row:Show()
        end
        rows:Finish(#list, "No pets ticked yet.\n\nTick pets on the Pets page and they will be listed here.")
    end
end

-- Page 3: Options ------------------------------------------------------------------------

local function BindingText()
    local key = GetBindingKey("PETAL_CHANGE_PET")
    return key and (GetBindingText and GetBindingText(key) or key) or nil
end

local function BuildOptions(page)
    local db = A.db
    local updaters = {}
    local CW = (PW - GAP) / 2
    local RIGHT = CW + GAP
    local TEXT_W = CW - 50
    local H1, H2 = 132, 100
    local H3 = PH - H1 - H2 - 2 * GAP

    local auto = Card(page, "Automatic summoning", 0, 0, CW, H1)
    Check(auto, "enabled", "Summon pets automatically", 10, -36, TEXT_W)
    Note(auto, "When you arrive in a new place, or when your pet is gone.", 40, -60, TEXT_W)
    local own = Check(auto, "respectOwnChoice", "Keep pets I summon myself", 10, -80, TEXT_W)
    Note(auto, "Petal won't replace them until you change place.", 40, -104, TEXT_W)

    local rest = Card(page, "After you dismiss a pet", 0, -H1 - GAP, CW, H2)
    local grace = Check(rest, "graceEnabled", "Wait before summoning again", 10, -36, TEXT_W)
    Text(rest, "Wait", 40, -72, "GameFontHighlight")
    local graceStep = Stepper(rest, 80, -68, 70, function(delta)
        A.SetOption("graceMinutes", math.max(1, math.min(60, db.graceMinutes + delta * (db.graceMinutes >= 10 and 5 or 1))))
    end)
    updaters[#updaters + 1] = function()
        graceStep.value:SetText(db.graceMinutes .. " min")
        graceStep:SetEnabled(db.enabled and db.graceEnabled)
        SetCheckEnabled(grace, db.enabled)
    end

    local chat = Card(page, "Chat message", 0, -H1 - H2 - 2 * GAP, CW, H3)
    Check(chat, "whispers", "Show a message when Petal summons a pet", 10, -36, TEXT_W)
    Note(chat, "Only you see it. For example:", 40, -60, TEXT_W)
    local sample = Text(chat, "", 40, -76, "GameFontHighlightSmall", TEXT_W, CHAT)
    local samples = { "Your Tabby Cat sniffs the wind and follows you.", "Your Prairie Dog settles in by the hearth.",
        "Your Cockroach creeps in behind you, keeping close.", "Your Sprite Darter Hatchling stares wide-eyed at the crowds." }
    local sampleIndex = 1
    sample:SetText(samples[1])
    -- Clicking the example shows another one.
    local cycle = CreateFrame("Button", nil, chat)
    cycle:SetAllPoints(sample)
    cycle:SetScript("OnClick", function()
        sampleIndex = sampleIndex % #samples + 1
        sample:SetText(samples[sampleIndex])
    end)
    Tooltip(cycle, "Example", "Click for another example.")

    local switch = Card(page, "Switch pets", RIGHT, 0, CW, H1)
    local shuffle = Check(switch, "shuffle", "Switch pets from time to time", 10, -36, TEXT_W)
    Text(switch, "Every", 40, -72, "GameFontHighlight")
    local minStep = Stepper(switch, 84, -68, 36, function(delta)
        local value = math.max(5, math.min(180, db.shuffleMin + delta * 5))
        A.SetOption("shuffleMin", value)
        if db.shuffleMax < value then A.SetOption("shuffleMax", value) end
    end)
    Text(switch, "to", 176, -72, "GameFontHighlight")
    local maxStep = Stepper(switch, 194, -68, 36, function(delta)
        A.SetOption("shuffleMax", math.max(db.shuffleMin, math.min(240, db.shuffleMax + delta * 5)))
    end)
    Text(switch, "min", 284, -72, "GameFontHighlight")
    local nextChange = Note(switch, "", 40, -102, TEXT_W)
    updaters[#updaters + 1] = function()
        minStep.value:SetText(db.shuffleMin); maxStep.value:SetText(db.shuffleMax)
        minStep:SetEnabled(db.enabled and db.shuffle); maxStep:SetEnabled(db.enabled and db.shuffle)
        SetCheckEnabled(shuffle, db.enabled); SetCheckEnabled(own, db.enabled)
        if db.enabled and db.shuffle and A.shuffleDueAt then
            nextChange:SetText(("Next switch in about %d min."):format(math.max(1, math.ceil((A.shuffleDueAt - A.Now()) / 60))))
        else
            nextChange:SetText("Picks another pet for your current place.")
        end
    end

    local keyCard = Card(page, "Key: summon another pet", RIGHT, -H1 - GAP, CW, H2)
    local keyButton = Button(keyCard, "", 10, -38, 180, nil, 24)
    Note(keyCard, "Click, then press a key. Right-click to clear.\nOr type /petal next.", 12, -70, CW - 24)
    local capturing = false
    local function ShowKey()
        keyButton:SetText(capturing and "|cffffd100Press a key...|r" or (BindingText() or "|cff808080Not set|r"))
    end
    local function StopCapture()
        capturing = false
        keyButton:EnableKeyboard(false)
        keyButton:SetScript("OnKeyDown", nil)
        ShowKey()
    end
    keyButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    keyButton:SetScript("OnClick", function(self, mouse)
        if InCombatLockdown() then UIErrorsFrame:AddMessage("Can't change keys in combat.", 1, 0.3, 0.3); return end
        if mouse == "RightButton" then
            local old = GetBindingKey("PETAL_CHANGE_PET")
            if old then SetBinding(old); SaveBindings(GetCurrentBindingSet()) end
            StopCapture()
            return
        end
        capturing = true
        ShowKey()
        self:EnableKeyboard(true)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        self:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then StopCapture(); return end
            if key:find("SHIFT") or key:find("CTRL") or key:find("ALT") or key == "UNKNOWN" then return end
            local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
                .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
            local old = GetBindingKey("PETAL_CHANGE_PET")
            if old then SetBinding(old) end
            SetBinding(combo, "PETAL_CHANGE_PET")
            SaveBindings(GetCurrentBindingSet())
            StopCapture()
        end)
    end)
    keyButton:HookScript("OnHide", function() if capturing then StopCapture() end end)
    updaters[#updaters + 1] = function() if not capturing then ShowKey() end end

    local waits = Card(page, "When Petal waits", RIGHT, -H1 - H2 - 2 * GAP, CW, H3)
    Note(waits, "No summoning while you are in combat, mounted, on a flight path, eating or drinking, "
        .. "at a campfire, stealthed, shapeshifted, or casting.\n\n"
        .. "After a mount or a flight, the same pet comes back.", 12, -38, CW - 24)

    pageRefresh[3] = function()
        for _, entry in ipairs(checks) do entry.check:SetChecked(db[entry.key] == true) end
        for _, update in ipairs(updaters) do update() end
    end
end

-- Page 4: Saved sets ------------------------------------------------------------------------

local function BuildSets(page)
    local selected
    local CW = (PW - GAP) / 2
    local left = Card(page, "Saved sets", 0, 0, CW, PH)
    local nameBox = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", 18, -38); nameBox:SetSize(CW - 124, 22)
    nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(32)
    local hint = nameBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0); hint:SetText("Set name")
    nameBox:SetScript("OnTextChanged", function(self) hint:SetShown((self:GetText() or "") == "") end)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local message = Note(left, "", 12, -66, CW - 24)
    local function Save()
        local name, err = A.SaveKeepsake(nameBox:GetText())
        if name then
            selected = name
            nameBox:SetText(""); nameBox:ClearFocus()
            message:SetText("Saved \"" .. name .. "\".")
        else
            message:SetText(err)
        end
        pageRefresh[4]()
    end
    nameBox:SetScript("OnEnterPressed", Save)
    Button(left, "Save", CW - 96, -38, 86, Save, 22)
    Line(left, 8, -82, CW - 16, 1, 0.25)

    local rows = ScrollList(left, 4, -86, CW - 32, 40, 36, function(child)
        local row = CreateFrame("Button", nil, child)
        row:SetSize(CW - 32, 34)
        ListRowArt(row, 0.7)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24); icon:SetPoint("LEFT", 6, 0)
        icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 38, -3); row.name:SetPoint("RIGHT", -8, 0)
        row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2); row.sub:SetPoint("RIGHT", -8, 0)
        row.sub:SetJustifyH("LEFT"); row.sub:SetTextColor(unpack(NOTE))
        row:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            selected = self.keepsake; pageRefresh[4]()
        end)
        return row
    end)

    -- Two clicks for anything that replaces or removes.
    local armed
    local function Confirm(button, label, action)
        button:SetScript("OnClick", function(self)
            if not selected then return end
            if armed == self then
                armed = nil
                action(selected)
                self:SetText(label)
                pageRefresh[4]()
            else
                armed = self
                self:SetText("|cffff8040Confirm?|r")
                C_Timer.After(3, function() if armed == self then armed = nil; self:SetText(label) end end)
            end
        end)
    end
    local BW = (CW - 28) / 3
    local load = Button(left, "Load", 10, -PH + 32, BW, nil, 22)
    Confirm(load, "Load", function(name)
        A.LoadKeepsake(name)
        message:SetText("Loaded \"" .. name .. "\".")
    end)
    Tooltip(load, "Load", "Replaces your ticked pets and places with this set. Click twice.")
    local overwrite = Button(left, "Overwrite", 14 + BW, -PH + 32, BW, nil, 22)
    Confirm(overwrite, "Overwrite", function(name)
        A.SaveKeepsake(name)
        message:SetText("Updated \"" .. name .. "\".")
    end)
    Tooltip(overwrite, "Overwrite", "Saves your current pets and places into this set. Click twice.")
    local delete = Button(left, "Delete", 18 + 2 * BW, -PH + 32, BW, nil, 22)
    Confirm(delete, "Delete", function(name)
        A.DeleteKeepsake(name); selected = nil
        message:SetText("Deleted \"" .. name .. "\".")
    end)
    Tooltip(delete, "Delete", "Click twice.")

    local right = Card(page, "Share", CW + GAP, 0, CW, PH)
    Note(right, "A code contains your ticked pets and their places. Pets the other player doesn't own are "
        .. "skipped. Retail PETAL codes also work.", 12, -36, CW - 24)
    local box = CreateFrame("Frame", nil, right)
    box:SetPoint("TOPLEFT", 12, -84); box:SetSize(CW - 24, PH - 196)
    local boxBg = box:CreateTexture(nil, "BACKGROUND")
    boxBg:SetAllPoints(); boxBg:SetColorTexture(0, 0, 0, 0.45)
    local boxScroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    boxScroll:SetPoint("TOPLEFT", 6, -6); boxScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local edit = CreateFrame("EditBox", nil, boxScroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontSmall")
    edit:SetWidth(CW - 62)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    boxScroll:SetScrollChild(edit)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    local boxHint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    boxHint:SetPoint("CENTER")
    boxHint:SetText("Export a code, or paste one here.")
    edit:SetScript("OnTextChanged", function(self) boxHint:SetShown((self:GetText() or "") == "") end)
    local shareMessage = Note(right, "", 12, -PH + 104, CW - 24)

    local function Show(code, text)
        edit:SetText(code)
        edit:SetFocus(); edit:HighlightText()
        shareMessage:SetText(text)
    end
    Button(right, "Export current setup", 10, -PH + 84, CW - 20, function()
        Show(A.ExportCode(nil), "Press Ctrl+C to copy.")
    end, 22)
    local exportSelected = Button(right, "Export selected set", 10, -PH + 58, CW - 20, function()
        if selected then Show(A.ExportCode(selected), "Press Ctrl+C to copy \"" .. selected .. "\".") end
    end, 22)
    Button(right, "Import code", 10, -PH + 32, CW - 20, function()
        local name, err = A.ImportCode(edit:GetText())
        if name then
            selected = name
            shareMessage:SetText("Imported as \"" .. name .. "\". Select it and click Load.")
            edit:SetText(""); edit:ClearFocus()
        else
            shareMessage:SetText("|cffff8040" .. err .. "|r")
        end
        pageRefresh[4]()
    end, 22)

    pageRefresh[4] = function()
        local names = A.KeepsakeNames()
        if selected and not A.GetKeepsake(selected) then selected = nil end
        for i, name in ipairs(names) do
            local row = rows:Row(i)
            local snap = A.GetKeepsake(name)
            local total, owned = A.KeepsakeCounts(snap)
            row.keepsake = name
            row.name:SetText(name)
            local sub = Plural(total, "pet", "pets")
            if owned < total then sub = sub .. (" (%d not owned)"):format(total - owned) end
            if snap.saved and snap.saved > 0 and date then sub = sub .. "  -  " .. date("%d %b %Y", snap.saved) end
            row.sub:SetText(sub)
            row.selected:SetShown(name == selected)
            row:Show()
        end
        rows:Finish(#names, "No saved sets.\n\nType a name above and click Save.")
        for _, button in ipairs({ load, overwrite, delete, exportSelected }) do button:SetEnabled(selected ~= nil) end
    end
end

-- Window ------------------------------------------------------------------------------------

local header
local function RefreshHeader()
    if not A.db.enabled then header.status:SetText("|cffff6040Automatic summoning is off|r")
    else
        header.status:SetText("|cff9d9d9d" .. Plural(#A.pets, "pet", "pets") .. ", " .. A.TravellingCount() .. " ticked|r")
    end
end

local function SelectPage(index)
    index = pageFrames[index] and index or 1
    A.db.page = index
    for i, page in ipairs(pageFrames) do
        page:SetShown(i == index)
        tabs[i].selected:SetShown(i == index)
    end
    header.title:SetText(PAGES[index][1])
    pageRefresh[index]()
    RefreshHeader()
end

local function Build()
    skin = A.Skin
    frame = CreateFrame("Frame", "PetalJournal", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(W, H)
    local point = A.db.point
    if type(point) == "table" and point[1] then
        frame:SetPoint(point[1], UIParent, point[3] or point[1], point[4] or 0, point[5] or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetToplevel(true)
    table.insert(UISpecialFrames, "PetalJournal")
    -- Stay visible in Frame Gambit's cinematic modes, like the suite's other windows.
    if FrameGambitAPI and FrameGambitAPI.RegisterCinematicWindow then
        pcall(FrameGambitAPI.RegisterCinematicWindow, frame)
    end
    local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetText("Petal")
    skin.Frame(frame, heading)
    hooksecurefunc(frame, "StopMovingOrSizing", function(self)
        local p, _, rel, x, y = self:GetPoint()
        A.db.point = { p, nil, rel, x, y }
    end)
    local border = frame.legacyBorder or frame

    -- Content: a one-line header (page name, counts), then the page.
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 26, -42)
    content:SetPoint("BOTTOMRIGHT", -22, 44)
    header = { title = Text(content, "", 2, -2, "GameFontNormalLarge") }
    header.status = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    header.status:SetPoint("TOPRIGHT", -2, -6)
    header.status:SetJustifyH("RIGHT")
    Line(content, 0, -26, PW, 1, 0.45)

    local enable = Check(frame, "enabled", "Summon pets automatically", 0, 0, 240)
    enable:ClearAllPoints(); enable:SetPoint("BOTTOMLEFT", 22, 11)
    local close = Button(frame, "Close", 0, 0, 96, function() frame:Hide() end, 22)
    close:ClearAllPoints(); close:SetPoint("BOTTOMRIGHT", -18, 13)
    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("RIGHT", close, "LEFT", -10, 0)
    version:SetText("v" .. A.version)

    -- Same size as Halo's and Forever Names' side tabs (90% of Blizzard's), so the windows match.
    local TAB_SCALE = 0.9
    local tabInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-sidetab")
    local tabWidth, tabHeight = tabInfo and tabInfo.width or 43, tabInfo and (tabInfo.height - 5) or 55
    for i, info in ipairs(PAGES) do
        local page = CreateFrame("Frame", nil, content)
        page:SetPoint("TOPLEFT", 0, -36)
        page:SetSize(PW, PH)
        page:Hide()
        pageFrames[i] = page
        local tab = CreateFrame("Button", nil, frame)
        tab:SetSize(tabWidth, tabHeight)
        tab:SetScale(TAB_SCALE)
        -- Same placement as LegacySystemFrame's tabs: outside the right edge.
        -- Offsets are in the tab's own (scaled) units, so the first tab keeps its place.
        if i == 1 then tab:SetPoint("TOPLEFT", border, "TOPRIGHT", 0, -44 / TAB_SCALE)
        else tab:SetPoint("TOPLEFT", tabs[i - 1], "BOTTOMLEFT", 0, -2) end
        local background = tab:CreateTexture(nil, "BACKGROUND")
        background:SetAtlas("common-sidetab", true)
        background:SetPoint("CENTER")
        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(info[2])
        icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
        icon:SetPoint("CENTER", -4, 0)
        if tab.CreateMaskTexture and icon.AddMaskTexture then
            icon:SetSize(50, 50)
            local mask = tab:CreateMaskTexture()
            mask:SetAtlas("common-sidetab-mask", true)
            mask:SetPoint("CENTER")
            icon:AddMaskTexture(mask)
        else
            icon:SetSize(34, 34)
        end
        tab.selected = tab:CreateTexture(nil, "OVERLAY")
        tab.selected:SetAtlas("common-sidetab-selected", true)
        tab.selected:SetPoint("CENTER")
        local hover = tab:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAtlas("common-sidetab-hover", true)
        hover:SetPoint("CENTER")
        tab:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", -3, -1) end)
        tab:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", -4, 0) end)
        tab:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            SelectPage(i)
        end)
        Tooltip(tab, info[1], info[3])
        tabs[i] = tab
    end

    BuildPets(pageFrames[1])
    BuildPlaces(pageFrames[2])
    BuildOptions(pageFrames[3])
    BuildSets(pageFrames[4])

    frame:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
        if not A.scanned or A.Now() - (A.lastOpenScan or 0) > 5 then
            A.lastOpenScan = A.Now()
            A.ScanCollection()
        end
        SelectPage(A.db.page)
    end)
    frame:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE) end)
end

-- Live refresh: one refresh per frame at most, only while the window is open.
local refreshQueued = false
local function QueueRefresh()
    if not (frame and frame:IsShown()) or refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if frame and frame:IsShown() then
            local refresh = pageRefresh[A.db.page]
            if refresh then refresh() end
            RefreshHeader()
            for _, entry in ipairs(checks) do entry.check:SetChecked(A.db[entry.key] == true) end
        end
    end)
end
for _, kind in ipairs({ "collection", "roster", "pet", "state", "place", "options", "keepsakes" }) do
    A.On(kind, QueueRefresh)
end

A.On("feedback", function(reason)
    if reason and UIErrorsFrame then UIErrorsFrame:AddMessage(A.BlockText(reason), 1, 0.82, 0) end
end)

function A.ToggleJournal(page)
    if not frame then Build() end
    if frame:IsShown() and not page then
        frame:Hide()
    else
        if page then A.db.page = page end
        frame:Show()
        if page then SelectPage(page) end
    end
end
