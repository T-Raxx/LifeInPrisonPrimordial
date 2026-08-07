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
        -- FIX freeze-tras-reload: el restore loop está tracked (se DESCONECTA en Unload), pero el guard
        -- getgenv persistía → en el re-load Spoof.init hacía return y NO recreaba el loop → sin restore el
        -- cuerpo queda pegado a la fakePos y la cámara se congela raro. Limpiar el guard en cleanup lo recrea.
        LIP.onCleanup(function() getgenv().__LIP_RESTORE = nil end)
        LIP.track(RunService.RenderStepped:Connect(function(dt)
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
            -- (2) connection weld tracking (server te ve en connPart; cuerpo real NUNCA se escribe).
            -- El ORBIT se computa AQUÍ (render, no Heartbeat) contra la pos SUAVE del target → cero jitter.
            -- SIN rotación (identidad) → el weld ya sigue al target por posición; no doble-aplicamos rotación.
            if D.connRep and D.connPart then
                local tr = D.connTargetHRP
                if tr and tr.Parent then
                    local off = D.connOffsetVec
                    if D.connOrbit then off = Spoof.orbitOffset(D.connOrbit, dt) end   -- orbit smooth por-frame
                    pcall(function() D.connPart.CFrame = CFrame.new(tr.Position + (off or Vector3.zero)) end)
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
    -- SOLDAR AL TARGET: el server te ve en target.Position + orbit (radius/speed/height/mode). El tracking +
    -- el orbit corren en RENDER contra la CFrame SUAVE del target (cero jitter, no depende del Heartbeat).
    -- `orbit` = tabla {radius,speed,height,mode} (orbit smooth por-frame) o Vector3 (offset fijo). Coexiste
    -- con pos spoof (harmonía): el cuerpo real NUNCA se escribe → sin fling, sin pausa clientside.
    function Spoof.weldToTarget(targetHRP, orbit)
        if not (targetHRP and targetHRP.Parent) then return end
        LIP.connTargetHRP = targetHRP
        LIP.connStaticPos = nil
        if typeof(orbit) == "Vector3" then
            LIP.connOrbit = nil; LIP.connOffsetVec = orbit
        elseif type(orbit) == "table" then
            LIP.connOrbit = orbit; LIP.connOffsetVec = nil
        end
        -- set inmediato (evita 1 frame de connPart viejo antes del render)
        if LIP.connPart then
            local off = LIP.connOffsetVec or (LIP.connOrbit and Spoof.orbitOffset(LIP.connOrbit, 0)) or Vector3.zero
            pcall(function() LIP.connPart.CFrame = CFrame.new(targetHRP.Position + off) end)
        end
        armPhysRep()
    end
    -- SOLDAR A UNA POS FIJA (void spam / bait: sin target, pos absoluta). El render mantiene connPart ahí.
    function Spoof.weldToPos(pos)
        LIP.connTargetHRP = nil
        LIP.connOrbit = nil
        LIP.connStaticPos = pos
        if LIP.connPart then pcall(function() LIP.connPart.CFrame = CFrame.new(pos) end) end
        armPhysRep()
    end
    function Spoof.unweld()
        -- cortar el tracking YA (el render deja de mover connPart)
        LIP.connRep = false; LIP.connTargetHRP = nil; LIP.connStaticPos = nil
        LIP.connOffsetVec = nil; LIP.connOrbit = nil
        -- RESTAURAR el connection a vos mismo: un solo set de PhysicsRepRootPart puede NO pegar (timing de red)
        -- → quedarías soldado al target tras terminar el strafe / untoggle. Pulso: reafirmar self varios frames.
        if sethidden then
            task.spawn(function()
                for _ = 1, 10 do
                    local rr = myRoot()
                    if rr then pcall(function() sethidden(rr, "PhysicsRepRootPart", rr) end) end
                    task.wait()
                end
            end)
        end
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

    -- OFFSET del orbit para el connection weld, computado por-FRAME en el render (ángulo continuo por dt →
    -- suave, independiente del framerate/Heartbeat). WORLD-space (no sigue la rotación del target: el weld ya
    -- lo sigue por posición). Normal=círculo, Spiral=hélice 3D (lento), Behind=world -Z fijo, Random=noise.
    local connAng = 0
    function Spoof.orbitOffset(o, dt)
        dt = dt or (1/60)
        connAng = connAng + (o.speed or 4) * dt * 0.9
        local R, h, mode = o.radius or 10, o.height or 0, o.mode or "Normal"
        if mode == "Spiral" then
            local vAmp = (math.abs(h) > 0.1) and math.abs(h) or 6     -- amplitud vertical de la hélice
            return Vector3.new(math.cos(connAng) * R, math.sin(connAng * 0.5) * vAmp, math.sin(connAng) * R)
        elseif mode == "Behind" then
            return Vector3.new(0, h, -R)                              -- detrás en world-space (sin jitter de rotación)
        elseif mode == "Random" then
            return Vector3.new(math.noise(connAng, 0) * R, h + math.noise(0, connAng) * R * 0.4, math.noise(connAng, connAng) * R)
        else -- Normal: círculo
            return Vector3.new(math.cos(connAng) * R, h, math.sin(connAng) * R)
        end
    end

    function Spoof.camToLocal(cam, realCF)
        -- ancla la cámara a la pos REAL, subida un poco (+2.5 studs) → mejor visión durante el pos spoof.
        -- CameraSubject solo se escribe si CAMBIÓ (setearlo cada frame resetea el estado de la cámara default
        -- y al alternar con el humanoid = churn = freeze raro).
        if LIP.camAnchor then pcall(function()
            LIP.camAnchor.CFrame = realCF + Vector3.new(0, 2.5, 0)
            if cam.CameraSubject ~= LIP.camAnchor then cam.CameraSubject = LIP.camAnchor end
        end) end
    end
    function Spoof.camToChar(cam)
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() if cam.CameraSubject ~= hum then cam.CameraSubject = hum end end) end
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
