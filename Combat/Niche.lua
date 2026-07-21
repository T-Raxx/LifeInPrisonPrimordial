-- Combat/Niche.lua — FACTORY. Exploits niche (payloads del reverse, docs/exploits-2026-07.md).
--  · Throw spam  op43  OnThrow(tool,1)=arm  →  OnThrow(tool,2,aimMode,targetPos,power)=throw
--  · C4 detonate op44  ItemC4Detonate(tool)  (detona sin delay)
--  · Arrest/cuffs op57 Handcuffs(cuffsTool, targetPlayer)  (validación 8-studs/LOS es client-side → a distancia)
return function(require, LIP, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Target = require("Combat.Target")
    local Niche = {}

    local function char() return LP.Character end
    local function myHRP() local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
    local function equipped() local c = char(); return c and c:FindFirstChildOfClass("Tool") end
    local function findTool(namePart)
        namePart = namePart:lower()
        for _, src in ipairs({ char(), LP:FindFirstChild("Backpack") }) do
            for _, x in ipairs(src and src:GetChildren() or {}) do
                if x:IsA("Tool") and x.Name:lower():find(namePart) then return x end
            end
        end
    end

    -- THROW (op43) al enemigo más cercano
    local lastThrow = 0
    function Niche.throwAt(opts)
        local now = os.clock()
        if now - lastThrow < (opts.rate or 1.0) then return end
        local t = equipped(); local hrp = myHRP(); if not (t and hrp) then return end
        local tgt = Target.nearestEnemy({ range = opts.range or 250, teamCheck = opts.teamCheck, friendCheck = opts.friendCheck })
        local ch = tgt and tgt.Character
        local part = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
        if not part then return end
        lastThrow = now
        local dist = (part.Position - hrp.Position).Magnitude
        local power = math.clamp(dist * 0.5, 1, 25)
        LIP.fire(43, t, 1)                                -- arm
        LIP.fire(43, t, 2, 0, part.Position, power)       -- throw (aimMode 0 = raycast)
    end

    -- C4 (op44) — detona el C4 (busca el tool por nombre)
    function Niche.detonateC4()
        local c4 = findTool("c4")
        if c4 then LIP.fire(44, c4) end
    end

    -- ARREST (op57) — esposa al enemigo más cercano (necesita Handcuffs; ideal Police)
    local lastArrest = 0
    function Niche.arrest(opts)
        local now = os.clock()
        if now - lastArrest < (opts.rate or 1.0) then return end
        local cuffs = findTool("cuff") or findTool("handcuff")
        if not cuffs then return end
        local tgt = Target.nearestEnemy({ range = opts.range or 30, teamCheck = opts.teamCheck, friendCheck = opts.friendCheck })
        if not tgt then return end
        lastArrest = now
        LIP.fire(57, cuffs, tgt)
    end

    return Niche
end
