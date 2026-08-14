-- Movement/VelDesync.lua — FACTORY. VELOCITY DESYNC: seteás una AssemblyLinearVelocity ENORME cada frame en
-- dirección ALTERNADA (±) que rota lento → el server extrapola tu pos LEJOS a la tasa del replicator (network
-- ownership) sin escribir CFrame → tu pos SERVERSIDE queda lejos/jittereando de la clientside todo el tiempo.
-- Es el side-effect del walkfling PERO sin flingear (no colisionás con nadie: horizontal + alternado net~0
-- clientside → no te fuiste literalmente, solo el server te ve lejos). Evasión: los enemigos te ven desyncado.
-- Sin CFrame write → el AC de CFrame no se toca (y el de teleport está muerto). Toggle + magnitud.
return function(require, LIP, Lib)
    local RunService = game:GetService("RunService")
    local Players    = game:GetService("Players")
    local LP = Players.LocalPlayer
    local VD = {}

    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end

    local seed, sign = 0, 1
    function VD.init()
        LIP.track(RunService.Heartbeat:Connect(function()
            if not T("VelDesync") then return end
            -- no pisar el desync/spoof/strafe/void (esos ya manejan la pos por CFrame)
            if LIP.spoofOn or LIP.connRep then return end
            local c = LP.Character
            local root = c and c:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local mag = O("VDMagnitude") or 5000
            seed = seed + 0.15
            -- FIX (antes te volaba): PINEAR la CFrame clientside cada frame (no te movés — el AC de CFrame está
            -- muerto) + setear la velocidad enorme → el server tiene (posReal, velHuge) → extrapola LEJOS entre
            -- updates de red = tu pos serverside JITTEREA lejos (desync) mientras tu cuerpo queda quieto.
            local dir = Vector3.new(math.cos(seed), 0, math.sin(seed))
            local real = root.Position
            pcall(function()
                root.CFrame = CFrame.new(real)                 -- pin clientside
                root.AssemblyLinearVelocity = dir * mag        -- server extrapola lejos = desync
            end)
        end))
    end

    return VD
end
