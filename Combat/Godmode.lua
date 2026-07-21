-- Combat/Godmode.lua — anti-hit vía self-ragdoll + mover el assembly (RESTAURADO).
-- El HBE NO era esto (era el hitPos offset del disparo, ya fixeado). Reverse: IsRagdoll = campo Lua,
-- gate de disparo solo-cliente → op14 directo dispara ragdolleado (AutoFire lo hace). El anti-hit =
-- mover el HITBOX (Head/Torso/HRP) lejos. Movemos el assembly ENTERO junto (mismo delta, velocidad 0
-- → no estira constraints, no borra partes). Equipar arma ANTES de ragdollear.
return function(require, LIP, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Ragdoll = require("Combat.Ragdoll")
    local God = {}

    local function char() return LP.Character end
    local function hrp() local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end

    -- presets EXTREMOS (height en studs)
    God.PRESETS = {
        High        = { mode = "High",   height = 150 },
        ExtremeHigh = { mode = "High",   height = 800 },
        Jitter      = { mode = "Jitter", height = 250 },
        FarJitter   = { mode = "Jitter", height = 600 },
    }
    function God.applyPreset(name)
        local p = God.PRESETS[name]; if not p then return end
        local Op = Lib.Options
        if Op.GodMode   then Op.GodMode:SetValue(p.mode) end
        if Op.GodHeight then Op.GodHeight:SetValue(p.height) end
    end

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
            pos = base + Vector3.new(math.noise(seed,0) * 80, h + math.noise(0,seed) * 50, math.noise(seed,seed) * 80)
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
