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
                    -- OBSERVA FIRERATE REAL (op14 que NO disparó nuestro autofire) → no sobre-disparar
                    if op == 14 and not D._selfFiring then
                        local now = os.clock()
                        if D._lastRealShot then
                            local dt = now - D._lastRealShot
                            if dt > 0.02 and dt < 2 then D.observedFirerate = dt end
                        end
                        D._lastRealShot = now
                    end
                    -- SILENT AIM (op14): redirige cada bullet al target cacheado (Head)
                    if op == 14 and D.swapOn and D.cachedHitPart and D.cachedHitPos then
                        local bullets = p[3]
                        if type(bullets) == "table" then
                            for i = 1, #bullets do
                                local b = bullets[i]
                                if type(b) == "table" then
                                    b[3] = D.cachedHitPos    -- hitPos
                                    b[4] = D.cachedHitPart   -- hitPart
                                    b[5] = D.cachedHitPos    -- partPos
                                    b[6] = ZERO              -- objspace (centro)
                                    -- WALLBANG: mueve el origin al lado del target de la pared (LOS clara)
                                    if D.wallbang and D.cachedOrigin then
                                        b[1] = D.cachedOrigin
                                        b[2] = D.cachedOrigin
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
