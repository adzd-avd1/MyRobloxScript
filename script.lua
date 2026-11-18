--[[
    Modern ESP + Aimbot UI (Optimized for Performance)
    Default Menu Key: RightAlt
]]

-- === SETUP ===
local cloneref = cloneref or function(o) return o end
local Players    = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UIS        = cloneref(game:GetService("UserInputService"))
local HttpService= cloneref(game:GetService("HttpService"))
local TweenService = cloneref(game:GetService("TweenService"))
local Camera     = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Cache math functions for speed
local math_abs, math_floor, math_clamp, math_sqrt = math.abs, math.floor, math.clamp, math.sqrt

-- Filesystem Setup
local configFolder = "Potassium_Configs"
if not isfolder(configFolder) then makefolder(configFolder) end

-- Cleanup
if getgenv().SimpleESP then
    for _, data in pairs(getgenv().SimpleESP.boxes) do
        data.box:Remove(); data.name:Remove(); data.healthBar:Remove(); data.distText:Remove()
    end
    getgenv().SimpleESP.conn:Disconnect()
    if getgenv().SimpleESP.gui then getgenv().SimpleESP.gui:Destroy() end
    if getgenv().SimpleESP.fovCircle then getgenv().SimpleESP.fovCircle:Remove() end
    getgenv().SimpleESP = nil
end

-- === CONFIGURATION ===
local Config = {
    ESPEnabled = true, TeamCheck = true, HealthCheck = true, ShowHealthBar = true, ShowDistance = true, DistanceCheck = true, MaxDistance = 1000,
    boxColor = Color3.fromRGB(0, 255, 140), textColor = Color3.fromRGB(255, 255, 255), matchTextColor = true,
    AimbotEnabled = false, StickyAim = true, TargetPart = "Head", ShowFOV = true, FOVSize = 150, Smoothness = 0.15,
    AimKey = Enum.UserInputType.MouseButton2, AimKeyType = "UserInputType", IsListeningForAim = false,
    ToggleKey = Enum.KeyCode.RightAlt, IsListeningForKey = false,
    MinDistance = 50, AbsoluteMaxDist = 5000, textSize = 14, thickness = 1,
    BoxR = 0, BoxG = 255, BoxB = 140
}

-- === STORAGE ===
local boxes = {}
local isAiming = false
local stickyTargetPlayer = nil
local UIUpdates = {} 

local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1; fovCircle.NumSides = 60; fovCircle.Radius = Config.FOVSize
fovCircle.Filled = false; fovCircle.Color = Config.boxColor
fovCircle.Transparency = 1; fovCircle.Visible = false

-- ==========================================
-- 1. CONFIG MANAGEMENT
-- ==========================================
local function saveConfig(configName)
    if not configName or configName == "" then return end
    local path = configFolder .. "/" .. configName .. ".json"
    local saveData = {}
    for k, v in pairs(Config) do
        if k ~= "IsListeningForKey" and k ~= "IsListeningForAim" then
            if typeof(v) == "EnumItem" then saveData[k] = v.Name
            elseif typeof(v) == "Color3" then saveData[k] = {R = v.R, G = v.G, B = v.B}
            else saveData[k] = v end
        end
    end
    local success, json = pcall(function() return HttpService:JSONEncode(saveData) end)
    if success then writefile(path, json); return true end
    return false
end

local function loadConfig(configName)
    local path = configFolder .. "/" .. configName .. ".json"
    if not isfile(path) then return false end
    local success, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if success and type(data) == "table" then
        for k, v in pairs(data) do
            if Config[k] ~= nil then
                if k == "ToggleKey" then Config[k] = Enum.KeyCode[v] or Config[k]
                elseif k == "AimKey" then
                    if Config.AimKeyType == "KeyCode" then Config[k] = Enum.KeyCode[v] or Config[k]
                    else Config[k] = Enum.UserInputType[v] or Config[k] end
                elseif k == "boxColor" or k == "textColor" then
                    if type(v) == "table" then Config[k] = Color3.new(v.R, v.G, v.B) end
                else Config[k] = v end
            end
        end
        for key, updateFunc in pairs(UIUpdates) do
            if Config[key] ~= nil then updateFunc(Config[key]) end
        end
        return true
    end
    return false
end

local function deleteConfig(configName)
    local path = configFolder .. "/" .. configName .. ".json"
    if isfile(path) then delfile(path); return true end
    return false
