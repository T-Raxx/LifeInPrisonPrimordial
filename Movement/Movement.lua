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

    ------------------------------------------------------------------ FLY (por AssemblyLinearVelocity)
    -- Fly velocity-based: subir/bajar (Space/Shift) y moverse por AssemblyLinearVelocity directo. En hover
    -- (sin input vertical) sumamos una contra-gravedad (Gravity*dt/2) para no hundirse. Solo un BodyGyro
    -- para mantener la orientación (mirando la cámara). Mantiene el assembly despierto → no pisa el keep-alive.
    local flyBG, flying = nil, false
    local function stopFly()
        flying = false
        if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
        local h = hum(); if h then pcall(function() h.PlatformStand = false end) end
    end
    local function startFly()
        local root = hrp(); if not root then return end
        stopFly()
        flying = true
        local h = hum(); if h then h.PlatformStand = true end
        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(1, 1, 1) * 9e9
        flyBG.P = 1e4
        flyBG.CFrame = root.CFrame
        flyBG.Parent = root
    end
    local function updateFly(dt)
        local root, cam = hrp(), Workspace.CurrentCamera
        if not (root and cam) then return end
        if not flyBG or flyBG.Parent ~= root then startFly(); return end
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
        local vel = (dir.Magnitude > 0) and (dir.Unit * speed) or Vector3.zero
        -- contra-gravedad (frame-rate independiente) → hover estable sin hundirse
        local gcomp = Workspace.Gravity * (dt or (1/60)) * 0.5
        root.AssemblyLinearVelocity  = vel + Vector3.new(0, gcomp, 0)
        root.AssemblyAngularVelocity = Vector3.zero
    end

    ------------------------------------------------------------------ NOCLIP
    local function updateNoclip()
        local c = char(); if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end

    ------------------------------------------------------------------ SPEED / JUMP  (AC-SAFE)
    -- Escribir Humanoid.WalkSpeed/JumpHeight CRUDO dispara el AC (WalkSpeedUnexpected/JumpHeightUnexpected)
    -- → auto-kill a los 0.5s. La vía sancionada = el sistema de buffs op47 (CharacterDeOrBuff local),
    -- que entra por el setter graceado del juego (u2686). Verificado en vivo: WalkSpeed sube, sin kill.
    -- El buff SUMA en una lista → firamos solo el DELTA cuando cambia (no per-frame), y lo revertimos.
    local WS_BASE, JH_BASE = 16, 7.2
    local wsApplied, jhApplied = 0, 0
    local function applyBuff(effect, want, appliedRef)
        local applied = appliedRef()
        if want == applied then return applied end
        local c = char(); if not c then return applied end
        -- op47: (Model, Effects[WalkSpeed=1|JumpHeight=2], deltaValue, Type.Duration=1, bigTime, Interp.None=1)
        LIP.fireLocal(47, c, effect, want - applied, 1, 1e9, 1)
        return want
    end
    local function updateSpeed()
        local wantWS = (T("WalkSpeedOn") and ((O("WalkSpeed") or WS_BASE) - WS_BASE)) or 0
        wsApplied = applyBuff(1, wantWS, function() return wsApplied end)
        local wantJH = (T("JumpOn") and ((O("JumpHeight") or JH_BASE) - JH_BASE)) or 0
        jhApplied = applyBuff(2, wantJH, function() return jhApplied end)
    end

    ------------------------------------------------------------------ INIT
    function Move.init()
        LIP.onCleanup(stopFly)

        LIP.track(RunService.RenderStepped:Connect(function(dt)
            if T("Fly") then
                if not flying then startFly() end
                updateFly(dt)
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

        -- respawn: soltar el fly viejo + resetear buffs aplicados (el char nuevo no tiene ninguno)
        LIP.track(LP.CharacterAdded:Connect(function()
            stopFly(); wsApplied, jhApplied = 0, 0
        end))
    end

    return Move
end
