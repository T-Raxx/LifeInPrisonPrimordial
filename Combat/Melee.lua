-- Combat/Melee.lua — FACTORY. Melee/puños.
--  · AUTO-PUNCH (op33 OnPunchRemote): FireServer(33, enemyBasePart). NO usa GST → fire activo.
--    (el cliente legit lo dispara en el .Touched del puño; nosotros lo firamos directo al enemigo.)
--  · MELEE AURA (op16): precache del target; el redirect real lo hace el hook en Net.lua.
return function(require, LIP, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Target = require("Combat.Target")
    local Melee = {}

    local lastPunch = 0

    local function bodyPart(char)
        return char and (char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            or char:FindFirstChild("Head"))
    end

    -- precache del target de melee-aura (corre en el driver, afuera del hook)
    function Melee.cacheMelee(opts)
        if not LIP.meleeOn then LIP.meleePart = nil; return end
        local t = Target.nearestEnemy(opts)
        LIP.meleePart = t and bodyPart(t.Character) or nil
    end

    -- AUTO-PUNCH activo (op33). Enemigo dentro de rango → fire su parte, con rate limit.
    function Melee.autoPunch(opts)
        local now = os.clock()
        if now - lastPunch < (opts.rate or 0.5) then return end
        local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end
        local t = Target.nearestEnemy({ range = opts.range or 8, teamCheck = opts.teamCheck,
                                        friendCheck = opts.friendCheck, wallcheck = false })
        local part = t and bodyPart(t.Character)
        if not part then return end
        lastPunch = now
        LIP.fire(33, part)   -- OnPunchRemote(part) — sin GST
    end

    return Melee
end
