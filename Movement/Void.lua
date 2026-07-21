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
    local orbSeed, tpAnchor, tpT = 0, nil, 0
    local TWEEN = { Vector3.new(1,0,1), Vector3.new(-1,0,1), Vector3.new(-1,0,-1), Vector3.new(1,0,-1) }
    local function patternCF(dist, pattern)
        local rot = CFrame.Angles(rnd() * 6.2831, rnd() * 6.2831, rnd() * 6.2831)
        local off
        if pattern == "High" then
            off = Vector3.new(0, dist, 0)
        elseif pattern == "Orbit" then
            orbSeed = orbSeed + 0.25
            off = Vector3.new(math.cos(orbSeed) * dist, 60 + rnd() * dist * 0.3, math.sin(orbSeed) * dist)
        elseif pattern == "Tween" then
            orbSeed = orbSeed + 0.03
            local i = (math.floor(orbSeed) % #TWEEN) + 1
            local j = (i % #TWEEN) + 1
            local f = orbSeed - math.floor(orbSeed)
            local c = TWEEN[i]:Lerp(TWEEN[j], f) * dist
            off = Vector3.new(c.X, 60 + math.abs(c.Y), c.Z)
        elseif pattern == "Teleport" then
            if not tpAnchor or (os.clock() - tpT) > 0.3 then
                tpAnchor = Vector3.new(rndSigned() * dist, rnd() * dist * 0.5, rndSigned() * dist); tpT = os.clock()
            end
            off = tpAnchor
        else -- "Random" (default): XYZ random cada frame, muy lejos
            off = Vector3.new(rndSigned() * dist, rnd() * dist * 0.5, rndSigned() * dist)
        end
        local pos = ORIGIN + off
        if pos.Y < 30 then pos = Vector3.new(pos.X, 30 + math.abs(pos.Y), pos.Z) end   -- NUNCA al vacío
        return CFrame.new(pos) * rot
    end

    function Void.tick(opts)
        local root = myRoot(); local cam = Workspace.CurrentCamera
        if not root then Spoof.stop(cam); return end
        local dist = opts.dist or 1000
        local goCF = patternCF(dist, opts.pattern)
        LIP.spoofFakePos = goCF.Position

        if opts.connExploit then
            if LIP.spoofOn then Spoof.stopDesyncOnly(cam) end   -- corta desync, mantiene el weld
            Spoof.weldToPos(goCF.Position)   -- void: sin target → pos absoluta lejana; cuerpo real libre
        elseif opts.posSpoof then
            if LIP.connRep then Spoof.unweld() end
            -- DESYNC: server ve las posiciones random lejanas, cuerpo/cámara reales quietos
            local realCF = Spoof.trueCF(root)
            LIP.cachedRoot   = root
            LIP.spoofRealCF  = realCF
            LIP.spoofOn      = true
            LIP.spoofVel     = root.AssemblyLinearVelocity
            LIP.spoofRestore = realCF
            Spoof.camToLocal(cam, realCF)
            pcall(function() root.CFrame = goCF end)
        else
            -- SIN spoof: mueve el cuerpo real (teleport crudo, riesgoso)
            if LIP.spoofOn or LIP.connRep then Spoof.stop(cam) end
            pcall(function() root.CFrame = goCF; root.AssemblyLinearVelocity = Vector3.zero end)
        end
    end

    -- ── VOID SPAM REAL (shoot / dodge) ─────────────────────────────────────────
    -- Oscila entre IN VOID (server te ve lejos con el pattern → disparo PAUSADO, reload opcional) y OUT
    -- VOID (server te ve en tu pos REAL → disparás). El salto constante rompe el resolver de PREDICCIÓN
    -- de otros cheaters (tu pos aparece/desaparece = no te predicen). Sliders In/Out (0.1-2s). Gate de
    -- disparo = LIP.voidShootOk (Weapon.tickAuto lo respeta si voidShootOut). Usa el pattern seleccionado.
    local function spoofTo(root, cam, goCF, connExploit)
        if connExploit then
            if LIP.spoofOn then Spoof.stopDesyncOnly(cam) end
            Spoof.weldToPos(goCF.Position)
        else
            if LIP.connRep then Spoof.unweld() end
            local realCF = Spoof.trueCF(root)
            LIP.cachedRoot = root; LIP.spoofRealCF = realCF; LIP.spoofOn = true
            LIP.spoofVel = root.AssemblyLinearVelocity; LIP.spoofRestore = realCF
            Spoof.camToLocal(cam, realCF)
            pcall(function() root.CFrame = goCF end)
        end
    end
    function Void.tickSpam(opts)
        local root = myRoot(); local cam = Workspace.CurrentCamera
        if not root then Spoof.stop(cam); LIP.voidShootOk = true; return end
        local now = os.clock()
        -- máquina de estados IN ↔ OUT
        if not LIP.voidPhase or now >= (LIP.voidPhaseUntil or 0) then
            if LIP.voidPhase == "in" then
                LIP.voidPhase = "out"; LIP.voidPhaseUntil = now + (opts.outTime or 0.5)
            else
                LIP.voidPhase = "in"; LIP.voidPhaseUntil = now + (opts.inTime or 0.5)
                -- al ENTRAR al void: reload si el cargador está gastado (recargás escondido)
                if opts.voidReload and not LIP.reloading and (LIP.shotsFired or 0) >= (Weapon.magSize() or 15) then
                    Weapon.reload()
                end
            end
        end
        if LIP.voidPhase == "in" then
            local goCF = patternCF(opts.dist or 1000, opts.pattern)
            LIP.spoofFakePos = goCF.Position
            LIP.voidShootOk = false                    -- disparo pausado en el void
            spoofTo(root, cam, goCF, opts.connExploit)
        else
            -- OUT VOID: server te ve en tu pos REAL → disparás desde acá
            if LIP.spoofOn or LIP.connRep then Spoof.stop(cam) end
            LIP.spoofFakePos = nil
            LIP.voidShootOk = true
        end
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
    local function updateViz()
        -- viz cuando hay pos spoofeada por CUALQUIER método (desync spoofOn o connection weld connRep)
        if not (T("VoidViz") and (LIP.spoofOn or LIP.connRep) and LIP.spoofFakePos) then return hideViz() end
        ensureViz()
        local c = O("VizColor") or Color3.fromRGB(202,151,161)
        local pos = LIP.spoofFakePos
        vizPart.Transparency = 0.3; vizPart.Position = pos; vizPart.Color = c; vizBillboard.Enabled = true
        if vizBillboard:FindFirstChildOfClass("TextLabel") then vizBillboard:FindFirstChildOfClass("TextLabel").TextColor3 = c end
        tracer.Color = c; dot.Color = c
        local cam = Workspace.CurrentCamera
        local sp, on = cam:WorldToViewportPoint(pos)
        if on then
            local vp = cam.ViewportSize
            tracer.From = Vector2.new(vp.X/2, vp.Y); tracer.To = Vector2.new(sp.X, sp.Y); tracer.Visible = true
            dot.Position = Vector2.new(sp.X, sp.Y); dot.Visible = true
        else tracer.Visible = false; dot.Visible = false end
    end

    function Void.init()
        Spoof.init()
        LIP.onCleanup(function()
            if vizPart then pcall(function() vizPart:Destroy() end) end
            if tracer then pcall(function() tracer:Remove() end) end
            if dot then pcall(function() dot:Remove() end) end
        end)
        LIP.track(RunService.RenderStepped:Connect(function() pcall(updateViz) end))
    end

    return Void
end
