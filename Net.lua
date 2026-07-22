-- Net.lua — FACTORY. UN solo __namecall hook unificado (regla LiP: 1 hook, no apilar).
-- Passive, PRECACHE model: el driver (main) computa afuera del hook los targets; el hook
-- SOLO escribe arrays (cero reentrancy → no rompe la secuencia síncrona del disparo).
--
-- Firmas (v48, RemoteEvent multiplexado netevgen, opcode=arg1):
--   op14 FirearmBullets: FireServer(14, Tool, bullets, GST)   bullets[i]={org,muz,hitPos,hitPart,partPos,objspace}
--   op16 OnMeleeRemote : FireServer(16, Tool, GST, hitPart, objspace)
-- GST() lo genera el cliente (stub/token) → lo dejamos intacto, solo redirigimos el HIT.
-- Reload-safe: hook instalado UNA vez (flag getgenv), lee getgenv().LIP dinámico.
return function(require, LIP, Lib)
    local Net = {}
    local getncm  = getnamecallmethod
    local newcc   = newcclosure or function(f) return f end
    local hookmm  = hookmetamethod
    local unpackf = table.unpack or unpack
    local ZERO    = Vector3.zero

    function Net.install()
        LIP.RE = LIP.RE or (LIP.Events and LIP.Events:FindFirstChild("RemoteEvent"))
        if getgenv().__LIP_HOOK then return end
        local orig
        local ok = pcall(function()
            orig = hookmm(game, "__namecall", newcc(function(self, ...)
                local D = getgenv().LIP
                if D and self == D.RE and getncm() == "FireServer" then
                    local p = table.pack(...)
                    local op = p[1]
                    -- marca del último disparo (juego O nuestro) → HitEffects correlaciona con la pérdida
                    -- de vida del enemigo para detectar hits/kills.
                    if op == 14 then D.lastShotT = os.clock() end
                    -- OBSERVA FIRERATE REAL (op14 del juego, no nuestro autofire) → no sobre-disparar.
                    -- (El conteo de balas para el reload vive en Weapon.fireOne, NO acá: este hook
                    --  persiste entre reloads y no se puede actualizar sin rejoin limpio.)
                    if op == 14 and not D._selfFiring then
                        local now = os.clock()
                        if D._lastRealShot then
                            local dt = now - D._lastRealShot
                            if dt > 0.02 and dt < 2 then D.observedFirerate = dt end
                        end
                        D._lastRealShot = now
                    end
                    -- DETECCIÓN de cargador + TIEMPO DE RELOAD del juego (op42 MagDrop → op40 OnReload):
                    -- el delta = la duración real de la anim de recarga → la usamos para que nuestro auto-reload
                    -- matchee (op40 muy temprano/tarde = server rechaza = munición no se rellena = balas rojas).
                    if op == 42 and not D._selfReload then D._magDropT = os.clock() end
                    if op == 40 and not D._selfReload then
                        local mag, wtool = p[3], p[2]
                        if type(mag) == "number" and mag >= 2 and mag <= 200 and typeof(wtool) == "Instance" then
                            D.magByWeapon = D.magByWeapon or {}
                            D.magByWeapon[wtool.Name] = mag
                        end
                        if D._magDropT then
                            local rt = os.clock() - D._magDropT
                            if rt > 0.3 and rt < 6 then D.observedReloadTime = rt end
                            D._magDropT = nil
                        end
                    end
                    -- op14: SILENT AIM (redirige al target) + BULLET MULTIPLIER (padea el array a N pellets).
                    -- Se aplica al op14 del JUEGO (mouse1) y al nuestro → N× daño por disparo LEGAL (mismo
                    -- GST/firerate/timing del juego = sin rate-limit, sin unequip). Escopetas: suma pellets.
                    if op == 14 then
                        local bullets = p[3]
                        local mult = D.bulletMult or 1
                        local swap = D.swapOn and D.cachedHitPart and D.cachedHitPos
                        if type(bullets) == "table" and (swap or mult > 1) then
                            -- 1) redirige los existentes al target (silent aim)
                            if swap then
                                for i = 1, #bullets do
                                    local b = bullets[i]
                                    if type(b) == "table" then
                                        b[3] = D.cachedHitPos; b[4] = D.cachedHitPart; b[5] = D.cachedHitPos; b[6] = ZERO
                                        if D.wallbang and D.cachedOrigin then b[1] = D.cachedOrigin; b[2] = D.cachedOrigin end
                                    end
                                end
                            end
                            -- 2) MULTIPLICADOR: clona el array hasta #bullets*mult (cada clon = bala nueva)
                            local base = #bullets
                            if mult > 1 and base > 0 then
                                for k = 1, base * (mult - 1) do
                                    local s = bullets[((k - 1) % base) + 1]
                                    if type(s) == "table" then
                                        bullets[base + k] = { s[1], s[2], s[3], s[4], s[5], s[6] }
                                    end
                                end
                            end
                            return orig(self, unpackf(p, 1, p.n))
                        end
                    -- MELEE AURA (op16): redirige el hitPart al target de melee cacheado
                    elseif op == 16 and D.meleeOn and D.meleePart then
                        p[4] = D.meleePart                   -- hitPart
                        p[5] = ZERO                          -- objspace (centro)
                        return orig(self, unpackf(p, 1, p.n))
                    -- TURRET silent aim (op56, fase 2 = fire): swap el hit-table al target (mismo formato)
                    elseif op == 56 and p[3] == 2 and D.swapOn and D.cachedHitPart and D.cachedHitPos then
                        local hits = p[4]
                        if type(hits) == "table" then
                            for i = 1, #hits do
                                local hh = hits[i]
                                if type(hh) == "table" then
                                    hh[3] = D.cachedHitPos; hh[4] = D.cachedHitPart; hh[5] = D.cachedHitPos; hh[6] = ZERO
                                end
                            end
                            return orig(self, unpackf(p, 1, p.n))
                        end
                    end
                end
                return orig(self, ...)                        -- passthrough transparente
            end))
        end)
        if ok then
            getgenv().__LIP_HOOK = true
            getgenv().__LIP_ORIG_NAMECALL = orig
        end
    end

    return Net
end
