-- Combat/Godmode.lua — FACTORY. Anti-hit vía self-ragdoll (WIP).
-- Reverse: IsRagdoll es campo Lua, gate de disparo solo-cliente → firar op14 DIRECTO dispara
-- ragdolleado (AutoFire/RapidFire ya lo hacen). Ragdoll NO da inmunidad server; el anti-hit =
-- mover el HITBOX real (Head/Torso/HRP) lejos. Para NO borrar partes: mover el assembly ENTERO
-- junto con el mismo offset y velocidades en 0 (nada de rotvelocity absurda). Equipar arma ANTES.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Ragdoll = require("Combat.Ragdoll")
    local God = {}

    local function char() return LP.Character end
    local function hrp() local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end

    local seed = 0
    -- mueve el assembly ENTERO (mismo delta) + velocidades 0 → no estira constraints, no borra partes
    local function moveAssembly(targetPos)
        local c = char(); local root = hrp(); if not (c and root) then return end
        local delta = targetPos - root.Position
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                pcall(function()
                    p.CFrame = p.CFrame + delta
                    p.AssemblyLinearVelocity = Vector3.zero
                    p.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
    end

    function God.tick()
        if not Ragdoll.isRagdolled() then LIP.fire(23); return end   -- asegura ragdoll on (1 frame)
        local root = hrp(); if not root then return end
        if not LIP.godBase then LIP.godBase = root.Position end
        local mode = O("GodMode") or "High"
        local h = O("GodHeight") or 150
        local base = LIP.godBase
        local pos
        if mode == "Jitter" then
            seed = seed + 1
            pos = base + Vector3.new(math.noise(seed,0)*40, h + math.noise(0,seed)*20, math.noise(seed,seed)*40)
        else -- High: te sube; enemigos apuntan al piso, vos arriba
            pos = base + Vector3.new(0, h, 0)
        end
        moveAssembly(pos)
    end

    function God.stop()
        LIP.godBase = nil
        if Ragdoll.isRagdolled() then LIP.fire(23) end   -- des-ragdoll
    end

    return God
end