end

-- ==========================================
-- 2. ESP & AIMBOT LOGIC
-- ==========================================
local function createESP(player)
    if player == LocalPlayer then return end
    local box = Drawing.new("Square"); box.Thickness = Config.thickness; box.Filled = false
    local name = Drawing.new("Text"); name.Size = Config.textSize; name.Center = true; name.Outline = true
    local healthBar = Drawing.new("Square"); healthBar.Thickness = 1; healthBar.Filled = true
    local distText = Drawing.new("Text"); distText.Color = Color3.fromRGB(200, 200, 200); distText.Size = 12; distText.Center = true; distText.Outline = true
    boxes[player] = { box = box, name = name, healthBar = healthBar, distText = distText }
end

local function destroyESP(player)
    local data = boxes[player]; if not data then return end
    data.box:Remove(); data.name:Remove(); data.healthBar:Remove(); data.distText:Remove(); boxes[player] = nil
end

for _, p in ipairs(Players:GetPlayers()) do createESP(p) end
Players.PlayerAdded:Connect(createESP)
Players.PlayerRemoving:Connect(destroyESP)

local function getTargetPart(character)
    if not character then return nil end
    if Config.TargetPart == "Head" then return character.Head
    elseif Config.TargetPart == "Torso" then return character.UpperTorso or character.Torso
    elseif Config.TargetPart == "HumanoidRootPart" then return character.HumanoidRootPart end
    return character.Head
end

local function getTarget()
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar.HumanoidRootPart
    if not myHRP then return nil end

    local viewportX, viewportY = Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5
    local maxDistSqr = Config.MaxDistance * Config.MaxDistance
    local fovSqr = Config.FOVSize * Config.FOVSize

    local closestPart = nil
    local shortestDistSqr = fovSqr
    local myPos = myHRP.Position

    -- Sticky Aim Check
    if Config.StickyAim and stickyTargetPlayer then
        local sChar = stickyTargetPlayer.Character
        local sHum = sChar and sChar.Humanoid
        if sChar and sHum and sHum.Health > 0 then
            local part = getTargetPart(sChar)
            if part then
                local sPos = Camera:WorldToViewportPoint(part.Position)
                if sPos.Z > 0 then
                    local dx, dy = sPos.X - viewportX, sPos.Y - viewportY
                    if (dx*dx + dy*dy) <= fovSqr then return part end
                end
            end
        end
        stickyTargetPlayer = nil
    end

    -- New Target Check
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char then
                local hum = char.Humanoid
                if hum and hum.Health > 0 then
                    if not Config.TeamCheck or (LocalPlayer.Team and player.Team ~= LocalPlayer.Team) then
                        local targetPart = getTargetPart(char)
                        if targetPart then
                            local pos = targetPart.Position
                            local dx, dy, dz = pos.X - myPos.X, pos.Y - myPos.Y, pos.Z - myPos.Z
                            local distSqr = dx*dx + dy*dy + dz*dz
                            
                            if not Config.DistanceCheck or distSqr <= maxDistSqr then
                                local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                                if onScreen then
                                    local sx, sy = screenPos.X - viewportX, screenPos.Y - viewportY
                                    local distToCenterSqr = sx*sx + sy*sy
                                    if distToCenterSqr < shortestDistSqr then
                                        shortestDistSqr = distToCenterSqr
                                        closestPart = targetPart
                                        if Config.StickyAim then stickyTargetPlayer = player end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return closestPart
end

