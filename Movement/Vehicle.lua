-- Movement/Vehicle.lua — FACTORY. Exploits de vehículo.
-- Los vehículos son FÍSICA 100% client-side: el ocupante del VehicleSeat es network owner del
-- assembly (Roblox). NO hay autoridad server sobre el movimiento → basta con sentarse y escribir
-- la física / los attributes que el loop de manejo del cliente ya lee cada frame (Car4W/Motorcycle
-- leen FastSpeed/FastTorque/SlowSpeed/SlowTorque/MaxSpeed/Torque del Model como attributes).
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Veh = {}

    local function hum()  local c = LP.Character; return c and c:FindFirstChildOfClass("Humanoid") end
    local function seat() local h = hum(); return h and h.SeatPart end
    local function vehicleModel()
        local s = seat(); if not s then return nil, nil end
        return s:FindFirstAncestorWhichIsA("Model"), s
    end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end
    local function O(f) local o = Lib.Options[f];  return o and o.Value end

    local SPEED_ATTRS = { "FastSpeed", "FastTorque", "SlowSpeed", "SlowTorque", "MaxSpeed", "Torque" }
    local saved = {}   -- [model] = { attr = origValue }  (para restaurar, evita compounding)

    local function applySpeed()
        local m = vehicleModel(); if not m then return end
        local mult = O("VehSpeed") or 5
        local s = saved[m]
        if not s then
            s = {}; saved[m] = s
            for _, a in ipairs(SPEED_ATTRS) do
                local v = m:GetAttribute(a)
                if type(v) == "number" then s[a] = v end
            end
        end
        for a, orig in pairs(s) do m:SetAttribute(a, orig * mult) end
    end
    local function restoreSpeed()
        for m, s in pairs(saved) do
            if m and m.Parent then
                for a, orig in pairs(s) do pcall(function() m:SetAttribute(a, orig) end) end
            end
        end
        saved = {}
    end

    -- FLING: velocidad enorme al assembly del vehículo en dirección de la cámara
    function Veh.fling()
        local m, s = vehicleModel()
        local root = (m and m.PrimaryPart) or (s and s.AssemblyRootPart) or s
        if not root then return end
        local dir = Workspace.CurrentCamera.CFrame.LookVector
        pcall(function() root.AssemblyLinearVelocity = dir * (O("VehFlingPower") or 500) end)
    end

    -- auto-sit del VehicleSeat vacío más cercano (clientsit abuse: seat:Sit lo hace el juego mismo)
    function Veh.sitNearest()
        local h = hum(); local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not (h and myHRP) then return end
        local best, bestD = nil, O("SitRange") or 40
        for _, s in ipairs(Workspace:GetDescendants()) do
            if s:IsA("VehicleSeat") and not s.Occupant then
                local d = (s.Position - myHRP.Position).Magnitude
                if d <= bestD then best, bestD = s, d end
            end
        end
        if best then pcall(function() best:Sit(h) end) end
    end

    function Veh.init()
        LIP.onCleanup(restoreSpeed)
        LIP.track(RunService.Heartbeat:Connect(function()
            if T("VehSpeedOn") then applySpeed()
            elseif next(saved) then restoreSpeed() end
        end))
    end

    return Veh
end
