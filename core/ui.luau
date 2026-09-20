return function(import)

local i18n = import("core/i18n")
local UserInputService = game:GetService("UserInputService")

-- Theme: ported from S:\emc-pos\packages\core\ires_theme. Default is the
-- light scheme (white cards on a light grey page); swap these to re-skin
-- every game at once.
local THEME = {
    BrandName = "MekPro",
    Background = Color3.fromRGB(0xF1, 0xF2, 0xF6), -- IresPalette.light50 (surfaceContainer, light)
    Card = Color3.fromRGB(0xFE, 0xFE, 0xFE), -- IresPalette.white (surface, light)
    CardHover = Color3.fromRGB(0xE9, 0xEA, 0xF0), -- IresPalette.light100
    Accent = Color3.fromRGB(0x1C, 0xAF, 0x82), -- IresPalette.primary500
    ToggleOff = Color3.fromRGB(0xE3, 0xE7, 0xEA), -- IresPalette.dark100 (outlineVariant, light)
    Text = Color3.fromRGB(0x25, 0x25, 0x25), -- IresPalette.black (onSurface, light)
    SubText = Color3.fromRGB(0x5F, 0x71, 0x7B), -- IresPalette.dark500 (onSurfaceVariant, light)
    Premium = Color3.fromRGB(0xFD, 0x64, 0x12), -- IresPalette.secondary500
    Badge = Color3.fromRGB(0xFD, 0x64, 0x12), -- IresPalette.secondary500
    Font = Enum.Font.GothamMedium,
}

-- IresRadius, in Roblox UICorner pixels.
local RADIUS = {
    Small = 8,
    Control = 16,
    Card = 24,
}

local function corner(instance, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or RADIUS.Control)
    c.Parent = instance
    return c
end

-- Fully rounded, regardless of size (IresRadius.pill).
local function pill(instance)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = instance
    return c
end

local function padding(instance, amount)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, amount)
    p.PaddingRight = UDim.new(0, amount)
    p.PaddingTop = UDim.new(0, amount)
    p.PaddingBottom = UDim.new(0, amount)
    p.Parent = instance
    return p
end

