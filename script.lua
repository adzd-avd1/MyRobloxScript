--[[
    Simple ESP + Aimbot with Health Bars & Distance Text
    Libraries: Drawing, Instance, UserInputService, getgenv
]]

-- === SETUP ===
local cloneref = cloneref or function(o) return o end
local Players    = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UIS        = cloneref(game:GetService("UserInputService"))
local Camera     = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Cleanup previous instances
if getgenv().SimpleESP then
    for _, data in pairs(getgenv().SimpleESP.boxes) do
        data.box:Remove()
        data.name:Remove()
        data.healthBar:Remove()
        data.distText:Remove()
    end
    getgenv().SimpleESP.conn:Disconnect()
    if getgenv().SimpleESP.gui then getgenv().SimpleESP.gui:Destroy() end
    if getgenv().SimpleESP.fovCircle then getgenv().SimpleESP.fovCircle:Remove() end
    getgenv().SimpleESP = nil
end

-- === CONFIGURATION ===
local Config = {
    -- ESP Settings
    ESPEnabled = true,
    TeamCheck = true,
    HealthCheck = true,
    ShowHealthBar = true, -- NEW
    ShowDistance = true,  -- NEW
    DistanceCheck = true,
    MaxDistance = 1000,
    MinDistance = 50,
    AbsoluteMaxDist = 5000,
    
    -- Aimbot Settings
    AimbotEnabled = false,
    StickyAim = true,
    TargetPart = "Head",
    ShowFOV = true,
    FOVSize = 150,
    Smoothness = 0.15,
    AimKey = Enum.UserInputType.MouseButton2,
    
    -- UI Config
    ToggleKey = Enum.KeyCode.RightShift,
    IsListeningForKey = false,
    
    -- Colors
    boxColor = Color3.fromRGB(0, 255, 140),
    textColor = Color3.new(1, 1, 1),
    textSize = 14,
    thickness = 1,
}

-- === STORAGE ===
local boxes = {}
local isAiming = false
local stickyTargetPlayer = nil

local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1
fovCircle.NumSides = 60
fovCircle.Radius = Config.FOVSize
fovCircle.Filled = false
fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Transparency = 1
fovCircle.Visible = false
fovCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

-- ==========================================
-- 1. ESP FUNCTIONS
-- ==========================================
local function createESP(player)
    if player == LocalPlayer then return end

    local box = Drawing.new("Square")
    box.Color     = Config.boxColor
    box.Thickness = Config.thickness
    box.Filled    = false
    box.Visible   = false

    local name = Drawing.new("Text")
    name.Color    = Config.textColor
    name.Size     = Config.textSize
    name.Center   = true
    name.Outline  = true
    name.Visible  = false

    -- NEW: Health Bar
    local healthBar = Drawing.new("Square")
    healthBar.Thickness = 1
    healthBar.Filled = true
    healthBar.Visible = false

    -- NEW: Distance Text
    local distText = Drawing.new("Text")
    distText.Color = Color3.fromRGB(200, 200, 200)
    distText.Size = 12
    distText.Center = true
    distText.Outline = true
    distText.Visible = false

    boxes[player] = { box = box, name = name, healthBar = healthBar, distText = distText }
end

local function destroyESP(player)
    local data = boxes[player]
    if not data then return end
    data.box:Remove()
    data.name:Remove()
    data.healthBar:Remove()
    data.distText:Remove()
    boxes[player] = nil
end

for _, player in ipairs(Players:GetPlayers()) do createESP(player) end
Players.PlayerAdded:Connect(createESP)
Players.PlayerRemoving:Connect(destroyESP)

-- ==========================================
-- 2. AIMBOT LOGIC
-- ==========================================
local function getTargetPart(character)
    if not character then return nil end
    if Config.TargetPart == "Head" then
        return character:FindFirstChild("Head")
    elseif Config.TargetPart == "Torso" then
        local upper = character:FindFirstChild("UpperTorso")
        if upper then return upper end
        local torso = character:FindFirstChild("Torso")
        if torso then return torso end
        return character:FindFirstChild("HumanoidRootPart")
    elseif Config.TargetPart == "HumanoidRootPart" then
        return character:FindFirstChild("HumanoidRootPart")
    end
    return character:FindFirstChild("Head")
end