-- ==========================================
-- 3. OPTIMIZED RENDER LOOP
-- ==========================================
local conn = RunService.RenderStepped:Connect(function()
    local cameraPos = Camera.CFrame.Position
    local viewportX, viewportY = Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar.HumanoidRootPart
    local myPos = myHRP and myHRP.Position
    local myTeam = LocalPlayer.Team
    
    -- FOV Circle Update
    if Config.AimbotEnabled and Config.ShowFOV then
        fovCircle.Visible = true
        fovCircle.Radius = Config.FOVSize
        fovCircle.Position = Vector2.new(viewportX, viewportY)
        fovCircle.Color = Config.boxColor
    else
        fovCircle.Visible = false
    end

    -- Aimbot Logic
    if Config.AimbotEnabled then
        local isCurrentlyAiming = false
        if Config.AimKeyType == "UserInputType" then isCurrentlyAiming = UIS:IsMouseButtonPressed(Config.AimKey)
        elseif Config.AimKeyType == "KeyCode" then isCurrentlyAiming = UIS:IsKeyDown(Config.AimKey) end

        if isAiming and not isCurrentlyAiming then stickyTargetPlayer = nil end
        isAiming = isCurrentlyAiming

        if isAiming then
            local targetPart = getTarget()
            if targetPart then
                Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(cameraPos, targetPart.Position), Config.Smoothness)
            end
        end
    end

    -- ESP Logic (Cached Config values for speed)
    if not Config.ESPEnabled then
        for _, data in pairs(boxes) do
            data.box.Visible = false; data.name.Visible = false; data.healthBar.Visible = false; data.distText.Visible = false
        end
        return -- Skip the rest of the loop entirely
    end

    local teamCheck = Config.TeamCheck
    local healthCheck = Config.HealthCheck
    local distCheck = Config.DistanceCheck
    local maxDist = Config.MaxDistance
    local boxColor = Config.boxColor
    local textColor = Config.matchTextColor and boxColor or Config.textColor
    local textSize = Config.textSize

    for player, data in pairs(boxes) do
        local visible = false
        local char = player.Character
        
        if char then
            local hrp = char.HumanoidRootPart
            local head = char.Head
            local hum = char.Humanoid
            
            if hrp and head and hum and (not healthCheck or hum.Health > 0) then
                if not teamCheck or not myTeam or player.Team ~= myTeam then
                    local dist = 0
                    if myPos then
                        local dx, dy, dz = hrp.Position.X - myPos.X, hrp.Position.Y - myPos.Y, hrp.Position.Z - myPos.Z
                        dist = math_sqrt(dx*dx + dy*dy + dz*dz)
                    end
                    
                    if not distCheck or dist <= maxDist then
                        local topVec, onScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.75, 0))
                        if onScreen then
                            local botVec = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                            local height = math_abs(botVec.Y - topVec.Y)
                            local width = height * 0.5
                            
                            if height >= 2 and width >= 1 then
                                visible = true
                                
                                data.box.Size = Vector2.new(width, height)
                                data.box.Position = Vector2.new(topVec.X - width * 0.5, topVec.Y)
                                data.box.Color = boxColor
                                data.box.Visible = true

                                data.name.Text = player.Name
                                data.name.Position = Vector2.new(topVec.X, topVec.Y - textSize - 4)
                                data.name.Color = textColor
                                data.name.Visible = true

                                if Config.ShowHealthBar then
                                    local hpPct = math_clamp(hum.Health / hum.MaxHealth, 0, 1)
                                    data.healthBar.Size = Vector2.new(3, height * hpPct)
                                    data.healthBar.Position = Vector2.new(topVec.X - width * 0.5 - 6, topVec.Y + height * (1 - hpPct))
                                    data.healthBar.Color = Color3.fromHSV(hpPct * 0.3, 1, 1)
                                    data.healthBar.Visible = true
                                else
                                    data.healthBar.Visible = false
                                end

                                if Config.ShowDistance then
                                    data.distText.Text = math_floor(dist) .. "m"
                                    data.distText.Position = Vector2.new(topVec.X, topVec.Y + height + 2)
                                    data.distText.Visible = true
                                else
                                    data.distText.Visible = false
                                end
                            end
                        end
                    end
                end
            end
        end
        
        if not visible then
            data.box.Visible = false; data.name.Visible = false; data.healthBar.Visible = false; data.distText.Visible = false
        end
    end
end)