-- Drags `target` by clicking/touching anywhere on `handle`. If the pointer
-- never moves past a small threshold, treats it as a tap and fires
-- `onClick` instead - lets a single element (e.g. the collapsed avatar)
-- both be dragged and act as a button.
local function makeDraggable(handle, target, onClick)
    local dragging, dragInput, dragStart, startPos, moved
    local connections = {}

    table.insert(connections, handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPos = target.Position
            table.insert(connections, input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if onClick and not moved then
                        onClick()
                    end
                end
            end))
        end
    end))

    table.insert(connections, handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    table.insert(connections, UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            if delta.Magnitude > 3 then
                moved = true
            end
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    return connections
end

local UI = {}
UI.__index = UI

function UI:AddTab(name, icon, opts)
    opts = opts or {}
    -- Captured under its own name because `tab:AddCard` etc below are
    -- colon methods too, and Lua's colon sugar gives each of THEM their
    -- own `self` (bound to the tab) that shadows this one.
    local window = self

    local tabButton = Instance.new("TextButton")
    tabButton.Name = name
    tabButton.Size = UDim2.new(0, 44, 0, 44)
    tabButton.BackgroundColor3 = THEME.Card
    tabButton.AutoButtonColor = false
    tabButton.Text = ""
    tabButton.Parent = self.TabBar
    corner(tabButton, RADIUS.Control)

    -- Card and Background are close enough in the light theme that an
    -- inactive tab button is nearly invisible against the window without
    -- an outline - this is what makes it look "missing" rather than just
    -- unstyled.
    local tabStroke = Instance.new("UIStroke")
    tabStroke.Color = THEME.ToggleOff
    tabStroke.Thickness = 1
    tabStroke.Parent = tabButton

    local icoLabel = Instance.new("TextLabel")
    icoLabel.BackgroundTransparency = 1
    icoLabel.Size = UDim2.new(1, 0, 1, 0)
    icoLabel.Text = icon or "?"
    icoLabel.TextSize = 18
    icoLabel.Font = THEME.Font
    icoLabel.TextColor3 = THEME.SubText
    icoLabel.Parent = tabButton

    if opts.Premium then
        local tag = Instance.new("TextLabel")
        tag.Size = UDim2.new(0, 16, 0, 10)
        tag.Position = UDim2.new(1, -14, 0, -4)
        tag.BackgroundColor3 = THEME.Premium
        tag.Text = ""
        tag.Parent = tabButton
        corner(tag, 4)
    end

    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = next(self.Tabs) == nil
    page.Parent = self.Content

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 10)
    layout.Parent = page

    local function setActive(activeName)
        for tabName, tab in pairs(self.Tabs) do
            tab.Button.BackgroundColor3 = tabName == activeName and THEME.Accent or THEME.Card
            tab.Icon.TextColor3 = tabName == activeName and THEME.Background or THEME.SubText
            tab.Page.Visible = tabName == activeName
        end
    end

    tabButton.MouseButton1Click:Connect(function()
        setActive(name)
    end)

    local tab = {}
    tab.Button = tabButton
    tab.Icon = icoLabel
    tab.Page = page

    function tab:AddSectionHeader(text)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextColor3 = THEME.SubText
        lbl.TextSize = 13
        lbl.Font = THEME.Font
        lbl.Parent = page
        return lbl
    end

    function tab:AddCard(title, subtitle)
        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, 0, 0, 0)
        card.AutomaticSize = Enum.AutomaticSize.Y
        card.BackgroundColor3 = THEME.Card
        card.Parent = page
        corner(card, RADIUS.Card)
        padding(card, 12)

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(1, -80, 0, 20)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Text = title
        titleLbl.Font = THEME.Font
        titleLbl.TextSize = 15
        titleLbl.TextColor3 = THEME.Text
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.Parent = card

        local subtitleLbl
        if subtitle then
            subtitleLbl = Instance.new("TextLabel")
            subtitleLbl.Size = UDim2.new(1, -80, 0, 0)
            subtitleLbl.AutomaticSize = Enum.AutomaticSize.Y
            subtitleLbl.Position = UDim2.new(0, 0, 0, 20)
            subtitleLbl.BackgroundTransparency = 1
            subtitleLbl.Text = subtitle
            subtitleLbl.Font = Enum.Font.Gotham
            subtitleLbl.TextSize = 12
            subtitleLbl.TextWrapped = true
            subtitleLbl.TextColor3 = THEME.SubText
            subtitleLbl.TextXAlignment = Enum.TextXAlignment.Left
            subtitleLbl.Parent = card
        end

        table.insert(window.SearchIndex, { Frame = card, Title = title, Subtitle = subtitle })

        local cardApi = {}
        cardApi.Frame = card

        function cardApi:SetSubtitle(text)
            if not subtitleLbl then
                subtitleLbl = Instance.new("TextLabel")
                subtitleLbl.Size = UDim2.new(1, -80, 0, 0)
                subtitleLbl.AutomaticSize = Enum.AutomaticSize.Y
                subtitleLbl.Position = UDim2.new(0, 0, 0, 20)
                subtitleLbl.BackgroundTransparency = 1
                subtitleLbl.Font = Enum.Font.Gotham
                subtitleLbl.TextSize = 12
                subtitleLbl.TextWrapped = true
                subtitleLbl.TextColor3 = THEME.SubText
                subtitleLbl.TextXAlignment = Enum.TextXAlignment.Left
                subtitleLbl.Parent = card
            end
            subtitleLbl.Text = text
        end

        function cardApi:SetValue(text)
            local valueLbl = card:FindFirstChild("ValueLabel")
            if not valueLbl then
                valueLbl = Instance.new("TextLabel")
                valueLbl.Name = "ValueLabel"
                valueLbl.Size = UDim2.new(0, 70, 0, 20)
                valueLbl.Position = UDim2.new(1, -70, 0, 0)
                valueLbl.BackgroundTransparency = 1
                valueLbl.Font = THEME.Font
                valueLbl.TextSize = 14
                valueLbl.TextColor3 = THEME.SubText
                valueLbl.TextXAlignment = Enum.TextXAlignment.Right
                valueLbl.Parent = card
            end
            valueLbl.Text = text
            return valueLbl
        end

        function cardApi:SetBadge(text, color)
            local badge = card:FindFirstChild("Badge")
            if not badge then
                badge = Instance.new("TextLabel")
                badge.Name = "Badge"
                badge.Size = UDim2.new(0, 70, 0, 18)
                badge.Position = UDim2.new(1, -70, 0, 0)
                badge.Font = THEME.Font
                badge.TextSize = 11
                badge.TextColor3 = THEME.Text
                badge.Parent = card
                corner(badge, RADIUS.Small)
            end
            badge.Text = text
            badge.BackgroundColor3 = color or THEME.Badge
            return badge
        end

        function cardApi:AddButton(text, callback)
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0, 70, 0, 28)
            btn.Position = UDim2.new(1, -70, 0, -4)
            btn.BackgroundColor3 = THEME.Accent
            btn.AutoButtonColor = false
            btn.Text = text
            btn.Font = THEME.Font
            btn.TextSize = 13
            btn.TextColor3 = THEME.Background
            btn.Parent = card
            corner(btn, RADIUS.Small)

            btn.MouseButton1Click:Connect(callback)

            return btn
        end

        function cardApi:AddToggle(default, callback)
            local state = default or false

            local track = Instance.new("Frame")
            track.Size = UDim2.new(0, 40, 0, 22)
            track.Position = UDim2.new(1, -40, 0, 0)
            track.BackgroundColor3 = state and THEME.Accent or THEME.ToggleOff
            track.Parent = card
            pill(track)

            local knob = Instance.new("Frame")
            knob.Size = UDim2.new(0, 18, 0, 18)
            knob.Position = state and UDim2.new(1, -20, 0, 2) or UDim2.new(0, 2, 0, 2)
            knob.BackgroundColor3 = THEME.Text
            knob.Parent = track
            pill(knob)

            local clicker = Instance.new("TextButton")
            clicker.Size = UDim2.new(1, 0, 1, 0)
            clicker.BackgroundTransparency = 1
            clicker.Text = ""
            clicker.Parent = track

            clicker.MouseButton1Click:Connect(function()
                state = not state
                track.BackgroundColor3 = state and THEME.Accent or THEME.ToggleOff
                knob.Position = state and UDim2.new(1, -20, 0, 2) or UDim2.new(0, 2, 0, 2)
                callback(state)
            end)

            return track
        end

        return cardApi
    end

    function tab:AddSlider(title, subtitle, min, max, default, callback)
        local card = self:AddCard(title, subtitle)
        local valueLbl = card:SetValue(tostring(default) .. "%")

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, 0, 0, 4)
        track.Position = UDim2.new(0, 0, 0, 45)
        track.BackgroundColor3 = THEME.ToggleOff
        track.Parent = card.Frame
        corner(track, 2)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = THEME.Accent
        fill.Parent = track
        corner(fill, 2)

        local knob = Instance.new("TextButton")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.Position = UDim2.new(fill.Size.X.Scale, -7, 0.5, -7)
        knob.BackgroundColor3 = THEME.Text
        knob.Text = ""
        knob.Parent = track
        pill(knob)

        local dragging = false
        knob.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local relative = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                fill.Size = UDim2.new(relative, 0, 1, 0)
                knob.Position = UDim2.new(relative, -7, 0.5, -7)
                local value = math.floor(min + (max - min) * relative)
                valueLbl.Text = tostring(value) .. "%"
                callback(value)
            end
        end)

        return card
    end

    function tab:AddSegmented(options, defaultIndex, callback)
        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, 0, 0, 36)
        card.BackgroundColor3 = THEME.Card
        card.Parent = page
        corner(card, RADIUS.Control)

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.Padding = UDim.new(0, 4)
        layout.Parent = card
        padding(card, 4)

        local buttons = {}

        local function setActive(index)
            for i, btn in ipairs(buttons) do
                btn.BackgroundColor3 = i == index and THEME.Accent or THEME.Card
                btn.TextColor3 = i == index and THEME.Background or THEME.SubText
            end
        end

        for i, optionText in ipairs(options) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1 / #options, -4, 1, 0)
            btn.BackgroundColor3 = THEME.Card
            btn.AutoButtonColor = false
            btn.Text = optionText
            btn.Font = THEME.Font
            btn.TextSize = 13
            btn.TextColor3 = THEME.SubText
            btn.Parent = card
            corner(btn, RADIUS.Small)

            btn.MouseButton1Click:Connect(function()
                setActive(i)
                callback(i, optionText)
            end)

            buttons[i] = btn
        end

        setActive(defaultIndex or 1)

        return card
    end

    self.Tabs[name] = tab
    return tab
