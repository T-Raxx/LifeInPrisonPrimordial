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

    -- ── GST por disparo = TIEMPO REAL (time()) ──
    -- PROBADO EN VIVO (M60, muzzle correcto): 50 disparos/s con GST REAL = 0 unequip. Forjar el timestamp
    -- (reloj virtual) lo INVALIDA → el server valida que el GST decodifique a un time() real/reciente y te
    -- quita el arma si no. NO forjar. El server tampoco rate-limita por tiempo real (50/s pasó limpio) ni
    -- gatea munición estricto (40 disparos > mag SIN recargar = 0 unequip). Solo hay que mandar GST REAL fresco.
    local function nextGST() LIP._gstReal = os.clock(); return GST() end
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

    -- RELOAD con TIMING REAL (manual, botón/keybind). op42 MagDrop → esperar ReloadTime → op40(mag, GST()).
    -- El server valida la duración del reload por el timestamp del GST del op40 (el juego manda el op40
    -- SOLO tras animLen); un reload INSTANTÁNEO (op42→op40 mismo frame) = duración 0 = inválido = UNEQUIP.
    -- Por eso el reload NO es instantáneo. La munición no se gatea estricto (probado), así que el reload es
    -- opcional; existe por si algún arma sí la valida, o para resincronizar el cargador visual del juego.
    function Weapon.reload()
        if LIP.reloading then return end
        local tool = firearm(); if not tool then return end
        local mag = magSize()
        local rt  = O("ReloadTime") or 1.2
        LIP.reloading = true
        LIP._selfReload = true               -- Net NO captura magammo de nuestros op40
        LIP._lastReloadReal = os.clock()
        task.spawn(function()
            if T("ShotgunReload") then
                -- ESCOPETA: op40 por bala, espaciado rt/mag (protocolo per-shell)
                for i = 1, mag do
                    local t2 = firearm() or tool
                    pcall(function() LIP.fire(40, t2, i, GST()) end)
                    task.wait(rt / mag)
                end
            else
                -- CARGADOR: MagDrop → esperar la duración REAL de la anim → OnReload(mag)
                pcall(function() LIP.fire(42, tool) end)
                task.wait(rt)
                local t2 = firearm() or tool
                pcall(function() LIP.fire(40, t2, mag, GST()) end)
            end
            LIP._selfReload = false; LIP.shotsFired = 0; LIP.reloading = false
        end)
    end
    Weapon.instantReload = Weapon.reload   -- alias UI (botón "Force Reload")

    -- construye el bullet {origin, muzzle, hitPos, hitPart, hitPart.Position, objspace}
    -- origin: si el server te ve en otra pos (desync spoofOn O connection weld connRep), el origin debe ser
    -- esa pos FALSA (spoofFakePos) → origin→hitPos consistente con dónde te ve el server. Si no, disparar
    -- desde la pos real mientras el server te ve en el weld = mismatch = rechazado/unequip. (rival = weld
    -- bajo el target + fire: el origin va del weld). Sin spoof/weld → head real.
    local function buildBullet(hitPart, hitPos)
        local c = char(); local head = c and c:FindFirstChild("Head")
        if not head then return nil end
        local origin = ((LIP.spoofOn or LIP.connRep) and LIP.spoofFakePos)
                       and (LIP.spoofFakePos + Vector3.new(0, 1.5, 0)) or head.Position
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

    -- AUTO/RAPID tick (main Heartbeat). Stream de op14 (GST real) CAPEADO al firerate del arma → exceder
    -- el firerate = el server te quita la tool (probado: M9 a 50/s = unequip; M60 = OK porque su firerate
    -- es alto). El DPS extra NO sale de disparar más rápido (rate-limited) sino del BULLET MULTIPLIER (el
    -- Net hook padea el array a N pellets → N× daño por disparo legal). Auto-reload con timing real al
    -- agotar el cargador (op42→wait→op40). observedFirerate se aprende de tus disparos manuales (Net).
    local lastTick = 0
    function Weapon.tickAuto()
        local autoOn  = T("AutoFire") and T("TargetStrafe")   -- autofire SOLO con target strafe activo
        local rapidOn = T("RapidFire") and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if not (autoOn or rapidOn) then LIP.fireAccum = 0; lastTick = 0; return end
        local now = os.clock()
        if LIP.reloading then LIP.fireAccum = 0; lastTick = now; return end
        -- RANGO (solo autofire al target): no firar fuera de rango. ref = pos que ve el server.
        if autoOn and LIP.cachedHitPos then
            local h = char() and char():FindFirstChild("Head")
            local ref = (LIP.wallbang and LIP.cachedOrigin) or (LIP.spoofOn and LIP.spoofFakePos)
                        or (LIP.connRep and LIP.spoofFakePos) or (h and h.Position)
            if ref and (LIP.cachedHitPos - ref).Magnitude > (O("FireRange") or 200) then
                LIP.fireAccum = 0; lastTick = now; return
            end
        end
        -- AUTO-RELOAD al agotar el cargador (timing real, no instantáneo). Solo en AutoFire; con mouse1 el
        -- juego recarga su propia munición.
        if autoOn and T("AutoReload") ~= false and (LIP.shotsFired or 0) >= magSize() then
            Weapon.reload(); LIP.fireAccum = 0; lastTick = now; return
        end
        -- CAP al firerate REAL del arma (exceder = unequip). observedFirerate = seg/disparo (de tus disparos
        -- manuales); sin calibrar = cap conservador 9/s. El multiplier compensa el rate bajo con más pellets.
        local userRate = math.clamp(O("AutoFireRate") or 12, 1, 120)
        local capRate  = LIP.observedFirerate and (1 / LIP.observedFirerate) or 9
        local rate = math.min(userRate, capRate)
        local dt = (lastTick > 0) and math.min(now - lastTick, 0.1) or 0
        lastTick = now
        LIP.fireAccum = (LIP.fireAccum or 0) + dt * rate
        local budget = 0
        while LIP.fireAccum >= 1 and budget < 4 do
            LIP.fireAccum = LIP.fireAccum - 1; budget = budget + 1
            fireOne(LIP.cachedHitPart, LIP.cachedHitPos, nextGST())   -- 1 bala; el hook la multiplica a N
        end
    end

    -- respawn: resetea el contador (el arma nueva viene con el cargador lleno)
    LP.CharacterAdded:Connect(function() LIP.shotsFired = 0; LIP.reloading = false end)

    -- ── DIAGNÓSTICO DE UNEQUIP (solo si WeaponDebug ON) ──────────────────────────
    -- Loguea el estado cuando el server te quita el arma disparando (shots/mag, dest, reload). Off por
    -- defecto para no ensuciar consola; encender con getgenv().LIP.weaponDebug = true.
    local function watchChar(c)
        if not c then return end
        c.ChildRemoved:Connect(function(ch)
            if not (ch:IsA("Tool") and LIP.weaponDebug) then return end
            local firedRecently = LIP._gstReal and (os.clock() - LIP._gstReal) < 1
            if not firedRecently then return end
            task.defer(function()
                local dest = (ch.Parent and ch.Parent.Name) or "nil/destroyed"
                warn(string.format("[LIP][UNEQUIP] arma=%s dest=%s shots=%s/%s reloading=%s sinceReload=%.2fs sinceFire=%.3fs",
                    ch.Name, dest, tostring(LIP.shotsFired), tostring(magSize()), tostring(LIP.reloading),
                    os.clock() - (LIP._lastReloadReal or 0), os.clock() - (LIP._gstReal or 0)))
            end)
        end)
    end
    LP.CharacterAdded:Connect(watchChar)
    watchChar(LP.Character)

    return Weapon
end