local function isValidTarget(player)
    if player == LocalPlayer then return false, nil end
    
    local char = player.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hum) then return false, nil end
    if Config.HealthCheck and hum.Health <= 0 then return false, nil end
    if Config.TeamCheck and LocalPlayer.Team and player.Team == LocalPlayer.Team then return false, nil end

    local targetPart = getTargetPart(char)
    if not targetPart then return false, nil end

    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if Config.DistanceCheck and myHRP then
        local dist = (myHRP.Position - targetPart.Position).Magnitude
        if dist > Config.MaxDistance then return false, nil end
    end
    return true, targetPart
end

local function getTarget()
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    
    if Config.StickyAim and stickyTargetPlayer then
        local isValid, targetPart = isValidTarget(stickyTargetPlayer)
        if isValid then
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            if onScreen then
                local distToCenter = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                if distToCenter <= Config.FOVSize then
                    return targetPart
                end
            end
        end
        stickyTargetPlayer = nil
    end

    local closestTargetPlayer = nil
    local closestPart = nil
    local shortestDistance = Config.FOVSize

    for _, player in ipairs(Players:GetPlayers()) do
        local isValid, targetPart = isValidTarget(player)
        if isValid then
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            if onScreen then
                local distToCenter = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                if distToCenter < shortestDistance then
                    shortestDistance = distToCenter
                    closestTargetPlayer = player
                    closestPart = targetPart
                end
            end
        end
    end

    if Config.StickyAim and closestTargetPlayer then
        stickyTargetPlayer = closestTargetPlayer
    end
    return closestPart
end

-- ==========================================
-- 3. RENDER LOOP
-- ==========================================
local conn = RunService.RenderStepped:Connect(function()
    fovCircle.Visible = Config.AimbotEnabled and Config.ShowFOV
    fovCircle.Radius = Config.FOVSize
    fovCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    if Config.AimbotEnabled and isAiming then
        local targetPart = getTarget()
        if targetPart then
            local cameraPos = Camera.CFrame.Position
            local newCFrame = CFrame.lookAt(cameraPos, targetPart.Position)
            Camera.CFrame = Camera.CFrame:Lerp(newCFrame, Config.Smoothness)
        end
    end

    for player, data in pairs(boxes) do
        -- Hide everything if ESP is off
        if not Config.ESPEnabled then
            data.box.Visible = false
            data.name.Visible = false
            data.healthBar.Visible = false
            data.distText.Visible = false
            continue
        end

        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")

        if not (char and hrp and head and hum) then
            data.box.Visible = false
            data.name.Visible = false
            data.healthBar.Visible = false
            data.distText.Visible = false
            continue
        end
        
        if Config.HealthCheck and hum.Health <= 0 then
            data.box.Visible = false
            data.name.Visible = false
            data.healthBar.Visible = false
            data.distText.Visible = false
            continue
        end
        
        if Config.TeamCheck and LocalPlayer.Team and player.Team == LocalPlayer.Team then
            data.box.Visible = false
            data.name.Visible = false
            data.healthBar.Visible = false
            data.distText.Visible = false
            continue
        end

        local myChar = LocalPlayer.Character
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local distance = 0
        
        if myHRP then
            distance = (myHRP.Position - hrp.Position).Magnitude
            if Config.DistanceCheck and distance > Config.MaxDistance then
                data.box.Visible = false
                data.name.Visible = false
                data.healthBar.Visible = false
                data.distText.Visible = false
                continue
            end
        end

        local topVec, onScreenTop = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.75, 0))
        local botVec              = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))

        if not onScreenTop then
            data.box.Visible = false
            data.name.Visible = false
            data.healthBar.Visible = false
            data.distText.Visible = false
            continue
        end

        local height = math.abs(botVec.Y - topVec.Y)
        local width  = height / 2
        if height < 2 or width < 1 then
            data.box.Visible = false
            data.name.Visible = false
            data.healthBar.Visible = false
            data.distText.Visible = false
            continue
        end

        -- 1. Draw Box
        data.box.Size     = Vector2.new(width, height)
        data.box.Position = Vector2.new(topVec.X - width / 2, topVec.Y)
        data.box.Visible  = true

        -- 2. Draw Name
        data.name.Text     = player.Name
        data.name.Position = Vector2.new(topVec.X, topVec.Y - Config.textSize - 4)
        data.name.Visible  = true

        -- 3. Draw Health Bar
        if Config.ShowHealthBar then
            local hpPct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            -- Make the health bar 3 pixels wide, scale height based on health
            data.healthBar.Size = Vector2.new(3, height * hpPct)
            -- Position it to the left of the box. 
            -- Y position adds the missing height so it shrinks from the top down
            data.healthBar.Position = Vector2.new(topVec.X - (width / 2) - 6, topVec.Y + (height * (1 - hpPct)))
            -- Color transitions from Red (0) -> Yellow (0.15) -> Green (0.3) in HSV
            data.healthBar.Color = Color3.fromHSV(hpPct * 0.3, 1, 1)
            data.healthBar.Visible = true
        else
            data.healthBar.Visible = false
        end

        -- 4. Draw Distance Text
        if Config.ShowDistance then
            data.distText.Text = math.floor(distance) .. "m"
            -- Position it directly below the box
            data.distText.Position = Vector2.new(topVec.X, topVec.Y + height + 2)
            data.distText.Visible = true
        else
            data.distText.Visible = false
        end
    end