end

function UI:SetSearchCallback(callback)
    self.SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        callback(self.SearchBox.Text)
    end)
end

local function createWindow(config)
    config = config or {}

    -- Re-running the loader script (e.g. testing the same URL repeatedly)
    -- otherwise leaves the previous window's UI AND its background loops
    -- (Anti-AFK, auto-mine, etc, via OnDestroy below) running forever,
    -- invisible and uncontrolled by the new one's toggles.
    local env = getgenv and getgenv() or _G
    if env.MekProWindow then
        pcall(function()
            env.MekProWindow:Destroy()
        end)
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CoreUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = game:GetService("CoreGui")

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 430, 0, 620)
    main.Position = UDim2.new(0.5, -215, 0.5, -310)
    main.BackgroundColor3 = THEME.Background
    -- Lets the window be dragged from anywhere on its body, not just the
    -- header - see the Active note on the old header-only drag handle.
    main.Active = true
    main.Parent = screenGui
    corner(main, RADIUS.Card)
    local expandedSize = main.Size
    local collapsedSize = UDim2.new(0, 64, 0, 64)

    local uiScale = Instance.new("UIScale")
    uiScale.Scale = 1
    uiScale.Parent = main

    -- Header: icon tab bar
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, -24, 0, 44)
    tabBar.Position = UDim2.new(0, 12, 0, 12)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = main

    local tabBarLayout = Instance.new("UIListLayout")
    tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
    tabBarLayout.Padding = UDim.new(0, 6)
    tabBarLayout.Parent = tabBar

    -- Header: avatar + title + subtitle
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, -24, 0, 48)
    header.Position = UDim2.new(0, 12, 0, 64)
    header.BackgroundTransparency = 1
    header.Parent = main

    -- A direct child of `main` (not `header`) so it survives header.Visible
    -- = false when collapsed. Its expanded position is chosen to land
    -- exactly where it used to sit inside `header`.
    local avatarExpandedPos = UDim2.new(0, 12, 0, 64)
    local avatarCollapsedPos = UDim2.new(0, 12, 0, 12)
    local avatar = Instance.new("TextButton")
    avatar.Size = UDim2.new(0, 40, 0, 40)
    avatar.Position = avatarExpandedPos
    avatar.BackgroundColor3 = THEME.Accent
    avatar.AutoButtonColor = false
    avatar.Text = config.Avatar or THEME.BrandName:sub(1, 1)
    avatar.Font = THEME.Font
    avatar.TextSize = 18
    avatar.TextColor3 = THEME.Background
    avatar.Parent = main
    corner(avatar, RADIUS.Control)

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -160, 0, 20)
    titleLbl.Position = UDim2.new(0, 50, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = config.Title or THEME.BrandName
    titleLbl.Font = THEME.Font
    titleLbl.TextSize = 16
    titleLbl.TextColor3 = THEME.Text
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = header

    local subtitleLbl = Instance.new("TextLabel")
    subtitleLbl.Size = UDim2.new(1, -160, 0, 16)
    subtitleLbl.Position = UDim2.new(0, 50, 0, 20)
    subtitleLbl.BackgroundTransparency = 1
    subtitleLbl.Text = config.Subtitle or ""
    subtitleLbl.Font = Enum.Font.Gotham
    subtitleLbl.TextSize = 12
    subtitleLbl.TextColor3 = THEME.SubText
    subtitleLbl.TextXAlignment = Enum.TextXAlignment.Left
    subtitleLbl.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -28, 0, 6)
    closeBtn.BackgroundColor3 = THEME.Card
    closeBtn.Text = "X"
    closeBtn.Font = THEME.Font
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = THEME.Text
    closeBtn.Parent = header
    corner(closeBtn, RADIUS.Small)

    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Size = UDim2.new(0, 28, 0, 28)
    minimizeBtn.Position = UDim2.new(1, -62, 0, 6)
    minimizeBtn.BackgroundColor3 = THEME.Card
    minimizeBtn.Text = "-"
    minimizeBtn.Font = THEME.Font
    minimizeBtn.TextSize = 16
    minimizeBtn.TextColor3 = THEME.Text
    minimizeBtn.Parent = header
    corner(minimizeBtn, RADIUS.Small)

    -- Search bar
    local searchBox = Instance.new("TextBox")
    searchBox.Name = "Search"
    searchBox.Size = UDim2.new(1, -24, 0, 36)
    searchBox.Position = UDim2.new(0, 12, 0, 118)
    searchBox.BackgroundColor3 = THEME.Card
    searchBox.PlaceholderText = i18n.T("search_placeholder")
    searchBox.Text = ""
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 13
    searchBox.TextColor3 = THEME.Text
    searchBox.PlaceholderColor3 = THEME.SubText
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = main
    corner(searchBox, RADIUS.Control)
    padding(searchBox, 10)

    -- Content area holds one ScrollingFrame page per tab
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -24, 1, -220)
    content.Position = UDim2.new(0, 12, 0, 164)
    content.BackgroundTransparency = 1
    content.Parent = main

    -- Footer: keybind hint
    local footer = Instance.new("Frame")
    footer.Size = UDim2.new(1, -24, 0, 30)
    footer.Position = UDim2.new(0, 12, 1, -42)
    footer.BackgroundTransparency = 1
    footer.Parent = main

    local footerLabel = Instance.new("TextLabel")
    footerLabel.Size = UDim2.new(1, -80, 1, 0)
    footerLabel.BackgroundTransparency = 1
    footerLabel.Text = i18n.T("open_menu_hint")
    footerLabel.Font = Enum.Font.Gotham
    footerLabel.TextSize = 12
    footerLabel.TextColor3 = THEME.SubText
    footerLabel.TextXAlignment = Enum.TextXAlignment.Left
    footerLabel.Parent = footer

    local keybind = config.Keybind or Enum.KeyCode.RightShift
    local keybindLabel = Instance.new("TextLabel")
    keybindLabel.Size = UDim2.new(0, 80, 1, 0)
    keybindLabel.Position = UDim2.new(1, -80, 0, 0)
    keybindLabel.BackgroundColor3 = THEME.Card
    keybindLabel.Text = keybind.Name
    keybindLabel.Font = THEME.Font
    keybindLabel.TextSize = 12
    keybindLabel.TextColor3 = THEME.Text
    keybindLabel.Parent = footer
    corner(keybindLabel, RADIUS.Small)

    local minimized = false

    local function setMinimized(state)
        minimized = state
        tabBar.Visible = not minimized
        header.Visible = not minimized
        searchBox.Visible = not minimized
        content.Visible = not minimized
        footer.Visible = not minimized
        main.Size = minimized and collapsedSize or expandedSize
        avatar.Position = minimized and avatarCollapsedPos or avatarExpandedPos
    end

    -- Whole-window drag (works from any empty spot on `main`, since active
    -- children like buttons/toggles/sliders capture their own input first
    -- and never let it reach this handler).
    local connections = makeDraggable(main, main)

    -- The collapsed state's only visible/interactive element: drag it like
    -- the rest of the window, but a plain tap (no movement) restores it.
    for _, connection in ipairs(makeDraggable(avatar, main, function()
        if minimized then
            setMinimized(false)
        end
    end)) do
        table.insert(connections, connection)
    end

    local self = setmetatable({}, UI)
    self.ScreenGui = screenGui
    self.Main = main
    self.TabBar = tabBar
    self.Content = content
    self.SearchBox = searchBox
    self.Tabs = {}
    self.Connections = connections
    self.UIScale = uiScale
    self.SearchIndex = {}
    self.DestroyListeners = {}

    table.insert(connections, minimizeBtn.MouseButton1Click:Connect(function()
        setMinimized(not minimized)
    end))

    table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.KeyCode == keybind then
            screenGui.Enabled = not screenGui.Enabled
        end
    end))

    table.insert(connections, closeBtn.MouseButton1Click:Connect(function()
        self:Destroy()
    end))

    -- Filters cards by title/subtitle within whichever tab is open. Only
    -- touches card visibility, never tab.Page.Visible - so it never pulls
    -- in results from other tabs or switches the open tab on its own.
    table.insert(connections, searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = searchBox.Text:lower()

        for _, item in ipairs(self.SearchIndex) do
            if query == "" then
                item.Frame.Visible = true
            else
                local haystack = (item.Title .. " " .. (item.Subtitle or "")):lower()
                item.Frame.Visible = haystack:find(query, 1, true) ~= nil
            end
        end
    end))

    local unsubscribeLanguage = i18n.OnChanged(function()
        searchBox.PlaceholderText = i18n.T("search_placeholder")
        footerLabel.Text = i18n.T("open_menu_hint")
    end)
    self.UnsubscribeLanguage = unsubscribeLanguage

    env.MekProWindow = self

    return self
end

-- Registers a function to run when the window is torn down (X button, or
-- auto-cleanup from a fresh loader run). Use this to stop background loops
-- (auto-mine, anti-afk, ...) that outlive the UI itself otherwise.
function UI:OnDestroy(callback)
    table.insert(self.DestroyListeners, callback)
end

-- Tears the whole UI down: disconnects every listener this window created and
-- removes the ScreenGui, so re-running the loader script doesn't stack a
-- second copy on top of the first.
function UI:Destroy()
    for _, connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    for _, listener in ipairs(self.DestroyListeners) do
        pcall(listener)
    end
    self.UnsubscribeLanguage()
    self.ScreenGui:Destroy()
end

-- percent is whatever range the caller's AddSlider uses (e.g. 50-150).
function UI:SetScale(percent)
    self.UIScale.Scale = percent / 100
end

return createWindow

end
