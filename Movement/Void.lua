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
    local Spoof = require("Combat.Spoof")
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

    -- calcula la pos+rot absoluta random (muy lejos del origen 0,100,0)
    local function randomFar(dist)
        local pos = ORIGIN + Vector3.new(rndSigned() * dist, rndSigned() * dist * 0.5, rndSigned() * dist)
        local rot = CFrame.Angles(rnd() * 6.2831, rnd() * 6.2831, rnd() * 6.2831)
        return CFrame.new(pos) * rot
    end

    function Void.tick(opts)
        local root = myRoot(); local cam = Workspace.CurrentCamera
        if not root then Spoof.stop(cam); return end
        local dist = opts.dist or 1000
        local goCF = randomFar(dist)
        LIP.spoofFakePos = goCF.Position

        if opts.posSpoof then
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
            if LIP.spoofOn then Spoof.stop(cam) end
            pcall(function() root.CFrame = goCF; root.AssemblyLinearVelocity = Vector3.zero end)
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