end)

-- ==========================================
-- 4. GUI CREATION
-- ==========================================
local function createGUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "PotassiumESP_GUI"
    gui.ResetOnSpawn = false
    gui.Parent = gethui and gethui() or game:GetService("CoreGui")

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 220, 0, 630) -- Increased height for new toggles
    main.Position = UDim2.new(0, 50, 0, 50)
    main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = main

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    title.BorderSizePixel = 0
    title.Text = "ESP & Aimbot Settings"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = main
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = title

    local function createToggle(text, yPos, configKey)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.9, 0, 0, 30)
        btn.Position = UDim2.new(0.05, 0, 0, yPos)
        btn.BackgroundColor3 = Config[configKey] and Color3.fromRGB(0, 170, 100) or Color3.fromRGB(60, 60, 70)
        btn.BorderSizePixel = 0
        btn.Text = text .. ": " .. (Config[configKey] and "ON" or "OFF")
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 13
        btn.Parent = main

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btn

        btn.MouseButton1Click:Connect(function()
            Config[configKey] = not Config[configKey]
            btn.BackgroundColor3 = Config[configKey] and Color3.fromRGB(0, 170, 100) or Color3.fromRGB(60, 60, 70)
            btn.Text = text .. ": " .. (Config[configKey] and "ON" or "OFF")
        end)
    end

    local function createSlider(text, yPos, min, max, configKey, isFloat)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0.9, 0, 0, 40)
        container.Position = UDim2.new(0.05, 0, 0, yPos)
        container.BackgroundTransparency = 1
        container.Parent = main

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 20)
        label.BackgroundTransparency = 1
        label.Text = text .. ": " .. Config[configKey]
        label.TextColor3 = Color3.fromRGB(200, 200, 200)
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, 0, 0, 6)
        track.Position = UDim2.new(0, 0, 0, 25)
        track.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        track.BorderSizePixel = 0
        track.Parent = container

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(1, 0)
        trackCorner.Parent = track

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(0, 170, 100)
        fill.BorderSizePixel = 0
        fill.Parent = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(1, 0)
        fillCorner.Parent = fill

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.new(0, 0, 0.5, 0)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0
        knob.Parent = track
        
        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = knob

        local isDragging = false

        local function updateVisuals(value)
            local alpha = (value - min) / (max - min)
            alpha = math.clamp(alpha, 0, 1)
            
            fill.Size = UDim2.new(alpha, 0, 1, 0)
            knob.Position = UDim2.new(alpha, 0, 0.5, 0)
            
            local finalVal = isFloat and tonumber(string.format("%.2f", value)) or math.floor(value)
            Config[configKey] = finalVal
            label.Text = text .. ": " .. finalVal
        end

        updateVisuals(Config[configKey])

        UIS.InputChanged:Connect(function(input)
            if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local relativeX = math.clamp(input.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X)
                local alpha = relativeX / track.AbsoluteSize.X
                updateVisuals(min + ((max - min) * alpha))
            end
        end)

        UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                isDragging = false
            end
        end)

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                isDragging = true
                local relativeX = math.clamp(input.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X)
                local alpha = relativeX / track.AbsoluteSize.X
                updateVisuals(min + ((max - min) * alpha))
            end
        end)
    end

    -- === POPULATE GUI ===
    createToggle("Enable ESP", 40, "ESPEnabled")
    createToggle("Team Check", 80, "TeamCheck")
    createToggle("Health Check", 120, "HealthCheck")
    
    -- NEW TOGGLES
    createToggle("Health Bar", 160, "ShowHealthBar")
    createToggle("Distance Text", 200, "ShowDistance")
    
    createSlider("Max Distance", 240, Config.MinDistance, Config.AbsoluteMaxDist, "MaxDistance", false)

    -- Aimbot Section
    createToggle("Enable Aimbot", 300, "AimbotEnabled")
    createToggle("Sticky Aim", 340, "StickyAim")
    
    local partBtn = Instance.new("TextButton")
    partBtn.Size = UDim2.new(0.9, 0, 0, 30)
    partBtn.Position = UDim2.new(0.05, 0, 0, 380)
    partBtn.BackgroundColor3 = Color3.fromRGB(50, 120, 200)
    partBtn.BorderSizePixel = 0
    partBtn.Text = "Aim Part: " .. Config.TargetPart
    partBtn.TextColor3 = Color3.new(1, 1, 1)
    partBtn.Font = Enum.Font.Gotham
    partBtn.TextSize = 13
    partBtn.Parent = main

    local partCorner = Instance.new("UICorner")
    partCorner.CornerRadius = UDim.new(0, 6)
    partCorner.Parent = partBtn

    local partsList = {"Head", "Torso", "HumanoidRootPart"}
    local partIndex = 1

    partBtn.MouseButton1Click:Connect(function()
        partIndex = partIndex + 1
        if partIndex > #partsList then partIndex = 1 end
        Config.TargetPart = partsList[partIndex]
        partBtn.Text = "Aim Part: " .. Config.TargetPart
        stickyTargetPlayer = nil
    end)

    createToggle("Show FOV Circle", 420, "ShowFOV")
    createSlider("Aimbot FOV", 460, 10, 500, "FOVSize", false)
    createSlider("Aim Smoothness", 500, 0.01, 1.0, "Smoothness", true)
    
    local aimInfo = Instance.new("TextLabel")
    aimInfo.Size = UDim2.new(0.9, 0, 0, 20)
    aimInfo.Position = UDim2.new(0.05, 0, 0, 540)
    aimInfo.BackgroundTransparency = 1
    aimInfo.Text = "[ HOLD RIGHT-CLICK TO AIM ]"
    aimInfo.TextColor3 = Color3.fromRGB(255, 100, 100)
    aimInfo.Font = Enum.Font.GothamBold
    aimInfo.TextSize = 12
    aimInfo.Parent = main

    local keybindBtn = Instance.new("TextButton")
    keybindBtn.Size = UDim2.new(0.9, 0, 0, 30)
    keybindBtn.Position = UDim2.new(0.05, 0, 0, 570)
    keybindBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    keybindBtn.BorderSizePixel = 0
    keybindBtn.Text = "Menu Key: " .. Config.ToggleKey.Name
    keybindBtn.TextColor3 = Color3.new(1, 1, 1)
    keybindBtn.Font = Enum.Font.Gotham
    keybindBtn.TextSize = 13
    keybindBtn.Parent = main

    local keybindCorner = Instance.new("UICorner")
    keybindCorner.CornerRadius = UDim.new(0, 6)
    keybindCorner.Parent = keybindBtn

    keybindBtn.MouseButton1Click:Connect(function()
        Config.IsListeningForKey = true
        keybindBtn.Text = "Press any key..."
        keybindBtn.BackgroundColor3 = Color3.fromRGB(170, 100, 0)
    end)

    UIS.InputBegan:Connect(function(input, gameProcessed)
        if input.UserInputType == Config.AimKey then
            isAiming = true
        end

        if Config.IsListeningForKey then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                Config.ToggleKey = input.KeyCode
                Config.IsListeningForKey = false
                keybindBtn.Text = "Menu Key: " .. Config.ToggleKey.Name
                keybindBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            end
            return 
        end

        if not gameProcessed and input.KeyCode == Config.ToggleKey then
            main.Visible = not main.Visible
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Config.AimKey then
            isAiming = false
            stickyTargetPlayer = nil
        end
    end)

    return gui
end

local myGui = createGUI()

-- Expose for cleanup
getgenv().SimpleESP = {
    boxes = boxes,
    conn  = conn,
    gui   = myGui,
    fovCircle = fovCircle,
    Config = Config,
    stop  = function()
        conn:Disconnect()
        for _, data in pairs(boxes) do
            data.box:Remove()
            data.name:Remove()
            data.healthBar:Remove()
            data.distText:Remove()
        end
        if myGui then myGui:Destroy() end
        if fovCircle then fovCircle:Remove() end
    end
}
