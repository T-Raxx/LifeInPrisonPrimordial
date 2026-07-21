-- Combat/Weapon.lua — FACTORY. Auto/Rapid fire (op14) con GST FORJADO.
-- CAUSA REAL del unequip (re-reverse v48 + evidencia de cheater rival 100/s):
--   · El server NO rate-limita por tiempo real, NO gatea por munición (se comprobó: 100 disparos/s
--     con cualquier arma en flujo constante, sin recargar, sin unequip).
--   · El GST = obfuscate(time()) del cliente, SIN nonce/secuencia, y acepta CUALQUIER argumento
--     (u3669 = function(t) return u4162(t or time()) end). El server decodifica el timestamp del GST
--     y valida el DELTA entre disparos consecutivos ≥ firerate. Mandar GST(time()) REAL a 100/s =
--     deltas < firerate = UNEQUIP.
-- FIX (como el rival): forjar el GST con un RELOJ VIRTUAL que avanza por el firerate del arma en cada
--   disparo → el server ve espaciado legal aunque disparemos 100/s reales → sin unequip, cualquier arma.
--   Sin gate de munición (el server no la valida). Reload sigue disponible (botón/keybind) por si acaso.
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

    -- ── GST FORJADO (reloj virtual) ──
    -- El server valida el DELTA entre timestamps GST consecutivos ≥ firerate. Mantenemos un reloj
    -- virtual que avanza por `fakeInt` (firerate legal del arma) en CADA disparo, sin importar cuán
    -- rápido disparemos de verdad → el server ve espaciado legal siempre. Se re-sincroniza a time()
    -- cuando arranca un stream nuevo (tras idle) para no mandar timestamps del pasado.
    local function fakeInterval()
        -- firerate real observado (de tus disparos manuales) o el slider; nunca menos que el mínimo legal
        return LIP.observedFirerate or O("FakeFirerate") or 0.11
    end
    local function nextGST(now)
        -- resync al arrancar stream (idle > 0.25s) → el reloj parte de "ahora" real
        if not LIP.gstClock or (now - (LIP._gstReal or 0)) > 0.25 then LIP.gstClock = time() end
        local g = GST(LIP.gstClock)
        LIP.gstClock = LIP.gstClock + fakeInterval()   -- avanza SIEMPRE el intervalo legal
        LIP._gstReal = now
        return g
    end
    Weapon.nextGST = nextGST

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
    local function fireOne(hitPart, hitPos, gst)
        local tool = firearm(); if not tool then return false end
        local bullet = buildBullet(hitPart, hitPos)
        if not bullet then return false end
        LIP._selfFiring = true
        LIP.fire(14, tool, { bullet }, gst or GST())
        LIP._selfFiring = false
        LIP.shotsFired = (LIP.shotsFired or 0) + 1
        return true
    end

    -- AUTO/RAPID tick (main Heartbeat). Stream de op14 con GST FORJADO (reloj virtual = espaciado
    -- legal) → dispara a `Fire Rate` disparos/s REALES (hasta 120) sin que el server te quite la tool.
    -- Acumulador desacoplado del Heartbeat (fires-per-frame) → alcanza >60/s aunque el HB corra a 60fps.
    -- Sin gate de munición (el server no la valida; reload sigue en botón/keybind por si el arma lo pide).
    local lastTick = 0
    function Weapon.tickAuto()
        local autoOn  = T("AutoFire") and T("TargetStrafe")   -- autofire SOLO con target strafe activo
        local rapidOn = T("RapidFire") and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if not (autoOn or rapidOn) then LIP.fireAccum = 0; lastTick = 0; return end
        if LIP.reloading then return end
        local now = os.clock()
        -- RANGO (solo autofire al target): no firar fuera de rango. ref = pos que ve el server.
        if autoOn and LIP.cachedHitPos then
            local h = char() and char():FindFirstChild("Head")
            local ref = (LIP.wallbang and LIP.cachedOrigin) or (LIP.spoofOn and LIP.spoofFakePos)
                        or (LIP.connRep and LIP.spoofFakePos) or (h and h.Position)
            if ref and (LIP.cachedHitPos - ref).Magnitude > (O("FireRange") or 200) then
                LIP.fireAccum = 0; lastTick = now; return
            end
        end
        -- acumulador: rate = disparos/s REALES (desacoplado del framerate)
        local rate = math.clamp(O("AutoFireRate") or 30, 1, 120)
        local dt = (lastTick > 0) and math.min(now - lastTick, 0.1) or 0
        lastTick = now
        LIP.fireAccum = (LIP.fireAccum or 0) + dt * rate
        local budget = 0
        while LIP.fireAccum >= 1 and budget < 8 do   -- cap 8 disparos/frame (anti-lag)
            LIP.fireAccum = LIP.fireAccum - 1; budget = budget + 1
            fireOne(LIP.cachedHitPart, LIP.cachedHitPos, nextGST(now))   -- GST FORJADO
        end
    end

    -- respawn: resetea el contador (el arma nueva viene con el cargador lleno)
    LP.CharacterAdded:Connect(function() LIP.shotsFired = 0; LIP.reloading = false end)

    return Weapon
end
