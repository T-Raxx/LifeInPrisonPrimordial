-- Combat/Strafe.lua — FACTORY. Target Strafe (desync HvH) + manual target/spectator + spam resolver.
-- Usa Combat/Spoof (desync por __index hook): el server te ve orbitando, tu cuerpo/cámara NO se mueven.
-- Target manual persiste por UserId (sobrevive muerte/rejoin de ambos; se limpia solo manualmente).
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Spoof = require("Combat.Spoof")
    local Strafe = {}

    local function myRoot() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end

    ------------------------------------------------------------------ MANUAL TARGET / SPECTATOR
    -- LIP.manualUID = UserId elegido a mano (persiste). nil = auto (silent aim / cercano).
    function Strafe.setManual(plr) LIP.manualUID = plr and plr.UserId or nil end
    function Strafe.clearManual() LIP.manualUID = nil end
    -- elige como target manual al enemigo más cercano a la MIRA (bind "Set Target")
    function Strafe.pickCrosshair()
        local cam = Workspace.CurrentCamera
        local best, bestD = nil, 1e9
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local c = plr.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local sp, on = cam:WorldToViewportPoint(hrp.Position)
                    if on and sp.Z > 0 then
                        local d = (Vector2.new(sp.X, sp.Y) - Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)).Magnitude
                        if d < bestD then best, bestD = plr, d end
                    end
                end
            end
        end
        if best then LIP.manualUID = best.UserId; if LIP.Library and LIP.Library.Notify then LIP.Library:Notify({ Title = "Target", Description = "Locked: " .. best.Name, Time = 3 }) end end
    end
    function Strafe.manualPlayer()
        if not LIP.manualUID then return nil end
        for _, p in ipairs(Players:GetPlayers()) do if p.UserId == LIP.manualUID then return p end end
        return nil   -- aún no reapareció; se re-resuelve cuando vuelva
    end
    function Strafe.spectate(cam)
        local t = Strafe.manualPlayer()
        local hum = t and t.Character and t.Character:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() cam.CameraSubject = hum end) end
    end

    ------------------------------------------------------------------ SPAM RESOLVER (métodos + pesos)
    local hist = {}   -- [player] = { s = {V3...}, t = {clock...} }
    local beh  = {}   -- [player] = { voidFrac, flipRate, prevVoid } — EMA de comportamiento (Auto-método)
    local MAX = 120   -- ~3s a ~40Hz (ventana del Density)
    local function sample(plr, pos, now)
        local h = hist[plr]; if not h then h = { s = {}, t = {} }; hist[plr] = h end
        -- SIN reject-vel: el clustering + void-manhattan rechazan basura; el pre-filtro tapaba TPs reales.
        h.s[#h.s + 1] = pos; h.t[#h.t + 1] = now
        if #h.s > (Strafe.CONF.histMax or MAX) then table.remove(h.s, 1); table.remove(h.t, 1) end
        -- comportamiento (Auto-método): fracción de muestras en void + tasa de flips real↔void
        local b = beh[plr]; if not b then b = { voidFrac = 0, flipRate = 0, prevVoid = false }; beh[plr] = b end
        local isVoid = (math.abs(pos.X) + math.abs(pos.Z)) >= 7000
        b.voidFrac = b.voidFrac + 0.15 * ((isVoid and 1 or 0) - b.voidFrac)
        b.flipRate = b.flipRate + 0.15 * (((isVoid ~= b.prevVoid) and 1 or 0) - b.flipRate)
        b.prevVoid = isVoid
    end
    function Strafe.sampleAll(now)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local c = plr.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then sample(plr, hrp.Position, now) end
            end
        end
    end
    -- velocidad instantánea del target (últimas 2 muestras) — para predicción/chase
    function Strafe.targetVel(plr)
        local h = hist[plr]; local n = h and #h.s or 0
        if n < 2 then return Vector3.zero end
        local dt = math.max(h.t[n] - h.t[n-1], 1/240)
        return (h.s[n] - h.s[n-1]) / dt
    end
    -- CONFIANZA del resolver (0.000–1.000) para el HUD. Mide qué tan PREDECIBLE se mueve el target: residual
    -- promedio de las muestras respecto al modelo lineal (última pos − vel·edad). Residual chico = movimiento
    -- limpio/consistente = alto (1.000 = full resuelto, tiro seguro). Residual grande = jitter/teleport/spoof
    -- = bajo (0.000 = tiro difícil, resolver profundo). Pocas muestras = confianza parcial (aún calibrando).
    function Strafe.confidence(plr)
        local h = hist[plr]; local n = h and #h.s or 0
        if n < 4 then return math.clamp(n / 4 * 0.5, 0, 0.5) end
        local k = math.min(n, 8)
        local vel = Strafe.targetVel(plr)
        local base, tN = h.s[n], h.t[n]
        local resid, cnt = 0, 0
        for i = n - k + 1, n - 1 do
            local pred = base - vel * (tN - h.t[i])     -- dónde DEBERÍA estar si se moviera lineal
            resid = resid + (h.s[i] - pred).Magnitude
            cnt = cnt + 1
        end
        local avg = cnt > 0 and resid / cnt or 0
        return math.clamp(math.exp(-avg / 4), 0, 1)     -- ~4 studs de residual → ~0.37
    end
    -- RESOLVER CLUSTER (histograma ponderado, estilo juju/symbol v2): void spam (magnitud >=9e5) suma poco
    -- y se dispersa -> nunca clusteriza; la pos REAL se re-visita -> gana peso*count -> cruza el gate de
    -- accuracy = pos resuelta. Inmune a teleports gigantes / void spam. RP = params (tuneables por slider).
    local clusters = {}   -- [player] = { list = {...}, lastPos, lastT }
    local RP = { posWeight = 1.5, voidWeight = 0.2, forget = 80, distPenalty = 2.0, accuracy = 1.35, lerp = 0.1 }
    Strafe.RParams = RP

    -- RESOLVER DENSITY (sakura / Unnamed Enhancements): batch O(n²) sobre el log; para cada muestra cuenta
    -- vecinos dentro de un radio CHICO (studs). El void (millones de studs entre sí) nunca clusteriza; solo
    -- la pos real (jitter de pocos studs) acumula vecinos. El radio ENCOGE con la distancia = resolución far.
    Strafe.DEN = { forgiveness = 14.4, outOfVoidBonus = 13, distPenalty = 3.2, minMatches = 3, window = 3.0, voidManhattan = 7000 }
    -- CONFIANZA DE DISPARO fusionada: pesos + umbrales (todo live-tuneable). wDom+wStab+wResid = 1.0.
    Strafe.CONF = { wDom = 0.45, wStab = 0.35, wResid = 0.20, stabThresh = 25, stabK = 3, voidManhattan = 50000,
                    predMaxSpeed = 60, hcWindow = 0.35, hcRate = 0.10, hcRelax = 0.40,
                    revisitBonus = 0.30, revisitMin = 4, revisitScale = 8, backtrackWindow = 0.15, histMax = 200,
                    chaseAmp = 10, chaseFreq = 2.5, ampMin = 6, ampMax = 30, freqMin = 0.5, freqMax = 4.0,
                    adaptInterval = 1.0, adaptLrAmp = 2.0, adaptLrFreq = 0.3, leadCap = 400 }
    local function resolveDensity(plr, localPos)
        local D = Strafe.DEN
        local h = hist[plr]; local n = h and #h.s or 0
        if n < D.minMatches + 1 then return nil, false, 0 end
        local now = os.clock()
        local bestPos, bestCount = nil, D.minMatches - 1
        for i = 1, n do
            if now - h.t[i] <= D.window then
                local p1 = h.s[i]
                local inMap = (math.abs(p1.X) + math.abs(p1.Z)) < D.voidManhattan
                local forg = D.forgiveness + (inMap and D.outOfVoidBonus or 0)
                if localPos then forg = forg - ((localPos - p1).Magnitude / 100) * D.distPenalty end
                forg = math.clamp(forg, 1, 1000)
                local count, sum = 0, p1
                for j = 1, n do
                    if i ~= j and (now - h.t[j] <= D.window) and (p1 - h.s[j]).Magnitude <= forg then
                        count = count + 1; sum = sum + h.s[j]
                    end
                end
                if count >= D.minMatches and count > bestCount then
                    bestCount = count; bestPos = sum / (count + 1)   -- centroide del vecindario denso
                end
            end
        end
        local didDef = bestPos ~= nil and bestCount >= (D.minMatches + 1)
        return bestPos, didDef, bestCount
    end

    local function resolveCluster(plr, hitbox, now, localPos)
        local t = clusters[plr]; if not t then t = { list = {} }; clusters[plr] = t end
        local dist = (localPos - hitbox).Magnitude
        local distPenalty = math.clamp(1 - (dist / 100) * (RP.distPenalty * 0.01), 0.25, 1)
        local mergeR = math.clamp(200 - dist * 0.4, 80, 200)
        local rate = RP.forget / 20
        local speed = 0
        if t.lastPos and t.lastT and (now - t.lastT) > 0 then speed = (hitbox - t.lastPos).Magnitude / (now - t.lastT) end
        t.lastPos = hitbox; t.lastT = now
        -- lerp: trackea TIGHT el movimiento REAL (target caminando / agarrando armas) y SOLO aflojá para los
        -- saltos del void (magnitud gigante) o flings extremos (>150 studs/s) → sigue al walker, ignora el void.
        local lerpAmt = (hitbox.Magnitude >= 9e5 or speed > 150) and RP.lerp or math.clamp(RP.lerp * 3, RP.lerp, 0.6)
        local keep = {}
        for _, c in ipairs(t.list) do
            local dt = now - c.last
            if dt > 0 then
                local dm = (c.pos - hitbox).Magnitude > mergeR and 2.5 or 1
                c.weight = c.weight - dt * rate * dm; c.last = now
            end
            if c.weight >= 0.1 then keep[#keep + 1] = c end
        end
        t.list = keep
        local isVoid = hitbox.Magnitude >= 9e5
        local addW = (isVoid and RP.voidWeight or RP.posWeight) * distPenalty
        local merged = false
        for _, c in ipairs(t.list) do
            if (c.pos - hitbox).Magnitude <= mergeR then
                c.pos = c.pos:Lerp(hitbox, lerpAmt); c.weight = math.clamp(c.weight + addW, -1, 18); c.count = c.count + 1; c.last = now; merged = true; break
            end
        end
        if not merged then t.list[#t.list + 1] = { pos = hitbox, weight = addW, count = 1, last = now } end
        local best, bestScore = nil, 0
        for _, c in ipairs(t.list) do
            local s = c.weight * math.clamp(c.count * 0.25, 1, 3)
            if s > bestScore then bestScore = s; best = c end
        end
        -- didDefensive = el cluster ganador cruzó el gate de accuracy = pos confiable + fire-ready (harmonía juju)
        local didDefensive = (best ~= nil and bestScore > RP.accuracy)
        local score = math.clamp(bestScore / (RP.accuracy * 2), 0, 1)
        return (didDefensive and best.pos) or hitbox, didDefensive, score, #t.list, (best and best.count or 0)
    end

    -- ESTABILIDAD TEMPORAL del ganador: cuántos frames seguidos la pos resuelta no saltó (> stabThresh studs).
    -- Un ganador que salta = void-spammer bueno = nunca acumula = confianza baja. Método-agnóstico.
    local stab = {}   -- [player] = { lastPos, frames }
    local function updateStability(plr, pos)
        local C = Strafe.CONF
        local st = stab[plr]
        if not st then stab[plr] = { lastPos = pos, frames = 0 }; return 0 end
        if (pos - st.lastPos).Magnitude <= C.stabThresh then
            st.frames = math.min(st.frames + 1, C.stabK)
        else
            st.frames = 0
        end
        st.lastPos = pos
        return st.frames
    end

    -- RUTEO UNIFICADO: Cluster / Density / Auto. Llena resState[plr] (lo leen peek/info) + cachea por frame.
    local resState = {}   -- [player] = { pos, didDef, method, score, clusters, state, frameT }
    local function pickMethod(plr)
        local b = beh[plr]
        if b and b.voidFrac > 0.30 and b.voidFrac < 0.75 and b.flipRate > 0.35 then return "Density" end
        return "Cluster"
    end
    local function resolveByMethod(plr, rawPos, localPos)
        local now = os.clock()
        local rs = resState[plr]
        if rs and rs.frameT == now then return rs.pos, rs.didDef end   -- cache por frame (varios callers/tick)
        local method = O("ResolverMethod") or "Cluster"
        if method == "Auto" then method = pickMethod(plr) end
        local pos, didDef, score, cl, state
        local winCount = 0
        if method == "Density" then
            local p, dd, cnt = resolveDensity(plr, localPos)
            pos, didDef = p or rawPos, dd or false
            score = math.clamp(((cnt or 0) - Strafe.DEN.minMatches) / 8, 0, 1)
            cl = cnt or 0; winCount = cnt or 0
            state = didDef and "LOCKED" or (p and "RESOLVING" or "VOID")
        else
            local p, dd, sc, n, wc = resolveCluster(plr, rawPos, now, localPos)
            pos, didDef = p, dd
            score = sc or 0; cl = n or 0; winCount = wc or 0
            state = dd and "LOCKED" or ((cl > 0) and "RESOLVING" or "NORMAL")
        end
        local sf = updateStability(plr, pos)
        resState[plr] = { pos = pos, didDef = didDef, method = method, score = score, clusters = cl, state = state, frameT = now, stabFrames = sf, winCount = winCount }
        return pos, didDef
    end

    -- velocidad muestreada a resolver_rate (por target) — finite-diff, NO cada frame (juju resolver_rate)
    local velState = {}   -- [plr] = { lastPos, lastT, vel }
    function Strafe.resolvedVel(plr, pos, now, rate)
        local v = velState[plr]
        if not v then v = { lastPos = pos, lastT = now, vel = Vector3.zero }; velState[plr] = v; return v.vel end
        if (now - v.lastT) > (rate or 0.037) then
            v.vel = (pos - v.lastPos) / math.max(now - v.lastT, 1e-3)
            v.lastPos = pos; v.lastT = now
        end
        return v.vel or Vector3.zero
    end
    -- AIM RESOLVER (harmonía juju): pos resuelta del cluster + prediction lead + flag didDefensive.
    -- rawHitboxPos = head crudo del target. didDefensive true = confiable + autoriza el disparo.
    function Strafe.resolveAim(plr, rawHitboxPos)
        local now = os.clock()
        local r = myRoot(); local loc = r and r.Position or rawHitboxPos
        local pos, didDefensive = resolveByMethod(plr, rawHitboxPos, loc)
        -- velocidad desde la pos RESUELTA (estable, sin los saltos del void) + sanity clamp (ningún player va
        -- >200 studs/s) → el lead nunca se vuela a millones aunque el target spamee void.
        local vel = Strafe.resolvedVel(plr, pos, now, O("ResolverRate") or 0.037)
        -- CAP (no ZERO) de la magnitud del lead: un target REAL rápido (fly/vehículo a 300 studs/s) IGUAL
        -- leadea (dirección preservada, magnitud capeada). El void ya está guarded aparte (resolveByMethod da
        -- pos in-map), así que el lead nunca vuela a millones. Slider LeadCap (subir para fast movers).
        local cap = O("LeadCap") or Strafe.CONF.leadCap
        if vel.Magnitude > cap then vel = vel.Unit * cap end
        -- LEAD escalado por CONFIANZA (anti-blocker): lead = tiempo (comp ping + extra). El extra se modula por
        -- la confianza del movimiento (residual lineal): fly smooth/consistente = confianza alta = lead FULL →
        -- le pegás adelante; jittery/random = confianza baja = lead ≈ base → no over-extrapolás basura. Un solo
        -- mecanismo cubre fast-smooth Y random; el resolver SIEMPRE intenta.
        local base = O("PredictBase") or 0.10
        local amp  = O("PredictAmp")  or 0.15
        local lead = base + amp * Strafe.confidence(plr)
        pos = pos + vel * lead
        return pos, didDefensive
    end

    -- CONFIANZA DE DISPARO fusionada (0..1). La lee el gate del autofire (rate-scaling). 0 = aguanta fuego.
    -- dominancia del cluster (score) + estabilidad temporal + residual lineal; anulada a 0 si la pos cae en void.
    function Strafe.fireConfidence(plr)
        local C = Strafe.CONF
        local rs = resState[plr]
        if not rs or not rs.pos then return 0 end
        if (math.abs(rs.pos.X) + math.abs(rs.pos.Z)) >= C.voidManhattan then return 0 end
        local sDom   = rs.score or 0
        local sStab  = math.clamp((rs.stabFrames or 0) / C.stabK, 0, 1)
        local sResid = Strafe.confidence(plr)
        local base   = C.wDom * sDom + C.wStab * sStab + C.wResid * sResid
        -- BONUS por revisita: un cluster golpeado muchas veces = el ancla real del void spam → lock más rápido.
        local revisit = C.revisitBonus * math.clamp(((rs.winCount or 0) - C.revisitMin) / C.revisitScale, 0, 1)
        return math.clamp(base + revisit, 0, 1)
    end

    -- HIT-CONFIRM: acc EMA por target. HP baja & disparamos < hcWindow → hit; disparamos sin baja → miss.
    -- Atribución aproximada (otro jugador podría pegar); el EMA suaviza. Relaja el piso del gate (Weapon).
    local hc = {}   -- [plr] = { lastHP, acc }
    function Strafe.updateHitConfirm(plr, now)
        local C = Strafe.CONF
        local ch = plr and plr.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if not hum then hc[plr] = nil; return end
        local h = hc[plr]; if not h then hc[plr] = { lastHP = hum.Health, acc = 0 }; return end
        local fired = (now - (LIP.lastFireT or 0)) <= C.hcWindow
        if fired then
            local hit = (hum.Health < h.lastHP - 0.01) and 1 or 0
            h.acc = h.acc + C.hcRate * (hit - h.acc)
        end
        h.lastHP = hum.Health
    end
    function Strafe.hitAccuracy(plr)
        local h = hc[plr]; return h and h.acc or 0
    end

    -- TELEMETRÍA del resolver para el HUD: método activo + score (0-1) + estado + nº de clusters. Lee resState.
    function Strafe.resolverInfo(plr)
        local rs = resState[plr]
        if not rs then return { score = 0, state = "NORMAL", clusters = 0, method = O("ResolverMethod") or "Cluster", confidence = 0, hitAcc = Strafe.hitAccuracy(plr) } end
        return { score = rs.score or 0, state = rs.state or "NORMAL", clusters = rs.clusters or 0, method = rs.method or "Cluster", confidence = Strafe.fireConfidence(plr), hitAcc = Strafe.hitAccuracy(plr) }
    end

    -- LECTOR PURO (para el tracer): pos resuelta del método activo + lead, SIN ingestar (lee resState →
    -- no perturba el resolver). Método-agnóstico (Cluster/Density). nil si aún no resolvió.
    function Strafe.resolvedPeek(plr)
        local rs = resState[plr]; if not rs or not rs.pos then return nil end
        local pos = rs.pos
        local v = velState[plr]
        if v and v.vel then
            local vel = v.vel
            local cap = O("LeadCap") or Strafe.CONF.leadCap
            if vel.Magnitude > cap then vel = vel.Unit * cap end
            local base = O("PredictBase") or 0.10
            local amp  = O("PredictAmp")  or 0.15
            pos = pos + vel * (base + amp * Strafe.confidence(plr))
        end
        return pos
    end

    -- PIVOTE del orbit del strafe: rutea por el método activo (Cluster/Density/Auto) + lead manual opcional.
    function Strafe.resolvePos(plr, rawPos, method, samples, predictT)
        local r = myRoot(); local loc = r and r.Position or rawPos
        local p = resolveByMethod(plr, rawPos, loc)   -- descarta didDef, solo la pos para orbitar
        if predictT and predictT > 0 then p = p + Strafe.targetVel(plr) * predictT end
        return p or rawPos
    end

    ------------------------------------------------------------------ PRESETS
    Strafe.PRESETS = {
        Normal = { mode = "Normal", radius = 10,   speed = 4,  height = 0 },
        Random = { mode = "Random", radius = 10.5, speed = 20, height = 0 },
        Behind = { mode = "Behind", radius = 8,    speed = 8,  height = 0 },
        Spiral = { mode = "Spiral", radius = 12,   speed = 6,  height = 8 },
    }
    function Strafe.applyPreset(name)
        local p = Strafe.PRESETS[name]; if not p then return end
        local O2 = Lib.Options
        if O2.StrafeMode   then O2.StrafeMode:SetValue(p.mode) end
        if O2.StrafeRadius then O2.StrafeRadius:SetValue(p.radius) end
        if O2.StrafeSpeed  then O2.StrafeSpeed:SetValue(p.speed) end
        if O2.StrafeHeight then O2.StrafeHeight:SetValue(p.height) end
    end

    ------------------------------------------------------------------ DRIVER (desync)
    function Strafe.init()
        Spoof.init()   -- hook __index + restore RenderStepped (compartido con Void)
    end

    -- LCG para random (Math.random bloqueado en el executor) — usado por bait Y el modo Random XYZ
    local brng = 987654321
    local function rnd() brng = (brng * 1103515245 + 12345) % 2147483648; return brng / 2147483648 end
    local function rndS() return rnd() * 2 - 1 end   -- signed [-1,1]

    -- NOISE-PATH: camino orgánico suave alrededor de un centro. Suma de octavas de seno con fases LCG-seedeadas
    -- (Math.random bloqueado). amp = radio, freq = velocidad angular. Reemplaza el switch de modos preset.
    local NP = {}   -- 9 fases (3 ejes × 3 octavas), seedeadas una vez
    for i = 1, 9 do NP[i] = rnd() * 6.2831853 end
    function Strafe.noiseOffset(t, amp, freq)
        local function axis(o)
            return math.sin(freq * t + NP[o]) * 0.6
                 + math.sin(freq * 2.3 * t + NP[o + 1]) * 0.3
                 + math.sin(freq * 4.1 * t + NP[o + 2]) * 0.1
        end
        return Vector3.new(axis(1) * amp, axis(4) * amp * 0.5, axis(7) * amp)   -- Y media amplitud
    end

    -- ADAPTACIÓN (hill-climb): nudgea amp/freq hacia lo que MAXIMIZA tus hits (Strafe.hitAccuracy). Coordinate
    -- ascent: sigue la dirección mientras el hit-rate mejora, la reversa al empeorar. Corre en la fase STRAFE.
    local adapt = { amp = 14, freq = 1.5, dirA = 1, dirF = 1, lastAcc = 0, lastT = 0 }
    Strafe.adapt = adapt
    local function adaptStep(target)
        local C = Strafe.CONF
        local now = os.clock()
        if (now - adapt.lastT) < C.adaptInterval then return end
        adapt.lastT = now
        local acc = Strafe.hitAccuracy(target)
        if acc < adapt.lastAcc - 1e-3 then adapt.dirA = -adapt.dirA; adapt.dirF = -adapt.dirF end
        adapt.lastAcc = acc
        adapt.amp  = math.clamp(adapt.amp  + adapt.dirA * C.adaptLrAmp,  C.ampMin,  C.ampMax)
        adapt.freq = math.clamp(adapt.freq + adapt.dirF * C.adaptLrFreq, C.freqMin, C.freqMax)
    end

    local seed = 0
    -- órbita alrededor de un CENTRO, mirando al centro. Normal/Random/Behind.
    local function orbitCF(center, tLook, opts)
        if LIP.strafeNoise then
            return CFrame.lookAt(center + Strafe.noiseOffset(os.clock(), LIP.curStrafeAmp or 12, LIP.curStrafeFreq or 1.5), center)
        end
        local R, spd, h = opts.radius or 10, opts.speed or 4, opts.height or 0
        local mode = (T("AutoMode") and LIP.strafeMode) or opts.mode or "Normal"
        if mode == "Behind" then
            local look = tLook or Vector3.new(0, 0, -1)
            local goPos = center - look * R + Vector3.new(0, h, 0)
            return CFrame.lookAt(goPos, center)
        elseif mode == "Random" then
            -- RANDOM XYZ: offset random en los 3 ejes cada frame, rango = radius (slider). Sin noise.
            local goPos = center + Vector3.new(rndS() * R, h + rndS() * R, rndS() * R)
            return CFrame.new(goPos)
        elseif mode == "Spiral" then
            -- ESPIRAL 3D (HvH): órbita circular X/Z + oscilación vertical Y a mitad de frecuencia = hélice
            -- LENTA alrededor del target. La más difícil de resolver (te movés en 3 ejes suave y continuo).
            seed = seed + spd * 0.03   -- lento
            local vAmp = (math.abs(h) > 0.1) and math.abs(h) or 6
            local off = Vector3.new(math.cos(seed) * R, math.sin(seed * 0.5) * vAmp, math.sin(seed) * R)
            return CFrame.lookAt(center + off, center)
        else -- Normal: órbita circular
            seed = seed + spd * 0.05
            local off = Vector3.new(math.cos(seed) * R, h, math.sin(seed) * R)
            return CFrame.lookAt(center + off, center)
        end
    end

    -- OFFSET (world-space) para el CONNECTION WELD: pos relativa al target donde el server debe verte
    -- (radius/height/mode). SIN rotación (identidad) → el server te ve orbitando/detrás del target sin
    -- jitter de rotación. El render suma esto a target.Position (suave) = sync perfecto al objetivo.
    local cseed = 0
    function Strafe.offsetVec(target, opts)
        local tRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        local R, spd, h = opts.radius or 10, opts.speed or 4, opts.height or 0
        local mode = (T("AutoMode") and LIP.strafeMode) or opts.mode or "Normal"
        if mode == "Behind" and tRoot then
            local lv = tRoot.CFrame.LookVector
            local flat = Vector3.new(lv.X, 0, lv.Z)
            if flat.Magnitude < 1e-3 then flat = Vector3.new(0, 0, -1) end
            return -flat.Unit * R + Vector3.new(0, h, 0)
        elseif mode == "Random" then
            cseed = cseed + spd * 0.02
            return Vector3.new(math.noise(cseed,0)*R, h + math.noise(0,cseed)*R*0.4, math.noise(cseed,cseed)*R)
        else -- Normal: órbita circular alrededor del target
            cseed = cseed + spd * 0.05
            return Vector3.new(math.cos(cseed)*R, h, math.sin(cseed)*R)
        end
    end

    -- OFFSET del connection weld en espacio LOCAL del target (se multiplica por target.CFrame → sigue su
    -- posición Y rotación). +Z = ATRÁS del target (LookVector es -Z). radius nunca 0 → nunca adentro = sin fling.
    local wseed = 0
    local function weldOrbitOffset(opts)
        if LIP.strafeNoise then
            return CFrame.new(Strafe.noiseOffset(os.clock(), LIP.curStrafeAmp or 12, LIP.curStrafeFreq or 1.5))
        end
        local R, spd, h = opts.radius or 10, opts.speed or 4, opts.height or 0
        local mode = (T("AutoMode") and LIP.strafeMode) or opts.mode or "Normal"
        if mode == "Behind" then
            return CFrame.new(0, h, R)                               -- fijo R atrás
        elseif mode == "Spiral" then
            wseed = wseed + spd * 0.03
            local vAmp = (math.abs(h) > 0.1) and math.abs(h) or 6
            return CFrame.new(math.cos(wseed) * R, math.sin(wseed * 0.5) * vAmp, math.sin(wseed) * R)
        elseif mode == "Random" then
            -- RANDOM XYZ local: offset random en los 3 ejes cada frame, rango = radius (slider)
            return CFrame.new(rndS() * R, h + rndS() * R, rndS() * R)
        else -- Normal: órbita circular en el plano local XZ del target
            wseed = wseed + spd * 0.05
            return CFrame.new(math.cos(wseed) * R, h, math.sin(wseed) * R)
        end
    end

    -- FLING al void para baitear el resolver enemigo (fase BAIT del ciclo). ORIGIN alto + XYZ random + rot
    -- random, clamp Y≥30 (NUNCA al vacío que mata). Reusa el rng brng (rnd/rndS).
    local VORIGIN = Vector3.new(0, 100, 0)
    local function voidBaitCF(dist)
        dist = dist or 5000
        local off = Vector3.new(rndS() * dist, rnd() * dist * 0.5, rndS() * dist)
        local pos = VORIGIN + off
        if pos.Y < 30 then pos = Vector3.new(pos.X, 30 + math.abs(pos.Y), pos.Z) end
        return CFrame.new(pos) * CFrame.Angles(rnd() * 6.2831, rnd() * 6.2831, rnd() * 6.2831)
    end

    -- FSM del ciclo dinámico de 3 FASES: CHASE (orbit tight + fire) → STRAFE (orbit ancho adaptativo + fire) →
    -- BAIT (fling void, no fire) → loop. Cada fase su timer (presets los setean).
    local function cycleStep()
        local now = os.clock()
        local preset = O("BaitPreset") or "Timed"
        local cT, sT, bT
        if preset == "Micro" then
            local ping = 0.1; pcall(function() ping = LP:GetNetworkPing() end)
            cT, sT, bT = ping + 0.02, O("StrafeTime") or 0.5, O("VoidTime") or 0.5
        elseif preset == "Spam" then
            cT, sT, bT = 0.06, 0.08, 0.11
        else
            cT, sT, bT = O("AroundTime") or 2.0, O("StrafeTime") or 2.0, O("VoidTime") or 1.0   -- Timed
        end
        if not LIP.strafePhase or not LIP.strafePhaseUntil then
            LIP.strafePhase = "chase"; LIP.strafePhaseUntil = now + cT
        elseif now >= LIP.strafePhaseUntil then
            if LIP.strafePhase == "chase" then
                LIP.strafePhase = "strafe"; LIP.strafePhaseUntil = now + sT
            elseif LIP.strafePhase == "strafe" then
                LIP.strafePhase = "bait"; LIP.strafePhaseUntil = now + bT
            else
                LIP.strafePhase = "chase"; LIP.strafePhaseUntil = now + cT
            end
        end
        return LIP.strafePhase
    end

    -- llamado por el driver cada Heartbeat con el target resuelto
    function Strafe.tick(target, opts)
        local root = myRoot(); local cam = Workspace.CurrentCamera
        local tRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if not (root and tRoot) then Strafe.stop(); return end

        -- CENTRO: pos RESUELTA del target (resolver, contra jitter/spoof enemigo, con predicción por
        -- velocidad para compensar el delay de replicación) o cruda + predicción manual.
        local center
        if opts.resolve then
            center = Strafe.resolvePos(target, tRoot.Position, opts.resolveMethod, opts.samples, opts.predict)
        else
            center = tRoot.Position
            if (opts.predict or 0) > 0 then center = center + Strafe.targetVel(target) * opts.predict end
        end

        -- CICLO DINÁMICO: si DynStrafe ON, alterna CHASE (orbita) / BAIT (fling void). En BAIT el goCF va al void.
        local phase = "chase"
        if T("DynStrafe") then phase = cycleStep() else LIP.strafePhase = "chase" end
        -- STRAFE PROPIO (noise-path adaptativo): reemplaza el switch de modos. amp/freq por fase — CHASE tight
        -- (CONF.chaseAmp/Freq), STRAFE ancho + adaptativo (adapt.amp/freq, corre el hill-climb sobre hit-rate).
        if T("DynStrafe") then
            LIP.strafeNoise = true
            if phase == "strafe" then
                adaptStep(target)
                LIP.curStrafeAmp, LIP.curStrafeFreq = adapt.amp, adapt.freq
            else
                LIP.curStrafeAmp, LIP.curStrafeFreq = Strafe.CONF.chaseAmp, Strafe.CONF.chaseFreq
            end
        else
            LIP.strafeNoise = false
        end

        local goCF
        if phase == "bait" then
            goCF = voidBaitCF(opts.radius and (opts.radius * 500) or 5000)
        else
            goCF = orbitCF(center, tRoot.CFrame.LookVector, opts)
        end

        -- BAIT: cada 1-3s salta a una pos random FIJA (dentro de 100 studs del target) por 0.5s, + jitter en
        -- X de ±5 studs cada frame → el enemigo ve un ghost lejano temblando = rompe/baitea su aim.
        local baiting = false
        if opts.bait then
            local now = os.clock()
            if not LIP.baitNext then LIP.baitNext = now + 1 + rnd() * 2 end
            if not LIP.baitUntil and now >= LIP.baitNext then
                LIP.baitUntil = now + 0.5                          -- pos FIJA por 0.5s
                local ang, d = rnd() * 6.2831853, rnd() * 100       -- random dentro de 100 studs del centro
                LIP.baitPos = center + Vector3.new(math.cos(ang) * d, opts.height or 0, math.sin(ang) * d)
            end
            if LIP.baitUntil then
                if now < LIP.baitUntil then
                    baiting = true
                    LIP.baitJitterPos = LIP.baitPos + Vector3.new((rnd() - 0.5) * 10, 0, 0)  -- jitter X, rango 10
                    goCF = CFrame.new(LIP.baitJitterPos)
                else LIP.baitUntil = nil; LIP.baitNext = now + 1 + rnd() * 2 end
            end
        end

        if opts.connExploit then
            -- CONNECTION WELD (WeldMenu-style): pos = target.CFrame*offset (local → sigue pos+rotación del target)
            -- + PhysicsRepRootPart = HRP REAL del target (su assembly → replica SIN delay ni flicker; un part
            -- anclado no replicaba). radius nunca 0 → sin fling. Composición con Pos Spoof (como symbol):
            local offCF  = weldOrbitOffset(opts)
            local weldCF = tRoot.CFrame * offCF
            LIP.spoofFakePos = weldCF.Position   -- origin del disparo + viz
            LIP.tightFollow = true
            if opts.posSpoof then
                -- WELD + SPOOF: el server te ve en el weld (PhysicsRepRootPart=target), pero tu cuerpo real queda
                -- QUIETO en pantalla → escribimos weldCF (desync) y el RenderStepped lo restaura a tu pos real.
                local realCF = Spoof.captureReal(root)
                LIP.cachedRoot   = root
                LIP.spoofRealCF  = realCF
                LIP.spoofOn      = true
                LIP.spoofVel     = root.AssemblyLinearVelocity
                LIP.spoofRestore = realCF
                Spoof.camToLocal(cam, realCF)
                pcall(function() root.CFrame = weldCF end)
                Spoof.setPhysRep(tRoot)
            else
                -- WELD solo: mové tu cuerpo real al target (te ves ahí) + PhysicsRepRootPart=target.
                if LIP.spoofOn then Spoof.stopDesyncOnly(cam) end
                Spoof.weldToTarget(tRoot, offCF)
                Spoof.camToChar(cam)
            end
        elseif opts.posSpoof then
            LIP.spoofFakePos = goCF.Position   -- visualizador + origin del disparo
            LIP.tightFollow = false
            -- DESYNC: server ve goCF (órbita), cuerpo/cámara reales quietos = mueve al jugador SPOOFEADO.
            if LIP.connRep then Spoof.unweld() end
            local realCF = Spoof.captureReal(root)
            LIP.cachedRoot   = root
            LIP.spoofRealCF  = realCF
            LIP.spoofOn      = true
            LIP.spoofVel     = root.AssemblyLinearVelocity
            LIP.spoofRestore = realCF
            Spoof.camToLocal(cam, realCF)
            pcall(function() root.CFrame = goCF end)
        else
            LIP.spoofFakePos = goCF.Position
            LIP.tightFollow = false
            -- SIN spoof: mueve el cuerpo real a la órbita. Zero de velocidad (no acumula momentum).
            if LIP.spoofOn or LIP.connRep then Spoof.stop(cam) end
            pcall(function()
                root.CFrame = goCF
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end

    function Strafe.stop() Spoof.stop(Workspace.CurrentCamera) end

    return Strafe
end
