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

    -- driver único (RenderStepped, compartido Strafe/Void):
    --  (1) restore del cuerpo real tras la replicación del desync (__index).
    --  (2) TRACKING del connection weld: connPart sigue al target (o a una pos fija) en RENDER, donde la
    --      CFrame del target ya está interpolada SUAVE → cero jitter (a diferencia de Heartbeat).
    function Spoof.init()
        Spoof.install()
        if getgenv().__LIP_RESTORE then return end
        getgenv().__LIP_RESTORE = true
        LIP.track(RunService.RenderStepped:Connect(function()
            local D = getgenv().LIP
            if not D then return end
            -- (1) desync restore
            local root = D.cachedRoot
            if root and root.Parent and D.spoofRestore then
                pcall(function()
                    root.CFrame = D.spoofRestore
                    if D.spoofVel then root.AssemblyLinearVelocity = D.spoofVel end
                end)
                D.spoofRestore = nil
            end
            -- (2) connection weld tracking (server te ve en connPart; cuerpo real NUNCA se escribe)
            if D.connRep and D.connPart then
                local tr = D.connTargetHRP
                if tr and tr.Parent then
                    -- pos del target (suave) + offset de config (radius/height/mode). SIN rotación (identidad)
                    pcall(function() D.connPart.CFrame = CFrame.new(tr.Position + (D.connOffsetVec or Vector3.zero)) end)
                elseif D.connStaticPos then
                    pcall(function() D.connPart.CFrame = CFrame.new(D.connStaticPos) end)
                end
                D.spoofFakePos = D.connPart.Position
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

    -- CONNECTION WELD EXPLOIT: el server replica tu pos desde PhysicsRepRootPart. Apuntándolo a connPart
    -- (anclado, network-owned por vos), el server te ve en connPart.CFrame mientras tu CUERPO REAL queda
    -- LIBRE (nunca escribimos root.CFrame → sin pelea de física, sin restore, sin jitter). connPart se
    -- posiciona en RENDER (Spoof.init loop): pegado al HRP del target + offset = sync PERFECTO.
    local sethidden = sethiddenproperty
    local function armPhysRep()
        local r = myRoot()
        if r and sethidden and LIP.connPart and not LIP.connRep then
            pcall(function() sethidden(r, "PhysicsRepRootPart", LIP.connPart) end)
            LIP.connRep = true
        end
    end
    -- SOLDAR AL TARGET: el server te ve en target.Position + offsetVec (radius/height/mode). El tracking
    -- real lo hace el loop de RENDER contra la CFrame SUAVE del target (cero jitter). Coexiste con pos spoof.
    function Spoof.weldToTarget(targetHRP, offsetVec)
        if not (targetHRP and targetHRP.Parent) then return end
        LIP.connTargetHRP = targetHRP
        LIP.connOffsetVec = offsetVec or Vector3.zero
        LIP.connStaticPos = nil
        -- set inmediato (evita 1 frame de connPart viejo antes del render)
        if LIP.connPart then pcall(function() LIP.connPart.CFrame = CFrame.new(targetHRP.Position + LIP.connOffsetVec) end) end
        armPhysRep()
    end
    -- SOLDAR A UNA POS FIJA (void spam: sin target, pos absoluta lejana). El render mantiene connPart ahí.
    function Spoof.weldToPos(pos)
        LIP.connTargetHRP = nil
        LIP.connStaticPos = pos
        if LIP.connPart then pcall(function() LIP.connPart.CFrame = CFrame.new(pos) end) end
        armPhysRep()
    end
    function Spoof.unweld()
        local r = myRoot()
        if r and sethidden then pcall(function() sethidden(r, "PhysicsRepRootPart", r) end) end
        LIP.connRep = false; LIP.connTargetHRP = nil; LIP.connStaticPos = nil; LIP.connOffsetVec = nil
    end
    -- corta SOLO el desync __index (restaura el cuerpo real) SIN tocar el connection weld → permite
    -- la transición desync→conn en el mismo target sin perder el weld (harmonía pedida por el usuario).
    function Spoof.stopDesyncOnly(cam)
        if LIP.spoofOn then
            local r = myRoot()
            if r and LIP.spoofRealCF then pcall(function() r.CFrame = LIP.spoofRealCF end) end
        end
        LIP.spoofOn = false; LIP.spoofRealCF = nil; LIP.spoofRestore = nil; LIP.spoofVel = nil
        if cam then Spoof.camToChar(cam) end
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

    -- captura la CF real para arrancar/mantener el desync, con guard anti-corrupción.
    -- BUG que arregla: si un frame se pierde el restore (RenderStepped no corrió / cuerpo quedó en la fakePos),
    -- trueCF leería la fakePos como "real" → spoofRealCF se corrompe → el teleport final (stop) te manda a la
    -- pos spoofeada (quedás 5000 studs fuera del mapa). Pasa raro pero es fatal.
    -- Defensa: mid-desync, si el trueCF (a) saltó >400 studs vs el último real bueno, o (b) cae pegado a la
    -- fakePos actual → estamos leyendo la fakePos, no la real → devolver el último real bueno (nunca corromper).
    function Spoof.captureReal(root)
        local tc = Spoof.trueCF(root)
        if LIP.spoofOn and LIP.spoofRealCF then
            local last = LIP.spoofRealCF
            if (tc.Position - last.Position).Magnitude > 400 then return last end
            if LIP.spoofFakePos and (tc.Position - LIP.spoofFakePos).Magnitude < 30 then return last end
        end
        return tc
    end

    function Spoof.camToLocal(cam, realCF)
        -- ancla la cámara a la pos REAL, subida un poco (+2.5 studs) → mejor visión durante el pos spoof.
        if LIP.camAnchor then pcall(function() LIP.camAnchor.CFrame = realCF + Vector3.new(0, 2.5, 0); cam.CameraSubject = LIP.camAnchor end) end
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