-- ==========================================
-- 4. MODERN UI CREATION
-- ==========================================
local function createGUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "ModernESP_GUI"; gui.ResetOnSpawn = false
    gui.Parent = gethui and gethui() or game:GetService("CoreGui")

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 450, 0, 350)
    main.Position = UDim2.new(0.5, -225, 0.5, -175)
    main.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    main.BorderSizePixel = 0; main.Active = true; main.Draggable = true; main.Parent = gui
    
    local mainCorner = Instance.new("UICorner"); mainCorner.CornerRadius = UDim.new(0, 10); mainCorner.Parent = main
    local mainStroke = Instance.new("UIStroke"); mainStroke.Color = Color3.fromRGB(50, 50, 60); mainStroke.Thickness = 1.5; mainStroke.Parent = main

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 35); titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 34); titleBar.BorderSizePixel = 0; titleBar.Parent = main
    local titleCorner = Instance.new("UICorner"); titleCorner.CornerRadius = UDim.new(0, 10); titleCorner.Parent = titleBar
    local titleFix = Instance.new("Frame"); titleFix.Size = UDim2.new(1, 0, 0.5, 0); titleFix.Position = UDim2.new(0, 0, 0.5, 0); titleFix.BackgroundColor3 = Color3.fromRGB(28, 28, 34); titleFix.BorderSizePixel = 0; titleFix.Parent = titleBar
    
    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -40, 1, 0); titleText.Position = UDim2.new(0, 15, 0, 0); titleText.BackgroundTransparency = 1
    titleText.Text = "Potassium Project"; titleText.TextColor3 = Color3.new(1, 1, 1); titleText.Font = Enum.Font.GothamBold; titleText.TextSize = 14; titleText.TextXAlignment = Enum.TextXAlignment.Left; titleText.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.Position = UDim2.new(1, -35, 0, 2.5); closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100); closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16; closeBtn.Parent = titleBar
    closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)

    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(0, 120, 1, -35); tabBar.Position = UDim2.new(0, 0, 0, 35); tabBar.BackgroundColor3 = Color3.fromRGB(24, 24, 28); tabBar.BorderSizePixel = 0; tabBar.Parent = main
    local tabCorner = Instance.new("UICorner"); tabCorner.CornerRadius = UDim.new(0, 10); tabCorner.Parent = tabBar
    local tabFix = Instance.new("Frame"); tabFix.Size = UDim2.new(0.5, 0, 1, 0); tabFix.Position = UDim2.new(0.5, 0, 0, 0); tabFix.BackgroundColor3 = Color3.fromRGB(24, 24, 28); tabFix.BorderSizePixel = 0; tabFix.Parent = tabBar
    
    local tabList = Instance.new("UIListLayout"); tabList.Padding = UDim.new(0, 5); tabList.HorizontalAlignment = Enum.HorizontalAlignment.Center; tabList.SortOrder = Enum.SortOrder.LayoutOrder; tabList.Parent = tabBar
    local tabPad = Instance.new("UIPadding"); tabPad.PaddingTop = UDim.new(0, 15); tabPad.Parent = tabBar

    local pages = {}
    local pageNames = {"ESP", "Visuals", "Aimbot", "Settings"}
    local activePage = nil

    local function createPage(name)
        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.new(1, -130, 1, -45); page.Position = UDim2.new(0, 125, 0, 40)
        page.BackgroundTransparency = 1; page.BorderSizePixel = 0; page.ScrollBarThickness = 2
        page.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
        page.Visible = false; page.Parent = main
        local layout = Instance.new("UIListLayout"); layout.Padding = UDim.new(0, 8); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Parent = page
        local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10); pad.PaddingTop = UDim.new(0, 5); pad.Parent = page
        pages[name] = page
        return page
    end

    local function createSwitch(parent, text, configKey, callback)
        local container = Instance.new("Frame"); container.Size = UDim2.new(1, 0, 0, 25); container.BackgroundTransparency = 1; container.Parent = parent
        local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, -50, 1, 0); label.BackgroundTransparency = 1; label.Text = text; label.TextColor3 = Color3.fromRGB(220, 220, 220); label.Font = Enum.Font.Gotham; label.TextSize = 13; label.TextXAlignment = Enum.TextXAlignment.Left; label.Parent = container
        local switch = Instance.new("TextButton"); switch.Size = UDim2.new(0, 40, 0, 20); switch.Position = UDim2.new(1, -40, 0.5, -10); switch.BackgroundColor3 = Color3.fromRGB(50, 50, 60); switch.BorderSizePixel = 0; switch.Text = ""; switch.Parent = container
        local switchCorner = Instance.new("UICorner"); switchCorner.CornerRadius = UDim.new(1, 0); switchCorner.Parent = switch
        local knob = Instance.new("Frame"); knob.Size = UDim2.new(0, 16, 0, 16); knob.Position = UDim2.new(0, 2, 0.5, -8); knob.BackgroundColor3 = Color3.new(1, 1, 1); knob.Parent = switch
        local knobCorner = Instance.new("UICorner"); knobCorner.CornerRadius = UDim.new(1, 0); knobCorner.Parent = knob
        local function updateVisuals(state)
            Config[configKey] = state
            if state then
                TweenService:Create(switch, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(0, 170, 100)}):Play()
                TweenService:Create(knob, TweenInfo.new(0.2), {Position = UDim2.new(1, -18, 0.5, -8)}):Play()
            else
                TweenService:Create(switch, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(50, 50, 60)}):Play()
                TweenService:Create(knob, TweenInfo.new(0.2), {Position = UDim2.new(0, 2, 0.5, -8)}):Play()
            end
            if callback then callback(state) end
        end
        updateVisuals(Config[configKey])
        UIUpdates[configKey] = updateVisuals
        switch.MouseButton1Click:Connect(function() updateVisuals(not Config[configKey]) end)
    end

    local function createSlider(parent, text, min, max, configKey, isFloat, callback)
        local container = Instance.new("Frame"); container.Size = UDim2.new(1, 0, 0, 35); container.BackgroundTransparency = 1; container.Parent = parent
        local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, 0, 0, 15); label.BackgroundTransparency = 1; label.Text = text; label.TextColor3 = Color3.fromRGB(180, 180, 180); label.Font = Enum.Font.Gotham; label.TextSize = 12; label.TextXAlignment = Enum.TextXAlignment.Left; label.Parent = container
        local valueLabel = Instance.new("TextLabel"); valueLabel.Size = UDim2.new(1, 0, 0, 15); valueLabel.BackgroundTransparency = 1; valueLabel.TextColor3 = Color3.fromRGB(0, 255, 140); valueLabel.Font = Enum.Font.GothamBold; valueLabel.TextSize = 12; valueLabel.TextXAlignment = Enum.TextXAlignment.Right; valueLabel.Parent = container
        local track = Instance.new("Frame"); track.Size = UDim2.new(1, 0, 0, 4); track.Position = UDim2.new(0, 0, 0, 20); track.BackgroundColor3 = Color3.fromRGB(50, 50, 60); track.BorderSizePixel = 0; track.Parent = container
        local trackCorner = Instance.new("UICorner"); trackCorner.CornerRadius = UDim.new(1, 0); trackCorner.Parent = track
        local fill = Instance.new("Frame"); fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = Color3.fromRGB(0, 255, 140); fill.BorderSizePixel = 0; fill.Parent = track
        local fillCorner = Instance.new("UICorner"); fillCorner.CornerRadius = UDim.new(1, 0); fillCorner.Parent = fill
        local knob = Instance.new("Frame"); knob.Size = UDim2.new(0, 10, 0, 10); knob.AnchorPoint = Vector2.new(0.5, 0.5); knob.Position = UDim2.new(0, 0, 0.5, 0); knob.BackgroundColor3 = Color3.new(1, 1, 1); knob.Parent = track
        local knobCorner = Instance.new("UICorner"); knobCorner.CornerRadius = UDim.new(1, 0); knobCorner.Parent = knob
        local isDragging = false
        local function updateVisuals(value)
            local alpha = math_clamp((value - min) / (max - min), 0, 1)
            fill.Size = UDim2.new(alpha, 0, 1, 0); knob.Position = UDim2.new(alpha, 0, 0.5, 0)
            local finalVal = isFloat and tonumber(string.format("%.2f", value)) or math_floor(value)
            Config[configKey] = finalVal; valueLabel.Text = tostring(finalVal)
            if callback then callback(finalVal) end
        end
        updateVisuals(Config[configKey])
        UIUpdates[configKey] = updateVisuals
        UIS.InputChanged:Connect(function(input)
            if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local relativeX = math_clamp(input.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X)
                updateVisuals(min + ((max - min) * (relativeX / track.AbsoluteSize.X)))
            end
        end)
        UIS.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then isDragging = false end end)
        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDragging = true
                local relativeX = math_clamp(input.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X)
                updateVisuals(min + ((max - min) * (relativeX / track.AbsoluteSize.X)))
            end
        end)
    end

    local function createButton(parent, text, callback)
        local btn = Instance.new("TextButton"); btn.Size = UDim2.new(1, 0, 0, 30); btn.BackgroundColor3 = Color3.fromRGB(40, 40, 50); btn.BorderSizePixel = 0; btn.Text = text; btn.TextColor3 = Color3.new(1, 1, 1); btn.Font = Enum.Font.Gotham; btn.TextSize = 13; btn.Parent = parent
        local btnCorner = Instance.new("UICorner"); btnCorner.CornerRadius = UDim.new(0, 6); btnCorner.Parent = btn
        btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(60, 60, 70)}):Play() end)
        btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(40, 40, 50)}):Play() end)
        btn.MouseButton1Click:Connect(callback)
        return btn
    end

    -- ESP PAGE
    local espPage = createPage("ESP")
    createSwitch(espPage, "Enable ESP", "ESPEnabled")
    createSwitch(espPage, "Team Check", "TeamCheck")
    createSwitch(espPage, "Health Check", "HealthCheck")
    createSwitch(espPage, "Health Bar", "ShowHealthBar")
    createSwitch(espPage, "Distance Text", "ShowDistance")
    createSlider(espPage, "Max Distance", Config.MinDistance, Config.AbsoluteMaxDist, "MaxDistance", false)

    -- VISUALS PAGE
    local visPage = createPage("Visuals")
    local presetLabel = Instance.new("TextLabel"); presetLabel.Size = UDim2.new(1, 0, 0, 15); presetLabel.BackgroundTransparency = 1
    presetLabel.Text = "Presets"; presetLabel.TextColor3 = Color3.fromRGB(180, 180, 180); presetLabel.Font = Enum.Font.GothamBold; presetLabel.TextSize = 12; presetLabel.TextXAlignment = Enum.TextXAlignment.Left; presetLabel.Parent = visPage
    local btnRow = Instance.new("Frame"); btnRow.Size = UDim2.new(1, 0, 0, 30); btnRow.BackgroundTransparency = 1; btnRow.Parent = visPage
    local rowLayout = Instance.new("UIListLayout"); rowLayout.FillDirection = Enum.FillDirection.Horizontal; rowLayout.Padding = UDim.new(0, 5); rowLayout.Parent = btnRow

    local function setPreset(r, g, b)
        Config.boxColor = Color3.fromRGB(r, g, b)
        if UIUpdates["BoxR"] then UIUpdates["BoxR"](r) end
        if UIUpdates["BoxG"] then UIUpdates["BoxG"](g) end
        if UIUpdates["BoxB"] then UIUpdates["BoxB"](b) end
    end

    local function createColorBtn(parent, color)
        local b = Instance.new("TextButton"); b.Size = UDim2.new(0, 30, 0, 30); b.BackgroundColor3 = color; b.Text = ""; b.Parent = parent
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = b
        local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(100, 100, 100); s.Thickness = 1; s.Parent = b
        b.MouseButton1Click:Connect(function() setPreset(color.R * 255, color.G * 255, color.B * 255) end)
    end

    createColorBtn(btnRow, Color3.fromRGB(0, 255, 140)); createColorBtn(btnRow, Color3.fromRGB(255, 50, 50))
    createColorBtn(btnRow, Color3.fromRGB(180, 0, 255)); createColorBtn(btnRow, Color3.fromRGB(0, 200, 255)); createColorBtn(btnRow, Color3.fromRGB(255, 255, 255))

    local customLabel = Instance.new("TextLabel"); customLabel.Size = UDim2.new(1, 0, 0, 15); customLabel.BackgroundTransparency = 1
    customLabel.Text = "Custom Box Color"; customLabel.TextColor3 = Color3.fromRGB(180, 180, 180); customLabel.Font = Enum.Font.GothamBold; customLabel.TextSize = 12; customLabel.TextXAlignment = Enum.TextXAlignment.Left; customLabel.Parent = visPage
    local preview = Instance.new("Frame"); preview.Size = UDim2.new(1, 0, 0, 10); preview.BackgroundColor3 = Config.boxColor; preview.BorderSizePixel = 0; preview.Parent = visPage
    local preCorner = Instance.new("UICorner"); preCorner.CornerRadius = UDim.new(0, 4); preCorner.Parent = preview

    createSlider(visPage, "Red", 0, 255, "BoxR", false, function() Config.boxColor = Color3.fromRGB(Config.BoxR*255, Config.BoxG*255, Config.BoxB*255); preview.BackgroundColor3 = Config.boxColor end)
    createSlider(visPage, "Green", 0, 255, "BoxG", false, function() Config.boxColor = Color3.fromRGB(Config.BoxR*255, Config.BoxG*255, Config.BoxB*255); preview.BackgroundColor3 = Config.boxColor end)
    createSlider(visPage, "Blue", 0, 255, "BoxB", false, function() Config.boxColor = Color3.fromRGB(Config.BoxR*255, Config.BoxG*255, Config.BoxB*255); preview.BackgroundColor3 = Config.boxColor end)
    createSwitch(visPage, "Match Text Color to Box", "matchTextColor")

    -- AIMBOT PAGE
    local aimPage = createPage("Aimbot")
    createSwitch(aimPage, "Enable Aimbot", "AimbotEnabled")
    createSwitch(aimPage, "Sticky Aim", "StickyAim")
    createSwitch(aimPage, "Show FOV Circle", "ShowFOV")
    createSlider(aimPage, "Aimbot FOV", 10, 500, "FOVSize", false)
    createSlider(aimPage, "Smoothness", 0.01, 1.0, "Smoothness", true)

    local partBtn
    partBtn = createButton(aimPage, "Aim Part: " .. Config.TargetPart, function()
        local parts = {"Head", "Torso", "HumanoidRootPart"}
        local idx = 1
        for i, v in ipairs(parts) do if v == Config.TargetPart then idx = i break end end
        Config.TargetPart = parts[(idx % #parts) + 1]
        partBtn.Text = "Aim Part: " .. Config.TargetPart
        stickyTargetPlayer = nil
    end)
    UIUpdates["TargetPart"] = function(val) if partBtn then partBtn.Text = "Aim Part: " .. val end end

    local aimKeyBtn
    aimKeyBtn = createButton(aimPage, "Aimbot Key: " .. Config.AimKey.Name, function()
        Config.IsListeningForAim = true
        aimKeyBtn.Text = "Press Key/Mouse..."
    end)
    UIUpdates["AimKey"] = function(enum) if aimKeyBtn then aimKeyBtn.Text = "Aimbot Key: " .. enum.Name end end

    -- SETTINGS PAGE
    local setPage = createPage("Settings")
    local nameInput = Instance.new("TextBox")
    nameInput.Size = UDim2.new(1, 0, 0, 30); nameInput.BackgroundColor3 = Color3.fromRGB(30, 30, 38); nameInput.BorderSizePixel = 0
    nameInput.Text = ""; nameInput.PlaceholderText = "Enter Config Name..."; nameInput.TextColor3 = Color3.new(1, 1, 1); nameInput.Font = Enum.Font.Gotham; nameInput.TextSize = 13; nameInput.Parent = setPage
    local inputCorner = Instance.new("UICorner"); inputCorner.CornerRadius = UDim.new(0, 6); inputCorner.Parent = nameInput

    local listContainer = Instance.new("Frame")
    listContainer.Size = UDim2.new(1, 0, 0, 150); listContainer.BackgroundTransparency = 1; listContainer.Parent = setPage
    local listLayout = Instance.new("UIListLayout"); listLayout.Padding = UDim.new(0, 5); listLayout.Parent = listContainer

    local function refreshConfigList()
        for _, child in ipairs(listContainer:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
        local files = listfiles(configFolder)
        for _, filePath in ipairs(files) do
            local fileName = string.match(filePath, "([^/\\]+)%.json$")
            if fileName then
                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, 0, 0, 30); row.BackgroundColor3 = Color3.fromRGB(35, 35, 42); row.Parent = listContainer
                local rowCorner = Instance.new("UICorner"); rowCorner.CornerRadius = UDim.new(0, 6); rowCorner.Parent = row
                local txt = Instance.new("TextLabel")
                txt.Size = UDim2.new(0.6, 0, 1, 0); txt.Position = UDim2.new(0, 10, 0, 0); txt.BackgroundTransparency = 1
                txt.Text = fileName; txt.TextColor3 = Color3.new(1, 1, 1); txt.Font = Enum.Font.Gotham; txt.TextSize = 13; txt.TextXAlignment = Enum.TextXAlignment.Left; txt.Parent = row
                local loadBtn = Instance.new("TextButton")
                loadBtn.Size = UDim2.new(0.15, 0, 0, 22); loadBtn.Position = UDim2.new(0.65, 0, 0.5, -11); loadBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 100); loadBtn.Text = "Load"; loadBtn.TextColor3 = Color3.new(1, 1, 1); loadBtn.Font = Enum.Font.GothamBold; loadBtn.TextSize = 11; loadBtn.Parent = row
                local lbCorner = Instance.new("UICorner"); lbCorner.CornerRadius = UDim.new(0, 4); lbCorner.Parent = loadBtn
                loadBtn.MouseButton1Click:Connect(function() loadConfig(fileName); preview.BackgroundColor3 = Config.boxColor end)
                local delBtn = Instance.new("TextButton")
                delBtn.Size = UDim2.new(0.15, 0, 0, 22); delBtn.Position = UDim2.new(0.82, 0, 0.5, -11); delBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50); delBtn.Text = "Delete"; delBtn.TextColor3 = Color3.new(1, 1, 1); delBtn.Font = Enum.Font.GothamBold; delBtn.TextSize = 11; delBtn.Parent = row
                local dbCorner = Instance.new("UICorner"); dbCorner.CornerRadius = UDim.new(0, 4); dbCorner.Parent = delBtn
                delBtn.MouseButton1Click:Connect(function() deleteConfig(fileName); refreshConfigList() end)
            end
        end
    end

    createButton(setPage, "Save New Config", function()
        if nameInput.Text ~= "" then
            if saveConfig(nameInput.Text) then nameInput.Text = ""; refreshConfigList() end
        end
    end)
    createButton(setPage, "Refresh Config List", refreshConfigList)

    local menuKeyBtn
    menuKeyBtn = createButton(setPage, "Menu Key: " .. Config.ToggleKey.Name, function()
        Config.IsListeningForKey = true
        menuKeyBtn.Text = "Press Key..."
    end)
    UIUpdates["ToggleKey"] = function(enum) if menuKeyBtn then menuKeyBtn.Text = "Menu Key: " .. enum.Name end end

    local tabButtons = {}
    local function switchTab(pageName)
        for name, page in pairs(pages) do page.Visible = (name == pageName) end
        for name, btn in pairs(tabButtons) do
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = (name == pageName) and Color3.fromRGB(40, 40, 50) or Color3.fromRGB(28, 28, 34)}):Play()
            btn.TextColor3 = (name == pageName) and Color3.fromRGB(0, 255, 140) or Color3.fromRGB(150, 150, 150)
        end
        if pageName == "Settings" then refreshConfigList() end
    end

    for i, name in ipairs(pageNames) do
        local tabBtn = Instance.new("TextButton")
        tabBtn.Size = UDim2.new(0.8, 0, 0, 30); tabBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 34); tabBtn.BorderSizePixel = 0
        tabBtn.Text = name; tabBtn.TextColor3 = Color3.fromRGB(150, 150, 150); tabBtn.Font = Enum.Font.GothamBold; tabBtn.TextSize = 13
        tabBtn.LayoutOrder = i; tabBtn.Parent = tabBar
        local tCorner = Instance.new("UICorner"); tCorner.CornerRadius = UDim.new(0, 6); tCorner.Parent = tabBtn
        tabBtn.MouseButton1Click:Connect(function() switchTab(name) end)
        tabButtons[name] = tabBtn
    end
    switchTab("ESP")

    UIS.InputBegan:Connect(function(input, gameProcessed)
        if Config.IsListeningForAim then
            if input.UserInputType == Enum.UserInputType.Keyboard then Config.AimKey, Config.AimKeyType = input.KeyCode, "KeyCode"
            elseif string.match(input.UserInputType.Name, "MouseButton") then Config.AimKey, Config.AimKeyType = input.UserInputType, "UserInputType" end
            Config.IsListeningForAim = false
            if UIUpdates["AimKey"] then UIUpdates["AimKey"](Config.AimKey) end
            return
        end
        if Config.IsListeningForKey then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                Config.ToggleKey = input.KeyCode; Config.IsListeningForKey = false
                if UIUpdates["ToggleKey"] then UIUpdates["ToggleKey"](Config.ToggleKey) end
            end
            return 
        end
        if not gameProcessed and input.KeyCode == Config.ToggleKey then main.Visible = not main.Visible end
    end)

    return gui
end

local myGui = createGUI()

getgenv().SimpleESP = {
    boxes = boxes, conn = conn, gui = myGui, fovCircle = fovCircle, Config = Config, save = saveConfig, load = loadConfig, delete = deleteConfig,
    stop = function()
        conn:Disconnect(); for _, d in pairs(boxes) do d.box:Remove(); d.name:Remove(); d.healthBar:Remove(); d.distText:Remove() end
        if myGui then myGui:Destroy() end; if fovCircle then fovCircle:Remove() end
    end
}
