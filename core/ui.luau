local UserInputService = game:GetService("UserInputService")

-- Theme: ported from S:\emc-pos\packages\core\ires_theme (dark scheme). Swap
-- these to re-skin every game at once.
local THEME = {
    BrandName = "MekPro",
    Background = Color3.fromRGB(0x25, 0x25, 0x25), -- IresPalette.black (surfaceContainer, dark)
    Card = Color3.fromRGB(0x37, 0x3D, 0x42), -- IresPalette.dark900 (surface, dark)
    CardHover = Color3.fromRGB(0x3E, 0x45, 0x4C), -- IresPalette.dark800
    Accent = Color3.fromRGB(0x1C, 0xAF, 0x82), -- IresPalette.primary500
    ToggleOff = Color3.fromRGB(0x51, 0x5F, 0x69), -- IresPalette.dark600 (outlineVariant, dark)
    Text = Color3.fromRGB(0xF4, 0xF6, 0xF7), -- IresPalette.dark50 (onSurface, dark)
    SubText = Color3.fromRGB(0xA6, 0xB4, 0xBA), -- IresPalette.dark300 (onSurfaceVariant, dark)
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

local function makeDraggable(handle, target)
    local dragging, dragInput, dragStart, startPos
    local connections = {}

    table.insert(connections, handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            table.insert(connections, input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
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

    local tabButton = Instance.new("TextButton")
    tabButton.Name = name
    tabButton.Size = UDim2.new(0, 44, 0, 44)
    tabButton.BackgroundColor3 = THEME.Card
    tabButton.AutoButtonColor = false
    tabButton.Text = ""
    tabButton.Parent = self.TabBar
    corner(tabButton, RADIUS.Control)

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

        local cardApi = {}
        cardApi.Frame = card

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

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CoreUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = game:GetService("CoreGui")

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 430, 0, 620)
    main.Position = UDim2.new(0.5, -215, 0.5, -310)
    main.BackgroundColor3 = THEME.Background
    main.Parent = screenGui
    corner(main, RADIUS.Card)

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

    local avatar = Instance.new("TextLabel")
    avatar.Size = UDim2.new(0, 40, 0, 40)
    avatar.BackgroundColor3 = THEME.Accent
    avatar.Text = config.Avatar or THEME.BrandName:sub(1, 1)
    avatar.Font = THEME.Font
    avatar.TextSize = 18
    avatar.TextColor3 = THEME.Background
    avatar.Parent = header
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
    searchBox.PlaceholderText = "ค้นหาฟังก์ชัน..."
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
    footerLabel.Text = "ปุ่มเปิดเมนู"
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

    local connections = makeDraggable(header, main)

    local self = setmetatable({}, UI)
    self.ScreenGui = screenGui
    self.Main = main
    self.TabBar = tabBar
    self.Content = content
    self.SearchBox = searchBox
    self.Tabs = {}
    self.Connections = connections

    local minimized = false
    local expandedSize = main.Size
    table.insert(connections, minimizeBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        searchBox.Visible = not minimized
        content.Visible = not minimized
        footer.Visible = not minimized
        main.Size = minimized and UDim2.new(expandedSize.X.Scale, expandedSize.X.Offset, 0, 112) or expandedSize
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

    return self
end

-- Tears the whole UI down: disconnects every listener this window created and
-- removes the ScreenGui, so re-running the loader script doesn't stack a
-- second copy on top of the first.
function UI:Destroy()
    for _, connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    self.ScreenGui:Destroy()
end

return createWindow
