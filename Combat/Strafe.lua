-- Combat/Strafe.lua — FACTORY. Target Strafe (desync HvH) + spam resolver.
-- Replicación en LiP = network ownership NATIVO del HRP (no hay remote de posición). Escribir
-- HRP.CFrame client-side lo replica al server. El AC del cliente NO detecta escritura directa de
-- CFrame (handler GetPropertyChangedSignal solo cuenta writes legítimos u2674>0; early-return si 0).
-- → orbitar el target escribiendo HRP.CFrame cada Heartbeat es AC-safe.
--
-- SPAM RESOLVER: el juego no tiene anti-fling/anti-noclip activo → está plagado de cheaters con
-- fling/noclip. Guardamos un ring buffer por enemigo y resolvemos el CENTRO real (mediana),
-- descartando saltos implausibles (fling/teleport spoof). El silent aim apunta al centro resuelto.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Strafe = {}

    local function myRoot() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end

    -- ── SPAM RESOLVER ────────────────────────────────────────────────────────────
    -- ring buffer [player] = { samples = {Vector3...}, t = {clock...} }
    local hist = {}
    local MAX = 12
    local function sample(plr, pos, now)
        local h = hist[plr]; if not h then h = { s = {}, t = {} }; hist[plr] = h end
        -- descarta salto implausible (fling/tp spoof): vel > 300 studs/s
        local n = #h.s
        if n > 0 then
            local dt = now - h.t[n]
            if dt > 0 and (pos - h.s[n]).Magnitude / dt > 300 then return end
        end
        h.s[#h.s + 1] = pos; h.t[#h.t + 1] = now
        if #h.s > MAX then table.remove(h.s, 1); table.remove(h.t, 1) end
    end
    -- centro robusto = mediana por componente (resiste outliers de strafe/spoof enemigo)
    local function resolved(plr, fallback)
        local h = hist[plr]; if not h or #h.s < 3 then return fallback end
        local xs, ys, zs = {}, {}, {}
        for i = 1, #h.s do xs[i] = h.s[i].X; ys[i] = h.s[i].Y; zs[i] = h.s[i].Z end
        table.sort(xs); table.sort(ys); table.sort(zs)
        local m = math.floor(#xs / 2) + 1
        return Vector3.new(xs[m], ys[m], zs[m])
    end
    -- llamado por el driver: actualiza historial de todos los enemigos vivos
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
    -- posición resuelta de un target (para que el silent aim la use si Resolver on)
    function Strafe.resolvePos(plr, rawPos) return resolved(plr, rawPos) end

    -- ── TARGET STRAFE (desync por escritura de HRP.CFrame) ───────────────────────
    -- orbita al target; el server te ve moviéndote, difícil de pegarte. Modes: Normal/Random/Behind.
    function Strafe.tick(target, opts)
        local root = myRoot(); if not root then return end
        local tRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if not tRoot then return end
        local R   = opts.radius or 10
        local spd = opts.speed or 12
        local mode = opts.mode or "Normal"
        local now = os.clock()

        local angle
        if mode == "Random" then
            angle = (LIP._strafeSeed or 0)
            LIP._strafeSeed = angle + (spd * 0.06) + (math.sin(now * 13.0) * 0.5)
        elseif mode == "Behind" then
            -- detrás del target respecto a su LookVector
            local behind = tRoot.CFrame.LookVector * -R
            local goPos = tRoot.Position + behind + Vector3.new(0, opts.height or 0, 0)
            pcall(function()
                root.CFrame = CFrame.lookAt(goPos, tRoot.Position)
                root.AssemblyLinearVelocity = Vector3.zero
            end)
            return
        else -- Normal: órbita circular
            angle = (LIP._strafeSeed or 0) + spd * 0.05
            LIP._strafeSeed = angle
        end
        local off = Vector3.new(math.cos(angle) * R, opts.height or 0, math.sin(angle) * R)
        local goPos = tRoot.Position + off
        pcall(function()
            root.CFrame = CFrame.lookAt(goPos, tRoot.Position)
            root.AssemblyLinearVelocity = Vector3.zero
        end)
    end

    return Strafe
end
