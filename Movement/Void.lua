-- Movement/Void.lua — FACTORY. Void spam (anti-aim posicional) + visualizador.
-- NO toca el vacío (Y baja = muerte). Manda la posición SPOOFEADA (server-seen) a ALTO y a
-- posiciones LEJANAS en patrones (orbita lejana / random / tween / TP spots). Usa el desync de
-- Combat/Spoof: el cuerpo/cámara reales NO se mueven, solo la pos que ve el server.
-- Visualizador: Part neón + BillboardGui icono + tracer Drawing a la pos spoofeada.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Spoof = require("Combat.Spoof")
    local Void = {}

    local function myRoot() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end

    -- presets: distancia XZ, altura, patrón
    Void.PRESETS = {
        High        = { pattern = "High",   height = 300,  dist = 0,    speed = 1 },
        FarOrbit    = { pattern = "Orbit",  height = 200,  dist = 400,  speed = 8 },
        RandomFar   = { pattern = "Random", height = 250,  dist = 600,  speed = 30 },
        TweenPoints = { pattern = "Tween",  height = 180,  dist = 350,  speed = 4 },
    }
    function Void.applyPreset(name)
        local p = Void.PRESETS[name]; if not p then return end
        local Op = Lib.Options
        if Op.VoidPattern then Op.VoidPattern:SetValue(p.pattern) end
        if Op.VoidHeight  then Op.VoidHeight:SetValue(p.height) end
        if Op.VoidDist    then Op.VoidDist:SetValue(p.dist) end
        if Op.VoidSpeed   then Op.VoidSpeed:SetValue(p.speed) end
    end

    local seed = 0
    local TWEEN = { Vector3.new(1,0,1), Vector3.new(-1,0,1), Vector3.new(-1,0,-1), Vector3.new(1,0,-1) }
    local function patternPos(realPos, opts)
        local h, d, spd = opts.height or 250, opts.dist or 400, opts.speed or 8
        local pat = opts.pattern or "Orbit"
        if pat == "High" then
            return realPos + Vector3.new(0, h, 0)
        elseif pat == "Random" then
            seed = seed + spd * 0.02
            local a, b = math.noise(seed, 0) * math.pi * 2, math.noise(0, seed)
            return realPos + Vector3.new(math.cos(a) * d, h + b * h * 0.3, math.sin(a) * d)
        elseif pat == "Tween" then
            seed = seed + spd * 0.01
            local i = (math.floor(seed) % #TWEEN) + 1
            local j = (i % #TWEEN) + 1
            local f = seed - math.floor(seed)
            local off = TWEEN[i]:Lerp(TWEEN[j], f) * d
            return realPos + Vector3.new(off.X, h, off.Z)
        else -- Orbit
            seed = seed + spd * 0.03
            return realPos + Vector3.new(math.cos(seed) * d, h, math.sin(seed) * d)
        end
    end

    function Void.tick(opts)
        local root = myRoot(); local cam = Workspace.CurrentCamera
        if not root then Spoof.stop(cam); return end
        local realCF = Spoof.trueCF(root)
        LIP.cachedRoot   = root
        LIP.spoofRealCF  = realCF
        LIP.spoofOn      = true
        LIP.spoofVel     = root.AssemblyLinearVelocity
        LIP.spoofRestore = realCF
        Spoof.camToLocal(cam, realCF)
        local goPos = patternPos(realCF.Position, opts)
        LIP.spoofFakePos = goPos
        pcall(function() root.CFrame = CFrame.new(goPos) end)
    end

    -- ── VISUALIZADOR ──────────────────────────────────────────────────────────
    local vizPart, vizBillboard, tracer, dot
    local function ensureViz()
        if not vizPart or not vizPart.Parent then
            vizPart = Instance.new("Part")
            vizPart.Name = "LIP_SpoofViz"; vizPart.Shape = Enum.PartType.Ball
            vizPart.Material = Enum.Material.Neon; vizPart.Color = Color3.fromRGB(202,151,161)
            vizPart.Size = Vector3.new(2,2,2); vizPart.Anchored = true; vizPart.CanCollide = false
            vizPart.Transparency = 0.3
            pcall(function() vizPart.Parent = Workspace end)
            local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(60,20)
            bb.AlwaysOnTop = true; bb.StudsOffset = Vector3.new(0,1.5,0); bb.Parent = vizPart
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
        if not (T("VoidViz") and LIP.spoofOn and LIP.spoofFakePos) then return hideViz() end
        ensureViz()
        local pos = LIP.spoofFakePos
        vizPart.Transparency = 0.3; vizPart.Position = pos; vizBillboard.Enabled = true
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
