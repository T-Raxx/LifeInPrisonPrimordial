-- Combat/Ragdoll.lua — FACTORY. Self-ragdoll vía opcode 23 (Ragdoll, sin args).
-- Confirmado en vivo (place 72659788689464 v48): Events.RemoteEvent:FireServer(23) TOGGLEA
-- el ragdoll server-side (Running <-> Physics), health intacta. El bind R original está gateado
-- tras IsStudio/IsDevGame en el cliente (debug de dev) → nosotros lo firamos manual.
return function(require, LIP, Lib)
    local Ragdoll = {}
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local LP = Players.LocalPlayer
    local OP = 23

    local lastFire = 0

    local function humState()
        local ch  = LP.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        return hum and hum:GetState()
    end
    -- Physics = ragdolleado
    local function isRagdolled()
        local st = humState()
        return st ~= nil and tostring(st):find("Physics") ~= nil
    end
    Ragdoll.isRagdolled = isRagdolled

    -- toggle manual (botón / keybind): el server flipea en cada fire
    function Ragdoll.toggle()
        LIP.fire(OP)
        lastFire = os.clock()
    end

    -- lock permanente: re-ragdolla cuando el estado sale de Physics.
    -- Event-driven (no spam): solo re-fira si NO está ragdolleado, con intervalo mínimo.
    function Ragdoll.tickLock()
        if isRagdolled() then return end
        local now = os.clock()
        if now - lastFire < 0.6 then return end   -- anti-spam del remote
        lastFire = now
        LIP.fire(OP)
    end

    -- ANTI-TAZE/RAGDOLL: resiste el taze/fling enemigo. El fling llega por RagdollImpulse.OnClientEvent (decompile
    -- 7900) → tu cliente hace ApplyImpulse a TU part, guardado por (IsRagdoll ∧ part tuya ∧ vel<30). Dos capas:
    --  1) RECOVER: saca el Humanoid de Physics (ChangeState GettingUp) + PlatformStand false + attr "Ragdoll" false
    --     → IsRagdoll false → el guard del juego skipea el impulse (`if not p1.IsRagdoll then return`).
    --  2) ANTI-FLING backup: mientras seguís ragdolleado, mantené la vel del torso ≥31 (alternando ±Y, net~0) → el
    --     guard `vel<30` del juego rechaza el ApplyImpulse igual. Solo actúa cuando te ragdollean (no spamea).
    local atSign = 1
    function Ragdoll.tickAntiTaze()
        if not isRagdolled() then return end           -- solo cuando te tazean/ragdollean
        local ch = LP.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        if not (hum and root) then return end
        atSign = -atSign
        pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, 31 * atSign, 0) end)  -- anti-fling (vel≥30 → skip)
        pcall(function()
            hum.PlatformStand = false
            if ch:GetAttribute("Ragdoll") ~= nil then ch:SetAttribute("Ragdoll", false) end
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end

    return Ragdoll
end
