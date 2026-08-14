-- Movement/Void.lua — FACTORY. Void spam (anti-aim posicional) + visualizador.
-- Origen ABSOLUTO fijo (0,100,0). Cada frame manda la pos spoofeada a coordenadas + rotación XYZ
-- random MUY LEJANAS de ese origen → el server te ve teleportando por todos lados = imposible pegarte.
-- Respeta el MASTER Pos Spoof (LIP.posSpoof): ON = desync (cuerpo/cámara reales quietos), OFF = mueve
-- el cuerpo real (teleport crudo, riesgoso). Visualizador: Part neón + icono + tracer.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Spoof  = require("Combat.Spoof")
    local Weapon = require("Combat.Weapon")
    local Void = {}

    local ORIGIN = Vector3.new(0, 100, 0)   -- origen absoluto (pedido del usuario)

    local function myRoot() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end

    -- PRNG LCG (Math.random está bloqueado en el executor) → random real por frame
    local rngState = 2463534242
    local function rnd()
        rngState = (rngState * 1103515245 + 12345) % 2147483648
        return rngState / 2147483648
    end
    local function rndSigned() return rnd() * 2 - 1 end

    -- patrones de void (TODOS altos — clamp Y≥30 para NUNCA tocar el vacío, que mata).
    -- Rotación XYZ random SIEMPRE. Origen absoluto (0,100,0).
    -- estado de los patrones. `anchor` = base (ORIGIN absoluto para void/idle; pos real para CFrame Desync).
    -- `dist` = RADIUS (1-100 close) para Random/Teleport/Jitter/StaticBreak; Nebula usa FarDist/MapRadius.
    local tpAnchor, tpT = nil, 0
    local jitP1, jitP2, jitReseed, jitFlip = nil, nil, 0, false
    local sbAnchor, sbT = nil, 0
    local nebT, nebPhase, nebSpot, nebFar, nebStatic = 0, "far", nil, nil, true
    local function patternCF(anchor, dist, pattern)
        anchor = anchor or ORIGIN
        -- ANTI-DELTA: mueve el origen al KILL PLANE (FallenPartsDestroyHeight) → todos los patrones pasan por ahí.
        -- Con Pos Spoof (cuerpo real arriba, safe) el server te ve al borde del kill plane; un delteo que te
        -- weldea/dragea cae bajo el plane = destruido. Requiere Pos Spoof (sin él te teleportás crudo y morís vos).
        local antiDelta = T("AntiDelta")
        if antiDelta then
            local killY = (Workspace.FallenPartsDestroyHeight or -500) + 3   -- justo ARRIBA del plane (vos safe)
            anchor = Vector3.new(anchor.X, killY, anchor.Z)
        end
        local rot = CFrame.Angles(rnd() * 6.2831, rnd() * 6.2831, rnd() * 6.2831)   -- anti-aim rotacional XYZ
        local now = os.clock()
        local off
        if pattern == "Teleport" then
            -- NON-PATTERN: mantiene un offset random ~0.3s y salta (discreto)
            if not tpAnchor or (now - tpT) > 0.3 then
                tpAnchor = Vector3.new(rndSigned() * dist, rnd() * dist * 0.5, rndSigned() * dist); tpT = now
            end
            off = tpAnchor
        elseif pattern == "Jitter" then
            -- PATTERN anti-centroide: 2 puntos fijos OPUESTOS en XZ, snap entre ellos cada frame → el promedio
            -- (centroide) cae en el punto medio = ORIGIN = aire. Re-seedea los 2 puntos cada ~0.6s (menos predecible).
            if not jitP1 or (now - jitReseed) > 0.6 then
                local a = Vector3.new(rndSigned() * dist, rnd() * dist * 0.5, rndSigned() * dist)
                jitP1 = a; jitP2 = Vector3.new(-a.X, a.Y, -a.Z); jitReseed = now
            end
            jitFlip = not jitFlip
            off = jitFlip and jitP1 or jitP2
        elseif pattern == "StaticBreak" then
            -- PATTERN peek-then-flick: QUIETO en un offset fijo ~0.5s (baitea al resolver a lockear) + FLICK al
            -- opuesto ~0.1s (el "break") → el enemigo lockea el punto estático y al break ya no estás ahí.
            if not sbAnchor or (now - sbT) > 0.6 then
                sbAnchor = Vector3.new(rndSigned() * dist, rnd() * dist * 0.5, rndSigned() * dist); sbT = now
            end
            if (now - sbT) > 0.5 then off = Vector3.new(-sbAnchor.X, sbAnchor.Y, -sbAnchor.Z)   -- BREAK (flick opuesto)
            else off = sbAnchor end                                                              -- STATIC (bait)
        elseif pattern == "Nebula" then
            -- FAR↔MAP a distancias RIDÍCULAS: FAR (~0.15s) = dir random 3D * FarDist (300M, un-hittable por
            -- latencia); MAP (~0.3s) = spot random cerca del anchor dentro de MapRadius, SOSTENIDO 0.3s. Cada
            -- spot es STATIC (rompe predicts: te lockean quieto y saltás) o con jitter chico (rompe centroide).
            -- Deltas 300M↔mapa = irresolvible. FarDist/MapRadius por slider.
            local FarD = O("FarDist") or 3e8
            local MapR = O("MapRadius") or 3000
            if now >= nebT then
                if nebPhase == "far" then
                    nebPhase = "map"; nebT = now + 0.3
                    nebSpot = Vector3.new(rndSigned() * MapR, rnd() * 50, rndSigned() * MapR)
                    nebStatic = (rnd() < 0.5)
                else
                    nebPhase = "far"; nebT = now + 0.15
                    local dx, dy, dz = rndSigned(), rndSigned(), rndSigned()
                    local m = math.sqrt(dx*dx + dy*dy + dz*dz); if m < 1e-6 then m = 1 end
                    nebFar = Vector3.new(dx/m, math.abs(dy/m), dz/m) * FarD   -- Y+ (nunca al vacío)
                end
            end
            if nebPhase == "far" then off = nebFar or Vector3.new(FarD, FarD, 0)
            elseif nebStatic then off = nebSpot or Vector3.zero                            -- ESTÁTICO (rompe predicts)
            else off = (nebSpot or Vector3.zero) + Vector3.new(rndSigned() * 5, 0, rndSigned() * 5) end  -- jitter (rompe centroide)
        else -- "Random" (NON-PATTERN, default): offset XYZ random cada frame dentro del radius
            off = Vector3.new(rndSigned() * dist, rnd() * dist * 0.5, rndSigned() * dist)
        end
        local pos = anchor + off
        if not antiDelta and pos.Y < 30 then pos = Vector3.new(pos.X, 30 + math.abs(pos.Y), pos.Z) end   -- NUNCA al vacío (salvo anti-delta, que VA al kill plane)
        return CFrame.new(pos) * rot
    end
    Void.patternCF = patternCF   -- expuesto para CFrame Desync (reusa con anchor = pos real)

    -- PRESETS PRO (VoidPreset): pattern + radius + timing in/out. Non-pattern (Legit/Chaos/Blink) vs pattern
    -- anti-centroide (Jitter/Peek). applyPreset setea las Options (mismo mecanismo que Strafe.applyPreset).
    Void.PRESETS = {
        Legit  = { pattern = "Random",      radius = 15,  inT = 0.6,  outT = 0.5  },
        Jitter = { pattern = "Jitter",      radius = 40,  inT = 0.3,  outT = 0.3  },
        Peek   = { pattern = "StaticBreak", radius = 60,  inT = 0.5,  outT = 0.4  },
        Blink  = { pattern = "Teleport",    radius = 80,  inT = 0.35, outT = 0.3  },
        Chaos  = { pattern = "Random",      radius = 100, inT = 0.15, outT = 0.15 },
    }
    function Void.applyPreset(name)
        local p = Void.PRESETS[name]; if not p then return end
        local Op = Lib.Options
        if Op.VoidPattern then Op.VoidPattern:SetValue(p.pattern) end
        if Op.VoidDist    then Op.VoidDist:SetValue(p.radius) end
        if Op.VoidInTime  then Op.VoidInTime:SetValue(p.inT) end
        if Op.VoidOutTime then Op.VoidOutTime:SetValue(p.outT) end
    end

    function Void.tick(opts)
        local root = myRoot(); local cam = Workspace.CurrentCamera
        if not root then Spoof.stop(cam); return end
        local dist = opts.dist or 1000
        local goCF = patternCF(ORIGIN, dist, opts.pattern)
        LIP.spoofFakePos = goCF.Position

        LIP.tightFollow = false
        -- Void no tiene target → connExploit no aplica acá. Pos Spoof decide: ON = DESYNC (server te ve lejos,
        -- cuerpo/cámara reales quietos), OFF = teleport crudo del cuerpo real (riesgoso). El weld PhysicsRep se
        -- eliminó (con connPart anclado no replicaba → no movía nada).
        if opts.posSpoof then
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
            if LIP.spoofOn or LIP.connRep then Spoof.stop(cam) end
            pcall(function() root.CFrame = goCF; root.AssemblyLinearVelocity = Vector3.zero end)
        end
    end

    -- ── VOID SPAM REAL (shoot / dodge) ─────────────────────────────────────────
    -- Oscila entre IN VOID (server te ve lejos con el pattern → disparo PAUSADO, reload opcional) y OUT
    -- VOID (server te ve en tu pos REAL → disparás). El salto constante rompe el resolver de PREDICCIÓN
    -- de otros cheaters (tu pos aparece/desaparece = no te predicen). Sliders In/Out (0.1-2s). Gate de
    -- disparo = LIP.voidShootOk (Weapon.tickAuto lo respeta si voidShootOut). Usa el pattern seleccionado.
    local function spoofTo(root, cam, goCF, posSpoof)
        if posSpoof == false then
            -- teleport crudo del cuerpo real (raro en void; respeta Pos Spoof OFF)
            if LIP.spoofOn or LIP.connRep then Spoof.stop(cam) end
            pcall(function() root.CFrame = goCF; root.AssemblyLinearVelocity = Vector3.zero end)
        else
            if LIP.connRep then Spoof.unweld() end
            local realCF = Spoof.captureReal(root)
            LIP.cachedRoot = root; LIP.spoofRealCF = realCF; LIP.spoofOn = true
            LIP.spoofVel = root.AssemblyLinearVelocity; LIP.spoofRestore = realCF
            Spoof.camToLocal(cam, realCF)
            pcall(function() root.CFrame = goCF end)
        end
    end
    -- Avanza la máquina de estados IN↔OUT y devuelve la fase ("in"/"out"). Setea LIP.voidShootOk (dispara
    -- solo OUT). **FORCE VOID durante la recarga** (LIP.reloading): se queda IN hasta que el reload termina
    -- → recargás 100% escondido. Compone con Target Strafe: main llama Strafe.tick en OUT, tickVoidPos en IN.
    function Void.voidStep(opts)
        local now = os.clock()
        if LIP.reloading then                          -- FORCE VOID mientras recarga (hasta completar)
            LIP.voidPhase = "in"; LIP.voidShootOk = false
            return "in"
        end
        if not LIP.voidPhase or now >= (LIP.voidPhaseUntil or 0) then
            if LIP.voidPhase == "in" then
                LIP.voidPhase = "out"; LIP.voidPhaseUntil = now + (opts.outTime or 0.5)
            else
                LIP.voidPhase = "in"; LIP.voidPhaseUntil = now + (opts.inTime or 0.5)
                -- al ENTRAR al void: reload si el cargador está gastado (recargás escondido; force-void lo cubre)
                if opts.voidReload and (LIP.shotsFired or 0) >= (Weapon.magSize() or 15) then Weapon.reload() end
            end
        end
        LIP.voidShootOk = (LIP.voidPhase == "out")
        return LIP.voidPhase
    end

    -- POSICIÓN del void (fase IN): spoofea lejos con el pattern (esconderse del resolver enemigo).
    function Void.tickVoidPos(opts)
        local root = myRoot(); local cam = Workspace.CurrentCamera
        if not root then return end
        local goCF = patternCF(ORIGIN, opts.dist or 1000, opts.pattern)
        LIP.spoofFakePos = goCF.Position
        LIP.tightFollow = false
        spoofTo(root, cam, goCF, opts.posSpoof)
    end

    -- ── VISUALIZADOR ──────────────────────────────────────────────────────────
    local vizPart, vizBillboard, tracer, dot
    local function ensureViz()
        if not vizPart or not vizPart.Parent then
            vizPart = Instance.new("Part")
            vizPart.Name = "LIP_SpoofViz"; vizPart.Shape = Enum.PartType.Ball
            vizPart.Material = Enum.Material.Neon; vizPart.Color = Color3.fromRGB(202,151,161)
            vizPart.Size = Vector3.new(3,3,3); vizPart.Anchored = true; vizPart.CanCollide = false
            vizPart.Transparency = 0.3
            pcall(function() vizPart.Parent = Workspace end)
            local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(70,20)
            bb.AlwaysOnTop = true; bb.StudsOffset = Vector3.new(0,2,0); bb.Parent = vizPart
            local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1,1); tl.BackgroundTransparency = 1
            tl.Text = "SPOOF"; tl.TextColor3 = Color3.fromRGB(202,151,161); tl.TextStrokeTransparency = 0
            tl.Font = Enum.Font.GothamBold; tl.TextSize = 12; tl.Parent = bb
            vizBillboard = bb
        end
        if not tracer then tracer = Drawing.new("Line"); tracer.Thickness = 1; tracer.Color = Color3.fromRGB(202,151,161) end
        if not dot then dot = Drawing.new("Circle"); dot.Radius = 5; dot.Thickness = 2; dot.Color = Color3.fromRGB(202,151,161) end
    end
    local function hideViz()
        if vizPart then vizPart.Transparency = 1; if vizBillboard then vizBillboard.Enabled = false end end
        if tracer then tracer.Visible = false end
        if dot then dot.Visible = false end
    end
    -- ── SIMULACIÓN DE REPLICACIÓN (puramente visual) ──────────────────────────
    -- El indicador NO muestra la pos spoofeada cruda, sino cómo la VEN los demás: demorada por tu ping y
    -- refrescada a ~16hz (como replica Roblox los characters), con suavizado (lerp). Así el icono/tracer
    -- reflejan la posición real que percibe el server/enemigos, no la instantánea.
    local vizHist = {}          -- { {t=clock, pos=V3}, ... }
    local vizShown              -- pos mostrada (interpolada)
    local vizNext16 = 0
    local segStart, segTarget, segT0 = nil, nil, 0   -- segmento de interpolación actual
    -- ease InOutExpo (lo que MÁS se parece a la interpolación de characters de Roblox: casi lineal/snappy
    -- en el medio, suave en los bordes). Se corre "demasiado rápido" (segDur < intervalo) + re-ancla al
    -- punto actual en cada update → CORTA CAMINOS en cambios bruscos (como Roblox).
    local function easeInOutExpo(t)
        if t <= 0 then return 0 end
        if t >= 1 then return 1 end
        if t < 0.5 then return 0.5 * 2 ^ (20 * t - 10) end
        return 1 - 0.5 * 2 ^ (-20 * t + 10)
    end
    local function delayedPos(now, delay)
        local tt = now - delay
        for i = #vizHist, 2, -1 do
            if vizHist[i-1].t <= tt then
                local a, b = vizHist[i-1], vizHist[i]
                local span = b.t - a.t
                local f = (span > 0) and math.clamp((tt - a.t) / span, 0, 1) or 0
                return a.pos:Lerp(b.pos, f)
            end
        end
        return vizHist[1] and vizHist[1].pos
    end
    local function updateViz()
        -- viz cuando hay desync activo (spoofOn) con pos spoofeada
        if not (T("VoidViz") and LIP.spoofOn and LIP.spoofFakePos) then
            vizHist = {}; vizShown = nil; segStart = nil; segTarget = nil; return hideViz()
        end
        ensureViz()
        local now = os.clock()
        if LIP.tightFollow then
            -- CONNECTION WELD (seguí pegado al target real): el server te ve donde te desyncás en vivo con él
            -- → el indicador NO lleva delay artificial. Mostralo crudo, sin ping-sim.
            vizShown = LIP.spoofFakePos
            vizHist = {}; segStart = nil; segTarget = nil
        else
            -- DESYNC (ghost): simular cómo lo ven los demás → demora por ping + refresh ~16hz + suavizado.
            -- 1) samplear la pos spoofeada real al historial (~2s)
            vizHist[#vizHist+1] = { t = now, pos = LIP.spoofFakePos }
            while #vizHist > 140 do table.remove(vizHist, 1) end
            -- 2) ping actual = delay de replicación
            local ping = 0.1
            pcall(function() ping = math.clamp(game:GetService("Players").LocalPlayer:GetNetworkPing(), 0, 0.6) end)
            -- 3) update ~16hz: NUEVO segmento eased desde donde ESTAMOS (corta caminos) → pos demorada por ping
            if now >= vizNext16 then
                vizNext16 = now + (1/16)
                local tgt = delayedPos(now, ping) or LIP.spoofFakePos
                segStart = vizShown or tgt
                segTarget = tgt
                segT0 = now
            end
            segTarget = segTarget or LIP.spoofFakePos
            segStart  = segStart or segTarget
            -- 4) InOutExpo "demasiado rápido": segDur < intervalo (16hz) → llega antes del próximo update, y en
            --    cambios bruscos el re-anclado + la curva snappy = shortcut casi lineal (interpolación Roblox).
            local a = math.clamp((now - segT0) / ((1/16) * 0.7), 0, 1)
            vizShown = segStart:Lerp(segTarget, easeInOutExpo(a))
        end
        -- render
        local c = O("VizColor") or Color3.fromRGB(202,151,161)
        vizPart.Transparency = 0.3; vizPart.Position = vizShown; vizPart.Color = c; vizBillboard.Enabled = true
        if vizBillboard:FindFirstChildOfClass("TextLabel") then vizBillboard:FindFirstChildOfClass("TextLabel").TextColor3 = c end
        tracer.Color = c; dot.Color = c
        local cam = Workspace.CurrentCamera
        local sp, on = cam:WorldToViewportPoint(vizShown)
        if on then
            local vp = cam.ViewportSize
            tracer.From = Vector2.new(vp.X/2, vp.Y/2); tracer.To = Vector2.new(sp.X, sp.Y); tracer.Visible = true   -- desde el CENTRO
            dot.Position = Vector2.new(sp.X, sp.Y); dot.Visible = true
        else tracer.Visible = false; dot.Visible = false end
    end

    -- ── Resolved Tracer: centro de pantalla → pos RESUELTA por el cluster ──────
    -- Independiente del VoidViz. Lee Strafe.resolvedPeek (read-only, no ingesta muestras
    -- → no perturba el resolver). Solo dibuja mientras el resolver tiene un cluster (o sea,
    -- mientras estás strafeando/disparando al target y el histograma está poblado).
    local resLine, _Strafe
    local function updateResTracer()
        if not (T("ResolvedTracer") and T("Resolver") and LIP.target and LIP.target.Character) then
            if resLine then resLine.Visible = false end; return
        end
        _Strafe = _Strafe or require("Combat.Strafe")
        local rp = _Strafe.resolvedPeek(LIP.target)
        if not rp then if resLine then resLine.Visible = false end; return end
        if not resLine then resLine = Drawing.new("Line"); resLine.Thickness = 1.5 end
        local cam = Workspace.CurrentCamera
        local sp, on = cam:WorldToViewportPoint(rp)
        if on then
            local vp = cam.ViewportSize
            resLine.From = Vector2.new(vp.X/2, vp.Y/2); resLine.To = Vector2.new(sp.X, sp.Y)
            resLine.Color = O("ResolvedTracerColor") or Color3.fromRGB(255, 120, 120); resLine.Visible = true
        else resLine.Visible = false end
    end

    function Void.init()
        Spoof.init()
        LIP.onCleanup(function()
            if vizPart then pcall(function() vizPart:Destroy() end) end
            if tracer then pcall(function() tracer:Remove() end) end
            if dot then pcall(function() dot:Remove() end) end
            if resLine then pcall(function() resLine:Remove() end) end
        end)
        LIP.track(RunService.RenderStepped:Connect(function() pcall(updateViz) end))
        LIP.track(RunService.RenderStepped:Connect(function() pcall(updateResTracer) end))
    end

    return Void
end
