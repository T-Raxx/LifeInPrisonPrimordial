-- Combat/Spoof.lua — FACTORY. Desync / pos-spoof por HOOK (cuerpo y cámara reales NO se mueven).
-- __index hook: al leer CFrame/Position del root local mientras spoofOn, devuelve la CF REAL → el
-- juego/AC/cámara ven la posición real y CONSISTENTE (Position==CFrame.Position, no dispara
-- CFrameReadHook). El driver escribe una CF FALSA al root (Roblox la replica al server por network
-- ownership) y la restaura el frame siguiente. Cámara anclada a un Part en la pos real. RELOAD-SAFE.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local Workspace  = game:GetService("Workspace")
    local RunService = game:GetService("RunService")
    local LP = Players.LocalPlayer
    local hookmm    = hookmetamethod
    local newcc     = newcclosure or function(f) return f end
    local Spoof = {}

    local function myRoot() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end

    -- driver único de restore: tras la replicación, devolver el cuerpo real (compartido Strafe/Void)
    function Spoof.init()
        Spoof.install()
        if getgenv().__LIP_RESTORE then return end
        getgenv().__LIP_RESTORE = true
        LIP.track(RunService.RenderStepped:Connect(function()
            local D = getgenv().LIP
            local root = D and D.cachedRoot
            if root and root.Parent and D.spoofRestore then
                pcall(function()
                    root.CFrame = D.spoofRestore
                    if D.spoofVel then root.AssemblyLinearVelocity = D.spoofVel end
                end)
                D.spoofRestore = nil
            end
        end))
    end

    -- anclas persistentes (cam + connection-weld). Sobreviven reload.
    function Spoof.ensureParts()
        if not getgenv().__LIP_CamAnchor or not getgenv().__LIP_CamAnchor.Parent then
            local p = Instance.new("Part")
            p.Name = "LIP_CamAnchor"; p.Anchored = true; p.CanCollide = false
            p.Transparency = 1; p.Size = Vector3.new(2, 2, 1)
            pcall(function() p.Parent = Workspace end)
            getgenv().__LIP_CamAnchor = p
        end
        if not getgenv().__LIP_ConnPart or not getgenv().__LIP_ConnPart.Parent then
            local p = Instance.new("Part")
            p.Name = "LIP_Conn"; p.Anchored = true; p.CanCollide = false
            p.Transparency = 1; p.Size = Vector3.new(2, 2, 1)
            pcall(function() p.Parent = Workspace end)
            getgenv().__LIP_ConnPart = p
        end
        LIP.camAnchor = getgenv().__LIP_CamAnchor
        LIP.connPart  = getgenv().__LIP_ConnPart
    end

    -- CONNECTION WELD EXPLOIT: el server replica la pos del root desde PhysicsRepRootPart. Apuntándolo
    -- a connPart, el server te ve en connPart.CFrame mientras tu CUERPO REAL queda LIBRE (sin escribir
    -- root.CFrame, sin pelea de física, sin restore). Camina/dispara normal; el server te ve en el weld.
    local sethidden = sethiddenproperty
    function Spoof.weldTo(goCF)
        local r = myRoot()
        if r and sethidden and LIP.connPart then
            pcall(function()
                LIP.connPart.CFrame = goCF
                sethidden(r, "PhysicsRepRootPart", LIP.connPart)
            end)
            LIP.connRep = true
        end
    end
    function Spoof.unweld()
        local r = myRoot()
        if r and sethidden then pcall(function() sethidden(r, "PhysicsRepRootPart", r) end) end
        LIP.connRep = false
    end

    function Spoof.install()
        Spoof.ensureParts()
        if getgenv().__LIP_IDX then return end
        local orig
        local ok = pcall(function()
            orig = hookmm(game, "__index", newcc(function(self, key)
                local D = getgenv().LIP
                if D and D.spoofOn and self == D.cachedRoot and D.spoofRealCF then
                    if key == "CFrame" then return D.spoofRealCF end
                    if key == "Position" then return D.spoofRealCF.Position end
                end
                return orig(self, key)
            end))
        end)
        if ok then getgenv().__LIP_IDX = true; getgenv().__LIP_ORIG_INDEX = orig end
    end

    -- lee la CF VERDADERA saltándose el hook
    function Spoof.trueCF(root)
        local o = getgenv().__LIP_ORIG_INDEX
        return (o and o(root, "CFrame")) or root.CFrame
    end

    function Spoof.camToLocal(cam, realCF)
        if LIP.camAnchor then pcall(function() LIP.camAnchor.CFrame = realCF; cam.CameraSubject = LIP.camAnchor end) end
    end
    function Spoof.camToChar(cam)
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() cam.CameraSubject = hum end) end
    end

    -- corta cualquier spoof/weld y restaura cámara + cuerpo a la pos real
    function Spoof.stop(cam)
        if LIP.spoofOn then
            local r = myRoot()
            if r and LIP.spoofRealCF then pcall(function() r.CFrame = LIP.spoofRealCF end) end
        end
        if LIP.connRep then Spoof.unweld() end
        LIP.spoofOn = false; LIP.spoofRealCF = nil; LIP.spoofRestore = nil; LIP.spoofVel = nil
        LIP.spoofFakePos = nil
        if cam then Spoof.camToChar(cam) end
    end

    return Spoof
end
