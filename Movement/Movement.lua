-- Movement/Movement.lua — FACTORY. Fly / Noclip / WalkSpeed / Jump / Infinite Jump.
-- El usuario trata el juego como SIN anticheat de movimiento → blatant OK.
-- Self-contained: se conecta solo (RenderStepped/Heartbeat/JumpRequest), lee Lib.Toggles/Options.
-- Limpieza vía LIP.onCleanup (destruye el BodyVelocity/Gyro del fly en Unload).
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local UIS        = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Move = {}

    local function char() return LP.Character end
    local function hrp()  local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
    local function hum()  local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
    local function T(f)   local t = Lib.Toggles[f]; return t and t.Value end
    local function O(f)   local o = Lib.Options[f];  return o and o.Value end

    ------------------------------------------------------------------ FLY
    local flyBV, flyBG, flying = nil, nil, false
    local function stopFly()
        flying = false
        if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end
        if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
        local h = hum(); if h then pcall(function() h.PlatformStand = false end) end
    end
    local function startFly()
        local root = hrp(); if not root then return end
        stopFly()
        flying = true
        local h = hum(); if h then h.PlatformStand = true end
        flyBV = Instance.new("BodyVelocity")
        flyBV.MaxForce = Vector3.new(1, 1, 1) * 9e9
        flyBV.P = 1.25e4
        flyBV.Velocity = Vector3.zero
        flyBV.Parent = root
        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(1, 1, 1) * 9e9
        flyBG.P = 1e4
        flyBG.CFrame = root.CFrame
        flyBG.Parent = root
    end
    local function updateFly()
        local root, cam = hrp(), Workspace.CurrentCamera
        if not (root and cam) then return end
        if not flyBV or flyBV.Parent ~= root then startFly(); return end
        flyBG.CFrame = cam.CFrame
        local dir = Vector3.zero
        if not UIS:GetFocusedTextBox() then
            if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space)     then dir = dir + Vector3.new(0, 1, 0) end
            if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
        end
        local speed = O("FlySpeed") or 60
        flyBV.Velocity = (dir.Magnitude > 0) and (dir.Unit * speed) or Vector3.zero
    end

    ------------------------------------------------------------------ NOCLIP
    local function updateNoclip()
        local c = char(); if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end

    ------------------------------------------------------------------ SPEED / JUMP
    local function updateSpeed()
        local h = hum(); if not h then return end
        if T("WalkSpeedOn") then h.WalkSpeed = O("WalkSpeed") or 16 end
        if T("JumpOn") then
            pcall(function() h.UseJumpPower = true; h.JumpPower = O("JumpPower") or 50 end)
        end
    end

    ------------------------------------------------------------------ INIT
    function Move.init()
        LIP.onCleanup(stopFly)

        LIP.track(RunService.RenderStepped:Connect(function()
            if T("Fly") then
                if not flying then startFly() end
                updateFly()
            elseif flying then
                stopFly()
            end
            if T("Noclip") then updateNoclip() end
        end))

        LIP.track(RunService.Heartbeat:Connect(function()
            updateSpeed()
        end))

        LIP.track(UIS.JumpRequest:Connect(function()
            if T("InfJump") then
                local h = hum(); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
            end
        end))

        -- respawn: soltar el fly viejo (el char nuevo no tiene el BV)
        LIP.track(LP.CharacterAdded:Connect(function() stopFly() end))
    end

    return Move
end
