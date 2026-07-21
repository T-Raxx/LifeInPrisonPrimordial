-- Combat/Weapon.lua — FACTORY. Auto/Rapid fire (op14) + reload seguro.
-- CAUSA del unequip (reverse): el server trackea el cargador y valida cadencia via el token GST.
--   · Mandar más op14 que balas del cargador → disparos sin munición → UNEQUIP.
--   · op40 instantáneo (reload sin esperar la animación / sin MagDrop) → recarga imposible → UNEQUIP.
--   · Firar bajo firerate → el token GST(time()) delata el spacing → UNEQUIP.
-- FIX: contador de balas local (Mag Size) + fire a rate configurable ≥ firerate del arma; reload
-- via `shared.ReloadCallback()` (el reload legítimo del juego, expuesto L247297, SIN riesgo de unequip).
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local Workspace  = game:GetService("Workspace")
    local UIS        = game:GetService("UserInputService")
    local LP = Players.LocalPlayer
    local Weapon = {}

    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end
    local function char() return LP.Character end
    local function firearm() local c = char(); return c and c:FindFirstChildOfClass("Tool") end  -- equipado (== u3379.Tool)

    -- ── GST(): token {int,int,int} de time() (reimpl exacta de u4162) ──
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

    -- DETECCIÓN DE CARGADOR POR ARMA: el Net hook captura `magammo` del op40 del reload REAL del juego
    -- (arg2), keyed por nombre de arma → LIP.magByWeapon[name]. Se aprende al recargar 1 vez (R o auto
    -- del juego). Fallback = slider Mag Size mientras no se detecte.
    local function magSize()
        local tool = firearm()
        local name = tool and tool.Name
        if name and LIP.magByWeapon and LIP.magByWeapon[name] then return LIP.magByWeapon[name] end
        return math.floor(O("ReloadAmmo") or 15)
    end
    Weapon.magSize = magSize

    -- RELOAD INTELIGENTE. El cliente cree que el mag está lleno (nuestros op14 no bajan su ammo local),
    -- así que shared.ReloadCallback NO recarga (chequea `if ammo==magammo then return`). Forzamos el
    -- reload directo con el flujo legítimo: op42 MagDrop → esperar la duración de la anim (evita el
    -- unequip por reload-imposible) → op40 OnReload(magSize). El server rellena su cargador.
    function Weapon.reload()
        if LIP.reloading then return end
        local tool = firearm(); if not tool then return end
        LIP.reloading = true
        task.spawn(function()
            local mag = magSize()
            LIP._selfReload = true   -- Net NO captura magammo de nuestros op40 (solo del reload del juego)
            if T("ShotgunReload") then
                -- ESCOPETA: op40 por bala (ammo acumulado), sin MagDrop, espaciado (protocolo per-shell)
                task.wait(0.3)
                for i = 1, mag do
                    local t2 = firearm() or tool
                    pcall(function() LIP.fire(40, t2, i, GST()) end)
                    task.wait((O("ReloadTime") or 1.2) / mag)
                end
            else
                -- CARGADOR normal: MagDrop → esperar anim → OnReload(magammo) absoluto
                pcall(function() LIP.fire(42, tool) end)
                task.wait(O("ReloadTime") or 1.2)                         -- ~duración anim (server valida)
                local t2 = firearm() or tool
                pcall(function() LIP.fire(40, t2, mag, GST()) end)
            end
            LIP._selfReload = false
            LIP.shotsFired = 0
            task.wait(0.1)
            LIP.reloading = false
        end)
    end
    Weapon.instantReload = Weapon.reload   -- alias UI (botón "Force Reload" = fuerza el reload)

    -- construye el bullet {origin, muzzle, hitPos, hitPart, hitPart.Position, objspace}
    -- origin: si estás pos-spoofeado, usar la pos FALSA (server-seen) → origin→hitPos corto y
    -- consistente con dónde te ve el server (si no, disparar lejos con spoof = rechazado/out-of-range).
    local function buildBullet(hitPart, hitPos)
        local c = char(); local head = c and c:FindFirstChild("Head")
        if not head then return nil end
        local origin = (LIP.spoofOn and LIP.spoofFakePos) and (LIP.spoofFakePos + Vector3.new(0, 1.5, 0)) or head.Position
        if LIP.wallbang and LIP.cachedOrigin then origin = LIP.cachedOrigin end   -- wallbang: origin con LOS
        local tool = firearm()
        local handle = tool and tool:FindFirstChild("Handle")
        local muzzleAtt = handle and handle:FindFirstChild("Muzzle")
        local muzzle = (muzzleAtt and muzzleAtt.WorldPosition) or origin
        if hitPart then
            local center = hitPart.Position   -- CENTRO exacto + objspace ZERO = HBE-safe (dentro del hitbox)
            return { origin, muzzle, center, hitPart, center, Vector3.zero }
        end
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

    -- dispara 1 bala op14 al hit dado (con GST fresco). Descuenta ammo. Marca _selfFiring para que
    -- el observador de firerate en Net NO cuente nuestros disparos.
    local function fireOne(hitPart, hitPos)
        local tool = firearm(); if not tool then return false end
        local bullet = buildBullet(hitPart, hitPos)
        if not bullet then return false end
        LIP._selfFiring = true
        LIP.fire(14, tool, { bullet }, GST())
        LIP._selfFiring = false
        LIP.shotsFired = (LIP.shotsFired or 0) + 1   -- cuenta acá (fireOne, siempre fresco)
        return true
    end

    -- AUTO/RAPID tick (main Heartbeat): fire al target de silent aim, tracking ammo + reload.
    -- NUNCA más rápido que el firerate REAL del arma (observado en Net) → evita el unequip por cadencia
    -- (armas rápidas: el firerate observado ya es bajo, así que no lo excedemos).
    local lastFire = 0
    function Weapon.tickAuto()
        local autoOn  = T("AutoFire") and T("TargetStrafe")   -- autofire SOLO con target strafe activo
        local rapidOn = T("RapidFire") and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if not (autoOn or rapidOn) then return end
        if LIP.reloading then return end
        -- cargador del SERVER vacío (contamos op14 en Net) → reload inteligente
        if (LIP.shotsFired or 0) >= magSize() then Weapon.reload(); return end
        local now = os.clock()
        -- dispara al rate del slider; si conocemos el firerate REAL del arma (observado de tus disparos
        -- manuales en el Net hook), lo usamos como CAP (no firar más rápido = no unequip). Sin calibrar
        -- = rate del slider directo.
        local slider = O("AutoFireRate") or 0.15
        local minInt = LIP.observedFirerate and math.max(slider, LIP.observedFirerate * 1.02) or slider
        if now - lastFire < minInt then return end
        -- guard de RANGO: no firar si el target está fuera de rango (server rechaza = bala perdida)
        if LIP.cachedHitPos then
            local h = char() and char():FindFirstChild("Head")
            local ref = (LIP.wallbang and LIP.cachedOrigin) or (h and h.Position)
            if ref and (LIP.cachedHitPos - ref).Magnitude > (O("FireRange") or 200) then return end
        end
        if fireOne(LIP.cachedHitPart, LIP.cachedHitPos) then lastFire = now end
    end

    -- respawn: resetea el contador (el arma nueva viene con el cargador lleno)
    LP.CharacterAdded:Connect(function() LIP.shotsFired = 0; LIP.reloading = false end)

    return Weapon
end
