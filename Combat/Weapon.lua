-- Combat/Weapon.lua — FACTORY. Instant reload (op40) + rapid fire (burst op14).
-- GST(): el 3er arg de shoot/reload NO es nil en runtime — es un token real derivado de time()
-- (el stub v56.GST se sobrescribe con u3669 en el init). Reimplementación exacta (agent reverse).
-- El gate de firerate y el delay de reload son 100% CLIENTE → firar op14/op40 directo los saltea.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Weapon = {}

    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function char() return LP.Character end
    local function firearm()
        local c = char(); if not c then return nil end
        return c:FindFirstChildOfClass("Tool")
    end

    -- ── GST(): token {int,int,int} de time() (reimpl exacta del builder u4162) ──
    local bnot, band, bor = bit32.bnot, bit32.band, bit32.bor
    local lsh, rsh = bit32.lshift, bit32.rshift
    local function GST(t)
        t = t or time()
        local b = buffer.create(8); buffer.writef64(b, 0, t)
        local r = buffer.readu8
        local b0, b1, b2, b3 = r(b, 0), r(b, 1), r(b, 2), r(b, 3)
        local b4, b5, b6, b7 = r(b, 4), r(b, 5), r(b, 6), r(b, 7)
        local x2  = bor(lsh(band(b2, 51), 2),  rsh(band(b2, 204), 2))
        local x3  = bor(rsh(band(b3, 240), 4), lsh(band(b3, 15), 4))
        local x4  = bor(rsh(band(b4, 240), 4), lsh(band(b4, 15), 4))
        local x4b = bor(rsh(band(x4, 204), 2), lsh(band(x4, 51), 2))
        local x4c = bor(rsh(band(x4b, 170), 1), lsh(band(x4b, 85), 1))
        local y7  = bor(rsh(band(b7, 240), 4), lsh(band(b7, 15), 4))
        local y7b = bor(rsh(band(y7, 204), 2), lsh(band(y7, 51), 2))
        local y7c = bor(rsh(band(y7b, 170), 1), lsh(band(y7b, 85), 1))
        local w1 = bor(band(255, bnot(b1)), lsh(band(255, bnot(b6)), 8), lsh(band(255, bnot(b0)), 16), lsh(x3, 24))
        local w2 = bor(y7c, lsh(band(255, bnot(b5)), 8), lsh(x2, 16), lsh(x4c, 24))
        return { w1, w2, bnot(bor(lsh(w1, 8), rsh(w2, 16))) }
    end
    Weapon.GST = GST

    -- ── INSTANT RELOAD (op40): OnReload(Tool, ammoValue, GST()) ──
    -- ammoValue = magammo absoluto (caso común, arma reserva infinita). Configurable por si el arma
    -- usa ammocategory (ahí sería delta). Saltea la animación de reload (100% cliente).
    function Weapon.instantReload()
        local tool = firearm(); if not tool then return end
        local mag = O("ReloadAmmo") or 30
        pcall(function() LIP.fire(40, tool, mag, GST()) end)
    end

    -- ── RAPID FIRE: burst de op14 al target cacheado por silent aim (o forward raycast) ──
    -- bullet = {origin(head), muzzle, hitPos, hitPart, hitPart.Position, objspace}. GST fresco por bala.
    local function buildBullet(hitPart, hitPos)
        local c = char(); local head = c and c:FindFirstChild("Head")
        if not head then return nil end
        local origin = head.Position
        local tool = firearm()
        local handle = tool and tool:FindFirstChild("Handle")
        local muzzleAtt = handle and handle:FindFirstChild("Muzzle")
        local muzzle = (muzzleAtt and muzzleAtt.WorldPosition) or origin
        if hitPart then
            return { origin, muzzle, hitPos, hitPart, hitPart.Position, hitPart.CFrame:PointToObjectSpace(hitPos) }
        end
        -- sin target: forward raycast desde cámara
        local cam = Workspace.CurrentCamera
        local dir = cam.CFrame.LookVector * 300
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { c }
        local res = Workspace:Raycast(cam.CFrame.Position, dir, rp)
        if res then
            local inst = res.Instance
            return { origin, muzzle, res.Position, inst, inst.Position, inst.CFrame:PointToObjectSpace(res.Position) }
        end
        return { origin, muzzle, cam.CFrame.Position + dir, nil, nil, nil }
    end

    -- dispara una ráfaga (N balas) al target de silent aim si existe. Cada op14 con GST fresco.
    function Weapon.rapidBurst()
        local tool = firearm(); if not tool then return end
        local n = math.floor(O("RapidCount") or 3)
        local hitPart = LIP.cachedHitPart      -- lo setea el driver (silent aim precache)
        local hitPos  = LIP.cachedHitPos
        for _ = 1, n do
            local bullet = buildBullet(hitPart, hitPos)
            if bullet then LIP.fire(14, tool, { bullet }, GST()) end
        end
    end

    return Weapon
end
