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
    local MAX = 16
    local function sample(plr, pos, now, rejectVel)
        local h = hist[plr]; if not h then h = { s = {}, t = {} }; hist[plr] = h end
        local n = #h.s
        if n > 0 then
            local dt = now - h.t[n]
            if dt > 0 and (pos - h.s[n]).Magnitude / dt > (rejectVel or 300) then return end  -- fling/tp spoof
        end
        h.s[#h.s + 1] = pos; h.t[#h.t + 1] = now
        if #h.s > MAX then table.remove(h.s, 1); table.remove(h.t, 1) end
    end
    function Strafe.sampleAll(now, rejectVel)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local c = plr.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then sample(plr, hrp.Position, now, rejectVel) end
            end
        end
    end
    local function median(a) local b = table.clone(a); table.sort(b); return b[math.floor(#b/2)+1] end
    -- velocidad instantánea del target (últimas 2 muestras) — para predicción/chase
    function Strafe.targetVel(plr)
        local h = hist[plr]; local n = h and #h.s or 0
        if n < 2 then return Vector3.zero end
        local dt = math.max(h.t[n] - h.t[n-1], 1/240)
        return (h.s[n] - h.s[n-1]) / dt
    end
    -- método de resolución + predicción (lead por velocidad, compensa ping/movimiento)
    function Strafe.resolvePos(plr, rawPos, method, samples, predictT)
        local h = hist[plr]; local n = h and #h.s or 0
        if n < 3 then return rawPos end
        local k = math.clamp(samples or 8, 3, n)
        local xs, ys, zs, wsum, wx, wy, wz = {}, {}, {}, 0, 0, 0, 0
        for i = n - k + 1, n do
            local p = h.s[i]
            xs[#xs+1] = p.X; ys[#ys+1] = p.Y; zs[#zs+1] = p.Z
            local w = (i - (n - k))           -- peso lineal: frames recientes pesan más
            wsum = wsum + w; wx = wx + p.X*w; wy = wy + p.Y*w; wz = wz + p.Z*w
        end
        local base
        if method == "Average" then
            local s = Vector3.zero; for i = n-k+1, n do s = s + h.s[i] end; base = s / k
        elseif method == "Weighted" then base = Vector3.new(wx/wsum, wy/wsum, wz/wsum)
        elseif method == "Latest" then base = h.s[n]
        else base = Vector3.new(median(xs), median(ys), median(zs)) end   -- Median (robusto)
        if predictT and predictT > 0 then base = base + Strafe.targetVel(plr) * predictT end
        return base
    end

    ------------------------------------------------------------------ PRESETS
    Strafe.PRESETS = {
        Normal = { mode = "Normal", radius = 10,   speed = 4,  height = 0 },
        Random = { mode = "Random", radius = 10.5, speed = 20, height = 0 },
        Behind = { mode = "Behind", radius = 8,    speed = 8,  height = 0 },
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

    local seed = 0
    -- órbita alrededor de un CENTRO, mirando al centro. Normal/Random/Behind.
    local function orbitCF(center, tLook, opts)
        local R, spd, h = opts.radius or 10, opts.speed or 4, opts.height or 0
        local mode = opts.mode or "Normal"
        if mode == "Behind" then
            local look = tLook or Vector3.new(0, 0, -1)
            local goPos = center - look * R + Vector3.new(0, h, 0)
            return CFrame.lookAt(goPos, center)
        elseif mode == "Random" then
            local rx = math.noise(seed, 0) * R
            local ry = math.noise(0, seed) * R
            local rz = math.noise(seed, seed) * R
            seed = seed + spd * 0.02 + math.abs(math.sin(os.clock() * 91.7)) * 0.15
            local goPos = center + Vector3.new(rx, h + ry * 0.4, rz)
            return CFrame.new(goPos) * CFrame.Angles(math.noise(seed,1)*3, math.noise(1,seed)*3, math.noise(seed,seed)*3)
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
        local mode = opts.mode or "Normal"
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

    -- LCG para bait (Math.random bloqueado en el executor)
    local brng = 987654321
    local function rnd() brng = (brng * 1103515245 + 12345) % 2147483648; return brng / 2147483648 end

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

        local goCF = orbitCF(center, tRoot.CFrame.LookVector, opts)

        -- BAIT: cada 1-3s (random) salta a un spot random lejano por 0.3s (baitea el aim enemigo)
        if opts.bait then
            local now = os.clock()
            if not LIP.baitNext then LIP.baitNext = now + 1 + rnd() * 2 end
            if not LIP.baitUntil and now >= LIP.baitNext then
                LIP.baitUntil = now + 0.3
                local R = opts.radius or 10
                LIP.baitPos = center + Vector3.new((rnd()-0.5) * R * 6, opts.height or 0, (rnd()-0.5) * R * 6)
            end
            if LIP.baitUntil then
                if now < LIP.baitUntil then goCF = CFrame.new(LIP.baitPos)
                else LIP.baitUntil = nil; LIP.baitNext = now + 1 + rnd() * 2 end
            end
        end

        LIP.spoofFakePos = goCF.Position   -- visualizador + origin del disparo

        if opts.connExploit then
            -- CONNECTION WELD al TARGET: soldamos tu PhysicsRepRootPart pegado al HRP del objetivo + offset
            -- (radius/height/mode) → el server te ve sincronizado PERFECTO con él, sin jitter (el tracking
            -- corre en render contra la CFrame suave del target, NO usa resolver/predict). Cuerpo REAL libre.
            -- Bypassa el orbit/goCF (resolver era la fuente de jitter). Coexiste con pos spoof (harmonía).
            if LIP.spoofOn then Spoof.stopDesyncOnly(cam) end   -- corta SOLO el desync, mantiene el weld
            local off = Strafe.offsetVec(target, opts)
            Spoof.weldToTarget(tRoot, off)
            LIP.spoofFakePos = tRoot.Position + off
        elseif opts.posSpoof then
            if LIP.connRep then Spoof.unweld() end
            -- DESYNC: server ve la órbita, cuerpo/cámara reales quietos
            local realCF = Spoof.captureReal(root)
            LIP.cachedRoot   = root
            LIP.spoofRealCF  = realCF
            LIP.spoofOn      = true
            LIP.spoofVel     = root.AssemblyLinearVelocity
            LIP.spoofRestore = realCF
            Spoof.camToLocal(cam, realCF)
            pcall(function() root.CFrame = goCF end)
        else
            -- SIN spoof: mueve el cuerpo real. Zero de velocidad linear+angular (no acumula momentum).
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
