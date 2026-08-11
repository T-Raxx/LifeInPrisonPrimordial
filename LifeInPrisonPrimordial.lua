-- LifeInPrisonPrimordial bundle self-contained (PrimordialUI inline). No editar a mano.
-- LifeInPrisonPrimordial — bundle generado por build.lua. No editar a mano.
local _MODS = {}
_MODS["Core.State"] = (function()
-- Core/State.lua — FACTORY. Estado global único getgenv().LIP, tracking de conns/hooks,
-- Unload, guard doble-carga, helper fire(op,...) del RemoteEvent multiplexado (netevgen).
-- (el param LIP se ignora aquí: State ES quien crea LIP y lo pone en getgenv)
return function(require, _unused, Lib)
    -- neutralizar build viejo ANTES de nada (hooks stale deben pasar transparentes)
    if getgenv().LIP then
        local old = getgenv().LIP
        old.enabled = false
        old.swapOn  = false          -- __namecall silent-aim viejo pasa transparente
        if old.Unload then pcall(old.Unload) end
    end

    local RS = game:GetService("ReplicatedStorage")

    local LIP = {
        enabled   = false,           -- master del engine
        swapOn    = false,           -- silent aim arg-swap activo
        target    = nil,             -- Player resuelto
        conns     = {},              -- RBXScriptConnections trackeadas
        cleanups  = {},              -- funciones de limpieza (destruir instancias en Unload)
        -- refs cacheadas del framework netevgen (1 RemoteEvent multiplexado, opcode=arg1)
        Events    = RS:FindFirstChild("Events"),
    }
    LIP.RE = LIP.Events and LIP.Events:FindFirstChild("RemoteEvent")
    getgenv().LIP = LIP

    -- dispara el RemoteEvent multiplexado con opcode + payload (client→server). Único punto de salida.
    function LIP.fire(op, ...)
        if LIP.RE then LIP.RE:FireServer(op, ...) end
    end

    -- dispara el OnClientEvent LOCAL (el dispatcher del juego rutea por opcode=arg1). Se usa para
    -- entrar por caminos "sancionados" del cliente (ej. buffs op47 → ruta graceada, sin flag AC).
    local firesig = firesignal or replicatesignal
    function LIP.fireLocal(op, ...)
        if LIP.RE and firesig then pcall(firesig, LIP.RE.OnClientEvent, op, ...) end
    end
    LIP.hasFireLocal = firesig ~= nil

    function LIP.track(c) LIP.conns[#LIP.conns + 1] = c ; return c end
    function LIP.onCleanup(fn) LIP.cleanups[#LIP.cleanups + 1] = fn ; return fn end

    function LIP.Unload()
        LIP.enabled, LIP.swapOn = false, false
        for _, fn in ipairs(LIP.cleanups) do pcall(fn) end   -- destruir instancias (fly BV, etc.)
        LIP.cleanups = {}
        for _, c in ipairs(LIP.conns) do pcall(function() c:Disconnect() end) end
        LIP.conns = {}
        -- los hooks (__namecall) NO se desinstalan (hookmetamethod); pasan transparentes
        -- porque leen getgenv().LIP dinámico y queda swapOn=false.
        if LIP.Library then pcall(function() LIP.Library:Unload() end) end
    end

    return LIP
end

end)()
_MODS["Net"] = (function()
-- Net.lua — FACTORY. UN solo __namecall hook unificado (regla LiP: 1 hook, no apilar).
-- Passive, PRECACHE model: el driver (main) computa afuera del hook los targets; el hook
-- SOLO escribe arrays (cero reentrancy → no rompe la secuencia síncrona del disparo).
--
-- Firmas (v48, RemoteEvent multiplexado netevgen, opcode=arg1):
--   op14 FirearmBullets: FireServer(14, Tool, bullets, GST)   bullets[i]={org,muz,hitPos,hitPart,partPos,objspace}
--   op16 OnMeleeRemote : FireServer(16, Tool, GST, hitPart, objspace)
-- GST() lo genera el cliente (stub/token) → lo dejamos intacto, solo redirigimos el HIT.
-- Reload-safe: hook instalado UNA vez (flag getgenv), lee getgenv().LIP dinámico.
return function(require, LIP, Lib)
    local Net = {}
    local getncm  = getnamecallmethod
    local newcc   = newcclosure or function(f) return f end
    local hookmm  = hookmetamethod
    local unpackf = table.unpack or unpack
    local ZERO    = Vector3.zero

    function Net.install()
        LIP.RE = LIP.RE or (LIP.Events and LIP.Events:FindFirstChild("RemoteEvent"))
        if getgenv().__LIP_HOOK then return end
        local orig
        local ok = pcall(function()
            orig = hookmm(game, "__namecall", newcc(function(self, ...)
                local D = getgenv().LIP
                if D and self == D.RE and getncm() == "FireServer" then
                    local p = table.pack(...)
                    local op = p[1]
                    -- marca del último disparo (juego O nuestro) → HitEffects correlaciona con la pérdida
                    -- de vida del enemigo para detectar hits/kills.
                    if op == 14 then D.lastShotT = os.clock() end
                    -- OBSERVA FIRERATE REAL (op14 del juego, no nuestro autofire) → no sobre-disparar.
                    -- (El conteo de balas para el reload vive en Weapon.fireOne, NO acá: este hook
                    --  persiste entre reloads y no se puede actualizar sin rejoin limpio.)
                    if op == 14 and not D._selfFiring then
                        -- PELLET COUNT por arma: las escopetas (SPAS/DB) mandan N pellets por tiro. Lo aprendemos
                        -- del op14 REAL del juego (dispará 1 vez con la escopeta) → el autofire replica N pellets.
                        do
                            local bl, wt = p[3], p[2]
                            if type(bl) == "table" and #bl >= 1 and typeof(wt) == "Instance" then
                                D.pelletsByWeapon = D.pelletsByWeapon or {}
                                D.pelletsByWeapon[wt.Name] = #bl
                            end
                        end
                        local now = os.clock()
                        if D._lastRealShot then
                            local dt = now - D._lastRealShot
                            if dt > 0.02 and dt < 2 then D.observedFirerate = dt end
                        end
                        D._lastRealShot = now
                    end
                    -- DETECCIÓN de cargador + TIEMPO DE RELOAD del juego (op42 MagDrop → op40 OnReload):
                    -- el delta = la duración real de la anim de recarga → la usamos para que nuestro auto-reload
                    -- matchee (op40 muy temprano/tarde = server rechaza = munición no se rellena = balas rojas).
                    if op == 42 and not D._selfReload then D._magDropT = os.clock() end
                    if op == 40 and not D._selfReload then
                        local mag, wtool = p[3], p[2]
                        if type(mag) == "number" and mag >= 2 and mag <= 200 and typeof(wtool) == "Instance" then
                            D.magByWeapon = D.magByWeapon or {}
                            D.magByWeapon[wtool.Name] = mag
                        end
                        if D._magDropT then
                            local rt = os.clock() - D._magDropT
                            if rt > 0.3 and rt < 6 then D.observedReloadTime = rt end
                            D._magDropT = nil
                        end
                    end
                    -- op14: SILENT AIM (redirige al target) + BULLET MULTIPLIER (padea el array a N pellets).
                    -- Se aplica al op14 del JUEGO (mouse1) y al nuestro → N× daño por disparo LEGAL (mismo
                    -- GST/firerate/timing del juego = sin rate-limit, sin unequip). Escopetas: suma pellets.
                    if op == 14 then
                        local bullets = p[3]
                        local mult = D.bulletMult or 1
                        local swap = D.swapOn and D.cachedHitPart and D.cachedHitPos
                        if type(bullets) == "table" and (swap or mult > 1) then
                            -- 1) redirige los existentes al target (silent aim)
                            if swap then
                                for i = 1, #bullets do
                                    local b = bullets[i]
                                    if type(b) == "table" then
                                        b[3] = D.cachedHitPos; b[4] = D.cachedHitPart; b[5] = D.cachedHitPos; b[6] = ZERO
                                        if D.wallbang and D.cachedOrigin then b[1] = D.cachedOrigin; b[2] = D.cachedOrigin end
                                    end
                                end
                            end
                            -- 2) MULTIPLICADOR: clona el array hasta #bullets*mult (cada clon = bala nueva)
                            local base = #bullets
                            if mult > 1 and base > 0 then
                                for k = 1, base * (mult - 1) do
                                    local s = bullets[((k - 1) % base) + 1]
                                    if type(s) == "table" then
                                        bullets[base + k] = { s[1], s[2], s[3], s[4], s[5], s[6] }
                                    end
                                end
                            end
                            return orig(self, unpackf(p, 1, p.n))
                        end
                    -- MELEE AURA (op16): redirige el hitPart al target de melee cacheado
                    elseif op == 16 and D.meleeOn and D.meleePart then
                        p[4] = D.meleePart                   -- hitPart
                        p[5] = ZERO                          -- objspace (centro)
                        return orig(self, unpackf(p, 1, p.n))
                    -- TURRET silent aim (op56, fase 2 = fire): swap el hit-table al target (mismo formato)
                    elseif op == 56 and p[3] == 2 and D.swapOn and D.cachedHitPart and D.cachedHitPos then
                        local hits = p[4]
                        if type(hits) == "table" then
                            for i = 1, #hits do
                                local hh = hits[i]
                                if type(hh) == "table" then
                                    hh[3] = D.cachedHitPos; hh[4] = D.cachedHitPart; hh[5] = D.cachedHitPos; hh[6] = ZERO
                                end
                            end
                            return orig(self, unpackf(p, 1, p.n))
                        end
                    end
                end
                return orig(self, ...)                        -- passthrough transparente
            end))
        end)
        if ok then
            getgenv().__LIP_HOOK = true
            getgenv().__LIP_ORIG_NAMECALL = orig
        end
    end

    return Net
end

end)()
_MODS["Combat.Target"] = (function()
-- Combat/Target.lua — FACTORY. Selección de target (silent aim + melee/punch).
-- Teams LiP: Police / Prisoners / Criminals. Enemigo = team distinto (teamCheck).
-- Target.pick(opts)      -> silent aim (Crosshair/Distance/Health, FOV, wallcheck) -> LIP.target
-- Target.nearestEnemy(opts) -> melee/punch (más cercano en rango mundo)
return function(require, LIP, Lib)
    local Players   = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Target = {}

    local function alive(char)
        local h = char and char:FindFirstChildOfClass("Humanoid")
        return (h and h.Health > 0) or false, h
    end
    local function visible(part, char)
        local cam = Workspace.CurrentCamera
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { LP.Character, char }
        rp.IgnoreWater = true
        local o = cam.CFrame.Position
        return Workspace:Raycast(o, (part.Position - o), rp) == nil
    end
    local function isFriend(plr)
        local s, r = pcall(function() return LP:IsFriendsWith(plr.UserId) end)
        return s and r
    end
    local function hasFF(char)   -- spawn protection (ForceField) → intocable
        return char and char:FindFirstChildOfClass("ForceField") ~= nil
    end
    -- checks UNIVERSALES de target (team / friend / forcefield). El wallcheck (LOS) va aparte en cada
    -- selector (usa la cámara). Los tres los comparten pick (silent aim) y nearestEnemy (melee/punch).
    local function isEnemy(plr, opts)
        if plr == LP then return false end
        if opts.teamCheck and LP.Team and plr.Team == LP.Team then return false end
        if opts.friendCheck and isFriend(plr) then return false end
        if opts.ffCheck and hasFF(plr.Character) then return false end   -- no enfocar target con FF
        return true
    end
    Target.hasFF = hasFF

    -- silent aim: elige el mejor target según modo. Setea LIP.target.
    function Target.pick(opts)
        local cam = Workspace.CurrentCamera
        local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local mode = opts.mode or "Crosshair"
        local best, bestScore = nil, math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and select(1, alive(char)) and isEnemy(plr, opts) then
                if not (opts.wallcheck and not visible(hrp, char)) then
                    local score
                    if mode == "Crosshair" then
                        local sp, on = cam:WorldToViewportPoint(hrp.Position)
                        if on and sp.Z > 0 then
                            local d = (Vector2.new(sp.X, sp.Y) - Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)).Magnitude
                            if d <= (opts.fov or 1e9) then score = d end
                        end
                    elseif mode == "Health" then
                        local _, hum = alive(char); score = hum and hum.Health or nil
                    else -- "Distance"
                        score = myHRP and (hrp.Position - myHRP.Position).Magnitude or nil
                    end
                    if score and score < bestScore then best, bestScore = plr, score end
                end
            end
        end
        LIP.target = best
        return best
    end

    -- melee/punch: enemigo vivo más cercano dentro de rango (mundo).
    function Target.nearestEnemy(opts)
        local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myHRP then return nil end
        local best, bestD = nil, (opts.range or 12)
        for _, plr in ipairs(Players:GetPlayers()) do
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and select(1, alive(char)) and isEnemy(plr, opts) then
                local d = (hrp.Position - myHRP.Position).Magnitude
                if d <= bestD and (not opts.wallcheck or visible(hrp, char)) then
                    best, bestD = plr, d
                end
            end
        end
        return best
    end

    return Target
end

end)()
_MODS["Combat.Ragdoll"] = (function()
-- Combat/Ragdoll.lua — FACTORY. Self-ragdoll vía opcode 23 (Ragdoll, sin args).
-- Confirmado en vivo (place 72659788689464 v48): Events.RemoteEvent:FireServer(23) TOGGLEA
-- el ragdoll server-side (Running <-> Physics), health intacta. El bind R original está gateado
-- tras IsStudio/IsDevGame en el cliente (debug de dev) → nosotros lo firamos manual.
return function(require, LIP, Lib)
    local Ragdoll = {}
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local LP = Players.LocalPlayer
    local OP = 23

    local lastFire = 0

    local function humState()
        local ch  = LP.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        return hum and hum:GetState()
    end
    -- Physics = ragdolleado
    local function isRagdolled()
        local st = humState()
        return st ~= nil and tostring(st):find("Physics") ~= nil
    end
    Ragdoll.isRagdolled = isRagdolled

    -- toggle manual (botón / keybind): el server flipea en cada fire
    function Ragdoll.toggle()
        LIP.fire(OP)
        lastFire = os.clock()
    end

    -- lock permanente: re-ragdolla cuando el estado sale de Physics.
    -- Event-driven (no spam): solo re-fira si NO está ragdolleado, con intervalo mínimo.
    function Ragdoll.tickLock()
        if isRagdolled() then return end
        local now = os.clock()
        if now - lastFire < 0.6 then return end   -- anti-spam del remote
        lastFire = now
        LIP.fire(OP)
    end

    return Ragdoll
end

end)()
_MODS["Combat.Melee"] = (function()
-- Combat/Melee.lua — FACTORY. Melee/puños.
--  · AUTO-PUNCH (op33 OnPunchRemote): FireServer(33, enemyBasePart). NO usa GST → fire activo.
--    (el cliente legit lo dispara en el .Touched del puño; nosotros lo firamos directo al enemigo.)
--  · MELEE AURA (op16): precache del target; el redirect real lo hace el hook en Net.lua.
return function(require, LIP, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Target = require("Combat.Target")
    local Melee = {}

    local lastPunch = 0

    local function bodyPart(char)
        return char and (char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            or char:FindFirstChild("Head"))
    end

    -- precache del target de melee-aura (corre en el driver, afuera del hook)
    function Melee.cacheMelee(opts)
        if not LIP.meleeOn then LIP.meleePart = nil; return end
        local t = Target.nearestEnemy(opts)
        LIP.meleePart = t and bodyPart(t.Character) or nil
    end

    -- AUTO-PUNCH activo (op33). Enemigo dentro de rango → fire su parte, con rate limit.
    function Melee.autoPunch(opts)
        local now = os.clock()
        if now - lastPunch < (opts.rate or 0.5) then return end
        local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end
        local t = Target.nearestEnemy({ range = opts.range or 8, teamCheck = opts.teamCheck,
                                        friendCheck = opts.friendCheck, wallcheck = false })
        local part = t and bodyPart(t.Character)
        if not part then return end
        lastPunch = now
        LIP.fire(33, part)   -- OnPunchRemote(part) — sin GST
    end

    return Melee
end

end)()
_MODS["Combat.Spoof"] = (function()
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
            -- (el connection weld ya NO se trackea acá: es WeldMenu-style, escribe el cuerpo real en Heartbeat
            --  desde Strafe.tick + PhysicsRepRootPart=target. Ya no hay connPart anclado que seguir.)
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
    -- SOLO la CONEXIÓN: PhysicsRepRootPart = HRP REAL del target (parte de su assembly → el server te replica
    -- adherido a él SIN delay; un part anclado FUERA del assembly no replicaba). Como el Connection Exploit de
    -- symbol: NO escribe tu CFrame → la posición la maneja el desync (spoof, cuerpo quieto) o el real-move.
    function Spoof.setPhysRep(targetHRP)
        local r = myRoot()
        if not (r and targetHRP and targetHRP.Parent) then return end
        if sethidden then pcall(function() sethidden(r, "PhysicsRepRootPart", targetHRP) end) end
        LIP.connRep = true
        LIP.connTargetHRP = targetHRP
    end
    -- WELD que MUEVE el cuerpo real al target.CFrame*offsetCF (WeldMenu-style, para weld SIN spoof) + la conexión.
    function Spoof.weldToTarget(targetHRP, offsetCF)
        local r = myRoot()
        if not (r and targetHRP and targetHRP.Parent) then return end
        pcall(function()
            r.CFrame = targetHRP.CFrame * offsetCF
            r.AssemblyLinearVelocity  = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end)
        Spoof.setPhysRep(targetHRP)
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

end)()
_MODS["Combat.Strafe"] = (function()
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
        if #h.s > MAX then table.remove(h.s, 1); table.remove(h.t, 1) end
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
    Strafe.CONF = { wDom = 0.45, wStab = 0.35, wResid = 0.20, stabThresh = 25, stabK = 6, voidManhattan = 7000,
                    predMaxSpeed = 60, hcWindow = 0.35, hcRate = 0.10, hcRelax = 0.40 }
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
        return (didDefensive and best.pos) or hitbox, didDefensive, score, #t.list
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
        if method == "Density" then
            local p, dd, cnt = resolveDensity(plr, localPos)
            pos, didDef = p or rawPos, dd or false
            score = math.clamp(((cnt or 0) - Strafe.DEN.minMatches) / 8, 0, 1)
            cl = cnt or 0
            state = didDef and "LOCKED" or (p and "RESOLVING" or "VOID")
        else
            local p, dd, sc, n = resolveCluster(plr, rawPos, now, localPos)
            pos, didDef = p, dd
            score = sc or 0; cl = n or 0
            state = dd and "LOCKED" or ((cl > 0) and "RESOLVING" or "NORMAL")
        end
        local sf = updateStability(plr, pos)
        resState[plr] = { pos = pos, didDef = didDef, method = method, score = score, clusters = cl, state = state, frameT = now, stabFrames = sf }
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
        if vel.Magnitude > 200 then vel = Vector3.zero end
        -- PREDICT base + amplitud×velocidad: base = lead constante (comp ping, aún quieto); amp escala con
        -- la velocidad normalizada del target (rápido = más lead). Reemplaza el vel*lead ping/manual.
        local base = O("PredictBase") or 0.10
        local amp  = O("PredictAmp")  or 0.15
        local speedNorm = math.clamp(vel.Magnitude / Strafe.CONF.predMaxSpeed, 0, 1)
        pos = pos + vel * (base + amp * speedNorm)
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
        return math.clamp(C.wDom * sDom + C.wStab * sStab + C.wResid * sResid, 0, 1)
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
        if v and v.vel and v.vel.Magnitude <= 200 then
            local base = O("PredictBase") or 0.10
            local amp  = O("PredictAmp")  or 0.15
            local speedNorm = math.clamp(v.vel.Magnitude / Strafe.CONF.predMaxSpeed, 0, 1)
            pos = pos + v.vel * (base + amp * speedNorm)
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

    local seed = 0
    -- órbita alrededor de un CENTRO, mirando al centro. Normal/Random/Behind.
    local function orbitCF(center, tLook, opts)
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

    -- AUTO-BEST-MODE (innovación): elige el modo de strafe según contexto, al entrar a CHASE. Se guarda en
    -- LIP.strafeMode; solo cambia en el borde del ciclo (LIP.strafeCycleNew) = histéresis natural.
    local function pickBestMode(dist, tvel, spoof)
        if spoof > (O("AutoSpoofThresh") or 0.40) then return "Spiral" end   -- target spoofea fuerte → 3D
        if tvel  > (O("AutoFastThresh")  or 40)   then return "Behind" end   -- rápido → pegado a su espalda
        if dist  > (O("AutoFarThresh")   or 60)   then return "Normal" end   -- lejos → órbita ancha
        return "Random"                                                       -- cerca+estático → máx jitter
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

    -- FSM del ciclo dinámico: CHASE (orbita la resuelta) aroundTime ↔ BAIT (fling void) voidTime. Los presets
    -- setean los timers. Marca LIP.strafeCycleNew al ENTRAR a un CHASE (lo usa el auto-mode para re-elegir).
    local function cycleStep()
        local now = os.clock()
        local preset = O("BaitPreset") or "Timed"
        local aT, vT
        if preset == "Micro" then
            local ping = 0.1; pcall(function() ping = LP:GetNetworkPing() end)
            aT, vT = ping + 0.02, O("VoidTime") or 0.5
        elseif preset == "Spam" then
            aT, vT = 0.06, 0.11
        else
            aT, vT = O("AroundTime") or 3.0, O("VoidTime") or 1.0   -- Timed
        end
        if not LIP.strafePhase or not LIP.strafePhaseUntil then
            LIP.strafePhase = "chase"; LIP.strafePhaseUntil = now + aT; LIP.strafeCycleNew = true
        elseif now >= LIP.strafePhaseUntil then
            if LIP.strafePhase == "chase" then
                LIP.strafePhase = "bait"; LIP.strafePhaseUntil = now + vT
            else
                LIP.strafePhase = "chase"; LIP.strafePhaseUntil = now + aT; LIP.strafeCycleNew = true
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
        -- AUTO-MODE: al ENTRAR a un CHASE nuevo, re-elegir el mejor modo desde el contexto resuelto (histéresis).
        if T("AutoMode") and LIP.strafeCycleNew then
            LIP.strafeCycleNew = false
            local myR = myRoot()
            local dist = (myR and center) and (myR.Position - center).Magnitude or 0
            local rs = resState[target]
            local tvel = Strafe.targetVel(target).Magnitude
            local spoof = (rs and rs.method == "Cluster") and (1 - (rs.score or 0)) or (beh[target] and beh[target].voidFrac or 0)
            LIP.strafeMode = pickBestMode(dist, tvel, spoof)
        end
        if not T("AutoMode") then LIP.strafeMode = nil end

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

end)()
_MODS["Combat.Weapon"] = (function()
-- Combat/Weapon.lua — FACTORY. Auto/Rapid fire (op14) con GST FORJADO.
-- CAUSA REAL del unequip (re-reverse v48 + evidencia de cheater rival 100/s):
--   · El server NO rate-limita por tiempo real, NO gatea por munición (se comprobó: 100 disparos/s
--     con cualquier arma en flujo constante, sin recargar, sin unequip).
--   · El GST = obfuscate(time()) del cliente, SIN nonce/secuencia, y acepta CUALQUIER argumento
--     (u3669 = function(t) return u4162(t or time()) end). El server decodifica el timestamp del GST
--     y valida el DELTA entre disparos consecutivos ≥ firerate. Mandar GST(time()) REAL a 100/s =
--     deltas < firerate = UNEQUIP.
-- FIX (como el rival): forjar el GST con un RELOJ VIRTUAL que avanza por el firerate del arma en cada
--   disparo → el server ve espaciado legal aunque disparemos 100/s reales → sin unequip, cualquier arma.
--   Sin gate de munición (el server no la valida). Reload sigue disponible (botón/keybind) por si acaso.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local Workspace  = game:GetService("Workspace")
    local UIS        = game:GetService("UserInputService")
    local LP = Players.LocalPlayer
    local Weapon = {}
    local Strafe   -- lazy-cached (require("Combat.Strafe")) para fireConfidence en el gate

    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end
    local function char() return LP.Character end
    local function firearm() local c = char(); return c and c:FindFirstChildOfClass("Tool") end  -- equipado (== u3379.Tool)

    -- ── GST(): token {int,int,int} de time() (reimpl exacta de u4162) ──
    local bnot, band, bor = bit32.bnot, bit32.band, bit32.bor
    local lsh, rsh = bit32.lshift, bit32.rshift
    local function GST(t)
        t = t or time()
        local b = buffer.create(8); buffer.writef64(b, 0, t)
        local r = buffer.readu8
        local b0, b1, b2, b3 = r(b, 0), r(b, 1), r(b, 2), r(b, 3)
        local b4, b5, b6, b7 = r(b, 4), r(b, 5), r(b, 6), r(b, 7)
        local x2  = bor(lsh(band(b2, 51), 2),  rsh(band(b2, 204), 2))
        local x3  = bor(rsh(band(b3, 240), 4), lsh(band(b3, 15), 4))
        local x4  = bor(rsh(band(b4, 240), 4), lsh(band(b4, 15), 4))
        local x4b = bor(rsh(band(x4, 204), 2), lsh(band(x4, 51), 2))
        local x4c = bor(rsh(band(x4b, 170), 1), lsh(band(x4b, 85), 1))
        local y7  = bor(rsh(band(b7, 240), 4), lsh(band(b7, 15), 4))
        local y7b = bor(rsh(band(y7, 204), 2), lsh(band(y7, 51), 2))
        local y7c = bor(rsh(band(y7b, 170), 1), lsh(band(y7b, 85), 1))
        local w1 = bor(band(255, bnot(b1)), lsh(band(255, bnot(b6)), 8), lsh(band(255, bnot(b0)), 16), lsh(x3, 24))
        local w2 = bor(y7c, lsh(band(255, bnot(b5)), 8), lsh(x2, 16), lsh(x4c, 24))
        return { w1, w2, bnot(bor(lsh(w1, 8), rsh(w2, 16))) }
    end
    Weapon.GST = GST

    -- ── GST por disparo = TIEMPO REAL (time()) ──
    -- PROBADO EN VIVO (M60, muzzle correcto): 50 disparos/s con GST REAL = 0 unequip. Forjar el timestamp
    -- (reloj virtual) lo INVALIDA → el server valida que el GST decodifique a un time() real/reciente y te
    -- quita el arma si no. NO forjar. El server tampoco rate-limita por tiempo real (50/s pasó limpio) ni
    -- gatea munición estricto (40 disparos > mag SIN recargar = 0 unequip). Solo hay que mandar GST REAL fresco.
    local function nextGST() LIP._gstReal = os.clock(); return GST() end
    Weapon.nextGST = nextGST

    -- DETECCIÓN DE CARGADOR POR ARMA: el Net hook captura `magammo` del op40 del reload REAL del juego
    -- (arg2), keyed por nombre de arma → LIP.magByWeapon[name]. Se aprende al recargar 1 vez (R o auto
    -- del juego). Fallback = slider Mag Size mientras no se detecte.
    local function magSize()
        local tool = firearm()
        local name = tool and tool.Name
        if name and LIP.magByWeapon and LIP.magByWeapon[name] then return LIP.magByWeapon[name] end
        return math.floor(O("ReloadAmmo") or 15)
    end
    Weapon.magSize = magSize

    -- RELOAD con TIMING REAL (manual, botón/keybind). op42 MagDrop → esperar ReloadTime → op40(mag, GST()).
    -- El server valida la duración del reload por el timestamp del GST del op40 (el juego manda el op40
    -- SOLO tras animLen); un reload INSTANTÁNEO (op42→op40 mismo frame) = duración 0 = inválido = UNEQUIP.
    -- Por eso el reload NO es instantáneo. La munición no se gatea estricto (probado), así que el reload es
    -- opcional; existe por si algún arma sí la valida, o para resincronizar el cargador visual del juego.
    function Weapon.reload()
        if LIP.reloading then return end
        local tool = firearm(); if not tool then return end
        local mag = magSize()
        -- duración REAL de la anim de recarga (observada del reload del juego en Net) → el op40 matchea =
        -- el server rellena la munición (si es muy temprano/tarde, rechaza = balas rojas después). Fallback slider.
        local rt  = LIP.observedReloadTime or O("ReloadTime") or 1.2
        LIP.reloading = true
        LIP._selfReload = true               -- Net NO captura magammo de nuestros op40
        LIP._lastReloadReal = os.clock()
        task.spawn(function()
            if T("ShotgunReload") then
                -- ESCOPETA: op40 por bala, espaciado rt/mag (protocolo per-shell)
                for i = 1, mag do
                    local t2 = firearm() or tool
                    pcall(function() LIP.fire(40, t2, i, GST()) end)
                    task.wait(rt / mag)
                end
            else
                -- CARGADOR: MagDrop → esperar la duración REAL de la anim → OnReload(mag)
                pcall(function() LIP.fire(42, tool) end)
                task.wait(rt)
                local t2 = firearm() or tool
                pcall(function() LIP.fire(40, t2, mag, GST()) end)
            end
            LIP._selfReload = false; LIP.shotsFired = 0
            task.wait(0.12)          -- que el op40 registre server-side antes de reanudar (evita balas rojas)
            LIP.reloading = false
        end)
    end
    Weapon.instantReload = Weapon.reload   -- alias UI (botón "Force Reload")

    -- construye el bullet {origin, muzzle, hitPos, hitPart, hitPart.Position, objspace}
    -- origin: si el server te ve en otra pos (desync spoofOn O connection weld connRep), el origin debe ser
    -- esa pos FALSA (spoofFakePos) → origin→hitPos consistente con dónde te ve el server. Si no, disparar
    -- desde la pos real mientras el server te ve en el weld = mismatch = rechazado/unequip. (rival = weld
    -- bajo el target + fire: el origin va del weld). Sin spoof/weld → head real.
    local function buildBullet(hitPart, hitPos)
        local c = char(); local head = c and c:FindFirstChild("Head")
        if not head then return nil end
        local origin = ((LIP.spoofOn or LIP.connRep) and LIP.spoofFakePos)
                       and (LIP.spoofFakePos + Vector3.new(0, 1.5, 0)) or head.Position
        if LIP.wallbang and LIP.cachedOrigin then origin = LIP.cachedOrigin end   -- wallbang: origin con LOS
        local tool = firearm()
        local handle = tool and tool:FindFirstChild("Handle")
        local muzzleAtt = handle and handle:FindFirstChild("Muzzle")
        local muzzle = (muzzleAtt and muzzleAtt.WorldPosition) or origin
        if hitPart then
            local center = hitPart.Position   -- CENTRO exacto + objspace ZERO = HBE-safe (dentro del hitbox)
            return { origin, muzzle, center, hitPart, center, Vector3.zero }
        end
        local cam = Workspace.CurrentCamera
        local dir = cam.CFrame.LookVector * 300
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { c }
        local res = Workspace:Raycast(cam.CFrame.Position, dir, rp)
        if res then
            local inst = res.Instance
            return { origin, muzzle, res.Position, inst, inst.Position, inst.CFrame:PointToObjectSpace(res.Position) }
        end
        return { origin, muzzle, cam.CFrame.Position + dir, nil, nil, nil }
    end

    -- dispara 1 bala op14 al hit dado (con GST fresco). Descuenta ammo. Marca _selfFiring para que
    -- el observador de firerate en Net NO cuente nuestros disparos.
    local function fireOne(hitPart, hitPos, gst)
        local tool = firearm(); if not tool then return false end
        local bullet = buildBullet(hitPart, hitPos)
        if not bullet then return false end
        -- ESCOPETAS: N pellets por tiro al MISMO hit = N× daño. Prioridad: count aprendido (Net, si reinició el
        -- proceso) > slider ShotgunPellets (escopeta detectada por nombre) > 1 (arma normal). El bulletMult multiplica.
        local n = 1
        if tool then
            local nm = tool.Name
            if LIP.pelletsByWeapon and LIP.pelletsByWeapon[nm] then
                n = LIP.pelletsByWeapon[nm]
            elseif nm:find("SPAS") or nm:find("Shotgun") or nm:find("Pump") or nm:find("DB ") then
                n = math.floor(O("ShotgunPellets") or 8)
            end
        end
        local bullets = { bullet }
        for i = 2, n do bullets[i] = { bullet[1], bullet[2], bullet[3], bullet[4], bullet[5], bullet[6] } end
        LIP._selfFiring = true
        LIP.fire(14, tool, bullets, gst or GST())
        LIP._selfFiring = false
        LIP.shotsFired = (LIP.shotsFired or 0) + 1
        LIP.lastFireT = os.clock()   -- hit-confirm: marca de disparo para atribuir HP-drop
        return true
    end

    -- AUTO/RAPID tick (main Heartbeat). Stream de op14 (GST real) CAPEADO al firerate del arma → exceder
    -- el firerate = el server te quita la tool (probado: M9 a 50/s = unequip; M60 = OK porque su firerate
    -- es alto). El DPS extra NO sale de disparar más rápido (rate-limited) sino del BULLET MULTIPLIER (el
    -- Net hook padea el array a N pellets → N× daño por disparo legal). Auto-reload con timing real al
    -- agotar el cargador (op42→wait→op40). observedFirerate se aprende de tus disparos manuales (Net).
    local lastTick = 0
    function Weapon.tickAuto()
        local autoOn  = T("AutoFire") and T("TargetStrafe")   -- autofire SOLO con target strafe activo
        local rapidOn = T("RapidFire") and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if not (autoOn or rapidOn) then LIP.fireAccum = 0; lastTick = 0; return end
        local now = os.clock()
        if LIP.reloading then LIP.fireAccum = 0; lastTick = now; return end
        if LIP.attackHold then LIP.fireAccum = 0; lastTick = now; return end   -- FF/dead: no disparar
        if LIP.awGrabbing then LIP.fireAccum = 0; lastTick = now; return end   -- AutoWeapons grabbing: pausar
        -- VOID SPAM: pausar disparo mientras estás IN void (solo disparar OUT del void)
        if LIP.voidSpamOn and LIP.voidShootOut and not LIP.voidShootOk then LIP.fireAccum = 0; lastTick = now; return end
        -- DYNAMIC STRAFE fase BAIT: tu origin está en el void → el disparo no registra, no quemar balas
        if LIP.strafePhase == "bait" then LIP.fireAccum = 0; lastTick = now; return end
        -- RANGO (solo autofire al target): no firar fuera de rango. ref = pos que ve el server. SPOOF PRIMERO
        -- (igual que el origin del disparo): spoofeado, el server te ve en spoofFakePos (weld/órbita, pegado al
        -- target) → el rango se mide desde ahí. Wallbang solo cuenta si NO estás spoofeado; si no, el gate medía
        -- desde tu cabeza REAL (lejos del target al spoofear) y NO disparaba hasta acercarte físicamente.
        -- didDefensive (resolver confiado) BYPASSA el gate de rango: el resolver ya validó la pos real →
        -- dispará aunque el head crudo esté en el void/lejos (la harmonía autoriza el disparo).
        if autoOn and LIP.cachedHitPos and not LIP.didDefensive then
            local h = char() and char():FindFirstChild("Head")
            local ref = ((LIP.spoofOn or LIP.connRep) and LIP.spoofFakePos)
                        or (LIP.wallbang and LIP.cachedOrigin) or (h and h.Position)
            if ref and (LIP.cachedHitPos - ref).Magnitude > (O("FireRange") or 200) then
                LIP.fireAccum = 0; lastTick = now; return
            end
        end
        -- AUTO-RELOAD al agotar el cargador (timing real, no instantáneo). Solo en AutoFire; con mouse1 el
        -- juego recarga su propia munición.
        -- auto-reload normal (NO si void spam lo maneja: ahí se recarga en el void, escondido)
        if autoOn and T("AutoReload") ~= false and not LIP.voidSpamOn and (LIP.shotsFired or 0) >= magSize() then
            Weapon.reload(); LIP.fireAccum = 0; lastTick = now; return
        end
        -- OBEDECE el firerate REAL del arma equipada. observedFirerate = seg/disparo, aprendido en Net de
        -- los disparos del JUEGO (mantené mouse1 1 vez para calibrar). Disparamos AL firerate con 3% de
        -- margen (nunca exceder = no unequip). Sin calibrar = rate seguro 8/s. AutoFireRate = tope manual.
        -- AUTOFIRE: NO disparar sin un target válido cacheado → si no, buildBullet raycastea la cámara y
        -- salen balas al vacío (tracers rojos = no registran). RapidFire (mouse1) sí dispara a la mira.
        if autoOn and not rapidOn and not LIP.cachedHitPart then LIP.fireAccum = 0; lastTick = now; return end
        local rate
        if LIP.observedFirerate and LIP.observedFirerate > 0.01 then
            rate = 1 / (LIP.observedFirerate * 0.99)
        else
            rate = 8
        end
        rate = math.min(rate, O("AutoFireRate") or 120)
        -- CONFIDENCE GATE (solo con Resolver on): escala el firerate efectivo por la confianza fusionada.
        -- conf < floor (slider Accuracy) → m=0 = aguanta fuego; floor..floor+0.3 → goteo eased (smoothstep); arriba → full.
        local m = 1
        if T("Resolver") and LIP.target then
            Strafe = Strafe or require("Combat.Strafe")
            if LIP.targetExposed then
                -- FIRE OPORTUNISTA: target real/visible (head no-void) → snapshot, saltea piso+estabilidad.
                m = 1; LIP.fireMult = 1
            else
                -- VOID: dispara a la pos recuperada, gateada por confianza. Piso relajado por hit-rate en vivo.
                local conf  = Strafe.fireConfidence(LIP.target)
                local floor = (O("RRAccuracy") or 0.5) * (1 - Strafe.CONF.hcRelax * Strafe.hitAccuracy(LIP.target))
                local hi    = math.min(1, floor + 0.30)
                local u     = (hi > floor) and math.clamp((conf - floor) / (hi - floor), 0, 1) or (conf >= floor and 1 or 0)
                m = u * u * (3 - 2 * u)
                LIP.fireMult = m
                if m < 0.02 then LIP.fireAccum = 0; lastTick = now; return end
            end
        else
            LIP.fireMult = 1
        end
        local dt = (lastTick > 0) and math.min(now - lastTick, 0.1) or 0
        lastTick = now
        LIP.fireAccum = (LIP.fireAccum or 0) + dt * rate * m
        local budget = 0
        while LIP.fireAccum >= 1 and budget < 4 do
            LIP.fireAccum = LIP.fireAccum - 1; budget = budget + 1
            fireOne(LIP.cachedHitPart, LIP.cachedHitPos, nextGST())   -- 1 bala; el hook la multiplica a N
        end
    end

    -- respawn: resetea el contador (el arma nueva viene con el cargador lleno)
    LP.CharacterAdded:Connect(function() LIP.shotsFired = 0; LIP.reloading = false end)

    -- ── DIAGNÓSTICO DE UNEQUIP (solo si WeaponDebug ON) ──────────────────────────
    -- Loguea el estado cuando el server te quita el arma disparando (shots/mag, dest, reload). Off por
    -- defecto para no ensuciar consola; encender con getgenv().LIP.weaponDebug = true.
    local function watchChar(c)
        if not c then return end
        c.ChildRemoved:Connect(function(ch)
            if not (ch:IsA("Tool") and LIP.weaponDebug) then return end
            local firedRecently = LIP._gstReal and (os.clock() - LIP._gstReal) < 1
            if not firedRecently then return end
            task.defer(function()
                local dest = (ch.Parent and ch.Parent.Name) or "nil/destroyed"
                warn(string.format("[LIP][UNEQUIP] arma=%s dest=%s shots=%s/%s reloading=%s sinceReload=%.2fs sinceFire=%.3fs",
                    ch.Name, dest, tostring(LIP.shotsFired), tostring(magSize()), tostring(LIP.reloading),
                    os.clock() - (LIP._lastReloadReal or 0), os.clock() - (LIP._gstReal or 0)))
            end)
        end)
    end
    LP.CharacterAdded:Connect(watchChar)
    watchChar(LP.Character)

    return Weapon
end

end)()
_MODS["Combat.Godmode"] = (function()
-- Combat/Godmode.lua — anti-hit vía self-ragdoll + mover el assembly (RESTAURADO).
-- El HBE NO era esto (era el hitPos offset del disparo, ya fixeado). Reverse: IsRagdoll = campo Lua,
-- gate de disparo solo-cliente → op14 directo dispara ragdolleado (AutoFire lo hace). El anti-hit =
-- mover el HITBOX (Head/Torso/HRP) lejos. Movemos el assembly ENTERO junto (mismo delta, velocidad 0
-- → no estira constraints, no borra partes). Equipar arma ANTES de ragdollear.
return function(require, LIP, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Ragdoll = require("Combat.Ragdoll")
    local God = {}

    local function char() return LP.Character end
    local function hrp() local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end

    -- presets EXTREMOS (height en studs)
    God.PRESETS = {
        High        = { mode = "High",   height = 150 },
        ExtremeHigh = { mode = "High",   height = 800 },
        Jitter      = { mode = "Jitter", height = 250 },
        FarJitter   = { mode = "Jitter", height = 600 },
    }
    function God.applyPreset(name)
        local p = God.PRESETS[name]; if not p then return end
        local Op = Lib.Options
        if Op.GodMode   then Op.GodMode:SetValue(p.mode) end
        if Op.GodHeight then Op.GodHeight:SetValue(p.height) end
    end

    local seed = 0
    -- mueve el assembly ENTERO (mismo delta) + velocidades 0 → no estira constraints, no borra partes
    local function moveAssembly(targetPos)
        local c = char(); local root = hrp(); if not (c and root) then return end
        local delta = targetPos - root.Position
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                pcall(function()
                    p.CFrame = p.CFrame + delta
                    p.AssemblyLinearVelocity = Vector3.zero
                    p.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
    end

    function God.tick()
        if not Ragdoll.isRagdolled() then LIP.fire(23); return end   -- asegura ragdoll on (1 frame)
        local root = hrp(); if not root then return end
        if not LIP.godBase then LIP.godBase = root.Position end
        local mode = O("GodMode") or "High"
        local h = O("GodHeight") or 150
        local base = LIP.godBase
        local pos
        if mode == "Jitter" then
            seed = seed + 1
            pos = base + Vector3.new(math.noise(seed,0) * 80, h + math.noise(0,seed) * 50, math.noise(seed,seed) * 80)
        else -- High: te sube; enemigos apuntan al piso, vos arriba
            pos = base + Vector3.new(0, h, 0)
        end
        moveAssembly(pos)
    end

    function God.stop()
        LIP.godBase = nil
        if Ragdoll.isRagdolled() then LIP.fire(23) end   -- des-ragdoll
    end

    return God
end

end)()
_MODS["Combat.Niche"] = (function()
-- Combat/Niche.lua — FACTORY. Exploits niche (payloads del reverse, docs/exploits-2026-07.md).
--  · Throw spam  op43  OnThrow(tool,1)=arm  →  OnThrow(tool,2,aimMode,targetPos,power)=throw
--  · C4 detonate op44  ItemC4Detonate(tool)  (detona sin delay)
--  · Arrest/cuffs op57 Handcuffs(cuffsTool, targetPlayer)  (validación 8-studs/LOS es client-side → a distancia)
return function(require, LIP, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Target = require("Combat.Target")
    local Niche = {}

    local function char() return LP.Character end
    local function myHRP() local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
    local function equipped() local c = char(); return c and c:FindFirstChildOfClass("Tool") end
    local function findTool(namePart)
        namePart = namePart:lower()
        for _, src in ipairs({ char(), LP:FindFirstChild("Backpack") }) do
            for _, x in ipairs(src and src:GetChildren() or {}) do
                if x:IsA("Tool") and x.Name:lower():find(namePart) then return x end
            end
        end
    end

    -- THROW (op43) al enemigo más cercano
    local lastThrow = 0
    function Niche.throwAt(opts)
        local now = os.clock()
        if now - lastThrow < (opts.rate or 1.0) then return end
        local t = equipped(); local hrp = myHRP(); if not (t and hrp) then return end
        local tgt = Target.nearestEnemy({ range = opts.range or 250, teamCheck = opts.teamCheck, friendCheck = opts.friendCheck })
        local ch = tgt and tgt.Character
        local part = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
        if not part then return end
        lastThrow = now
        local dist = (part.Position - hrp.Position).Magnitude
        local power = math.clamp(dist * 0.5, 1, 25)
        LIP.fire(43, t, 1)                                -- arm
        LIP.fire(43, t, 2, 0, part.Position, power)       -- throw (aimMode 0 = raycast)
    end

    -- C4 (op44) — detona el C4 (busca el tool por nombre)
    function Niche.detonateC4()
        local c4 = findTool("c4")
        if c4 then LIP.fire(44, c4) end
    end

    -- ARREST (op57) — esposa al enemigo más cercano (necesita Handcuffs; ideal Police)
    local lastArrest = 0
    function Niche.arrest(opts)
        local now = os.clock()
        if now - lastArrest < (opts.rate or 1.0) then return end
        local cuffs = findTool("cuff") or findTool("handcuff")
        if not cuffs then return end
        local tgt = Target.nearestEnemy({ range = opts.range or 30, teamCheck = opts.teamCheck, friendCheck = opts.friendCheck })
        if not tgt then return end
        lastArrest = now
        LIP.fire(57, cuffs, tgt)
    end

    return Niche
end

end)()
_MODS["Combat.Utility"] = (function()
-- Combat/Utility.lua — FACTORY. Exploits sueltos de remote (fire directo, args del reverse).
--  · Team swap  op1  JoinTeam(TeamInstance)         — sin gate client-side
--  · Heal spam  op28 Consume(Tool, nil)             — cura server-side, spam si no hay cooldown
--  · Grab tool  op12 ReceiveTool(Tool)              — recoge arma caída a distancia (~60 studs)
return function(require, LIP, Lib)
    local Teams     = game:GetService("Teams")
    local Players   = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Util = {}

    function Util.joinTeam(name)
        local t = Teams:FindFirstChild(name)
        if t then LIP.fire(1, t) end
    end

    -- heal spam: usa el consumible equipado (medkit/comida). op28 con nil = tick de cura.
    function Util.healSpam()
        local c = LP.Character; local tool = c and c:FindFirstChildOfClass("Tool")
        if tool then LIP.fire(28, tool, nil) end
    end

    -- grab: recoge el Tool caído más cercano (op12). El server resuelve por instancia.
    function Util.grabNearest()
        local c = LP.Character; local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local best, bestD = nil, 60
        for _, t in ipairs(Workspace:GetChildren()) do
            if t:IsA("Tool") then
                local h = t:FindFirstChild("Handle")
                local d = h and (h.Position - hrp.Position).Magnitude
                if d and d <= bestD then best, bestD = t, d end
            end
        end
        if best then LIP.fire(12, best) end
    end

    return Util
end

end)()
_MODS["Combat.AutoWeapons"] = (function()
-- Combat/AutoWeapons.lua — FACTORY. Recoge armas sueltas del mapa automáticamente (HvH).
-- Mecánica (reverse v48 + verificado en vivo): las armas sueltas son MODELS (SPAS/MP5/FAL/...) hijos del
-- contenedor "pickups" (tag PickupSource). El grab = op12 `ReceiveTool:FireServer(Model)` PERO el server
-- valida proximidad (≤8 studs; fire directo lejos = falla). → teleport rápido al pickup, firar, volver.
-- Cámara anclada a la pos real (no salta la vista). Ventana server-side ~0.3s (rápido = menos riesgo de
-- que un poli te arreste). Persiste en muerte (el driver re-chequea). Notifica encontrado/equipado/no-hay.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local CS         = game:GetService("CollectionService")
    local LP = Players.LocalPlayer
    local Spoof = require("Combat.Spoof")
    local AutoWeapons = {}

    local function myRoot() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end

    -- ¿el modelo `m` es un pickup de arma suelto? Model + PrimaryPart, hijo de un PickupSource "pickups",
    -- NO dentro de un Character ni de una vending machine.
    local function isLoosePickup(m)
        if not (m:IsA("Model") and m.PrimaryPart) then return false end
        local p = m.Parent
        if not (p and CS:HasTag(p, "PickupSource")) then return false end
        if p.Name ~= "pickups" then return false end                 -- vending usa Folder, no "pickups"
        return true
    end

    -- ¿ya tengo alguna de las armas seleccionadas (equipada o en el backpack)?
    function AutoWeapons.have(names)
        local set = {}; for _, n in ipairs(names) do set[n] = true end
        local c = LP.Character
        if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") and set[t.Name] then return t.Name end end end
        local bp = LP:FindFirstChild("Backpack")
        if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") and set[t.Name] then return t.Name end end end
        return nil
    end

    -- busca el pickup disponible más cercano cuyo nombre esté en `names`.
    function AutoWeapons.findPickup(names)
        local set = {}; for _, n in ipairs(names) do set[n] = true end
        local root = myRoot(); local myPos = root and root.Position
        local best, bestD
        for _, m in ipairs(Workspace:GetDescendants()) do
            if set[m.Name] and isLoosePickup(m) then
                local d = myPos and (m.PrimaryPart.Position - myPos).Magnitude or 0
                if not bestD or d < bestD then best, bestD = m, d end
            end
        end
        return best, bestD
    end

    -- GRAB: el server te tiene que ver ≤8 studs del pickup. Dos modos:
    --  · posSpoof (desync): server te ve en el pickup, tu cuerpo REAL se queda (restaurado cada frame por
    --    el loop de Spoof). NO teletransporta el cuerpo → menos riesgo de arresto. Cámara anclada (subida).
    --  · teleport (posSpoof=false): mueve el cuerpo real al pickup unos frames (más visible).
    -- Devuelve true si el pickup desapareció (o el arma entró al inventario).
    function AutoWeapons.grab(model, posSpoof)
        local root = myRoot(); if not (root and model and model.PrimaryPart) then return false end
        local cam = Workspace.CurrentCamera
        LIP.awGrabbing = true    -- pausa el position chain + fire del main (no pisar el desync del grab)
        Spoof.ensureParts()
        local realCF = Spoof.captureReal(root)
        local goCF   = CFrame.new(model.PrimaryPart.Position + Vector3.new(0, 3, 0))
        local name   = model.Name
        Spoof.camToLocal(cam, realCF)            -- cámara a la pos real (subida un poco)
        -- DESYNC (pos spoof, VERIFICADO): escribí el pickup cada Heartbeat + marcá el restore → el loop de
        -- Spoof devuelve tu cuerpo real cada frame. El server te ve en el pickup (pasa el check ≤8), tu
        -- cuerpo NO teleporta de verdad = menos riesgo de arresto. (El connection weld NO sirve para el
        -- check del pickup; el desync sí.) Sin pos spoof = teleport crudo del cuerpo.
        local hold = RunService.Heartbeat:Connect(function()
            if posSpoof then
                pcall(function()
                    LIP.cachedRoot = root; LIP.spoofRealCF = realCF; LIP.spoofOn = true
                    LIP.spoofRestore = realCF; LIP.spoofVel = Vector3.zero
                    root.CFrame = goCF
                end)
            else
                pcall(function() root.CFrame = goCF; root.AssemblyLinearVelocity = Vector3.zero end)
            end
        end)
        task.wait(0.22)                          -- el server registra la pos del pickup
        pcall(function() LIP.fire(12, model) end) -- ReceiveTool(Model) = grab
        task.wait(0.18)
        hold:Disconnect()
        if posSpoof then
            Spoof.stop(cam)                      -- limpia el desync + restaura cuerpo + cámara
        else
            pcall(function() root.CFrame = realCF; root.AssemblyLinearVelocity = Vector3.zero end)
            Spoof.camToChar(cam)
        end
        LIP.awGrabbing = false
        task.wait(0.15)
        -- AUTO-EQUIPAR el arma recién agarrada (el op12 la manda al Backpack → equiparla al personaje)
        do
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            local bp = LP:FindFirstChild("Backpack")
            local t = (bp and bp:FindFirstChild(name)) or (LP.Character and LP.Character:FindFirstChild(name))
            if hum and t and t:IsA("Tool") then pcall(function() hum:EquipTool(t) end) end
        end
        return (model.Parent == nil) or (AutoWeapons.have({ name }) ~= nil)
    end

    -- notificación con throttle por clave (evita spam)
    local lastNotify = {}
    local function notify(key, title, desc, gap)
        local now = os.clock()
        if lastNotify[key] and (now - lastNotify[key]) < (gap or 3) then return end
        lastNotify[key] = now
        if LIP.Library and LIP.Library.Notify then LIP.Library:Notify({ Title = title, Description = desc, Time = 4 }) end
    end

    -- DRIVER (llamado por main con throttle). Si no tengo ninguna seleccionada, busco pickup y lo agarro.
    AutoWeapons.busy = false
    AutoWeapons.nextRun = 0
    function AutoWeapons.tick(names, posSpoof)
        if AutoWeapons.busy or not names or #names == 0 then return end
        local now = os.clock()
        if now < AutoWeapons.nextRun then return end
        AutoWeapons.nextRun = now + 1.0                       -- re-chequeo cada 1s
        if AutoWeapons.have(names) then return end            -- ya tengo una → idle
        local model = AutoWeapons.findPickup(names)
        if not model then
            notify("nf", "Auto Weapons", table.concat(names, " / ") .. " — sin pickup en el mapa", 6)
            return
        end
        AutoWeapons.busy = true
        task.spawn(function()
            local nm = model.Name
            local ok = AutoWeapons.grab(model, posSpoof)
            notify("grab", "Auto Weapons", ok and ("Equipada: " .. nm) or ("Falló grab: " .. nm), 0.5)
            AutoWeapons.nextRun = os.clock() + 0.8
            AutoWeapons.busy = false
        end)
    end

    -- lista de nombres de armas conocidas (para poblar el multi-select del UI). Se puede ampliar leyendo
    -- los pickups vivos, pero un set estático es predecible.
    AutoWeapons.WEAPONS = {
        "AWM", "Minigun", "M79", "SPAS", "DB Shotgun", "SCAR-H", "FAL", "AK-74", "AR 15", "M40",
        "MP5", "UZI", "PDW", "Micro AK", "TEC-9", "Glock", "Luger", "M9", "M9A1", "Screwdriver",
    }

    return AutoWeapons
end

end)()
_MODS["Movement.Movement"] = (function()
-- Movement/Movement.lua — FACTORY. Fly / Noclip / WalkSpeed / Jump / Infinite Jump.
-- El usuario trata el juego como SIN anticheat de movimiento → blatant OK.
-- Self-contained: se conecta solo (RenderStepped/Heartbeat/JumpRequest), lee Lib.Toggles/Options.
-- Limpieza vía LIP.onCleanup (destruye el BodyVelocity/Gyro del fly en Unload).
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local UIS        = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Move = {}

    local function char() return LP.Character end
    local function hrp()  local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
    local function hum()  local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
    local function T(f)   local t = Lib.Toggles[f]; return t and t.Value end
    local function O(f)   local o = Lib.Options[f];  return o and o.Value end

    ------------------------------------------------------------------ FLY (por AssemblyLinearVelocity)
    -- Fly velocity-based: subir/bajar (Space/Shift) y moverse por AssemblyLinearVelocity directo. En hover
    -- (sin input vertical) sumamos una contra-gravedad (Gravity*dt/2) para no hundirse. Solo un BodyGyro
    -- para mantener la orientación (mirando la cámara). Mantiene el assembly despierto → no pisa el keep-alive.
    local flyBG, flying = nil, false
    local function stopFly()
        flying = false
        if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
        local h = hum(); if h then pcall(function() h.PlatformStand = false end) end
    end
    local function startFly()
        local root = hrp(); if not root then return end
        stopFly()
        flying = true
        local h = hum(); if h then h.PlatformStand = true end
        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(1, 1, 1) * 9e9
        flyBG.P = 1e4
        flyBG.CFrame = root.CFrame
        flyBG.Parent = root
    end
    local function updateFly(dt)
        local root, cam = hrp(), Workspace.CurrentCamera
        if not (root and cam) then return end
        if not flyBG or flyBG.Parent ~= root then startFly(); return end
        flyBG.CFrame = cam.CFrame
        local dir = Vector3.zero
        if not UIS:GetFocusedTextBox() then
            if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space)     then dir = dir + Vector3.new(0, 1, 0) end
            if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
        end
        local speed = O("FlySpeed") or 60
        local vel = (dir.Magnitude > 0) and (dir.Unit * speed) or Vector3.zero
        -- contra-gravedad (frame-rate independiente) → hover estable sin hundirse
        local gcomp = Workspace.Gravity * (dt or (1/60)) * 0.5
        root.AssemblyLinearVelocity  = vel + Vector3.new(0, gcomp, 0)
        root.AssemblyAngularVelocity = Vector3.zero
    end

    ------------------------------------------------------------------ NOCLIP
    local function updateNoclip()
        local c = char(); if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end

    ------------------------------------------------------------------ SPEED / JUMP  (AC-SAFE)
    -- Escribir Humanoid.WalkSpeed/JumpHeight CRUDO dispara el AC (WalkSpeedUnexpected/JumpHeightUnexpected)
    -- → auto-kill a los 0.5s. La vía sancionada = el sistema de buffs op47 (CharacterDeOrBuff local),
    -- que entra por el setter graceado del juego (u2686). Verificado en vivo: WalkSpeed sube, sin kill.
    -- El buff SUMA en una lista → firamos solo el DELTA cuando cambia (no per-frame), y lo revertimos.
    local WS_BASE, JH_BASE = 16, 7.2
    local wsApplied, jhApplied = 0, 0
    local function applyBuff(effect, want, appliedRef)
        local applied = appliedRef()
        if want == applied then return applied end
        local c = char(); if not c then return applied end
        -- op47: (Model, Effects[WalkSpeed=1|JumpHeight=2], deltaValue, Type.Duration=1, bigTime, Interp.None=1)
        LIP.fireLocal(47, c, effect, want - applied, 1, 1e9, 1)
        return want
    end
    local function updateSpeed()
        local wantWS = (T("WalkSpeedOn") and ((O("WalkSpeed") or WS_BASE) - WS_BASE)) or 0
        wsApplied = applyBuff(1, wantWS, function() return wsApplied end)
        local wantJH = (T("JumpOn") and ((O("JumpHeight") or JH_BASE) - JH_BASE)) or 0
        jhApplied = applyBuff(2, wantJH, function() return jhApplied end)
    end

    ------------------------------------------------------------------ INIT
    function Move.init()
        LIP.onCleanup(stopFly)

        LIP.track(RunService.RenderStepped:Connect(function(dt)
            if T("Fly") then
                if not flying then startFly() end
                updateFly(dt)
            elseif flying then
                stopFly()
            end
            if T("Noclip") then updateNoclip() end
        end))

        LIP.track(RunService.Heartbeat:Connect(function()
            updateSpeed()
        end))

        LIP.track(UIS.JumpRequest:Connect(function()
            if T("InfJump") then
                local h = hum(); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
            end
        end))

        -- respawn: soltar el fly viejo + resetear buffs aplicados (el char nuevo no tiene ninguno)
        LIP.track(LP.CharacterAdded:Connect(function()
            stopFly(); wsApplied, jhApplied = 0, 0
        end))
    end

    return Move
end

end)()
_MODS["Movement.Vehicle"] = (function()
-- Movement/Vehicle.lua — FACTORY. Exploits de vehículo.
-- Los vehículos son FÍSICA 100% client-side: el ocupante del VehicleSeat es network owner del
-- assembly (Roblox). NO hay autoridad server sobre el movimiento → basta con sentarse y escribir
-- la física / los attributes que el loop de manejo del cliente ya lee cada frame (Car4W/Motorcycle
-- leen FastSpeed/FastTorque/SlowSpeed/SlowTorque/MaxSpeed/Torque del Model como attributes).
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Veh = {}

    local function hum()  local c = LP.Character; return c and c:FindFirstChildOfClass("Humanoid") end
    local function seat() local h = hum(); return h and h.SeatPart end
    local function vehicleModel()
        local s = seat(); if not s then return nil, nil end
        return s:FindFirstAncestorWhichIsA("Model"), s
    end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end
    local function O(f) local o = Lib.Options[f];  return o and o.Value end

    local SPEED_ATTRS = { "FastSpeed", "FastTorque", "SlowSpeed", "SlowTorque", "MaxSpeed", "Torque" }
    local saved = {}   -- [model] = { attr = origValue }  (para restaurar, evita compounding)

    local function applySpeed()
        local m = vehicleModel(); if not m then return end
        local mult = O("VehSpeed") or 5
        local s = saved[m]
        if not s then
            s = {}; saved[m] = s
            for _, a in ipairs(SPEED_ATTRS) do
                local v = m:GetAttribute(a)
                if type(v) == "number" then s[a] = v end
            end
        end
        for a, orig in pairs(s) do m:SetAttribute(a, orig * mult) end
    end
    local function restoreSpeed()
        for m, s in pairs(saved) do
            if m and m.Parent then
                for a, orig in pairs(s) do pcall(function() m:SetAttribute(a, orig) end) end
            end
        end
        saved = {}
    end

    -- FLING: velocidad enorme al assembly del vehículo en dirección de la cámara
    function Veh.fling()
        local m, s = vehicleModel()
        local root = (m and m.PrimaryPart) or (s and s.AssemblyRootPart) or s
        if not root then return end
        local dir = Workspace.CurrentCamera.CFrame.LookVector
        pcall(function() root.AssemblyLinearVelocity = dir * (O("VehFlingPower") or 500) end)
    end

    -- auto-sit del VehicleSeat vacío más cercano (clientsit abuse: seat:Sit lo hace el juego mismo)
    function Veh.sitNearest()
        local h = hum(); local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not (h and myHRP) then return end
        local best, bestD = nil, O("SitRange") or 40
        for _, s in ipairs(Workspace:GetDescendants()) do
            if s:IsA("VehicleSeat") and not s.Occupant then
                local d = (s.Position - myHRP.Position).Magnitude
                if d <= bestD then best, bestD = s, d end
            end
        end
        if best then pcall(function() best:Sit(h) end) end
    end

    function Veh.init()
        LIP.onCleanup(restoreSpeed)
        LIP.track(RunService.Heartbeat:Connect(function()
            if T("VehSpeedOn") then applySpeed()
            elseif next(saved) then restoreSpeed() end
        end))
    end

    return Veh
end

end)()
_MODS["Movement.Void"] = (function()
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
        local goCF = patternCF(opts.dist or 1000, opts.pattern)
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

end)()
_MODS["Visuals.ESP"] = (function()
-- Visuals/ESP.lua — FACTORY. ESP Drawing API + Highlight (chams). Client-side puro = cero ban risk.
-- LiF usa R6 (Head/Torso/Left Arm/Right Arm/Left Leg/Right Leg + HumanoidRootPart).
-- Un solo RenderStepped; drawings pooled por jugador. Lee flags de Lib.Toggles/Options.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local ESP = {}

    local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
    local BONES = {                       -- R6
        { "Head", "Torso" },
        { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
        { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
    }

    local pool = {}

    local function mk(t, props)
        local d = Drawing.new(t)
        for k, v in pairs(props) do d[k] = v end
        return d
    end

    local function createSet(plr)
        if pool[plr] then return end
        local s = { all = {}, bones = {} }
        s.boxO   = mk("Square", { Thickness = 3, Filled = false, Color = BLACK, Visible = false, ZIndex = 1 })
        s.box    = mk("Square", { Thickness = 1, Filled = false, Color = WHITE, Visible = false, ZIndex = 2 })
        s.name   = mk("Text",   { Size = 13, Center = true, Outline = true, Color = WHITE, Visible = false })
        s.dist   = mk("Text",   { Size = 12, Center = true, Outline = true, Color = WHITE, Visible = false })
        s.hpBg   = mk("Line",   { Thickness = 3, Color = BLACK, Visible = false })
        s.hp     = mk("Line",   { Thickness = 1, Color = Color3.fromRGB(0, 255, 0), Visible = false })
        s.tracer = mk("Line",   { Thickness = 1, Color = WHITE, Visible = false })
        for i = 1, #BONES do s.bones[i] = mk("Line", { Thickness = 1, Color = WHITE, Visible = false }) end
        for _, d in pairs({ s.boxO, s.box, s.name, s.dist, s.hpBg, s.hp, s.tracer }) do s.all[#s.all + 1] = d end
        for _, b in ipairs(s.bones) do s.all[#s.all + 1] = b end
        pool[plr] = s
    end

    local function hideSet(s)
        for _, d in ipairs(s.all) do d.Visible = false end
        if s.highlight then s.highlight.Enabled = false end
    end
    local function destroySet(plr)
        local s = pool[plr]; if not s then return end
        for _, d in ipairs(s.all) do pcall(function() d:Remove() end) end
        if s.highlight then pcall(function() s.highlight:Destroy() end) end
        pool[plr] = nil
    end

    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function col(f, fallback) local o = Lib.Options[f]; return (o and o.Value) or fallback end

    local function isFriend(plr)
        local ok, r = pcall(function() return LP:IsFriendsWith(plr.UserId) end); return ok and r
    end
    local function visibleTo(cam, part, char)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { LP.Character, char }
        rp.IgnoreWater = true
        local o = cam.CFrame.Position
        return Workspace:Raycast(o, (part.Position - o), rp) == nil
    end

    local function ensureHighlight(s, char)
        if not s.highlight or s.highlight.Parent ~= char then
            if s.highlight then pcall(function() s.highlight:Destroy() end) end
            local h = Instance.new("Highlight")
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.FillTransparency = 0.5; h.OutlineTransparency = 0
            h.Adornee = char; h.Parent = char
            s.highlight = h
        end
    end

    local function update(plr, cam, myPos)
        local s = pool[plr]; if not s then return end
        local char = plr.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        if not (char and hum and hrp and hum.Health > 0) then return hideSet(s) end
        if T("ESPTeamCheck") and LP.Team and plr.Team == LP.Team then return hideSet(s) end
        if T("ESPFriendCheck") and isFriend(plr) then return hideSet(s) end

        local dist = (hrp.Position - myPos).Magnitude
        local maxD = O("ESPMaxDist") or 0
        if maxD > 0 and dist > maxD then return hideSet(s) end   -- 0 = sin límite

        local topV, onTop = cam:WorldToViewportPoint((hrp.CFrame * CFrame.new(0, 3, 0)).Position)
        local botV = cam:WorldToViewportPoint((hrp.CFrame * CFrame.new(0, -3.2, 0)).Position)
        if not onTop then return hideSet(s) end

        local h = math.abs(topV.Y - botV.Y)
        local w = h * 0.5
        local x = topV.X - w / 2
        local y = topV.Y
        -- color por LOS (box + chams fill). Cada otro elemento tiene su picker propio (fallback = LOS).
        local los = (visibleTo(cam, head or hrp, char) and col("ESPVisibleColor", Color3.fromRGB(80, 255, 120)))
                       or col("ESPHiddenColor", Color3.fromRGB(255, 80, 80))

        if T("ESPBox") then
            s.boxO.Size = Vector2.new(w, h); s.boxO.Position = Vector2.new(x, y); s.boxO.Visible = true
            s.box.Size  = Vector2.new(w, h); s.box.Position  = Vector2.new(x, y); s.box.Color = los; s.box.Visible = true
        else s.boxO.Visible = false; s.box.Visible = false end

        if T("ESPName") then
            s.name.Text = plr.Name; s.name.Position = Vector2.new(x + w / 2, y - 15)
            s.name.Color = col("ESPNameColor", los); s.name.Visible = true
        else s.name.Visible = false end

        if T("ESPDistance") then
            s.dist.Text = math.floor(dist) .. "m"; s.dist.Position = Vector2.new(x + w / 2, y + h + 2)
            s.dist.Color = col("ESPDistColor", los); s.dist.Visible = true
        else s.dist.Visible = false end

        if T("ESPHealth") then
            local pct = math.clamp(hum.Health / (hum.MaxHealth > 0 and hum.MaxHealth or 100), 0, 1)
            local bx = x - 5
            s.hpBg.From = Vector2.new(bx, y); s.hpBg.To = Vector2.new(bx, y + h); s.hpBg.Visible = true
            s.hp.From = Vector2.new(bx, y + h * (1 - pct)); s.hp.To = Vector2.new(bx, y + h)
            s.hp.Color = Color3.fromRGB(math.floor(255 * (1 - pct)), math.floor(255 * pct), 60); s.hp.Visible = true
        else s.hpBg.Visible = false; s.hp.Visible = false end

        if T("ESPTracer") then
            local vp = cam.ViewportSize
            local originMode = O("TracerOrigin") or "Bottom"
            local from = (originMode == "Center" and Vector2.new(vp.X / 2, vp.Y / 2))
                       or (originMode == "Top" and Vector2.new(vp.X / 2, 0))
                       or Vector2.new(vp.X / 2, vp.Y)
            s.tracer.From = from; s.tracer.To = Vector2.new(topV.X, y + h)
            s.tracer.Color = col("ESPTracerColor", los); s.tracer.Visible = true
        else s.tracer.Visible = false end

        if T("ESPSkeleton") then
            local skc = col("ESPSkeletonColor", los)
            for i, pair in ipairs(BONES) do
                local a = char:FindFirstChild(pair[1]); local b = char:FindFirstChild(pair[2])
                local bl = s.bones[i]
                if a and b then
                    local av, aon = cam:WorldToViewportPoint(a.Position)
                    local bv, bon = cam:WorldToViewportPoint(b.Position)
                    if aon and bon then
                        bl.From = Vector2.new(av.X, av.Y); bl.To = Vector2.new(bv.X, bv.Y); bl.Color = skc; bl.Visible = true
                    else bl.Visible = false end
                else bl.Visible = false end
            end
        else for _, b in ipairs(s.bones) do b.Visible = false end end

        if T("ESPChams") then
            ensureHighlight(s, char)
            s.highlight.FillColor = los
            s.highlight.OutlineColor = col("ESPChamsOutline", WHITE)
            s.highlight.Enabled = true
        elseif s.highlight then s.highlight.Enabled = false end
    end

    function ESP.init()
        for _, plr in ipairs(Players:GetPlayers()) do if plr ~= LP then createSet(plr) end end
        LIP.track(Players.PlayerAdded:Connect(function(plr) createSet(plr) end))
        LIP.track(Players.PlayerRemoving:Connect(function(plr) destroySet(plr) end))
        LIP.track(RunService.RenderStepped:Connect(function()
            local cam = Workspace.CurrentCamera
            local myChar = LP.Character
            local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local on = T("ESP")
            for plr, s in pairs(pool) do
                if not on or not myHrp then hideSet(s)
                else
                    local ok = pcall(update, plr, cam, myHrp.Position)
                    if not ok then hideSet(s) end
                end
            end
        end))
    end

    return ESP
end

end)()
_MODS["Visuals.HitEffects"] = (function()
-- Visuals/HitEffects.lua — FACTORY. Hitsounds + killsounds + hitmarker visual (X que se desvanece).
-- Hit = op46 Hitmarker (server→cliente, confirma TU hit; payload = pos 3D del impacto). Kill = enemigo
-- muere con un hit tuyo reciente. Sonidos por SoundService:PlayLocalSound (local, no lo oyen los demás).
-- Todo client-side puro = cero ban risk. IDs/volumen/pitch/color configurables.
return function(require, LIP, Lib)
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local Workspace    = game:GetService("Workspace")
    local SoundService = game:GetService("SoundService")
    local Debris       = game:GetService("Debris")
    local LP = Players.LocalPlayer
    local HE = {}

    local WHITE = Color3.new(1, 1, 1)
    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end

    -- hitsounds/killsounds del script de Overkill del usuario. (En LiP fallan 3: Neverlose Old / Sparkles /
    -- Ouch → asset-type; el resto carga. Los dejamos igual para que matchee la lista de Overkill.)
    HE.HITSOUNDS = {
        Neverlose = "139452805868562", ["Neverlose Old"] = "8679627751", Killsound1 = "75221171330522",
        ["Rust HS"] = "99796705017337", ["Fortnite HS"] = "132390332380260", Bell = "186809061",
        Sparkles = "110241936966089", Ouch = "119713732135343", Break = "125409047699942", Skeet = "83717596220569",
    }
    HE.HITNAMES  = { "Neverlose", "Rust HS", "Fortnite HS", "Killsound1", "Bell", "Break", "Skeet", "Neverlose Old", "Sparkles", "Ouch" }
    HE.KILLSOUNDS = { Killsound1 = "75221171330522", ["Rust HS"] = "99796705017337",
                      ["Fortnite HS"] = "132390332380260", Neverlose = "139452805868562" }
    HE.KILLNAMES  = { "Killsound1", "Rust HS", "Fortnite HS", "Neverlose" }

    -- resuelve el ID: custom (textbox) si está seteado, si no el nombre elegido en el dropdown.
    local function resolveId(customFlag, nameFlag, tbl, fallback)
        local c = O(customFlag)
        if c and tostring(c) ~= "" and tostring(c) ~= "0" then return c end
        return tbl[O(nameFlag) or ""] or fallback
    end

    -- cache de Sounds base (precargados, parented a SoundService) → clonar + Play = suena instantáneo y
    -- confiable (PlayLocalSound puede estar bloqueado/silenciado en algunos executors).
    local soundCache = {}
    local function getBase(id)
        if soundCache[id] then return soundCache[id] end
        local s = Instance.new("Sound")
        s.SoundId = id:find("rbxassetid") and id or ("rbxassetid://" .. id)
        s.Parent = SoundService
        soundCache[id] = s
        return s
    end
    local function playSound(id, vol, pitch)
        id = tostring(id or "")
        if id == "" or id == "0" then return end
        local base = getBase(id)
        local s = base:Clone()
        s.Volume = vol or 3
        s.PlaybackSpeed = pitch or 1
        s.Parent = SoundService
        pcall(function() s:Play() end)
        pcall(function() SoundService:PlayLocalSound(s) end)   -- fallback por si el Play parented no suena
        Debris:AddItem(s, 6)
    end
    HE.playSound = playSound
    -- test: reproduce el hitsound seleccionado (para aislar sonido de detección)
    function HE.testHit() playSound(resolveId("HitSoundId", "HitSoundName", HE.HITSOUNDS, "139452805868562"), O("HitVol") or 3, O("HitPitch") or 1) end
    function HE.testKill() playSound(resolveId("KillSoundId", "KillSoundName", HE.KILLSOUNDS, "75221171330522"), O("KillVol") or 3, O("KillPitch") or 1) end

    -- ── HITMARKER (pool de X de 4 líneas Drawing, fade) ──
    local FADE = 0.45
    local pool, poolI = {}, 0
    local function mkSet()
        local set = { lines = {}, untilT = 0, pos = nil }
        for i = 1, 4 do local l = Drawing.new("Line"); l.Thickness = 2; l.Visible = false; set.lines[i] = l end
        return set
    end
    local function showHitmarker(worldPos)
        poolI = (poolI % 6) + 1
        pool[poolI] = pool[poolI] or mkSet()
        pool[poolI].pos = worldPos
        pool[poolI].untilT = os.clock() + FADE
    end
    local function renderMarks()
        local cam = Workspace.CurrentCamera
        local gap = O("HitMarkGap") or 4
        local len = O("HitMarkSize") or 7
        local col = O("HitMarkColor") or WHITE
        local now = os.clock()
        for _, set in pairs(pool) do
            local live = set.untilT > now and set.pos
            if live then
                local sp, on = cam:WorldToViewportPoint(set.pos)
                if on and sp.Z > 0 then
                    local x, y = sp.X, sp.Y
                    local a = 1 - (set.untilT - now) / FADE   -- transparencia 0→1 (fade out)
                    local seg = {
                        {  gap,  gap,  gap + len,  gap + len },
                        { -gap, -gap, -gap - len, -gap - len },
                        {  gap, -gap,  gap + len, -gap - len },
                        { -gap,  gap, -gap - len,  gap + len },
                    }
                    for i = 1, 4 do
                        local l = set.lines[i]
                        l.From = Vector2.new(x + seg[i][1], y + seg[i][2])
                        l.To   = Vector2.new(x + seg[i][3], y + seg[i][4])
                        l.Color = col; l.Transparency = math.clamp(a, 0, 1); l.Visible = true
                    end
                else for i = 1, 4 do set.lines[i].Visible = false end end
            else for i = 1, 4 do if set.lines[i] then set.lines[i].Visible = false end end end
        end
    end

    function HE.hit(worldPos)
        if T("HitSound") then
            playSound(resolveId("HitSoundId", "HitSoundName", HE.HITSOUNDS, "139452805868562"), O("HitVol") or 2, O("HitPitch") or 1)
        end
        if T("HitMarker") and worldPos then showHitmarker(worldPos) end
        LIP.lastHitT = os.clock()
    end
    function HE.kill()
        if T("KillSound") then
            playSound(resolveId("KillSoundId", "KillSoundName", HE.KILLSOUNDS, "75221171330522"), O("KillVol") or 3, O("KillPitch") or 1)
        end
    end

    function HE.init()
        -- HIT/KILL por CORRELACIÓN (como Overkill): TU disparo (LIP.lastShotT, seteado en Net por cada op14)
        -- + el enemigo pierde vida / muere en la ventana → hit/kill. El hitmarker del server (op36 entrante)
        -- es un broadcast global de TODOS los jugadores, no aislable; esto es robusto y solo tuyo.
        -- ¿le estoy pegando YO? = es mi target de silent aim/autofire, o le estoy apuntando (mira <12°).
        -- Filtra los falsos positivos del daño que le hacen OTROS jugadores al mismo enemigo.
        local function aimingAt(char)
            if LIP.target and LIP.target.Character == char then return true end
            local part = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
            if not part then return false end
            local cam = Workspace.CurrentCamera
            local dir = part.Position - cam.CFrame.Position
            if dir.Magnitude < 2 then return true end
            local ang = math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(dir.Unit), -1, 1)))
            return ang < 12
        end
        local function hookChar(plr, char)
            local h = char and char:FindFirstChildOfClass("Humanoid")
            if not h then return end
            local last = h.Health
            local function mine() return not (LP.Team and plr.Team == LP.Team)
                and LIP.lastShotT and (os.clock() - LIP.lastShotT) < 0.3 and aimingAt(char) end
            LIP.track(h.HealthChanged:Connect(function(hp)
                local dropped = hp < (last - 0.5)
                last = hp
                if dropped and mine() then
                    local part = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
                    HE.hit(part and part.Position or nil)
                end
            end))
            LIP.track(h.Died:Connect(function()
                -- kill: enemigo muere apuntándole vos con un disparo reciente (ventana un toque más amplia)
                if not (LP.Team and plr.Team == LP.Team) and LIP.lastShotT
                   and (os.clock() - LIP.lastShotT) < 1.0 and aimingAt(char) then HE.kill() end
            end))
        end
        local function watch(plr)
            if plr == LP then return end
            if plr.Character then hookChar(plr, plr.Character) end
            LIP.track(plr.CharacterAdded:Connect(function(c) task.wait(0.3); hookChar(plr, c) end))
        end
        for _, p in ipairs(Players:GetPlayers()) do watch(p) end
        LIP.track(Players.PlayerAdded:Connect(watch))
        LIP.track(RunService.RenderStepped:Connect(function() pcall(renderMarks) end))
        LIP.onCleanup(function()
            for _, set in pairs(pool) do for _, l in ipairs(set.lines) do pcall(function() l:Remove() end) end end
        end)
    end

    return HE
end

end)()
_MODS["Visuals.CrosshairHUD"] = (function()
-- Visuals/CrosshairHUD.lua — FACTORY. Labels de estado del ragebot abajo del crosshair central.
-- Una línea, prioridad de overrides:
--   killedWait  → "Killed: <user>, waiting for HRP..."   (limpia al respawn del user + ForceField off)
--   reloadVoid  → "Reloading In Void..."                 (limpia al terminar la recarga)
--   base        → "killing: <user> | Resolved: x.xyz"    (x.xyz = confianza del resolver 0.000–1.000)
-- Font = el del watermark (GothamBold). Fade CONFIGURABLE + crossfade suave entre cambios de override
-- (fade-out del texto viejo → swap → fade-in del nuevo). Todo lo consume de flags LIP (los setea main).
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local CrossHUD = {}
    local Strafe   -- cacheado en init (para resolverInfo del HUD)

    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end

    -- parent seguro (gethui si existe, si no CoreGui) — sobrevive respawn
    local function guiParent()
        local ok, h = pcall(function() return gethui and gethui() end)
        if ok and h then return h end
        return game:GetService("CoreGui")
    end
    -- font idéntico al watermark si está creado, si no GothamBold (= T.FontBold del theme)
    local function wmFont()
        local wm = Lib._wm
        local ok, f = pcall(function() return wm and wm.T and wm.T.Font end)
        return (ok and f) or Enum.Font.GothamBold
    end

    local sg, lbl, grad
    local function ensure()
        if sg and sg.Parent and lbl and lbl.Parent then return end
        sg = Instance.new("ScreenGui")
        sg.Name = "LIP_XHUD"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true
        sg.DisplayOrder = 999; sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        pcall(function() sg.Parent = guiParent() end)
        lbl = Instance.new("TextLabel")
        lbl.Name = "L"; lbl.BackgroundTransparency = 1
        lbl.AnchorPoint = Vector2.new(0.5, 0)          -- centrado horizontal, crece simétrico desde el centro
        lbl.AutomaticSize = Enum.AutomaticSize.XY
        lbl.Size = UDim2.fromOffset(0, 0)
        lbl.TextXAlignment = Enum.TextXAlignment.Center
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)  -- outline para legibilidad sobre cualquier fondo
        lbl.Text = ""; lbl.Visible = false
        lbl.Parent = sg
        -- UIGradient para la OLA DE COLOR (recorre las letras). Enabled solo con el toggle de wave.
        grad = Instance.new("UIGradient")
        grad.Enabled = false
        grad.Parent = lbl
    end

    -- línea activa según prioridad (killed > reloadVoid > base). "" = nada que mostrar.
    local function activeLine()
        if LIP.killedWait then
            return ("Killed: %s, waiting for HRP..."):format(LIP.killedWait)
        elseif LIP.hudReloadVoid then
            return "Reloading In Void..."
        elseif LIP.hudTargetName then
            local ri = (Strafe and Strafe.resolverInfo(LIP.target)) or { score = LIP.hudResolved or 0, state = "NORMAL", clusters = 0, confidence = 0 }
            local hp = 0
            local tc = LIP.target and LIP.target.Character
            local th = tc and tc:FindFirstChildOfClass("Humanoid")
            if th then hp = math.floor(th.Health) end
            return ("killing: %s | Conf: %.2f | Fire: %.2f | Hit: %.2f | %s | HP: %d"):format(
                LIP.hudTargetName, ri.confidence or 0, LIP.fireMult or 1, ri.hitAcc or 0, ri.state, hp)
        end
        return ""
    end

    -- Smooth Fade = OLA DE COLOR (no fade alpha): una banda de color/brillo recorre las letras via UIGradient
    -- animado. El texto se muestra sólido al instante; en cambios de override sólo se swappea (la ola sigue).
    local function update(dt)
        if not T("CrossHUD") then if lbl then lbl.Visible = false end return end
        ensure()
        local shown = activeLine()
        if shown == "" then lbl.Visible = false; return end
        local col = O("CrossHUDColor") or Color3.fromRGB(202, 151, 161)
        lbl.Text = shown
        lbl.Font = wmFont()
        lbl.TextSize = O("CrossHUDSize") or 16
        lbl.TextColor3 = col
        lbl.TextTransparency = 0
        lbl.TextStrokeTransparency = 0.5
        lbl.Position = UDim2.new(0.5, 0, 0.5, O("CrossHUDOffset") or 34)   -- centro de pantalla + offset abajo
        lbl.Visible = true
        -- OLA DE COLOR: banda brillante que barre las letras de izq→der (UIGradient con offset animado).
        if T("CrossHUDFade") then
            local hi = col:Lerp(Color3.new(1, 1, 1), 0.75)   -- pico de la ola = color base aclarado
            grad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0.0, col),
                ColorSequenceKeypoint.new(0.4, col),
                ColorSequenceKeypoint.new(0.5, hi),
                ColorSequenceKeypoint.new(0.6, col),
                ColorSequenceKeypoint.new(1.0, col),
            })
            local spd = O("CrossHUDFadeSpeed") or 6
            grad.Offset = Vector2.new(((os.clock() * spd * 0.15) % 1.4) - 0.7, 0)   -- barrido continuo
            grad.Enabled = true
        else
            grad.Enabled = false
        end
    end

    function CrossHUD.init()
        pcall(function() Strafe = require("Combat.Strafe") end)   -- para resolverInfo (score/state/clusters)
        LIP.track(RunService.RenderStepped:Connect(function(dt) pcall(update, dt) end))
        LIP.onCleanup(function() if sg then pcall(function() sg:Destroy() end) end end)
    end

    return CrossHUD
end

end)()
_MODS["UI"] = (function()
-- UI.lua — FACTORY. Categorías Rage / Legit / Misc / Visuals. Paneles separados por función.
-- Flags en Lib.Toggles / Lib.Options.
return function(require, LIP, Lib)
    local UI = {}

    function UI.build(Window)
        local Ragdoll = require("Combat.Ragdoll")
        local Weapon  = require("Combat.Weapon")
        local Strafe  = require("Combat.Strafe")
        local Godmode = require("Combat.Godmode")
        local Niche   = require("Combat.Niche")
        local Vehicle = require("Movement.Vehicle")
        local Void    = require("Movement.Void")
        local Util    = require("Combat.Utility")
        local AutoWeapons = require("Combat.AutoWeapons")
        local HitFX   = require("Visuals.HitEffects")

        --========================= RAGE =========================--
        -- UNA sección con 3 columnas; cajas apiladas (estilo symbol: todas visibles a la vez).
        local Rage = Window:AddCategory("Rage", "crosshair")
        local RS = Rage:AddSection("Rage", "Aimbot · Strafe · Resolver · Void", { Columns = 3 })

        --== Col 1: Silent Aim + Resolver ==--
        local c1 = RS:AddPanel("Silent Aim", { Column = 1 })
        c1:AddToggle("SilentAim", { Text = "Silent Aim", Default = false,
            Tooltip = "op14 passive arg-swap al target. Cámara no se toca, GST intacto." })
        c1:AddDropdown("SelMode", { Text = "Selection", Values = { "Crosshair", "Distance", "Health" }, Default = "Crosshair" })
        c1:AddSlider("FOV", { Text = "FOV", Min = 0, Max = 500, Default = 150 })
        c1:AddToggle("Wallcheck", { Text = "Wallcheck", Default = false, Tooltip = "ON = solo con línea de vista" })
        c1:AddToggle("Wallbang", { Text = "Wallbang", Default = false,
            Tooltip = "Origin del lado del target de la pared = LOS garantizada (atraviesa paredes)" })
        c1:AddToggle("TeamCheck", { Text = "Team Check", Default = true })
        c1:AddToggle("FriendCheck", { Text = "Friend Check", Default = true })
        c1:AddToggle("FFCheck", { Text = "ForceField Check", Default = true,
            Tooltip = "Si el target tiene ForceField (spawn protection) o murió → te escondés (idle) y no disparás hasta que respawnee / se le quite el FF. Ignore temporal." })

        --== Col 2: Firepower + Void Spam ==--
        local c2 = RS:AddPanel("Firepower", { Column = 2 })
        c2:AddToggle("MultiFire", { Text = "Bullet Multiplier", Default = false,
            Tooltip = "Padea el array de balas del op14 (del juego Y nuestro) a N pellets → N× daño POR disparo legal. Este es el rapidfire real (el server rate-limita disparar rápido, pero NO cuántas balas por disparo)." })
        c2:AddSlider("BulletMult", { Text = "Bullets/Shot", Min = 1, Max = 20, Default = 6,
            Tooltip = "Cuántas balas mete cada disparo. Sube el daño por disparo. También arregla escopetas (autofire necesita varios pellets)." })
        c2:AddToggle("RapidFire", { Text = "Rapid Fire", Default = false,
            Tooltip = "Stream de op14 mientras mantenés mouse1, CAPEADO al firerate del arma (exceder = unequip). El daño extra viene del Bullet Multiplier, no de disparar más rápido." })
        c2:AddToggle("AutoFire", { Text = "Auto Fire", Default = false,
            Tooltip = "Dispara al target auto (sin click). SOLO con Target Strafe ON. Capeado al firerate." })
        c2:AddSlider("AutoFireRate", { Text = "Fire Rate Cap", Min = 1, Max = 120, Default = 120, Suffix = "/s",
            Tooltip = "TOPE manual opcional. El autofire ya obedece el firerate REAL del arma (mantené mouse1 1 vez para calibrarlo). Bajá esto solo si querés disparar más lento. El DPS lo da el Bullet Multiplier." })
        c2:AddToggle("AutoReload", { Text = "Auto Reload", Default = true,
            Tooltip = "Recarga sola al agotar el cargador (op42→espera ReloadTime→op40, timing real). Solo en Auto Fire." })
        c2:AddSlider("FireRange", { Text = "Fire Range", Min = 20, Max = 500, Default = 200, Suffix = "studs" })
        c2:AddDivider()
        c2:AddButton("Force Reload", function() Weapon.instantReload() end)
        c2:AddKeybind("ReloadKey", { Text = "Reload Key", Mode = "Toggle", Callback = function() Weapon.instantReload() end })
        c2:AddSlider("ReloadAmmo", { Text = "Mag Size", Min = 1, Max = 120, Default = 15,
            Tooltip = "Cargador de tu arma (se auto-detecta si recargás con R 1 vez)" })
        c2:AddSlider("ReloadTime", { Text = "Reload Time", Min = 0.3, Max = 3, Default = 1.2, Decimals = 1, Suffix = "s" })
        c2:AddToggle("ShotgunReload", { Text = "Shotgun Reload", Default = false, Tooltip = "Escopeta: op40 por bala. Pistola/rifle = OFF." })
        c2:AddSlider("ShotgunPellets", { Text = "Shotgun Pellets", Min = 1, Max = 16, Default = 8,
            Tooltip = "Pellets por tiro para escopetas (SPAS/DB). El autofire manda N pellets = registra. Ajustá hasta que peguen (si el juego aprendió el count real, lo usa; si no, este slider)." })

        local vd = RS:AddPanel("Void Spam", { Column = 2 })
        vd:AddToggle("VoidSpam", { Text = "Void Spam", Default = false,
            Tooltip = "SOLO con Target Strafe ON. Oscila OUT (strafe-orbit al target, disparás) ↔ IN void (server te ve lejos, esconde, disparo pausado). Rompe el resolver de PREDICCIÓN enemigo. Con Void Reload: fuerza el void durante toda la recarga (recargás escondido)." })
        vd:AddSlider("VoidInTime", { Text = "In Void", Min = 0.1, Max = 2, Default = 0.4, Decimals = 2, Suffix = "s",
            Tooltip = "Tiempo escondido en el void (disparo pausado)" })
        vd:AddSlider("VoidOutTime", { Text = "Out Void", Min = 0.1, Max = 2, Default = 0.3, Decimals = 2, Suffix = "s",
            Tooltip = "Tiempo en tu pos real (disparás desde acá)" })
        vd:AddToggle("VoidShootOut", { Text = "Shoot Out Only", Default = true,
            Tooltip = "Solo dispara OUT del void; pausa el disparo mientras estás IN void." })
        vd:AddToggle("VoidReload", { Text = "Void Reload", Default = false,
            Tooltip = "Recarga el arma mientras estás IN void (escondido) cuando el cargador se agota." })
        vd:AddList("VoidPattern", { Values = { "Random", "High", "Orbit", "Tween", "Teleport" }, Default = "Random" })
        vd:AddSlider("VoidDist", { Text = "Distance", Min = 100, Max = 1000000, Default = 1000, Suffix = "studs" })

        --== Col 3: Target Strafe + Server Position ==--
        local ts = RS:AddPanel("Target Strafe", { Column = 3 })
        ts:AddToggle("TargetStrafe", { Text = "Target Strafe", Default = false,
            Tooltip = "Desync: el server te ve orbitando; cuerpo/cámara reales quietos" })
        ts:AddKeybind("StrafeKey", { Text = "Strafe Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.TargetStrafe; if t then t:SetValue(a) end end })
        ts:AddDropdown("StrafePreset", { Text = "Preset", Values = { "Normal", "Random", "Behind", "Spiral" }, Default = "Normal",
            Callback = function(v) Strafe.applyPreset(v) end })
        ts:AddDropdown("StrafeMode", { Text = "Mode", Values = { "Normal", "Random", "Behind", "Spiral" }, Default = "Normal" })
        ts:AddSlider("StrafeRadius", { Text = "Radius", Min = 4, Max = 150, Default = 10, Decimals = 1, Suffix = "studs" })
        ts:AddSlider("StrafeSpeed",  { Text = "Speed", Min = 1, Max = 40, Default = 4 })
        ts:AddSlider("StrafeHeight", { Text = "Height", Min = -50, Max = 50, Default = 0 })
        ts:AddToggle("StrafeBait", { Text = "Bait", Default = false,
            Tooltip = "Cada 1-3s (random) salta a un spot random por 0.3s" })
        ts:AddDivider()
        ts:AddKeybind("SetTargetKey", { Text = "Set Target (crosshair)", Mode = "Toggle",
            Callback = function() Strafe.pickCrosshair() end })
        ts:AddButton("Clear Target", function() Strafe.clearManual() end)
        ts:AddToggle("Spectate", { Text = "Spectate Target", Default = false })

        local sp = RS:AddPanel("Server Position", { Column = 3 })
        sp:AddToggle("PosSpoof", { Text = "Pos Spoof", Default = true,
            Tooltip = "ON = desync (cuerpo real quieto). Con Connection Weld ON = ancla la cámara a tu pos real (vista estable, harmonía). OFF (solo desync) = mueve el cuerpo real." })
        sp:AddToggle("ConnExploit", { Text = "Connection Weld", Default = false,
            Tooltip = "WELD real al target: tu cuerpo se pega a él (target.CFrame*offset, sigue rotación) + PhysicsRepRootPart = su HRP → replica SIN delay ni flicker. Es el método de posición (ignora Pos Spoof). Radius = distancia atrás/órbita (sin fling)." })
        sp:AddToggle("VoidViz", { Text = "Indicator", Default = true, Tooltip = "Part + icono + tracer a la pos que ve el server" })
            :AddColorPicker("VizColor", { Default = Color3.fromRGB(202, 151, 161) })

        local idl = RS:AddPanel("Idle State", { Column = 3 })
        idl:AddToggle("IdleState", { Text = "Idle State", Default = false,
            Tooltip = "Anti-aim CONTINUO (no dispara): el server te ve teleportando lejos con el pattern todo el tiempo. Para esconderte cuando NO estás tirando. (Antes se llamaba Void Spam.)" })
        idl:AddList("IdlePattern", { Values = { "Random", "High", "Orbit", "Tween", "Teleport" }, Default = "Random" })
        idl:AddSlider("IdleDist", { Text = "Distance", Min = 100, Max = 1000000, Default = 1000, Suffix = "studs" })

        local hud = RS:AddPanel("Crosshair HUD", { Column = 3 })
        hud:AddToggle("CrossHUD", { Text = "Crosshair HUD", Default = true,
            Tooltip = "Labels de estado del ragebot abajo del crosshair (killing: user | Resolved: x.xyz; overrides: Reloading In Void / Killed waiting). Font del watermark. 1.000=full resuelto (tiro seguro), 0.000=tiro difícil." })
            :AddColorPicker("CrossHUDColor", { Default = Color3.fromRGB(202, 151, 161) })
        hud:AddToggle("CrossHUDFade", { Text = "Color Wave", Default = true,
            Tooltip = "Ola de color: una banda de brillo recorre las letras (en vez de fade de transparencia alpha)." })
        hud:AddSlider("CrossHUDFadeSpeed", { Text = "Wave Speed", Min = 1, Max = 20, Default = 6, Decimals = 1,
            Tooltip = "Velocidad de la ola de color." })
        hud:AddSlider("CrossHUDSize", { Text = "Text Size", Min = 10, Max = 28, Default = 16 })
        hud:AddSlider("CrossHUDOffset", { Text = "Y Offset", Min = 10, Max = 120, Default = 34, Suffix = "px",
            Tooltip = "Distancia abajo del centro del crosshair." })

        --========================= LEGIT =========================--
        --========================= RESOLVER (Section en el sidebar de Rage) =========================--
        local Res = Rage:AddSection("Resolver", "Cluster · Density · Dynamic Strafe", { Columns = 2 })
        local RParams = Strafe.RParams; local DEN = Strafe.DEN
        local rm = Res:AddPanel("Método", { Column = 1 })
        rm:AddToggle("Resolver", { Text = "Spam Resolver", Default = false,
            Tooltip = "Resuelve el centro REAL del target (el strafe orbita ahí, no su jitter)" })
        rm:AddDropdown("ResolverMethod", { Text = "Method", Values = { "Cluster", "Density", "Auto" }, Default = "Cluster",
            Tooltip = "Cluster = histograma (juju). Density = vecindad batch (sakura, anti-alternador + far). Auto = elige según el target." })
        rm:AddSlider("ResolverPredict", { Text = "Predict", Min = 0, Max = 0.4, Default = 0.12, Decimals = 2, Suffix = "s",
            Tooltip = "Lead por velocidad (compensa el delay de replicación). 0 = off" })
        rm:AddSlider("ResolverRate", { Text = "Resolver Rate", Min = 0, Max = 0.1, Default = 0.037, Decimals = 4, Suffix = "s",
            Tooltip = "Intervalo de muestreo de velocidad (juju 0.037)." })
        rm:AddSlider("PredictBase", { Text = "Predict Base", Min = 0, Max = 0.4, Default = 0.10, Decimals = 2, Suffix = "s",
            Tooltip = "Lead constante (comp de ping), aplicado aún quieto" })
        rm:AddSlider("PredictAmp", { Text = "Predict Amp", Min = 0, Max = 0.4, Default = 0.15, Decimals = 2, Suffix = "s",
            Tooltip = "Lead extra que escala con la velocidad del target" })
        rm:AddToggle("FireResolved", { Text = "Fire on Resolved", Default = false,
            Tooltip = "Autofire dispara a la pos RESUELTA (didDefensive). RIESGO HBE. OFF = HBE-safe." })
        rm:AddToggle("ResolvedTracer", { Text = "Resolved Tracer", Default = false,
            Tooltip = "Tracer del centro de pantalla a la pos RESUELTA por el método activo." })
            :AddColorPicker("ResolvedTracerColor", { Default = Color3.fromRGB(255, 120, 120) })
        rm:AddLabel("Cluster", { Header = true })
        rm:AddSlider("RRPosWeight", { Text = "Position Trust", Min = 0.1, Max = 5, Default = 1.5, Decimals = 2,
            Callback = function(v) if RParams then RParams.posWeight = v end end })
        rm:AddSlider("RRVoidWeight", { Text = "Void Trust", Min = 0.1, Max = 5, Default = 0.2, Decimals = 2,
            Callback = function(v) if RParams then RParams.voidWeight = v end end })
        rm:AddSlider("RRForget", { Text = "Forget Rate", Min = 0, Max = 1000, Default = 80, Suffix = "%",
            Callback = function(v) if RParams then RParams.forget = v end end })
        rm:AddSlider("RRDistPenalty", { Text = "Distance Penalty", Min = 0, Max = 5, Default = 2, Decimals = 1, Suffix = "x",
            Callback = function(v) if RParams then RParams.distPenalty = v end end })
        rm:AddSlider("RRAccuracy", { Text = "Accuracy", Min = 0, Max = 1, Default = 0.5, Decimals = 2,
            Tooltip = "Min resolver confidence to fire (0 = off, higher = holds fire on shaky resolves)",
            Callback = function() end })   -- leído en vivo por el gate del autofire: O('RRAccuracy')
        rm:AddSlider("RRLerp", { Text = "Lerp", Min = 0.1, Max = 1, Default = 0.1, Decimals = 2,
            Callback = function(v) if RParams then RParams.lerp = v end end })
        rm:AddLabel("Density", { Header = true })
        rm:AddSlider("DenForgiveness", { Text = "Forgiveness", Min = 2, Max = 60, Default = 14.4, Decimals = 1, Suffix = "st",
            Tooltip = "Radio de vecindad (studs). Chico = void nunca clusteriza.",
            Callback = function(v) if DEN then DEN.forgiveness = v end end })
        rm:AddSlider("DenOutBonus", { Text = "Out-of-Void Bonus", Min = 0, Max = 40, Default = 13, Decimals = 1, Suffix = "st",
            Callback = function(v) if DEN then DEN.outOfVoidBonus = v end end })
        rm:AddSlider("DenDistPenalty", { Text = "Distance Penalty", Min = 0, Max = 8, Default = 3.2, Decimals = 1, Suffix = "x",
            Tooltip = "Encoge el radio con la distancia (resolución far).",
            Callback = function(v) if DEN then DEN.distPenalty = v end end })
        rm:AddSlider("DenMinMatches", { Text = "Min Matches", Min = 2, Max = 10, Default = 3,
            Callback = function(v) if DEN then DEN.minMatches = math.floor(v) end end })
        rm:AddSlider("DenWindow", { Text = "Window", Min = 0.5, Max = 5, Default = 3, Decimals = 1, Suffix = "s",
            Callback = function(v) if DEN then DEN.window = v end end })

        local dyn = Res:AddPanel("Dynamic Strafe", { Column = 2 })
        dyn:AddToggle("DynStrafe", { Text = "Dynamic Cycle", Default = false,
            Tooltip = "Ciclo CHASE (orbita la resuelta) ↔ BAIT (fling al void). Baitea el resolver enemigo. No dispara en bait." })
        dyn:AddDropdown("BaitPreset", { Text = "Bait Preset", Values = { "Timed", "Micro", "Spam" }, Default = "Timed",
            Tooltip = "Timed = chase 3s/bait 1s. Micro = chase ping+0.02/bait corto (flash). Spam = 0.06/0.11 rápido (juju)." })
        dyn:AddSlider("AroundTime", { Text = "Chase Time", Min = 0.05, Max = 10, Default = 3, Decimals = 2, Suffix = "s" })
        dyn:AddSlider("VoidTime", { Text = "Bait Time", Min = 0.05, Max = 12, Default = 1, Decimals = 2, Suffix = "s" })
        dyn:AddToggle("AutoMode", { Text = "Auto Best-Mode", Default = false,
            Tooltip = "Elige Spiral/Behind/Normal/Random según distancia/velocidad/spoof del target, al entrar a CHASE." })
        dyn:AddSlider("AutoSpoofThresh", { Text = "Spoof→Spiral", Min = 0, Max = 1, Default = 0.40, Decimals = 2,
            Tooltip = "Si el spoof del target supera esto → Spiral (3D impredecible)." })
        dyn:AddSlider("AutoFastThresh", { Text = "Fast→Behind", Min = 5, Max = 150, Default = 40, Suffix = "st/s",
            Tooltip = "Si el target se mueve más rápido que esto → Behind." })
        dyn:AddSlider("AutoFarThresh", { Text = "Far→Normal", Min = 10, Max = 200, Default = 60, Suffix = "st",
            Tooltip = "Si el target está más lejos que esto → Normal (órbita ancha)." })

        local Legit = Window:AddCategory("Legit", "target")
        local LS = Legit:AddSection("Legit", "Melee · Fists", { Columns = 2 })
        local l1 = LS:AddPanel("Melee", { Column = 1 })
        l1:AddToggle("MeleeAura", { Text = "Melee Aura", Default = false,
            Tooltip = "op16 passive: al golpear con arma melee, redirige el hit al enemigo cercano" })
        l1:AddSlider("MeleeRange", { Text = "Melee Range", Min = 4, Max = 30, Default = 12, Suffix = "studs" })
        local l2 = LS:AddPanel("Fists", { Column = 2 })
        l2:AddToggle("AutoPunch", { Text = "Auto Punch", Default = false,
            Tooltip = "op33 activo (puños, sin GST): golpea al enemigo cercano en rango" })
        l2:AddSlider("PunchRange", { Text = "Punch Range", Min = 4, Max = 30, Default = 8, Suffix = "studs" })

        --========================= MISC =========================--
        local Misc = Window:AddCategory("Misc", "wrench")
        local MS = Misc:AddSection("Movement", "Fly · Noclip · Speed · Vehicle", { Columns = 3 })
        local m1 = MS:AddPanel("Fly / Noclip", { Column = 1 })
        m1:AddToggle("Fly", { Text = "Fly", Default = false, Tooltip = "WASD + Space/Shift" })
        m1:AddKeybind("FlyKey", { Text = "Fly Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.Fly; if t then t:SetValue(a) end end })
        m1:AddSlider("FlySpeed", { Text = "Fly Speed", Min = 10, Max = 300, Default = 60 })
        m1:AddToggle("Noclip", { Text = "Noclip", Default = false })
        m1:AddKeybind("NoclipKey", { Text = "Noclip Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.Noclip; if t then t:SetValue(a) end end })
        local m2 = MS:AddPanel("Speed / Jump", { Column = 2 })
        m2:AddToggle("WalkSpeedOn", { Text = "WalkSpeed", Default = false, Tooltip = "Via buff op47 (AC-safe)" })
        m2:AddSlider("WalkSpeed", { Text = "Speed", Min = 16, Max = 200, Default = 40 })
        m2:AddToggle("JumpOn", { Text = "JumpHeight", Default = false, Tooltip = "Via buff op47 (base 7.2)" })
        m2:AddSlider("JumpHeight", { Text = "Jump", Min = 7, Max = 100, Default = 25 })
        m2:AddToggle("InfJump", { Text = "Infinite Jump", Default = false })
        local m3 = MS:AddPanel("Vehicle", { Column = 3 })
        m3:AddToggle("VehSpeedOn", { Text = "Vehicle Speed", Default = false })
        m3:AddSlider("VehSpeed", { Text = "Multiplier", Min = 1, Max = 20, Default = 5, Suffix = "x" })
        m3:AddButton("Vehicle Fling", function() Vehicle.fling() end)
        m3:AddSlider("VehFlingPower", { Text = "Fling Power", Min = 100, Max = 5000, Default = 800 })
        m3:AddButton("Sit Nearest", function() Vehicle.sitNearest() end)
        m3:AddSlider("SitRange", { Text = "Sit Range", Min = 10, Max = 150, Default = 40 })

        local VS = Misc:AddSection("Body & Utility", "Ragdoll · Godmode · Utility", { Columns = 2 })
        local v2 = VS:AddPanel("Self", { Column = 1 })
        v2:AddButton("Self Ragdoll", function() Ragdoll.toggle() end)
        v2:AddKeybind("RagdollKey", { Text = "Ragdoll Key", Mode = "Toggle", Callback = function() Ragdoll.toggle() end })
        v2:AddToggle("RagdollLock", { Text = "Permanent Ragdoll", Default = false })
        v2:AddToggle("Godmode", { Text = "Godmode (ragdoll)", Default = false,
            Tooltip = "Self-ragdoll + mueve el assembly lejos (hitbox real fuera). Dispará con AutoFire (op14 directo bypasea el gate de ragdoll). Equipá el arma ANTES." })
        v2:AddDropdown("GodPreset", { Text = "Preset", Values = { "High", "ExtremeHigh", "Jitter", "FarJitter" }, Default = "High",
            Callback = function(v) Godmode.applyPreset(v) end })
        v2:AddDropdown("GodMode", { Text = "Mode", Values = { "High", "Jitter" }, Default = "High" })
        v2:AddSlider("GodHeight", { Text = "God Height", Min = 50, Max = 1500, Default = 150, Suffix = "studs" })
        local v3 = VS:AddPanel("Utility", { Column = 2 })
        v3:AddLabel("Join Team (op1)", { Header = true })
        v3:AddButton("Police", function() Util.joinTeam("Police") end)
        v3:AddButton("Criminals", function() Util.joinTeam("Criminals") end)
        v3:AddButton("Prisoners", function() Util.joinTeam("Prisoners") end)
        v3:AddButton("Neutral", function() Util.joinTeam("Neutral") end)
        v3:AddButton("Grab Tool (op12)", function() Util.grabNearest() end)
        v3:AddButton("Heal (op28)", function() Util.healSpam() end)
        v3:AddDivider()
        v3:AddLabel("Niche", { Header = true })
        v3:AddToggle("AutoThrow", { Text = "Auto Throw (op43)", Default = false,
            Tooltip = "Lanza el throwable equipado (granada/cuchillo) al enemigo cercano" })
        v3:AddToggle("AutoArrest", { Text = "Auto Arrest (op57)", Default = false,
            Tooltip = "Esposa al enemigo cercano (necesita Handcuffs; Police). Validación 8-studs es client-side" })
        v3:AddButton("Detonate C4 (op44)", function() Niche.detonateC4() end)

        -- Auto Weapons: teleport a un pickup suelto + grab (op12) + volver. Multi-select con búsqueda.
        local AW = Misc:AddSection("Auto Weapons", "Recoge armas sueltas del mapa (teleport + grab)", { Columns = 2 })
        local aw1 = AW:AddPanel("Auto Weapons", { Column = 1 })
        aw1:AddToggle("AutoWeapons", { Text = "Auto Weapons", Default = false,
            Tooltip = "Va al pickup de un arma seleccionada, la agarra (op12 ReceiveTool) y restaura tu posición. Persiste en muerte. Elegí las armas en la lista →" })
        aw1:AddToggle("AWPosSpoof", { Text = "Pos Spoof", Default = true,
            Tooltip = "ON = desync (server te ve en el pickup, tu cuerpo REAL se queda = menos riesgo de arresto). OFF = teletransporta el cuerpo real (más visible)." })
        aw1:AddButton("Grab Now", function()
            local wl = Lib.Options.WeaponList
            if wl then AutoWeapons.nextRun = 0; AutoWeapons.tick(wl:GetValue()) end
        end)
        aw1:AddDivider()
        aw1:AddLabel("Buscá y tildá las armas que querés. Agarra la 1a disponible de tu selección.", {})
        local aw2 = AW:AddPanel("Weapon List", { Column = 2 })
        local weaponList
        aw2:AddTextBox("WeaponSearch", { Text = "Search", Placeholder = "filtrar arma...",
            Callback = function(txt)
                if not weaponList then return end
                txt = (txt or ""):lower()
                if txt == "" then weaponList:SetValues(AutoWeapons.WEAPONS); return end
                local f = {}
                for _, n in ipairs(AutoWeapons.WEAPONS) do if n:lower():find(txt, 1, true) then f[#f+1] = n end end
                weaponList:SetValues(f)
            end })
        weaponList = aw2:AddList("WeaponList", { Values = AutoWeapons.WEAPONS, Multi = true, Height = 150 })

        --========================= VISUALS =========================--
        -- Categoría "Visuals": Hit Effects (LiP) + suite World Visuals (GUIVisuals: World/ESP/SelfFX/Preview),
        -- montada en main via Visuals.Attach que REUSA esta categoría por Window.__visualsCat. El ESP viejo
        -- de LiP lo reemplaza el ESP de GUIVisuals (box/health/skeleton/headdot/tracer/offscreen/chams/object).
        local Vis  = Window:AddCategory("Visuals", "eye")
        Window.__visualsCat = Vis

        -- Hit Effects: hitsounds + killsounds + hitmarker (detección por correlación con tu disparo)
        local HFX = Vis:AddSection("Hit Effects", "Hit/Kill sounds + hitmarker", { Columns = 2 })
        local hf1 = HFX:AddPanel("Sounds", { Column = 1 })
        hf1:AddToggle("HitSound", { Text = "Hit Sound", Default = false, Tooltip = "Suena al confirmar un hit (op46 del server)." })
        hf1:AddDropdown("HitSoundName", { Text = "Sound", Values = HitFX.HITNAMES, Default = "Neverlose",
            Tooltip = "Hitsounds de tu Overkill. (Neverlose Old / Sparkles / Ouch no cargan en LiP.)" })
        hf1:AddTextBox("HitSoundId", { Text = "Custom ID (opcional)", Default = "", Numeric = true,
            Tooltip = "rbxassetid propio; si lo ponés, overridea el dropdown." })
        hf1:AddSlider("HitVol", { Text = "Hit Volume", Min = 0.1, Max = 10, Default = 2, Decimals = 1 })
        hf1:AddSlider("HitPitch", { Text = "Hit Pitch", Min = 0.5, Max = 3, Default = 1, Decimals = 2 })
        hf1:AddDivider()
        hf1:AddToggle("KillSound", { Text = "Kill Sound", Default = false, Tooltip = "Suena al matar (enemigo muere con un hit tuyo reciente)." })
        hf1:AddDropdown("KillSoundName", { Text = "Sound", Values = HitFX.KILLNAMES, Default = "Killsound1" })
        hf1:AddTextBox("KillSoundId", { Text = "Custom ID (opcional)", Default = "", Numeric = true })
        hf1:AddSlider("KillVol", { Text = "Kill Volume", Min = 0.1, Max = 10, Default = 3, Decimals = 1 })
        hf1:AddSlider("KillPitch", { Text = "Kill Pitch", Min = 0.5, Max = 3, Default = 1, Decimals = 2 })
        hf1:AddDivider()
        hf1:AddButton("Test Hit", function() HitFX.testHit() end)
        hf1:AddButton("Test Kill", function() HitFX.testKill() end)
        local hf2 = HFX:AddPanel("Hitmarker", { Column = 2 })
        hf2:AddToggle("HitMarker", { Text = "Hitmarker (X)", Default = false, Tooltip = "X en el punto del hit, se desvanece." })
            :AddColorPicker("HitMarkColor", { Default = Color3.fromRGB(255, 255, 255) })
        hf2:AddSlider("HitMarkSize", { Text = "Size", Min = 2, Max = 20, Default = 7 })
        hf2:AddSlider("HitMarkGap", { Text = "Gap", Min = 0, Max = 15, Default = 4 })
    end

    return UI
end

end)()
_MODS["main"] = (function()
-- main.lua — FACTORY. Driver: Window PrimordialUI + loop de estado (Heartbeat).
-- Posición: Godmode > Target Strafe > Void Spam (mutuamente excluyentes, todos por desync/física).
return function(require, LIP, Lib)
    local RunService = game:GetService("RunService")
    local Players    = game:GetService("Players")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer

    local Ragdoll = require("Combat.Ragdoll")
    local Target  = require("Combat.Target")
    local Melee   = require("Combat.Melee")
    local Strafe  = require("Combat.Strafe")
    local Weapon  = require("Combat.Weapon")
    local Godmode = require("Combat.Godmode")
    local Niche   = require("Combat.Niche")
    local AutoWeapons = require("Combat.AutoWeapons")
    local Net     = require("Net")
    local Move    = require("Movement.Movement")
    local Vehicle = require("Movement.Vehicle")
    local Void    = require("Movement.Void")
    local HitFX   = require("Visuals.HitEffects")
    local CrossHUD = require("Visuals.CrosshairHUD")
    local UI      = require("UI")

    local Window = Lib:CreateWindow({ Title = "life in prison", Size = Vector2.new(834, 586) })
    LIP.Library = Lib
    UI.build(Window)
    -- Suite World Visuals (GUIVisuals) → categoría "Visuals" (World/ESP/SelfFX). Reemplaza el ESP viejo de
    -- LiP. Reusa la categoría "Visuals" que UI.build ya creó (Window.__visualsCat). Genérico (sin profile):
    -- ESP enumera Players (R6), SelfFX = Camera.FOV/crosshair/HUD, World = Lighting. Guarded por si falta.
    if LIP.Visuals and LIP.Visuals.Attach then
        pcall(function()
            LIP.Visuals.Attach(Lib, Window, { adapter = "primordial", modules = { "world", "esp", "selffx" } })
        end)
    end
    Net.install()    -- __namecall silent aim op14 + melee aura op16
    Move.init()      -- fly/noclip/speed/jump
    Vehicle.init()   -- vehicle speed
    Strafe.init()    -- Spoof.init (hook __index + restore RenderStepped, compartido con Void)
    Void.init()      -- void spam + visualizador (Spoof.init idempotente)
    HitFX.init()     -- hitsounds / killsounds / hitmarker (op46)
    CrossHUD.init()  -- labels de estado del ragebot abajo del crosshair

    -- ANTI-SLEEP (keep-alive del replicador): Roblox pausa la replicación de posición si el assembly
    -- "duerme" (velocity < ~0.05 studs/s) → rompe el desync/spoof. La velocity vieja (0.003) estaba POR
    -- DEBAJO del umbral → dormía igual. Ahora aplicamos una magnitud CLARAMENTE arriba del umbral (0.6
    -- studs/s) ALTERNANDO el signo cada frame → nunca duerme, pero el desplazamiento neto ≈ 0 (no derivás).
    local kaSign = 1
    LIP.track(RunService.Heartbeat:Connect(function()
        local c = LP.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if root and root.AssemblyLinearVelocity.Magnitude < 0.5 then
            kaSign = -kaSign
            root.AssemblyLinearVelocity = Vector3.new(0, 0.6 * kaSign, 0)
        end
    end))

    local T, O = Lib.Toggles, Lib.Options

    -- precache del hit de silent aim / autofire (Head del target, resolver opcional)
    local function cacheHit()
        local t = LIP.target
        if t and LIP.lastGoodUID ~= t.UserId then LIP.lastGoodHitPos = nil; LIP.lastGoodUID = t.UserId end
        local ch = t and t.Character
        local part = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
        LIP.cachedHitPart = part
        if part then
            -- HBE-SAFE por default: hitPos = CENTRO del hitPart (objspace ZERO), el server aplica daño al
            -- hitPart real. HARMONÍA (Resolver + Fire on Resolved): si el resolver está confiado (didDefensive),
            -- disparar a la pos RESUELTA (no al head crudo del ghost en el void) — RIESGO HBE, aceptado.
            local base = part.Position
            local resolveOn = T.Resolver and T.Resolver.Value
            local fireResOn = resolveOn and (T.FireResolved and T.FireResolved.Value)
            local voidMan = (Strafe.CONF and Strafe.CONF.voidManhattan) or 7000
            local inVoid = (math.abs(base.X) + math.abs(base.Z)) >= voidMan
            local resolved, didDef
            if resolveOn then resolved, didDef = Strafe.resolveAim(t, base) end   -- puebla resState (confianza) aunque FireResolved off
            if fireResOn and didDef and resolved then
                LIP.cachedHitPos = resolved; LIP.didDefensive = true
            elseif inVoid and LIP.lastGoodHitPos then
                LIP.cachedHitPos = LIP.lastGoodHitPos; LIP.didDefensive = false   -- guard anti-void: nunca latch al ghost
            else
                LIP.cachedHitPos = base; LIP.didDefensive = false
            end
            if not inVoid then LIP.lastGoodHitPos = base end
            LIP.targetExposed = not inVoid   -- head crudo real/visible → habilita fire oportunista
            -- WALLBANG: raycast target->yo; origin = del lado del target de la pared = LOS garantizada
            if T.Wallbang and T.Wallbang.Value then
                local myHead = LP.Character and LP.Character:FindFirstChild("Head")
                local hitPos = LIP.cachedHitPos
                if myHead then
                    local to = myHead.Position
                    local rp = RaycastParams.new()
                    rp.FilterType = Enum.RaycastFilterType.Exclude
                    rp.FilterDescendantsInstances = { LP.Character, ch }
                    rp.IgnoreWater = true
                    local res = Workspace:Raycast(hitPos, (to - hitPos), rp)
                    if res then
                        LIP.cachedOrigin = res.Position + (hitPos - to).Unit * 2   -- 2 studs del lado del target
                    else
                        LIP.cachedOrigin = to                                       -- LOS clara → origin real
                    end
                else LIP.cachedOrigin = hitPos end
            else
                LIP.cachedOrigin = nil
            end
        else
            LIP.cachedHitPos = nil; LIP.cachedOrigin = nil; LIP.didDefensive = false; LIP.lastGoodHitPos = nil; LIP.targetExposed = false
        end
    end

    local function stillValid(plr, filters)
        if not (plr and plr.Parent) then return false end
        local c = plr.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if not (hum and hrp and hum.Health > 0) then return false end
        if filters.teamCheck and LP.Team and plr.Team == LP.Team then return false end
        return true
    end

    -- target: manual (persiste muerte/rejoin) > selección por SelMode cada frame (Crosshair/Distance/Health)
    local function resolveTarget(filters, needAim)
        local manual = Strafe.manualPlayer()
        if manual then LIP.target = manual; return end
        if needAim then
            Target.pick({ mode = O.SelMode.Value, fov = O.FOV.Value, wallcheck = T.Wallcheck.Value,
                          teamCheck = filters.teamCheck, friendCheck = filters.friendCheck, ffCheck = filters.ffCheck })
        else
            LIP.target = nil
        end
    end

    LIP.track(RunService.Heartbeat:Connect(function()
        LIP.antiInvis = T.AntiInvis and T.AntiInvis.Value or false
        LIP.swapOn    = T.SilentAim and T.SilentAim.Value or false
        LIP.meleeOn   = T.MeleeAura and T.MeleeAura.Value or false
        LIP.wallbang  = T.Wallbang and T.Wallbang.Value or false
        -- bullet multiplier: N pellets por disparo (el Net hook padea el array del op14 del juego/nuestro)
        LIP.bulletMult = (T.MultiFire and T.MultiFire.Value and O.BulletMult and O.BulletMult.Value) or 1
        -- al CAMBIAR de arma: reset del firerate observado + contador → el autofire re-aprende el firerate nuevo
        do
            local et = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
            local en = et and et.Name
            if en ~= LIP.curWeapon then LIP.curWeapon = en; LIP.observedFirerate = nil; LIP.shotsFired = 0 end
        end
        local filters = { teamCheck = T.TeamCheck.Value, friendCheck = T.FriendCheck.Value,
                          ffCheck = T.FFCheck and T.FFCheck.Value }
        local cam = Workspace.CurrentCamera

        local strafeOn   = T.TargetStrafe and T.TargetStrafe.Value
        local autoOn     = T.AutoFire and T.AutoFire.Value
        local godOn      = T.Godmode and T.Godmode.Value
        -- Void Spam SOLO con Target Strafe (compone): OUT = strafe-orbit (dispara), IN = void (esconde).
        local voidSpamOn = T.VoidSpam and T.VoidSpam.Value and strafeOn
        local idleOn     = T.IdleState and T.IdleState.Value     -- viejo void = anti-aim idle continuo
        LIP.voidSpamOn   = voidSpamOn
        LIP.voidShootOut = (not T.VoidShootOut) or T.VoidShootOut.Value    -- default on
        if not voidSpamOn then LIP.voidShootOk = true; LIP.voidPhase = nil end
        local needAim  = LIP.swapOn or strafeOn or autoOn

        -- resolver sampling (historial de enemigos)
        if needAim or (T.Resolver and T.Resolver.Value) then Strafe.sampleAll(os.clock()) end

        -- target + precache (para silent aim swap Y autofire)
        resolveTarget(filters, needAim)
        if LIP.target then
            cacheHit()
            Strafe.updateHitConfirm(LIP.target, os.clock())   -- hit-confirm auto-tune (HP-drop → acc)
        else
            LIP.cachedHitPart, LIP.cachedHitPos, LIP.didDefensive, LIP.lastGoodHitPos, LIP.targetExposed = nil, nil, false, nil, false
        end

        -- FF/DEAD CHECK: si el target enfocado tiene ForceField (spawn protection) o murió → HOLD: esconderse
        -- (idle) y NO atacar hasta que respawnee / se le quite el FF. SOLO con Target Strafe activo (AutoFire
        -- ya requiere strafe) → al apagar Target Strafe el idle se quita SIEMPRE. Ignore TEMPORAL.
        local holdIdle = false
        if T.FFCheck and T.FFCheck.Value and strafeOn and LIP.target then
            local tc = LIP.target.Character
            local th = tc and tc:FindFirstChildOfClass("Humanoid")
            if (tc and tc:FindFirstChildOfClass("ForceField")) or not (th and th.Health > 0) then holdIdle = true end
        end
        LIP.attackHold = holdIdle
        if holdIdle then LIP.cachedHitPart = nil; LIP.cachedHitPos = nil; LIP.didDefensive = false end

        -- ── HUD del crosshair: estado del ragebot (base + overrides) ──
        do
            local eng = strafeOn and autoOn   -- label base solo con Target Strafe + Auto Fire AMBOS activos
            LIP.hudTargetName = (eng and LIP.target) and LIP.target.Name or nil
            LIP.hudResolved   = LIP.target and Strafe.confidence(LIP.target) or 0
            LIP.hudReloadVoid = (LIP.reloading and LIP.voidPhase == "in") or false
            -- killed-wait: armá el watch mientras enganchás un focus VIVO; al morir → "waiting for HRP"
            -- hasta que respawnee vivo + sin ForceField (o se vaya del server).
            if strafeOn and LIP.target and LIP.target.Character then
                local h = LIP.target.Character:FindFirstChildOfClass("Humanoid")
                if h and h.Health > 0 then LIP._killWatchUid = LIP.target.UserId; LIP._killWatchName = LIP.target.Name end
            end
            if LIP._killWatchUid then
                local wp
                for _, p in ipairs(Players:GetPlayers()) do if p.UserId == LIP._killWatchUid then wp = p; break end end
                if not wp then
                    LIP.killedWait, LIP._killWatchUid, LIP._killWatchName = nil, nil, nil        -- salió del server
                else
                    local wc  = wp.Character
                    local wh  = wc and wc:FindFirstChildOfClass("Humanoid")
                    local wff = wc and wc:FindFirstChildOfClass("ForceField")
                    if not (wh and wh.Health > 0) then
                        LIP.killedWait = LIP._killWatchName                                       -- muerto → esperando HRP
                    elseif not wff then
                        LIP.killedWait, LIP._killWatchUid, LIP._killWatchName = nil, nil, nil     -- respawn + FF off → limpiar
                    end
                end
            end
        end

        -- ── POSICIÓN: Godmode > Strafe (+VoidSpam) > IdleState (EXCLUYENTES). ConnExploit = master de método. ──
        local posSpoof = T.PosSpoof and T.PosSpoof.Value
        local connExp  = T.ConnExploit and T.ConnExploit.Value
        if LIP.awGrabbing then
            -- AutoWeapons está agarrando (controla su propio desync) → no tocar la posición ni disparar
        elseif godOn then
            if LIP.spoofOn or LIP.connRep then Strafe.stop() end
            Godmode.tick()
        elseif holdIdle then
            -- target protegido/muerto → esconderse temporal (idle anti-aim), sin atacar
            if LIP.godBase then Godmode.stop() end
            Void.tick({ dist = O.IdleDist.Value, pattern = O.IdlePattern:GetValue(),
                        posSpoof = posSpoof, connExploit = connExp })
        elseif strafeOn then
            if LIP.godBase then Godmode.stop() end
            local st = LIP.target or Target.nearestEnemy({ range = 200,
                          teamCheck = filters.teamCheck, friendCheck = filters.friendCheck, ffCheck = filters.ffCheck })
            if st then
                local strafeOpts = { mode = O.StrafeMode.Value, radius = O.StrafeRadius.Value,
                                  speed = O.StrafeSpeed.Value, height = O.StrafeHeight.Value,
                                  posSpoof = posSpoof, connExploit = connExp, bait = T.StrafeBait.Value,
                                  predict = O.ResolverPredict.Value,
                                  resolve = T.Resolver and T.Resolver.Value,
                                  resolveMethod = O.ResolverMethod.Value }
                if voidSpamOn then
                    -- VOID SPAM sobre el strafe: OUT = strafe-orbit (dispara), IN = void (esconde); force-void en reload
                    local phase = Void.voidStep({ inTime = O.VoidInTime.Value, outTime = O.VoidOutTime.Value,
                                                  voidReload = T.VoidReload and T.VoidReload.Value })
                    if phase == "out" then
                        Strafe.tick(st, strafeOpts)
                    else
                        Void.tickVoidPos({ dist = O.VoidDist.Value, pattern = O.VoidPattern:GetValue(), connExploit = connExp, posSpoof = posSpoof })
                    end
                else
                    Strafe.tick(st, strafeOpts)
                end
            else Strafe.stop() end
        elseif idleOn then
            if LIP.godBase then Godmode.stop() end
            Void.tick({ dist = O.IdleDist.Value, pattern = O.IdlePattern:GetValue(),
                        posSpoof = posSpoof, connExploit = connExp })
        else
            if LIP.godBase then Godmode.stop() end
            if LIP.spoofOn or LIP.connRep then Strafe.stop() end
        end

        -- spectator (override de cámara al target manual)
        if T.Spectate and T.Spectate.Value then Strafe.spectate(cam) end

        -- auto/rapid fire (op14 directo con ammo tracking; funciona ragdolleado)
        Weapon.tickAuto()

        -- melee aura / auto punch
        if LIP.meleeOn then
            Melee.cacheMelee({ range = O.MeleeRange.Value, teamCheck = filters.teamCheck, friendCheck = filters.friendCheck, ffCheck = filters.ffCheck })
        else LIP.meleePart = nil end
        if T.AutoPunch and T.AutoPunch.Value then
            Melee.autoPunch({ range = O.PunchRange.Value, rate = 0.5, teamCheck = filters.teamCheck, friendCheck = filters.friendCheck, ffCheck = filters.ffCheck })
        end

        -- niche autos (throw / arrest)
        if T.AutoThrow and T.AutoThrow.Value then
            Niche.throwAt({ teamCheck = filters.teamCheck, friendCheck = filters.friendCheck, ffCheck = filters.ffCheck })
        end
        if T.AutoArrest and T.AutoArrest.Value then
            Niche.arrest({ teamCheck = filters.teamCheck, friendCheck = filters.friendCheck, ffCheck = filters.ffCheck })
        end

        -- auto weapons: recoge armas sueltas del mapa (teleport+grab, pos real restaurada)
        if T.AutoWeapons and T.AutoWeapons.Value and O.WeaponList then
            AutoWeapons.tick(O.WeaponList:GetValue(), T.AWPosSpoof and T.AWPosSpoof.Value)
        end

        -- permanent ragdoll (si no está godmode, que ya maneja el ragdoll)
        if not godOn and T.RagdollLock and T.RagdollLock.Value then Ragdoll.tickLock() end
    end))

    pcall(function() if Window.AddSettingsTab then Window:AddSettingsTab() end end)
    pcall(function()
        if Lib.SetWatermark then Lib:SetWatermark("life in prison \226\128\162 primordial") end
        if Lib.SetWatermarkVisibility then Lib:SetWatermarkVisibility(true) end
    end)
    pcall(function() if Lib.LoadAutoloadConfig then Lib:LoadAutoloadConfig() end end)
    Lib:Notify({ Title = "LifeInPrisonPrimordial", Description = "Rage/Legit/Misc cargado.", Time = 5 })
end

end)()
local _cache = {}
local Lib = (function()
-- PrimordialUI bundle (auto-generado por build.lua) --
local P = {}
-- ==== Core/Signal ====
do local __m = (function()
return function(P)
    local Signal = {}
    Signal.__index = Signal
    function Signal.new()
        return setmetatable({ _cbs = {} }, Signal)
    end
    function Signal:Connect(fn)
        local conn = { fn = fn, _sig = self }
        function conn:Disconnect()
            for i, c in ipairs(self._sig._cbs) do
                if c == self then table.remove(self._sig._cbs, i) break end
            end
        end
        table.insert(self._cbs, conn)
        return conn
    end
    function Signal:Fire(...)
        for _, c in ipairs({ table.unpack(self._cbs) }) do
            task.spawn(c.fn, ...)
        end
    end
    function Signal:DisconnectAll() self._cbs = {} end
    P.Signal = Signal
end

end)(); __m(P) end
-- ==== Core/Theme ====
do local __m = (function()
return function(P)
    P.Theme = {
        Accent    = Color3.fromRGB(202, 151, 161),  -- rosa mauve exacto (swatch primordial)
        AccentDim = Color3.fromRGB(138, 102, 110),
        Bg        = Color3.fromRGB(29, 29, 32),      -- fondo window (no negro)
        Surface   = Color3.fromRGB(34, 34, 37),      -- panels
        Bar       = Color3.fromRGB(40, 40, 44),      -- header + barra de categorias (mas claro que bg/panels)
        Sidebar   = Color3.fromRGB(32, 32, 35),      -- sidebar (un pelin mas oscuro)
        Surface2  = Color3.fromRGB(23, 23, 26),      -- controls (toggle/dropdown/textbox/slider) mas oscuro que Bg
        Surface3  = Color3.fromRGB(56, 56, 62),      -- hover / pill categoria activa
        Knob      = Color3.fromRGB(206, 206, 211),   -- perilla gris clara
        Outline   = Color3.fromRGB(48, 48, 53),
        Border    = Color3.fromRGB(8, 8, 10),        -- borde negro thin de panels
        Text      = Color3.fromRGB(228, 228, 233),
        SubText   = Color3.fromRGB(132, 132, 140),
        Positive  = Color3.fromRGB(120, 200, 120),
        Negative  = Color3.fromRGB(210, 70, 70),
        Radius    = 5,
        RadiusBig = 7,
        Pad       = 6,
        RowH      = 22,          -- compacto (match primordial real)
        Font      = Enum.Font.Gotham,
        FontBold  = Enum.Font.GothamBold,
        TextSize  = 12,
        Shadow    = "rbxassetid://6014261993",       -- drop shadow 9-slice
    }
end

end)(); __m(P) end
-- ==== Core/Util ====
do local __m = (function()
return function(P)
    local TweenService = game:GetService("TweenService")
    local UIS = game:GetService("UserInputService")
    local Util = {}

    function Util.Create(class, props, children)
        local inst = Instance.new(class)
        for k, v in pairs(props or {}) do
            if k ~= "Parent" then inst[k] = v end
        end
        for _, c in ipairs(children or {}) do c.Parent = inst end
        if props and props.Parent then inst.Parent = props.Parent end
        return inst
    end

    function Util.Tween(inst, info, goal)
        local t = TweenService:Create(inst, info, goal); t:Play(); return t
    end

    function Util.Round(n, dec)
        local m = 10 ^ (dec or 0)
        return math.floor(n * m + 0.5) / m
    end

    function Util.GetGui()
        local parent
        local ok = pcall(function() parent = gethui() end)
        if not ok or not parent then
            parent = game:GetService("CoreGui")
        end
        return parent
    end

    -- Arrastre: handleGui recibe input, mueve targetFrame por delta.
    -- maid opcional: objeto con :Maid(conn) para limpiar la conexion global en Unload.
    function Util.Drag(handleGui, targetFrame, maid)
        local dragging, startPos, startInput
        local function reg(c) if maid then maid:Maid(c) end return c end
        reg(handleGui.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                if maid and maid.CloseActivePopup then maid:CloseActivePopup() end
                dragging = true
                startPos = targetFrame.Position
                startInput = input.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end))
        reg(UIS.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - startInput
                targetFrame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end))
    end

    -- Sombra suave y externa detras de un frame (elevacion sutil).
    -- Usar SOLO en frames que NO sean AutomaticSize (si no, la infla).
    function Util.Shadow(target, opts)
        opts = opts or {}
        local sp = opts.Spread or 22
        local sh = Instance.new("ImageLabel")
        sh.Name = "Shadow"
        sh.BackgroundTransparency = 1
        sh.Image = P.Theme.Shadow
        sh.ImageColor3 = opts.Color or Color3.new(0, 0, 0)
        sh.ImageTransparency = opts.Transparency or 0.78
        sh.ScaleType = Enum.ScaleType.Slice
        sh.SliceCenter = Rect.new(49, 49, 450, 450)
        sh.ZIndex = -1
        sh.AnchorPoint = Vector2.new(0.5, 0.5)
        sh.Position = UDim2.new(0.5, 0, 0.5, opts.YOffset or 4)
        sh.Size = UDim2.new(1, sp * 2, 1, sp * 2)
        sh.Parent = target
        return sh
    end

    -- Profundidad interna sutil para controles (Surface2). Oscurece hacia abajo
    -- (gradiente multiplicativo) + linea de highlight 1px arriba (borde superior con luz).
    -- opts.Bottom = cuanto oscurece abajo (0..1, default 0.14). opts.Highlight = agregar rim light.
    function Util.Depth(inst, opts)
        opts = opts or {}
        local b = 1 - (opts.Bottom or 0.14)
        local g = Instance.new("UIGradient")
        g.Rotation = 90
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.new(b, b, b)),
        })
        g.Parent = inst
        if opts.Highlight then
            local hl = Instance.new("Frame")
            hl.Name = "Rim"; hl.BorderSizePixel = 0
            hl.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            hl.BackgroundTransparency = opts.HighlightT or 0.9
            hl.Position = UDim2.fromOffset(2, 1)
            hl.Size = UDim2.new(1, -4, 0, 1)
            hl.ZIndex = (inst.ZIndex or 1) + 1
            hl.Parent = inst
        end
        return g
    end

    P.Util = Util
end

end)(); __m(P) end
-- ==== Core/Registry ====
do local __m = (function()
return function(P)
    local Registry = {}
    Registry.__index = Registry
    function Registry.new() return setmetatable({ _items = {} }, Registry) end
    function Registry:Add(inst, role, prop)
        table.insert(self._items, { inst = inst, role = role, prop = prop })
        if P.Theme[role] then inst[prop] = P.Theme[role] end
    end
    function Registry:Apply(theme)
        for _, it in ipairs(self._items) do
            if it.inst and it.inst.Parent ~= nil and theme[it.role] then
                it.inst[it.prop] = theme[it.role]
            end
        end
    end
    P.Registry = Registry
end

end)(); __m(P) end
-- ==== Core/Icons ====
do local __m = (function()
return function(P)
    local Icons = {}
    -- fuente Lucide para Roblox (spritesheet), cargada lazy + cacheada
    Icons.URL = "https://raw.githubusercontent.com/deividcomsono/lucide-roblox-direct/refs/heads/main/source.lua"
    Icons._mod = nil  -- nil = sin intentar; false = fallo; table = cargado

    function Icons.load()
        if Icons._mod ~= nil then return Icons._mod or nil end
        local ok, mod = pcall(function()
            return loadstring(game:HttpGet(Icons.URL))()
        end)
        Icons._mod = (ok and type(mod) == "table" and mod) or false
        return Icons._mod or nil
    end

    -- resuelve un icono a props de ImageLabel.
    -- acepta: nombre Lucide ("crosshair"), "rbxassetid://123", "rbxasset://...", o numero.
    function Icons.resolve(icon)
        if not icon or icon == "" then return nil end
        icon = tostring(icon)
        if icon:match("^%d+$") then return { Image = "rbxassetid://" .. icon } end
        if icon:match("^rbxasset") then return { Image = icon } end
        local mod = Icons.load()
        if mod and mod.GetAsset then
            local ok, a = pcall(mod.GetAsset, icon)
            if ok and type(a) == "table" then
                return { Image = a.Url or a.Image, ImageRectOffset = a.ImageRectOffset, ImageRectSize = a.ImageRectSize }
            end
        end
        return nil
    end

    -- aplica el icono a un ImageLabel/ImageButton existente
    function Icons.apply(img, icon)
        local r = Icons.resolve(icon)
        if not r then img.Image = ""; return false end
        img.Image = r.Image
        img.ImageRectOffset = r.ImageRectOffset or Vector2.zero
        img.ImageRectSize = r.ImageRectSize or Vector2.zero
        return true
    end

    P.Icons = Icons
end

end)(); __m(P) end
-- ==== Core/Library ====
do local __m = (function()
return function(P)
    local UIS = game:GetService("UserInputService")
    local Library = {
        Flags = {}, Toggles = {}, Options = {}, Windows = {},
        Open = true, Unloaded = false,
        ToggleKey = Enum.KeyCode.RightShift,
        Connections = {}, _flagSignals = {},
    }
    Library.Registry = P.Registry.new()
    Library.FlagChanged = P.Signal.new()

    function Library:Maid(x) table.insert(self.Connections, x); return x end

    function Library:GetFlagSignal(flag)
        local s = self._flagSignals[flag]
        if not s then s = P.Signal.new(); self._flagSignals[flag] = s end
        return s
    end

    function Library:SetFlag(flag, value)
        self.Flags[flag] = value
        self.FlagChanged:Fire(flag, value)
        local s = self._flagSignals[flag]
        if s then s:Fire(value) end
    end

    -- solo un popup (dropdown/colorpicker/gear) abierto a la vez
    function Library:OpenPopup(closer)
        if self._activePopup and self._activePopup ~= closer then pcall(self._activePopup) end
        self._activePopup = closer
    end
    function Library:ClosePopup(closer)
        if self._activePopup == closer then self._activePopup = nil end
    end
    function Library:CloseActivePopup()
        if self._activePopup then local c = self._activePopup; self._activePopup = nil; pcall(c) end
    end

    function Library:SetTheme(patch)
        for k, v in pairs(patch or {}) do P.Theme[k] = v end
        self.Registry:Apply(P.Theme)
    end

    function Library:CreateWindow(opts)
        if not P.Window then warn("PrimordialUI: Window module ausente"); return nil end
        local w = P.Window.new(self, opts or {})
        table.insert(self.Windows, w)
        return w
    end

    function Library:Unload()
        self.Unloaded = true
        for _, c in ipairs(self.Connections) do
            pcall(function() if c.Disconnect then c:Disconnect() elseif c.Destroy then c:Destroy() end end)
        end
        self.Connections = {}
        for _, w in ipairs(self.Windows) do pcall(function() w:Destroy() end) end
        self.Windows = {}
        if getgenv then getgenv().__PUI = nil end
    end

    -- toggle show/hide global
    Library:Maid(UIS.InputBegan:Connect(function(inp, gpe)
        if gpe then return end
        if inp.KeyCode == Library.ToggleKey then
            Library.Open = not Library.Open
            for _, w in ipairs(Library.Windows) do w:SetVisible(Library.Open) end
        end
    end))

    -- single-instance: descarga cualquier instancia previa al recargar la lib
    if getgenv then
        if getgenv().__PUI then pcall(function() getgenv().__PUI:Unload() end) end
        -- barrer guis huerfanas (windows PUI_ y overlays PUIo_) de instancias leakeadas
        pcall(function()
            local roots = {}
            local ok, hui = pcall(function() return gethui() end)
            if ok and hui then table.insert(roots, hui) end
            table.insert(roots, game:GetService("CoreGui"))
            for _, r in ipairs(roots) do
                for _, g in ipairs(r:GetChildren()) do
                    if g:IsA("ScreenGui") and (tostring(g.Name):match("^PUI_") or tostring(g.Name):match("^PUIo_")) then
                        g:Destroy()
                    end
                end
            end
        end)
        getgenv().__PUI = Library
    end
    P.Library = Library
end

end)(); __m(P) end
-- ==== Core/Overlays ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local UIS = game:GetService("UserInputService")
    local Lib = P.Library

    Lib.DPIScale = 1
    function Lib:SetDPIScale(pct)
        self.DPIScale = math.clamp(pct / 100, 0.5, 2)
        for _, w in ipairs(self.Windows) do
            if w.UIScale then w.UIScale.Scale = self.DPIScale end
        end
    end

    -- ScreenGui compartido para overlays (no escala con el DPI del menu)
    local function overlay()
        if Lib._overlayGui and Lib._overlayGui.Parent then return Lib._overlayGui end
        Lib._overlayGui = U.Create("ScreenGui", { Name = "PUIo_" .. tostring(math.random(1e5, 9e5)),
            ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9999, Parent = U.GetGui() })
        Lib:Maid(Lib._overlayGui)
        return Lib._overlayGui
    end

    -- hace un overlay arrastrable y persiste su posicion en self._overlayPos[key]
    function Lib:_trackOverlay(key, frame)
        self._overlayPos = self._overlayPos or {}
        local p = self._overlayPos[key]
        if p then frame.Position = UDim2.fromOffset(p[1], p[2]) end
        U.Drag(frame, frame, self)
        frame:GetPropertyChangedSignal("Position"):Connect(function()
            self._overlayPos[key] = { frame.Position.X.Offset, frame.Position.Y.Offset }
        end)
    end
    -- aplica posiciones guardadas (llamado por LoadConfig)
    function Lib:ApplyOverlayPositions(pos)
        self._overlayPos = pos or {}
        if self._wm and self._overlayPos.watermark then
            local p = self._overlayPos.watermark; self._wm.Position = UDim2.fromOffset(p[1], p[2])
        end
        if self._kbFrame and self._overlayPos.keybindlist then
            local p = self._overlayPos.keybindlist; self._kbFrame.Position = UDim2.fromOffset(p[1], p[2])
        end
    end

    ---------------------------------------------------------------- WATERMARK
    function Lib:SetWatermark(text)
        local g = overlay()
        if not self._wm then
            self._wm = U.Create("Frame", { Parent = g, BackgroundColor3 = T.Bar, BorderSizePixel = 0,
                Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(10, 24),
                AutomaticSize = Enum.AutomaticSize.X,
            }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
                U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
                U.Create("Frame", { Name = "Bar", BackgroundColor3 = T.Accent, BorderSizePixel = 0,
                    Size = UDim2.new(0, 2, 1, 0) }),
                U.Create("TextLabel", { Name = "T", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X,
                    Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 0, 1, 0),
                    Font = T.FontBold, TextSize = 13, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left },
                    { U.Create("UIPadding", { PaddingRight = UDim.new(0, 10) }) }) })
            self.Registry:Add(self._wm.Bar, "Accent", "BackgroundColor3")
            self:_trackOverlay("watermark", self._wm)
        end
        self._wm.T.Text = text
    end
    function Lib:SetWatermarkVisibility(b)
        if not self._wm and b then self:SetWatermark("PrimordialUI") end
        if self._wm then self._wm.Visible = b end
    end

    ---------------------------------------------------------------- TOOLTIP
    local function tip()
        if Lib._tip and Lib._tip.Parent then return Lib._tip end
        Lib._tip = U.Create("TextLabel", { Parent = overlay(), Visible = false, ZIndex = 50,
            BackgroundColor3 = T.Surface2, AutomaticSize = Enum.AutomaticSize.XY,
            Font = T.Font, TextSize = 12, TextColor3 = T.Text, Text = "",
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
            U.Create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
                PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }) })
        return Lib._tip
    end
    function Lib:ShowTooltip(text)
        local t = tip(); t.Text = text; t.Visible = true
        local m = UIS:GetMouseLocation()
        t.Position = UDim2.fromOffset(m.X + 14, m.Y + 6)
    end
    function Lib:MoveTooltip()
        if self._tip and self._tip.Visible then
            local m = UIS:GetMouseLocation()
            self._tip.Position = UDim2.fromOffset(m.X + 14, m.Y + 6)
        end
    end
    function Lib:HideTooltip() if self._tip then self._tip.Visible = false end end

    ---------------------------------------------------------------- NOTIFY
    function Lib:_notifyHolder()
        if self._nHolder and self._nHolder.Parent then return self._nHolder end
        self._nHolder = U.Create("Frame", { Parent = overlay(), BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16),
            Size = UDim2.fromOffset(250, 600),
        }, { U.Create("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Top,
            HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder }) })
        return self._nHolder
    end
    function Lib:Notify(a, b)
        local title, desc, time
        if type(a) == "table" then title, desc, time = a.Title, a.Description, a.Time
        else title, desc, time = a, nil, b end
        time = time or 4
        local card = U.Create("Frame", { Parent = self:_notifyHolder(), BackgroundColor3 = T.Bar,
            BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
            U.Create("Frame", { Name = "Bar", BackgroundColor3 = T.Accent, BorderSizePixel = 0,
                Size = UDim2.new(0, 2, 1, 0) }) })
        local content = U.Create("Frame", { Parent = card, BackgroundTransparency = 1,
            Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -18, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
        }, { U.Create("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }),
            U.Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }) })
        U.Create("TextLabel", { Parent = content, BackgroundTransparency = 1, LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 16), Font = T.FontBold, TextSize = 13, TextColor3 = T.Text,
            Text = title or "", TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y })
        if desc then
            U.Create("TextLabel", { Parent = content, BackgroundTransparency = 1, LayoutOrder = 2,
                Size = UDim2.new(1, 0, 0, 14), Font = T.Font, TextSize = 12, TextColor3 = T.SubText,
                Text = desc, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
                AutomaticSize = Enum.AutomaticSize.Y })
        end
        task.delay(time, function()
            if card and card.Parent then card:Destroy() end
        end)
        return card
    end

    ---------------------------------------------------------------- THEME PRESETS
    Lib.ThemePresets = {
        Default  = { Accent = Color3.fromRGB(202, 151, 161) },
        Crimson  = { Accent = Color3.fromRGB(214, 84, 84) },
        Ocean    = { Accent = Color3.fromRGB(96, 156, 214) },
        Emerald  = { Accent = Color3.fromRGB(104, 196, 140) },
        Amethyst = { Accent = Color3.fromRGB(168, 130, 214) },
        Amber    = { Accent = Color3.fromRGB(214, 168, 92) },
    }
    function Lib:ListThemePresets()
        local list = {}
        for k in pairs(self.ThemePresets) do table.insert(list, k) end
        table.sort(list)
        return list
    end
    function Lib:ApplyThemePreset(name)
        local p = self.ThemePresets[name]
        if p then self:SetTheme(p) end
    end

    ---------------------------------------------------------------- KEYBIND LIST
    function Lib:_kbHolder()
        if self._kbFrame and self._kbFrame.Parent then return self._kbFrame end
        self._kbFrame = U.Create("Frame", { Parent = overlay(), Visible = false,
            BackgroundColor3 = T.Bar, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 46),
            Size = UDim2.new(0, 160, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
            U.Create("Frame", { Name = "Bar", BackgroundColor3 = T.Accent, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 2) }) })
        self.Registry:Add(self._kbFrame.Bar, "Accent", "BackgroundColor3")
        local body = U.Create("Frame", { Parent = self._kbFrame, Name = "Body", BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        }, { U.Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
            U.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 6),
                PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
        U.Create("TextLabel", { Parent = body, BackgroundTransparency = 1, LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 15), Font = T.FontBold, TextSize = 13, TextColor3 = T.Text,
            Text = "Keybinds", TextXAlignment = Enum.TextXAlignment.Left })
        self._kbBody = body
        self:_trackOverlay("keybindlist", self._kbFrame)
        return self._kbFrame
    end
    function Lib:RegisterKeybind(kb)
        local body = self:_kbHolder().Body or self._kbBody
        local row = U.Create("TextLabel", { Parent = body, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14), Font = T.Font, TextSize = 12, TextColor3 = T.SubText,
            Text = "", TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = #self.KeybindEntries + 1 })
        local entry = { row = row, kb = kb }
        function entry:Update()
            local keyN = self.kb.Key and self.kb.Key.Name or "None"
            self.row.Text = ("%s  [%s]"):format(self.kb.Text or self.kb.Flag, keyN)
            self.row.TextColor3 = self.kb.Active and T.Accent or T.SubText
        end
        table.insert(self.KeybindEntries, entry)
        entry:Update()
        return entry
    end
    Lib.KeybindEntries = Lib.KeybindEntries or {}
    function Lib:SetKeybindListVisibility(b)
        self:_kbHolder().Visible = b
    end
end

end)(); __m(P) end
-- ==== Core/ConfigManager ====
do local __m = (function()
return function(P)
    local Lib = P.Library
    local HttpService = game:GetService("HttpService")

    Lib.ConfigFolder = "PrimordialUI/configs"

    local function ensure()
        if typeof(makefolder) == "function" then
            if not (typeof(isfolder) == "function" and isfolder(Lib.ConfigFolder)) then
                pcall(makefolder, Lib.ConfigFolder)
            end
        end
    end

    -- serializar tipos Roblox a JSON-safe
    local function ser(v)
        local t = typeof(v)
        if t == "boolean" or t == "number" or t == "string" then return v end
        if t == "Color3" then
            return { __ = "c3", r = math.floor(v.R * 255 + 0.5), g = math.floor(v.G * 255 + 0.5), b = math.floor(v.B * 255 + 0.5) }
        end
        if t == "EnumItem" then return { __ = "en", t = tostring(v.EnumType):gsub("^Enum%.", ""), n = v.Name } end
        if t == "table" then
            local o = {}
            for k, x in pairs(v) do o[k] = ser(x) end
            return o
        end
        return nil
    end
    local function deser(v)
        if type(v) ~= "table" then return v end
        if v.__ == "c3" then return Color3.fromRGB(v.r, v.g, v.b) end
        if v.__ == "en" then local ok, e = pcall(function() return Enum[v.t][v.n] end); return ok and e or nil end
        local o = {}
        for k, x in pairs(v) do if k ~= "__" then o[k] = deser(x) end end
        return o
    end

    Lib.ConfigIgnore = {}  -- flags a NO guardar (ej. los widgets del settings tab)
    function Lib:GetConfig()
        local out = {}
        for flag, t in pairs(self.Toggles) do
            if not self.ConfigIgnore[flag] then out[flag] = ser(t:GetValue()) end
        end
        for flag, o in pairs(self.Options) do
            if not self.ConfigIgnore[flag] and o.GetValue then
                local v = o:GetValue()
                if v ~= nil then out[flag] = ser(v) end
            end
        end
        if self._overlayPos then out.__overlays = self._overlayPos end
        return out
    end

    function Lib:LoadConfig(tbl)
        for flag, v in pairs(tbl or {}) do
            if flag ~= "__overlays" then
                local w = self.Toggles[flag] or self.Options[flag]
                if w and w.SetValue then pcall(function() w:SetValue(deser(v)) end) end
            end
        end
        if tbl and tbl.__overlays and self.ApplyOverlayPositions then
            self:ApplyOverlayPositions(tbl.__overlays)
        end
    end

    local function path(name) return Lib.ConfigFolder .. "/" .. name .. ".json" end

    function Lib:SaveConfig(name)
        if not name or name == "" then return false, "sin nombre" end
        ensure()
        local ok = pcall(function()
            writefile(path(name), HttpService:JSONEncode(self:GetConfig()))
        end)
        return ok
    end
    function Lib:LoadConfigFile(name)
        local p = path(name)
        if typeof(isfile) == "function" and not isfile(p) then return false end
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(p)) end)
        if ok and data then self:LoadConfig(data); return true end
        return false
    end
    function Lib:DeleteConfig(name)
        if typeof(delfile) == "function" then pcall(delfile, path(name)) end
    end
    function Lib:ListConfigs()
        local list = {}
        if typeof(listfiles) == "function" and typeof(isfolder) == "function" and isfolder(self.ConfigFolder) then
            for _, f in ipairs(listfiles(self.ConfigFolder)) do
                local n = tostring(f):match("([^/\\]+)%.json$")
                if n then table.insert(list, n) end
            end
        end
        return list
    end
    function Lib:SetAutoloadConfig(name)
        ensure()
        pcall(function() writefile(Lib.ConfigFolder .. "/autoload.txt", name or "") end)
    end
    function Lib:GetAutoloadConfig()
        local p = Lib.ConfigFolder .. "/autoload.txt"
        if typeof(isfile) == "function" and isfile(p) then
            local ok, n = pcall(readfile, p)
            if ok and n and n ~= "" then return n end
        end
        return nil
    end
    function Lib:LoadAutoloadConfig()
        local n = self:GetAutoloadConfig()
        if n then return self:LoadConfigFile(n) end
        return false
    end
end

end)(); __m(P) end
-- ==== Chrome/Window ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Window = {}
    Window.__index = Window

    function Window.new(Library, opts)
        local self = setmetatable({ Library = Library, Categories = {}, ActiveCategory = nil }, Window)
        local size = opts.Size or Vector2.new(834, 586)

        self.Gui = U.Create("ScreenGui", {
            Name = "PUI_"..tostring(math.random(1e5,9e5)),
            ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            Parent = U.GetGui(),
        })
        self.Root = U.Create("Frame", {
            Parent = self.Gui, Size = UDim2.fromOffset(size.X, size.Y),
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            BackgroundColor3 = T.Bg, BorderSizePixel = 0,
        }, {
            U.Create("UICorner", { CornerRadius = UDim.new(0, 10) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),   -- borde negro thin alrededor
        })
        self.UIScale = U.Create("UIScale", { Parent = self.Root, Scale = Library.DPIScale or 1 })
        Library.Registry:Add(self.Root, "Bg", "BackgroundColor3")

        -- Header (mismo alto que la barra inferior = 64); esquinas superiores redondeadas
        local HEADERH = 64
        self.Header = U.Create("Frame", {
            Parent = self.Root, Size = UDim2.new(1, 0, 0, HEADERH),
            BackgroundColor3 = T.Bar, BorderSizePixel = 0,
        }, {
            U.Create("UICorner", { CornerRadius = UDim.new(0, 10) }),
            U.Create("Frame", { Name = "SquareBottom", BorderSizePixel = 0, BackgroundColor3 = T.Bar,
                Position = UDim2.new(0, 0, 1, -10), Size = UDim2.new(1, 0, 0, 10) }),
            U.Create("TextLabel", {
                Name = "Title", BackgroundTransparency = 1,
                Position = UDim2.fromOffset(48, 0), Size = UDim2.new(0.5, -60, 1, 0),
                Font = T.FontBold, TextSize = 22, TextColor3 = T.Accent,
                Text = opts.Title or "primordial",
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
        })
        Library.Registry:Add(self.Header, "Bar", "BackgroundColor3")
        Library.Registry:Add(self.Header.SquareBottom, "Bar", "BackgroundColor3")

        -- barra de busqueda en el header (top-right): contenedor + icono separado del texto
        self.SearchBar = U.Create("Frame", {
            Parent = self.Header, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
            Size = UDim2.fromOffset(220, 28), BackgroundColor3 = T.Surface2, BorderSizePixel = 0,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
            U.Create("ImageLabel", { Name = "Icon", BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0),
                Size = UDim2.fromOffset(14, 14), Image = "rbxassetid://6031154871", ImageColor3 = T.SubText }) })
        self.Search = U.Create("TextBox", { Parent = self.SearchBar, BackgroundTransparency = 1,
            Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -36, 1, 0), ClearTextOnFocus = false,
            Font = T.Font, TextSize = 13, TextColor3 = T.Text, Text = "",
            PlaceholderText = "Search...", PlaceholderColor3 = T.SubText, TextXAlignment = Enum.TextXAlignment.Left })
        Library.Registry:Add(self.SearchBar, "Surface2", "BackgroundColor3")

        -- separador accent bajo header
        U.Create("Frame", { Parent = self.Root, Position = UDim2.fromOffset(0, HEADERH),
            Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, BackgroundColor3 = T.Accent })

        -- Category holder (franja inferior); esquinas inferiores redondeadas, superiores cuadradas
        self.CategoryHolder = U.Create("Frame", {
            Parent = self.Root, AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 56),
            BackgroundColor3 = T.Bar, BorderSizePixel = 0,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, 10) }),
            U.Create("Frame", { Name = "SquareTop", BorderSizePixel = 0, BackgroundColor3 = T.Bar,
                Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0, 10) }) })
        Library.Registry:Add(self.CategoryHolder, "Bar", "BackgroundColor3")
        Library.Registry:Add(self.CategoryHolder.SquareTop, "Bar", "BackgroundColor3")
        -- fila interna que ordena las categorias (fuera del cover)
        self.CategoryButtons = U.Create("Frame", { Parent = self.CategoryHolder,
            BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
        }, { U.Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 18) }) })
        -- linea de theme (accent) que separa el content de la barra de categorias
        local catLine = U.Create("Frame", { Parent = self.Root, BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 1, -56), Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = T.Accent })
        Library.Registry:Add(catLine, "Accent", "BackgroundColor3")

        -- Body (entre header y category holder)
        self.Body = U.Create("Frame", {
            Parent = self.Root, Position = UDim2.fromOffset(0, 65),
            Size = UDim2.new(1, 0, 1, -(65 + 56)), BackgroundTransparency = 1,
        })

        U.Drag(self.Header, self.Root, Library)
        return self
    end

    -- callback de la barra de busqueda del header
    function Window:OnSearch(fn)
        self._searchConn = self.Search:GetPropertyChangedSignal("Text"):Connect(function()
            fn(self.Search.Text)
        end)
        return self
    end

    function Window:AddCategory(name, icon)
        if not P.CategoryBar then warn("PrimordialUI: CategoryBar ausente"); return nil end
        local cat = P.CategoryBar.new(self, name, icon)
        table.insert(self.Categories, cat)
        if not self.ActiveCategory then self:SetActiveCategory(cat) end
        return cat
    end

    function Window:SetActiveCategory(cat)
        if self.Library.CloseActivePopup then self.Library:CloseActivePopup() end
        for _, c in ipairs(self.Categories) do c:SetActive(c == cat) end
        self.ActiveCategory = cat
    end

    -- categoria estandar para configurar la UI (accent, DPI, keybind, watermark, themes, configs, unload)
    function Window:AddSettingsTab(name)
        local Lib = self.Library
        local cat = self:AddCategory(name or "Settings", "settings")
        local sec = cat:AddSection("Configuration", "Configure the UI")

        -- no guardar los widgets del settings tab en las configs del usuario
        for _, f in ipairs({ "UIAccent", "UIDPIScale", "UIMenuKey", "UIWatermark", "UIWatermarkText",
            "UITheme", "UIKeybindList", "UIConfigName", "UIConfigList", "UIAutoload" }) do
            if Lib.ConfigIgnore then Lib.ConfigIgnore[f] = true end
        end

        local menu = sec:AddPanel("Menu", { Column = 1 })
        menu:AddColorPicker("UIAccent", { Text = "Accent Color", Default = T.Accent,
            Callback = function(c) Lib:SetTheme({ Accent = c }) end })
        if Lib.ListThemePresets then
            menu:AddDropdown("UITheme", { Text = "Theme Preset", Values = Lib:ListThemePresets(), Default = "Default",
                Callback = function(v) Lib:ApplyThemePreset(v) end })
        end
        menu:AddSlider("UIDPIScale", { Text = "DPI Scale", Min = 50, Max = 200, Default = 100, Suffix = "%",
            Callback = function(v) Lib:SetDPIScale(v) end })
        menu:AddKeybind("UIMenuKey", { Text = "Menu Keybind", Default = Lib.ToggleKey, NoUI = true,
            BindCallback = function(k) Lib.ToggleKey = k end })
        if Lib.SetKeybindListVisibility then
            menu:AddToggle("UIKeybindList", { Text = "Show Keybind List", Default = false,
                Callback = function(v) Lib:SetKeybindListVisibility(v) end })
        end
        menu:AddDivider()
        menu:AddButton("Unload", function() Lib:Unload() end)

        local wm = sec:AddPanel("Watermark", { Column = 2 })
        wm:AddToggle("UIWatermark", { Text = "Show Watermark", Default = false,
            Callback = function(v) Lib:SetWatermarkVisibility(v) end })
        wm:AddTextBox("UIWatermarkText", { Text = "Watermark Text", Default = "primordial",
            Placeholder = "text", Callback = function(t) if Lib.Flags.UIWatermark then Lib:SetWatermark(t) end end })

        -- Config manager (save/load)
        if Lib.SaveConfig then
            local cfg = sec:AddPanel("Configs", { Column = 2 })
            cfg:AddTextBox("UIConfigName", { Text = "Config Name", Placeholder = "my config" })
            local list = cfg:AddDropdown("UIConfigList", { Text = "Saved", Values = Lib:ListConfigs(), AllowNull = true })
            local function refresh() list:SetValues(Lib:ListConfigs()) end
            cfg:AddButton("Save", function()
                local n = Lib.Flags.UIConfigName
                if n and n ~= "" and Lib:SaveConfig(n) then refresh(); Lib:Notify("Config saved: " .. n, 3)
                else Lib:Notify("Enter a config name", 3) end
            end)
            cfg:AddButton("Load", function()
                local n = Lib.Flags.UIConfigList
                if n and Lib:LoadConfigFile(n) then Lib:Notify("Config loaded: " .. n, 3) end
            end)
            cfg:AddButton("Delete", function()
                local n = Lib.Flags.UIConfigList
                if n then Lib:DeleteConfig(n); refresh(); Lib:Notify("Config deleted: " .. n, 3) end
            end)
            cfg:AddToggle("UIAutoload", { Text = "Autoload selected", Default = Lib:GetAutoloadConfig() ~= nil,
                Callback = function(v) Lib:SetAutoloadConfig(v and Lib.Flags.UIConfigList or "") end })
        end
        return cat
    end

    function Window:SetVisible(b) self.Root.Visible = b end
    function Window:Destroy() self.Gui:Destroy() end

    P.Window = Window
end

end)(); __m(P) end
-- ==== Chrome/CategoryBar ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Category = {}
    Category.__index = Category

    function Category.new(Window, name, icon)
        local self = setmetatable({ Window = Window, Name = name, Sections = {}, ActiveSection = nil }, Category)

        -- botón en la franja inferior (icono + label)
        self.Button = U.Create("TextButton", {
            Parent = Window.CategoryButtons, AutoButtonColor = false,
            BackgroundTransparency = 1, Size = UDim2.fromOffset(72, 52), Text = "",
        }, {
            U.Create("Frame", { Name = "Hi", BackgroundColor3 = T.Surface3,
                BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) },
                { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }) }),
            U.Create("ImageLabel", {
                Name = "Icon", BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4),
                Size = UDim2.fromOffset(24, 24), Image = "",
                ImageColor3 = T.SubText,
            }),
            U.Create("TextLabel", {
                Name = "Label", BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
                Size = UDim2.new(1, 0, 0, 16), Font = T.Font, TextSize = 12,
                Text = name, TextColor3 = T.SubText,
            }),
        })

        -- icono: nombre Lucide ("crosshair") o rbxassetid
        if P.Icons then P.Icons.apply(self.Button.Icon, icon)
        elseif icon then self.Button.Icon.Image = icon end

        -- página de contenido
        self.Page = U.Create("Frame", {
            Parent = Window.Body, Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1, Visible = false,
        })
        self.Sidebar = U.Create("Frame", {
            Parent = self.Page, Size = UDim2.new(0, 172, 1, 0),
            BackgroundColor3 = T.Sidebar, BorderSizePixel = 0, ClipsDescendants = true,
        }, { U.Create("UIListLayout", { Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder }),
            U.Create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8),
                PaddingRight = UDim.new(0, 8) }) })
        Window.Library.Registry:Add(self.Sidebar, "Sidebar", "BackgroundColor3")
        self.Content = U.Create("Frame", {
            Parent = self.Page, Position = UDim2.fromOffset(180, 8),
            Size = UDim2.new(1, -188, 1, -16), BackgroundTransparency = 1,
        })
        -- separador vertical entre sidebar y content, con sombra suave
        U.Create("Frame", { Parent = self.Page, BorderSizePixel = 0,
            Position = UDim2.fromOffset(172, 0), Size = UDim2.new(0, 1, 1, 0),
            BackgroundColor3 = T.Border })
        U.Create("Frame", { Parent = self.Page, BorderSizePixel = 0,
            Position = UDim2.fromOffset(173, 0), Size = UDim2.new(0, 8, 1, 0),
            BackgroundColor3 = Color3.new(0, 0, 0) },
            { U.Create("UIGradient", { Rotation = 0, Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.6),
                NumberSequenceKeypoint.new(1, 1) }) }) })

        self.Button.MouseButton1Click:Connect(function()
            Window:SetActiveCategory(self)
        end)
        return self
    end

    function Category:AddSection(title, subtitle, opts)
        if not P.Section then warn("PrimordialUI: Section ausente"); return nil end
        local s = P.Section.new(self, title, subtitle, opts)
        table.insert(self.Sections, s)
        if not self.ActiveSection then self:SetActiveSection(s) end
        return s
    end

    function Category:SetActiveSection(s)
        local Lib = self.Window.Library
        if Lib.CloseActivePopup then Lib:CloseActivePopup() end
        for _, sec in ipairs(self.Sections) do sec:SetActive(sec == s) end
        self.ActiveSection = s
    end

    function Category:SetActive(b)
        self.Page.Visible = b
        self.Button.Hi.BackgroundTransparency = b and 0.55 or 1
        self.Button.Icon.ImageColor3 = b and T.Accent or T.SubText
        self.Button.Label.TextColor3 = b and T.Text or T.SubText
    end

    P.Category = Category
    P.CategoryBar = Category  -- alias esperado por Window
end

end)(); __m(P) end
-- ==== Chrome/Section ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Section = {}
    Section.__index = Section

    -- crea un set de N columnas (scrolling) dentro de parent, offset yOff arriba
    local function makeBoardSet(parent, yOff, nCols)
        nCols = nCols or 2
        local gap = 8
        local board = U.Create("Frame", { Parent = parent, BackgroundTransparency = 1, Visible = false,
            Position = UDim2.fromOffset(0, yOff), Size = UDim2.new(1, 0, 1, -yOff),
        }, { U.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder }) })
        local cols = {}
        local off = -(gap * (nCols - 1) / nCols)
        for i = 1, nCols do
            cols[i] = U.Create("ScrollingFrame", { Parent = board, LayoutOrder = i,
                Size = UDim2.new(1 / nCols, off, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.Y,
            }, { U.Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
                U.Create("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2),
                    PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 5) }) })
        end
        return board, cols
    end

    function Section.new(Category, title, subtitle, opts)
        opts = opts or {}
        local self = setmetatable({ Category = Category, Panels = {}, Columns = {}, HasTabs = false,
            NumCols = math.clamp(opts.Columns or 2, 1, 4) }, Section)

        self.Button = U.Create("TextButton", {
            Parent = Category.Sidebar, AutoButtonColor = false, Text = "",
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44),
        }, {
            U.Create("Frame", { Name = "Hi", BackgroundColor3 = T.Accent, BorderSizePixel = 0,
                BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(-8, 0),
            }, { U.Create("UIGradient", { Rotation = 0, Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.7),
                NumberSequenceKeypoint.new(0.65, 0.9),
                NumberSequenceKeypoint.new(1, 1) }) }) }),
            U.Create("Frame", { Name = "Bar", BackgroundColor3 = T.Accent, BorderSizePixel = 0,
                Position = UDim2.fromOffset(-8, 0), Size = UDim2.new(0, 2, 1, 0), Visible = false }),
            U.Create("TextLabel", { Name = "Title", BackgroundTransparency = 1,
                Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 16),
                Font = T.FontBold, TextSize = 14, Text = title, TextColor3 = T.SubText,
                TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }),
            U.Create("TextLabel", { Name = "Sub", BackgroundTransparency = 1,
                Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -16, 0, 14),
                Font = T.Font, TextSize = 12, Text = subtitle or "", TextColor3 = T.SubText,
                TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }),
        })

        -- raiz de contenido (toggle por SetActive)
        self.Board = U.Create("Frame", { Parent = Category.Content, Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1, Visible = false })
        -- set de columnas por defecto (sin content-tabs)
        local b, c = makeBoardSet(self.Board, 0, self.NumCols)
        b.Visible = true
        self._defaultBoard = b
        self.Columns = c
        self._activeCols = c

        self.Button.MouseButton1Click:Connect(function()
            Category:SetActiveSection(self)
        end)
        return self
    end

    -- content-tabs de arma que abarcan AMBAS columnas (Rifles/Pistols/...)
    -- opts.PerRow = cuantos tabs por fila (default: todos en 1 fila). Envuelve en varias filas.
    function Section:AddTabs(list, opts)
        opts = opts or {}
        self.HasTabs = true
        self._defaultBoard.Visible = false
        self._tabBoards = {}
        self._tabOrder = list

        local n = #list
        local perRow = math.max(1, math.min(opts.PerRow or n, n))
        local rowH = 28
        local rows = math.ceil(n / perRow)
        local barH = rows * rowH

        self.TabBar = U.Create("Frame", { Parent = self.Board, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, barH),
        }, { U.Create("UIGridLayout", { CellSize = UDim2.new(1 / perRow, 0, 0, rowH),
            CellPadding = UDim2.fromOffset(0, 0), FillDirectionMaxCells = perRow,
            SortOrder = Enum.SortOrder.LayoutOrder }) })
        -- separador bajo la barra de tabs
        U.Create("Frame", { Parent = self.Board, Position = UDim2.fromOffset(0, barH),
            Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, BackgroundColor3 = T.Border })

        for i, name in ipairs(list) do
            local btn = U.Create("TextButton", { Parent = self.TabBar, AutoButtonColor = false,
                BackgroundTransparency = 1, LayoutOrder = i,
                Font = T.FontBold, TextSize = 13, Text = name, TextColor3 = T.SubText,
            }, { U.Create("Frame", { Name = "UL", BorderSizePixel = 0, BackgroundColor3 = T.Accent,
                AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
                Size = UDim2.new(0, 40, 0, 2), Visible = false }) })
            local board, cols = makeBoardSet(self.Board, barH + 4, self.NumCols)
            self._tabBoards[name] = { board = board, cols = cols, btn = btn }
            btn.MouseButton1Click:Connect(function() self:SetContentTab(name) end)
        end
        self:SetContentTab(list[1])
        return self
    end

    function Section:SetContentTab(name)
        local Lib = self.Category.Window.Library
        if Lib.CloseActivePopup then Lib:CloseActivePopup() end
        for n, t in pairs(self._tabBoards) do
            local on = n == name
            t.board.Visible = on
            t.btn.TextColor3 = on and T.Accent or T.SubText
            t.btn.UL.Visible = on
        end
        self._activeCols = self._tabBoards[name].cols
        self._activeTab = name
    end

    function Section:AddPanel(title, opts)
        opts = opts or {}
        local col = opts.Column
        if not col then col = (#self.Panels % self.NumCols) + 1 end
        col = math.clamp(col, 1, self.NumCols)
        local cols = self.Columns
        if self.HasTabs then
            local tab = opts.Tab or self._activeTab
            local tb = self._tabBoards[tab]
            cols = (tb and tb.cols) or self._activeCols
        end
        if not P.Panel then warn("PrimordialUI: Panel ausente"); return nil end
        local p = P.Panel.new(self, cols[col], title, opts)
        table.insert(self.Panels, p)
        return p
    end

    function Section:SetActive(b)
        self.Board.Visible = b
        self.Button.Bar.Visible = b
        self.Button.Hi.BackgroundTransparency = b and 0 or 1
        self.Button.Title.TextColor3 = b and T.Text or T.SubText
    end

    P.Section = Section
end

end)(); __m(P) end
-- ==== Chrome/Panel ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Panel = {}
    Panel.__index = Panel

    function Panel.new(Section, columnFrame, title, opts)
        local self = setmetatable({
            Section = Section,
            Library = Section.Category.Window.Library,
            _widgets = {}, Tabs = nil,
        }, Panel)

        local HH = 26 -- alto header (compacto)
        -- alto FIJO ligado al Body (no AutomaticSize) para que la sombra offset no lo infle
        self.Frame = U.Create("Frame", {
            Parent = columnFrame, Size = UDim2.new(1, 0, 0, HH + 1), ClipsDescendants = false,
            BackgroundColor3 = T.Surface, BorderSizePixel = 0, LayoutOrder = #Section.Panels + 1,
        }, {
            U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
            -- gradiente sutil de profundidad (arriba mas claro -> abajo mas oscuro)
            U.Create("UIGradient", { Rotation = 90,
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(224, 224, 228)),
                }) }),
        })
        self.Library.Registry:Add(self.Frame, "Surface", "BackgroundColor3")

        -- sombra externa suave (Frame no es AutomaticSize => segura)
        U.Shadow(self.Frame, { Spread = 18, Transparency = 0.78, YOffset = 4 })

        self.Header = U.Create("TextLabel", {
            Parent = self.Frame, BackgroundTransparency = 1,
            Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -18, 0, HH),
            Font = T.FontBold, TextSize = 13, Text = title, TextColor3 = T.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        -- separador bajo el titulo: color principal (accent)
        local sep = U.Create("Frame", { Parent = self.Frame, Position = UDim2.fromOffset(0, HH),
            Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, BackgroundColor3 = T.Accent })
        self.Library.Registry:Add(sep, "Accent", "BackgroundColor3")

        self.Body = U.Create("Frame", {
            Parent = self.Frame, Position = UDim2.fromOffset(0, HH + 1),
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, {
            U.Create("UIListLayout", { Padding = UDim.new(0, 2),
                SortOrder = Enum.SortOrder.LayoutOrder }),
            U.Create("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6),
                PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
        })

        -- ligar alto del Frame al contenido del Body
        local function resize()
            self.Frame.Size = UDim2.new(1, 0, 0, (HH + 1) + self.Body.AbsoluteSize.Y)
        end
        self.Library:Maid(self.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize))
        resize()
        return self
    end

    function Panel:_rowParent()
        if self.Tabs then return self.Tabs:ActiveContent() end
        return self.Body
    end

    local function widgetAdder(moduleKey)
        return function(self, flag, o)
            if not P[moduleKey] then warn("PrimordialUI: "..moduleKey.." ausente"); return nil end
            local W = P[moduleKey].new(self, flag, o or {})
            table.insert(self._widgets, W)
            return W
        end
    end
    Panel.AddToggle   = widgetAdder("Toggle")
    Panel.AddSlider   = widgetAdder("Slider")
    Panel.AddDropdown = widgetAdder("Dropdown")
    Panel.AddKeybind  = widgetAdder("Keybind")
    Panel.AddTextBox  = widgetAdder("TextBox")
    Panel.AddColorPicker = widgetAdder("ColorPicker")
    Panel.AddList        = widgetAdder("List")

    function Panel:AddButton(text, cb, opts)
        if not P.Button then return nil end
        opts = opts or {}
        local W = P.Button.new(self, nil, { Text = text, Callback = cb, DoubleClick = opts.DoubleClick })
        table.insert(self._widgets, W); return W
    end
    function Panel:AddLabel(text, opts)
        if not P.Label then return nil end
        local W = P.Label.new(self, nil, { Text = text, Header = opts and opts.Header })
        table.insert(self._widgets, W); return W
    end
    function Panel:AddDivider()
        if not P.Divider then return nil end
        local W = P.Divider.new(self, nil, {})
        table.insert(self._widgets, W); return W
    end
    function Panel:AddTabs(list)
        if not P.PanelTabs then return nil end
        self.Tabs = P.PanelTabs.new(self, list); return self.Tabs
    end
    function Panel:AddViewport(opts)
        if not P.Viewport then return nil end
        local W = P.Viewport.new(self, opts or {})
        table.insert(self._widgets, W); return W
    end
    function Panel:AddGrid(opts)
        if not P.Grid then return nil end
        local W = P.Grid.new(self, opts or {})
        table.insert(self._widgets, W); return W
    end

    P.Panel = Panel
end

end)(); __m(P) end
-- ==== Chrome/PanelTabs ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local PanelTabs = {}
    PanelTabs.__index = PanelTabs

    function PanelTabs.new(Panel, list)
        local self = setmetatable({ Panel = Panel, Tabs = {}, Contents = {}, Active = nil }, PanelTabs)

        self.Bar = U.Create("Frame", { Parent = Panel.Body, Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1, LayoutOrder = 0,
        }, { U.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })

        for i, name in ipairs(list) do
            local btn = U.Create("TextButton", { Parent = self.Bar, AutoButtonColor = false,
                BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.new(0, 0, 1, 0), Font = T.FontBold, TextSize = 13,
                Text = name, TextColor3 = T.SubText, LayoutOrder = i,
            }, { U.Create("Frame", { Name = "UL", BorderSizePixel = 0, BackgroundColor3 = T.Accent,
                AnchorPoint = Vector2.new(0.5,1), Position = UDim2.new(0.5,0,1,0),
                Size = UDim2.new(1,0,0,2), Visible = false }) })
            local content = U.Create("Frame", { Parent = Panel.Body, LayoutOrder = 1,
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, Visible = false,
            }, { U.Create("UIListLayout", { Padding = UDim.new(0, 4),
                SortOrder = Enum.SortOrder.LayoutOrder }) })
            self.Tabs[name] = btn; self.Contents[name] = content
            btn.MouseButton1Click:Connect(function() self:SetActive(name) end)
            if i == 1 then self:SetActive(name) end
        end
        return self
    end

    function PanelTabs:SetActive(name)
        local Lib = self.Panel.Library
        if Lib and Lib.CloseActivePopup then Lib:CloseActivePopup() end
        for n, btn in pairs(self.Tabs) do
            local on = n == name
            btn.TextColor3 = on and T.Accent or T.SubText
            btn.UL.Visible = on
            self.Contents[n].Visible = on
        end
        self.Active = name
    end

    function PanelTabs:ActiveContent() return self.Contents[self.Active] end

    P.PanelTabs = PanelTabs
end

end)(); __m(P) end
-- ==== Widgets/_Base ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Base = {}
    Base.__index = Base

    function Base.new(Panel, opts)
        local self = setmetatable({
            Panel = Panel, Library = Panel.Library,
            Changed = P.Signal.new(), _deps = {},
        }, Base)
        local h = opts.Height or T.RowH
        self.Row = U.Create("Frame", {
            Parent = Panel:_rowParent(), Size = UDim2.new(1, 0, 0, h),
            BackgroundTransparency = 1, LayoutOrder = #Panel._widgets + 10,
        })
        if opts.LabelText ~= nil then
            self.Label = U.Create("TextLabel", { Parent = self.Row, BackgroundTransparency = 1,
                Size = UDim2.new(1, -120, 1, 0), Font = T.Font, TextSize = T.TextSize,
                Text = opts.LabelText, TextColor3 = T.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Center })
            self.Library.Registry:Add(self.Label, "Text", "TextColor3")
        end
        self.Control = U.Create("Frame", { Parent = self.Row,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 110, 1, 0), BackgroundTransparency = 1 })
        if opts.Tooltip and self.Library.ShowTooltip then
            self.Row.MouseEnter:Connect(function() self.Library:ShowTooltip(opts.Tooltip) end)
            self.Row.MouseMoved:Connect(function() self.Library:MoveTooltip() end)
            self.Row.MouseLeave:Connect(function() self.Library:HideTooltip() end)
        end
        return self
    end

    function Base:SetVisible(b) self.Row.Visible = b end

    function Base:_evalDeps()
        local vis = true
        for _, d in ipairs(self._deps) do
            if self.Library.Flags[d.flag] ~= d.expected then vis = false break end
        end
        self:SetVisible(vis)
    end

    function Base:DependsOn(flag, expected)
        table.insert(self._deps, { flag = flag, expected = expected })
        self.Library:GetFlagSignal(flag):Connect(function() self:_evalDeps() end)
        self:_evalDeps()
        return self._widget or self
    end

    function Base:OnChanged(fn)
        self.Changed:Connect(fn)
        return self._widget or self
    end

    P.Base = Base
end

end)(); __m(P) end
-- ==== Widgets/Toggle ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Toggle = {}
    Toggle.__index = Toggle

    function Toggle.new(Panel, flag, opts)
        -- checkbox a la IZQUIERDA + label despues (estilo primordial)
        local base = P.Base.new(Panel, { LabelText = nil, Height = 22, Tooltip = opts.Tooltip })
        local self = setmetatable({ _base = base, Panel = Panel, Library = Panel.Library,
            Flag = flag, Value = opts.Default and true or false, Callback = opts.Callback }, Toggle)
        base._widget = self

        self.Box = U.Create("TextButton", { Parent = base.Row, AutoButtonColor = false,
            Text = "", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 1, 0.5, 0),
            Size = UDim2.fromOffset(14, 14), BackgroundColor3 = T.Surface2,
        }, {
            U.Create("UICorner", { CornerRadius = UDim.new(0, 3) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
            U.Create("UIGradient", { Name = "Depth", Rotation = 90, Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.new(0.82, 0.82, 0.82)) }) }),
            U.Create("ImageLabel", { Name = "Check", BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromScale(0.82, 0.82), Image = "rbxassetid://6031094667",
                ImageColor3 = Color3.fromRGB(18, 18, 20), ImageTransparency = 1 }),
        })
        self.Label = U.Create("TextLabel", { Parent = base.Row, BackgroundTransparency = 1,
            Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -140, 1, 0),
            Font = T.Font, TextSize = T.TextSize, Text = opts.Text or flag, TextColor3 = T.Text,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center })

        self.Box.MouseButton1Click:Connect(function() self:SetValue(not self.Value) end)
        self.Library.Toggles[flag] = self
        self:_render()
        self.Library:SetFlag(flag, self.Value)
        return self
    end

    function Toggle:_render()
        self.Box.BackgroundColor3 = self.Value and T.Accent or T.Surface2
        self.Box.Check.ImageTransparency = self.Value and 0 or 1
        -- texto atenuado cuando esta apagado
        self.Label.TextColor3 = self.Value and T.Text or Color3.fromRGB(150, 150, 157)
    end

    function Toggle:SetValue(v)
        v = v and true or false
        if v == self.Value then return end
        self.Value = v; self:_render()
        self.Library:SetFlag(self.Flag, v)
        self._base.Changed:Fire(v)
        if self.Callback then task.spawn(self.Callback, v) end
    end
    function Toggle:GetValue() return self.Value end
    -- adjunta un swatch de color a la fila del toggle (patron Hitmarker); apilable
    function Toggle:AddColorPicker(flag, opts)
        if not P.ColorPicker then return self end
        self._cpCount = (self._cpCount or 0) + 1
        local xOffset = -(24 + (self._cpCount - 1) * 34)  -- deja lugar al checkbox + apila
        P.ColorPicker._attach(self.Library, self._base.Control, flag, opts or {}, xOffset)
        return self
    end
    function Toggle:DependsOn(f, e) self._base:DependsOn(f, e); return self end
    function Toggle:OnChanged(fn) self._base:OnChanged(fn); return self end
    function Toggle:SetVisible(b) self._base:SetVisible(b) end

    P.Toggle = Toggle
end

end)(); __m(P) end
-- ==== Widgets/Slider ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local UIS = game:GetService("UserInputService")
    local Slider = {}
    Slider.__index = Slider

    function Slider.new(Panel, flag, opts)
        local base = P.Base.new(Panel, { LabelText = nil, Height = 40, Tooltip = opts.Tooltip })
        local self = setmetatable({ _base = base, Library = Panel.Library, Flag = flag,
            Min = opts.Min or 0, Max = opts.Max or 100, Decimals = opts.Decimals or 0,
            Suffix = opts.Suffix or "", Prefix = opts.Prefix or "", OffAtMin = opts.OffAtMin,
            Callback = opts.Callback }, Slider)
        base._widget = self
        base.Control.Visible = false

        -- linea superior: nombre + box de valor pegado al lado
        local topRow = U.Create("Frame", { Parent = base.Row, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 16),
        }, { U.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

        U.Create("TextLabel", { Parent = topRow, BackgroundTransparency = 1, LayoutOrder = 1,
            AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
            Font = T.FontBold, TextSize = T.TextSize, Text = opts.Text or flag,
            TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left })

        self.ValBox = U.Create("Frame", { Parent = topRow, LayoutOrder = 2,
            AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 15),
            BackgroundColor3 = T.Surface2,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
            U.Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }),
            U.Create("TextLabel", { Name = "V", BackgroundTransparency = 1,
                AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
                Font = T.Font, TextSize = 12, Text = "", TextColor3 = T.SubText,
                TextYAlignment = Enum.TextYAlignment.Center }) })
        self.ValLabel = self.ValBox.V

        -- track con fill (gradient de textura) + perilla
        self.Track = U.Create("TextButton", { Parent = base.Row, Text = "", AutoButtonColor = false,
            Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 8),
            BackgroundColor3 = T.Surface2,
        }, {
            U.Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
            U.Create("Frame", { Name = "Fill", BorderSizePixel = 0, BackgroundColor3 = T.Accent,
                Size = UDim2.new(0, 0, 1, 0) }, {
                U.Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
                U.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.15),
                    NumberSequenceKeypoint.new(0.5, 0),
                    NumberSequenceKeypoint.new(1, 0.2) }) }),
            }),
        })
        -- perilla deslizable GRIS con textura (gradient vertical claro->oscuro)
        self.Knob = U.Create("Frame", { Parent = self.Track, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(7, 13),
            BackgroundColor3 = T.Knob, ZIndex = 3,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, 2) }),
            U.Create("UIStroke", { Color = Color3.fromRGB(20,20,22), Transparency = 0.5, Thickness = 1 }),
            U.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(235,235,238)),
                ColorSequenceKeypoint.new(0.5, T.Knob),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(150,150,156)) }) }) })
        U.Depth(self.Track, { Bottom = 0.18 })
        U.Depth(self.ValBox, { Bottom = 0.12 })
        base.Control.Visible = false

        local function setFromX(px)
            local abs = self.Track.AbsolutePosition.X
            local w = self.Track.AbsoluteSize.X
            local a = math.clamp((px - abs) / w, 0, 1)
            self:SetValue(self.Min + a * (self.Max - self.Min))
        end
        local dragging = false
        self.Track.MouseButton1Down:Connect(function() dragging = true
            setFromX(UIS:GetMouseLocation().X) end)
        self.Library:Maid(UIS.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end))
        self.Library:Maid(UIS.InputChanged:Connect(function(i)
            if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
                setFromX(UIS:GetMouseLocation().X) end end))

        self.Library.Options[flag] = self
        self:SetValue(opts.Default ~= nil and opts.Default or self.Min)
        return self
    end

    function Slider:_fmt(v)
        if self.OffAtMin and v <= self.Min then return "Off" end
        local num
        if self.Decimals > 0 then
            num = string.format("%." .. self.Decimals .. "f", v)
        else
            num = tostring(math.floor(v + 0.5))
        end
        return self.Prefix .. num .. self.Suffix
    end

    function Slider:SetValue(v)
        v = math.clamp(v, self.Min, self.Max)
        if self.Decimals == 0 then v = math.floor(v + 0.5) end
        self.Value = v
        local a = (v - self.Min) / (self.Max - self.Min)
        self.Track.Fill.Size = UDim2.new(a, 0, 1, 0)
        self.Knob.Position = UDim2.new(a, 0, 0.5, 0)
        self.ValLabel.Text = self:_fmt(v)
        self.Library:SetFlag(self.Flag, v)
        self._base.Changed:Fire(v)
        if self.Callback then task.spawn(self.Callback, v) end
    end
    function Slider:GetValue() return self.Value end
    function Slider:DependsOn(f, e) self._base:DependsOn(f, e); return self end
    function Slider:OnChanged(fn) self._base:OnChanged(fn); return self end
    function Slider:SetVisible(b) self._base:SetVisible(b) end

    P.Slider = Slider
end

end)(); __m(P) end
-- ==== Widgets/Dropdown ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Dropdown = {}
    Dropdown.__index = Dropdown

    local function hamburger(parent)
        local f = U.Create("Frame", { Parent = parent, Name = "Ham", BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0),
            Size = UDim2.fromOffset(14, 11) })
        for i = 0, 2 do
            U.Create("Frame", { Parent = f, BorderSizePixel = 0, BackgroundColor3 = T.SubText,
                Position = UDim2.new(0, 0, 0, i * 5), Size = UDim2.new(1, 0, 0, 1.5) })
        end
        return f
    end

    function Dropdown.new(Panel, flag, opts)
        local base = P.Base.new(Panel, { LabelText = nil, Height = 46, Tooltip = opts.Tooltip })
        local self = setmetatable({ _base = base, Library = Panel.Library, Flag = flag,
            Values = opts.Values or {}, AllowNull = opts.AllowNull, Callback = opts.Callback,
            Multi = opts.Multi and true or false, Searchable = opts.Searchable and true or false,
            Open = false }, Dropdown)
        base._widget = self
        base.Control.Visible = false

        self.Title = U.Create("TextLabel", { Parent = base.Row, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 16), Font = T.FontBold, TextSize = T.TextSize,
            Text = opts.Text or flag, TextColor3 = T.SubText,
            TextXAlignment = Enum.TextXAlignment.Left })

        self.DControl = U.Create("TextButton", { Parent = base.Row, Text = "", AutoButtonColor = false,
            Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = T.Surface2,
        }, {
            U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
            U.Create("TextLabel", { Name = "Val", BackgroundTransparency = 1,
                Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -30, 1, 0),
                Font = T.Font, TextSize = T.TextSize, Text = "...", TextColor3 = T.Text,
                TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }),
        })
        U.Depth(self.DControl, { Highlight = true })
        if self.Multi then
            hamburger(self.DControl)
            self.Value = {}
        else
            U.Create("ImageLabel", { Parent = self.DControl, Name = "Chev", BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0),
                Size = UDim2.fromOffset(14, 14), Image = "rbxassetid://6034818372",
                ImageColor3 = T.SubText })
        end
        self.DControl.MouseButton1Click:Connect(function() self:Toggle() end)

        self.Library.Options[flag] = self
        if self.Multi then
            local def = opts.Default
            if type(def) == "table" then for _, v in ipairs(def) do self.Value[v] = true end end
            self:_renderMulti()
            self.Library:SetFlag(flag, self:GetValue())
        else
            local def = opts.Default
            if def == nil and not self.AllowNull then def = self.Values[1] end
            self:SetValue(def)
        end
        return self
    end

    function Dropdown:_closePopup()
        if self.Popup then self.Popup:Destroy(); self.Popup = nil end
        self.Open = false
        self.Library:ClosePopup(self._closer)
    end

    function Dropdown:Toggle()
        if self.Open then self:_closePopup(); return end
        self._closer = self._closer or function() self:_closePopup() end
        self.Library:OpenPopup(self._closer)
        self.Open = true
        local gui = self.DControl:FindFirstAncestorWhichIsA("ScreenGui")
        local ap, sz = self.DControl.AbsolutePosition, self.DControl.AbsoluteSize
        local rows = math.min(#self.Values, 7)
        local searchH = self.Searchable and 26 or 0
        self.Popup = U.Create("Frame", { Parent = gui, ZIndex = 50,
            Position = UDim2.fromOffset(ap.X, ap.Y + sz.Y + 2),
            Size = UDim2.fromOffset(sz.X, rows * 24 + 4 + searchH), BackgroundColor3 = T.Surface2, BorderSizePixel = 0,
            ClipsDescendants = true,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }) })
        local searchBox
        if self.Searchable then
            searchBox = U.Create("TextBox", { Parent = self.Popup, ZIndex = 52,
                Position = UDim2.fromOffset(4, 3), Size = UDim2.new(1, -8, 0, 20),
                BackgroundColor3 = T.Bg, ClearTextOnFocus = false, Font = T.Font, TextSize = 12,
                TextColor3 = T.Text, PlaceholderText = "Search...", PlaceholderColor3 = T.SubText,
                Text = "", TextXAlignment = Enum.TextXAlignment.Left,
            }, { U.Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
                U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
                U.Create("UIPadding", { PaddingLeft = UDim.new(0, 6) }) })
        end
        local scroll = U.Create("ScrollingFrame", { Parent = self.Popup, ZIndex = 51,
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, searchH), Size = UDim2.new(1, 0, 1, -searchH),
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 0,
        }, { U.Create("UIListLayout", {}), U.Create("UIPadding", {
            PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }) })

        local itemBtns = {}
        if searchBox then
            searchBox:GetPropertyChangedSignal("Text"):Connect(function()
                local q = searchBox.Text:lower()
                for _, ib in ipairs(itemBtns) do
                    ib.btn.Visible = (q == "") or ib.name:lower():find(q, 1, true) ~= nil
                end
            end)
        end

        for _, v in ipairs(self.Values) do
            local sel = self.Multi and self.Value[v] or (v == self.Value)
            local it = U.Create("TextButton", { Parent = scroll, ZIndex = 52,
                BackgroundColor3 = T.Surface3, BackgroundTransparency = sel and 0.5 or 1,
                Size = UDim2.new(1, 0, 0, 24), AutoButtonColor = false,
                Font = T.Font, TextSize = T.TextSize, Text = "",
            }, { U.Create("TextLabel", { Name = "L", BackgroundTransparency = 1, ZIndex = 52,
                Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -12, 1, 0),
                Font = T.Font, TextSize = T.TextSize, Text = tostring(v),
                TextColor3 = sel and T.Accent or T.Text, TextXAlignment = Enum.TextXAlignment.Left }) })
            table.insert(itemBtns, { btn = it, name = tostring(v) })
            it.MouseButton1Click:Connect(function()
                if self.Multi then
                    self.Value[v] = (not self.Value[v]) or nil
                    it.BackgroundTransparency = self.Value[v] and 0.5 or 1
                    it.L.TextColor3 = self.Value[v] and T.Accent or T.Text
                    self:_renderMulti()
                    self.Library:SetFlag(self.Flag, self:GetValue())
                    self._base.Changed:Fire(self:GetValue())
                    if self.Callback then task.spawn(self.Callback, self:GetValue()) end
                else
                    self:SetValue(v); self:_closePopup()
                end
            end)
        end
    end

    function Dropdown:_renderMulti()
        local list = {}
        for _, v in ipairs(self.Values) do if self.Value[v] then table.insert(list, v) end end
        self.DControl.Val.Text = (#list == 0) and "None Selected" or table.concat(list, ", ")
        self.DControl.Val.TextColor3 = (#list == 0) and T.SubText or T.Text
    end

    function Dropdown:SetValue(v)
        if self.Multi then
            self.Value = {}
            if type(v) == "table" then for _, x in ipairs(v) do self.Value[x] = true end end
            self:_renderMulti()
            self.Library:SetFlag(self.Flag, self:GetValue())
        else
            self.Value = v
            self.DControl.Val.Text = v == nil and "None" or tostring(v)
            self.DControl.Val.TextColor3 = v == nil and T.SubText or T.Text
            self.Library:SetFlag(self.Flag, v)
        end
        self._base.Changed:Fire(self:GetValue())
        if self.Callback then task.spawn(self.Callback, self:GetValue()) end
    end

    function Dropdown:GetValue()
        if not self.Multi then return self.Value end
        local list = {}
        for _, v in ipairs(self.Values) do if self.Value[v] then table.insert(list, v) end end
        return list
    end
    function Dropdown:SetValues(list) self.Values = list end
    -- gear ⚙ a la derecha del titulo, abre un mini-panel de settings
    function Dropdown:AddGear()
        if not P.Gear then return nil end
        local g = P.Gear.new(self.Library)
        local icon = P.Gear.icon(self._base.Row)
        g:attachTo(icon)
        return g
    end
    function Dropdown:DependsOn(f, e) self._base:DependsOn(f, e); return self end
    function Dropdown:OnChanged(fn) self._base:OnChanged(fn); return self end
    function Dropdown:SetVisible(b) self._base:SetVisible(b) end

    P.Dropdown = Dropdown
end

end)(); __m(P) end
-- ==== Widgets/Keybind ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local UIS = game:GetService("UserInputService")
    local Keybind = {}
    Keybind.__index = Keybind

    local function keyName(kc) return kc and kc.Name or "None" end

    function Keybind.new(Panel, flag, opts)
        local base = P.Base.new(Panel, { LabelText = opts.Text or flag, Tooltip = opts.Tooltip })
        local self = setmetatable({ _base = base, Library = Panel.Library, Flag = flag,
            Mode = opts.Mode or "Toggle", Key = opts.Default, Capturing = false, Active = false,
            Callback = opts.Callback, BindCallback = opts.BindCallback }, Keybind)
        base._widget = self

        self.Btn = U.Create("TextButton", { Parent = base.Control, AutoButtonColor = false,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(96, 20), BackgroundColor3 = T.Surface2,
            Font = T.Font, TextSize = 12, TextColor3 = T.Text, Text = "Key: "..keyName(self.Key),
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Outline, Thickness = 1 }) })

        self.Btn.MouseButton1Click:Connect(function()
            self.Capturing = true; self.Btn.Text = "Key: ..."
        end)

        self.Library:Maid(UIS.InputBegan:Connect(function(inp, gpe)
            if self.Capturing and inp.KeyCode ~= Enum.KeyCode.Unknown then
                self.Capturing = false; self:SetKey(inp.KeyCode); return
            end
            if not gpe and self.Key and inp.KeyCode == self.Key then
                if self.Mode == "Toggle" then self:_setActive(not self.Active)
                elseif self.Mode == "Hold" then self:_setActive(true) end
            end
        end))
        self.Library:Maid(UIS.InputEnded:Connect(function(inp)
            if self.Mode == "Hold" and self.Key and inp.KeyCode == self.Key then
                self:_setActive(false)
            end
        end))

        self.Library.Options[flag] = self
        self.Library.Flags[flag] = self.Key
        if opts.NoUI ~= true and self.Library.RegisterKeybind then
            self._kbEntry = self.Library:RegisterKeybind(self)
        end
        if self.Mode == "Always" then self:_setActive(true) end
        return self
    end

    function Keybind:_setActive(v)
        self.Active = v
        self.Library.Flags[self.Flag.."Active"] = v
        if self._kbEntry then self._kbEntry:Update() end
        if self.Callback then task.spawn(self.Callback, v) end
        self._base.Changed:Fire(v)
    end
    function Keybind:SetKey(kc)
        self.Key = kc; self.Btn.Text = "Key: "..keyName(kc)
        self.Library.Flags[self.Flag] = kc
        if self._kbEntry then self._kbEntry:Update() end
        if self.BindCallback then task.spawn(self.BindCallback, kc) end
    end
    function Keybind:GetKey() return self.Key end
    function Keybind:SetValue(kc) self:SetKey(kc) end
    function Keybind:GetValue() return self.Key end
    function Keybind:DependsOn(f, e) self._base:DependsOn(f, e); return self end
    function Keybind:OnChanged(fn) self._base:OnChanged(fn); return self end
    function Keybind:SetVisible(b) self._base:SetVisible(b) end

    P.Keybind = Keybind
end

end)(); __m(P) end
-- ==== Widgets/TextBox ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local TextBox = {}
    TextBox.__index = TextBox
    function TextBox.new(Panel, flag, opts)
        local base = P.Base.new(Panel, { LabelText = nil, Height = 46, Tooltip = opts.Tooltip })
        local self = setmetatable({ _base = base, Library = Panel.Library, Flag = flag,
            Numeric = opts.Numeric, MaxLength = opts.MaxLength, Callback = opts.Callback }, TextBox)
        base._widget = self; base.Control.Visible = false
        U.Create("TextLabel", { Parent = base.Row, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 16), Font = T.FontBold, TextSize = T.TextSize,
            Text = opts.Text or flag, TextColor3 = T.SubText,
            TextXAlignment = Enum.TextXAlignment.Left })
        self.Input = U.Create("TextBox", { Parent = base.Row, Position = UDim2.fromOffset(0, 20),
            Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = T.Surface2, ClearTextOnFocus = false,
            Font = T.Font, TextSize = T.TextSize, TextColor3 = T.Text,
            PlaceholderText = opts.Placeholder or "Enter Text...", PlaceholderColor3 = T.SubText,
            Text = opts.Default or "", TextXAlignment = Enum.TextXAlignment.Left,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Outline, Thickness = 1 }),
            U.Create("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
        U.Depth(self.Input, { Highlight = true })
        self.Input:GetPropertyChangedSignal("Text"):Connect(function()
            local t = self.Input.Text
            if self.Numeric then t = t:gsub("[^%d%.%-]", "") end
            if self.MaxLength then t = t:sub(1, self.MaxLength) end
            if t ~= self.Input.Text then self.Input.Text = t end
            self:_set(t)
        end)
        self.Library.Options[flag] = self
        self:_set(opts.Default or "")
        return self
    end
    function TextBox:_set(t) self.Value = t; self.Library:SetFlag(self.Flag, t)
        self._base.Changed:Fire(t); if self.Callback then task.spawn(self.Callback, t) end end
    function TextBox:SetValue(t) self.Input.Text = t end
    function TextBox:GetValue() return self.Value end
    function TextBox:DependsOn(f, e) self._base:DependsOn(f, e); return self end
    function TextBox:OnChanged(fn) self._base:OnChanged(fn); return self end
    function TextBox:SetVisible(b) self._base:SetVisible(b) end
    P.TextBox = TextBox
end

end)(); __m(P) end
-- ==== Widgets/Button ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Button = {}
    Button.__index = Button
    function Button.new(Panel, _flag, opts)
        local base = P.Base.new(Panel, { LabelText = nil, Height = 30, Tooltip = opts.Tooltip })
        local self = setmetatable({ _base = base, Callback = opts.Callback,
            Double = opts.DoubleClick, _last = 0 }, Button)
        base._widget = self; base.Control.Visible = false
        self.Btn = U.Create("TextButton", { Parent = base.Row, AutoButtonColor = false,
            Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = T.Surface2,
            Font = T.FontBold, TextSize = T.TextSize, TextColor3 = T.Text, Text = opts.Text or "Button",
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Outline, Thickness = 1 }) })
        self.Btn.MouseEnter:Connect(function() self.Btn.BackgroundColor3 = T.AccentDim end)
        self.Btn.MouseLeave:Connect(function() self.Btn.BackgroundColor3 = T.Surface2 end)
        self.Btn.MouseButton1Click:Connect(function()
            if self.Double then
                local now = os.clock()
                if now - self._last > 0.4 then self._last = now; self.Btn.Text = "Are you sure?"; return end
                self.Btn.Text = opts.Text or "Button"
            end
            if self.Callback then task.spawn(self.Callback) end
        end)
        return self
    end
    function Button:DependsOn(f, e) self._base:DependsOn(f, e); return self end
    function Button:SetVisible(b) self._base:SetVisible(b) end
    P.Button = Button
end

end)(); __m(P) end
-- ==== Widgets/Label ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Label = {}
    Label.__index = Label
    function Label.new(Panel, _flag, opts)
        local base = P.Base.new(Panel, { LabelText = nil, Height = opts.Header and 20 or 18 })
        local self = setmetatable({ _base = base }, Label)
        base._widget = self; base.Control.Visible = false
        self.Text = U.Create("TextLabel", { Parent = base.Row, BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1), Text = opts.Text or "",
            Font = opts.Header and T.FontBold or T.Font, TextSize = T.TextSize,
            TextColor3 = opts.Header and T.Text or T.SubText,
            TextXAlignment = Enum.TextXAlignment.Left })
        return self
    end
    function Label:SetText(t) self.Text.Text = t end
    function Label:DependsOn(f, e) self._base:DependsOn(f, e); return self end
    function Label:SetVisible(b) self._base:SetVisible(b) end
    P.Label = Label
end

end)(); __m(P) end
-- ==== Widgets/Divider ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Divider = {}
    Divider.__index = Divider
    function Divider.new(Panel, _flag, _opts)
        local base = P.Base.new(Panel, { LabelText = nil, Height = 9 })
        local self = setmetatable({ _base = base }, Divider)
        base._widget = self; base.Control.Visible = false
        U.Create("Frame", { Parent = base.Row, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 1),
            BorderSizePixel = 0, BackgroundColor3 = T.Outline })
        return self
    end
    function Divider:SetVisible(b) self._base:SetVisible(b) end
    P.Divider = Divider
end

end)(); __m(P) end
-- ==== Widgets/ColorPicker ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local UIS = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local function mouseXY()
        local m = UIS:GetMouseLocation()
        local ins = GuiService:GetGuiInset()
        return m.X - ins.X, m.Y - ins.Y
    end
    local CP = {}
    CP.__index = CP

    local RAINBOW = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.34, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.51, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.68, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.85, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
    })

    local function swatch(parent)
        return U.Create("TextButton", { Parent = parent, Text = "", AutoButtonColor = false,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(28, 14), BackgroundColor3 = Color3.new(1, 1, 1),
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
            U.Create("UIStroke", { Color = T.Outline, Thickness = 1 }) })
    end

    -- Crea el swatch en un parent arbitrario (uso standalone o adjunto a toggle)
    function CP._attach(Library, parentControl, flag, opts, xOffset)
        local self = setmetatable({ Library = Library, Flag = flag, Callback = opts.Callback,
            Open = false }, CP)
        self.Swatch = swatch(parentControl)
        if xOffset then self.Swatch.Position = UDim2.new(1, xOffset, 0.5, 0) end
        local d = opts.Default or Color3.fromRGB(255, 0, 0)
        self.H, self.S, self.V = d:ToHSV()
        self.Swatch.MouseButton1Click:Connect(function() self:Toggle() end)
        Library.Options[flag] = self
        self:_apply()
        return self
    end

    function CP.new(Panel, flag, opts)
        local base = P.Base.new(Panel, { LabelText = opts.Text or flag })
        local self = CP._attach(Panel.Library, base.Control, flag, opts, nil)
        self._base = base
        base._widget = self
        return self
    end

    function CP:_color() return Color3.fromHSV(self.H, self.S, self.V) end

    function CP:_apply()
        local c = self:_color()
        self.Value = c                      -- expone .Value como Color3 (fresco) para leerlo directo
        self.Swatch.BackgroundColor3 = c
        self.Library:SetFlag(self.Flag, c)
        if self._base then self._base.Changed:Fire(c) end
        if self.Callback then task.spawn(self.Callback, c) end
    end

    function CP:SetColor(c) self.H, self.S, self.V = c:ToHSV(); self:_apply()
        if self.SVCursor then self:_syncCursors() end end
    function CP:GetColor() return self:_color() end
    function CP:SetValue(c) self:SetColor(c) end
    function CP:GetValue() return self:_color() end

    function CP:_syncCursors()
        self.SVCursor.Position = UDim2.new(self.S, 0, 1 - self.V, 0)
        self.SV.BackgroundColor3 = Color3.fromHSV(self.H, 1, 1)
        self.HueCursor.Position = UDim2.new(0.5, 0, self.H, 0)
    end

    function CP:_closePopup()
        if self._c1 then self._c1:Disconnect(); self._c1 = nil end
        if self._c2 then self._c2:Disconnect(); self._c2 = nil end
        if self.Popup then self.Popup:Destroy(); self.Popup = nil end
        self.Open = false
        self.Library:ClosePopup(self._closer)
    end

    function CP:Toggle()
        if self.Open then self:_closePopup(); return end
        self._closer = self._closer or function() self:_closePopup() end
        self.Library:OpenPopup(self._closer)
        self.Open = true
        local gui = self.Swatch:FindFirstAncestorWhichIsA("ScreenGui")
        local ap = self.Swatch.AbsolutePosition
        local PH = 150
        local py = ap.Y + 20
        if py + PH > gui.AbsoluteSize.Y - 8 then py = ap.Y - PH - 6 end  -- flip arriba si no cabe
        self.Popup = U.Create("Frame", { Parent = gui, ZIndex = 60,
            Position = UDim2.fromOffset(ap.X - 150, py),
            Size = UDim2.fromOffset(190, PH), BackgroundColor3 = T.Surface2, BorderSizePixel = 0,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Outline, Thickness = 1 }),
            U.Create("UIPadding", { PaddingTop = UDim.new(0,8), PaddingLeft = UDim.new(0,8),
                PaddingBottom = UDim.new(0,8), PaddingRight = UDim.new(0,8) }) })

        -- cuadro SV (saturacion x, valor y)
        self.SV = U.Create("Frame", { Parent = self.Popup, ZIndex = 61,
            Size = UDim2.fromOffset(150, 134), BackgroundColor3 = Color3.fromHSV(self.H, 1, 1),
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
            -- blanco horizontal (saturacion)
            U.Create("Frame", { BackgroundColor3 = Color3.new(1,1,1), Size = UDim2.fromScale(1,1),
                ZIndex = 61 }, { U.Create("UICorner", { CornerRadius = UDim.new(0,4) }),
                U.Create("UIGradient", { Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }) }),
            -- negro vertical (valor)
            U.Create("Frame", { BackgroundColor3 = Color3.new(0,0,0), Size = UDim2.fromScale(1,1),
                ZIndex = 62 }, { U.Create("UICorner", { CornerRadius = UDim.new(0,4) }),
                U.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) }) }),
        })
        self.SVBtn = U.Create("TextButton", { Parent = self.SV, Text = "", BackgroundTransparency = 1,
            Size = UDim2.fromScale(1,1), ZIndex = 64 })
        self.SVCursor = U.Create("Frame", { Parent = self.SV, ZIndex = 63,
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 8),
            BackgroundColor3 = Color3.new(1,1,1) },
            { U.Create("UICorner", { CornerRadius = UDim.new(1,0) }),
              U.Create("UIStroke", { Color = Color3.new(0,0,0), Thickness = 1 }) })

        -- barra de hue vertical
        self.Hue = U.Create("TextButton", { Parent = self.Popup, Text = "", AutoButtonColor = false,
            ZIndex = 61, Position = UDim2.fromOffset(160, 0), Size = UDim2.fromOffset(14, 134),
            BackgroundColor3 = Color3.new(1,1,1),
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
            U.Create("UIGradient", { Rotation = 90, Color = RAINBOW }) })
        self.HueCursor = U.Create("Frame", { Parent = self.Hue, ZIndex = 62,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, self.H, 0),
            Size = UDim2.new(1, 4, 0, 3), BackgroundColor3 = Color3.new(1,1,1) },
            { U.Create("UIStroke", { Color = Color3.new(0,0,0), Thickness = 1 }) })

        self:_syncCursors()

        -- drag SV
        local function svFrom(px, py)
            local s = math.clamp((px - self.SV.AbsolutePosition.X) / self.SV.AbsoluteSize.X, 0, 1)
            local v = 1 - math.clamp((py - self.SV.AbsolutePosition.Y) / self.SV.AbsoluteSize.Y, 0, 1)
            self.S, self.V = s, v; self:_apply(); self:_syncCursors()
        end
        local function hueFrom(py)
            self.H = math.clamp((py - self.Hue.AbsolutePosition.Y) / self.Hue.AbsoluteSize.Y, 0, 1)
            self:_apply(); self:_syncCursors()
        end
        local svDrag, hueDrag = false, false
        self.SVBtn.MouseButton1Down:Connect(function() svDrag = true
            local mx, my = mouseXY(); svFrom(mx, my) end)
        self.Hue.MouseButton1Down:Connect(function() hueDrag = true
            local _, my = mouseXY(); hueFrom(my) end)
        self._c1 = UIS.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then svDrag, hueDrag = false, false end end)
        self._c2 = UIS.InputChanged:Connect(function(i)
            if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            local mx, my = mouseXY()
            if svDrag then svFrom(mx, my) elseif hueDrag then hueFrom(my) end
        end)
    end

    function CP:DependsOn(f, e) if self._base then self._base:DependsOn(f, e) end; return self end
    function CP:OnChanged(fn) if self._base then self._base:OnChanged(fn) end; return self end
    function CP:SetVisible(b) if self._base then self._base:SetVisible(b) end end

    P.ColorPicker = CP
end

end)(); __m(P) end
-- ==== Widgets/Gear ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local UIS = game:GetService("UserInputService")
    local Gear = {}
    Gear.__index = Gear

    -- icono engranaje
    function Gear.icon(parent)
        return U.Create("ImageButton", { Parent = parent, Name = "Gear", BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 2), Size = UDim2.fromOffset(14, 14),
            Image = "rbxassetid://6031280882", ImageColor3 = T.SubText, ZIndex = 5 })
    end

    -- mini-panel flotante que imita la interfaz de Panel (para reusar los widgets)
    function Gear.new(Library)
        local self = setmetatable({ Library = Library, _widgets = {}, Open = false }, Gear)
        self.Popup = U.Create("Frame", { Visible = false, ZIndex = 70, BackgroundColor3 = T.Surface,
            BorderSizePixel = 0, Size = UDim2.new(0, 210, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }) })
        U.Shadow(self.Popup, { Spread = 18, Transparency = 0.72, YOffset = 5 })
        self.Body = U.Create("Frame", { Parent = self.Popup, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        }, { U.Create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
            U.Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8),
                PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
        return self
    end

    function Gear:_rowParent() return self.Body end

    local function adder(key)
        return function(self, flag, o)
            if not P[key] then return nil end
            local W = P[key].new(self, flag, o or {})
            table.insert(self._widgets, W); return W
        end
    end
    Gear.AddToggle   = adder("Toggle")
    Gear.AddSlider   = adder("Slider")
    Gear.AddDropdown = adder("Dropdown")
    Gear.AddKeybind  = adder("Keybind")
    Gear.AddTextBox  = adder("TextBox")
    function Gear:AddButton(t, cb) local W = P.Button.new(self, nil, { Text = t, Callback = cb })
        table.insert(self._widgets, W); return W end
    function Gear:AddLabel(t, o) local W = P.Label.new(self, nil, { Text = t, Header = o and o.Header })
        table.insert(self._widgets, W); return W end
    function Gear:AddColorPicker(f, o) local W = P.ColorPicker.new(self, f, o or {})
        table.insert(self._widgets, W); return W end

    function Gear:attachTo(iconBtn)
        self._icon = iconBtn
        iconBtn.MouseButton1Click:Connect(function() self:Toggle() end)
    end

    function Gear:_forceClose()
        self.Popup.Visible = false; self.Open = false
        if self._icon then self._icon.ImageColor3 = T.SubText end
        self.Library:ClosePopup(self._closer)
    end

    function Gear:Toggle()
        if self.Open then self:_forceClose(); return end
        self._closer = self._closer or function() self:_forceClose() end
        self.Library:OpenPopup(self._closer)
        local gui = self._icon:FindFirstAncestorWhichIsA("ScreenGui")
        self.Popup.Parent = gui
        local ap = self._icon.AbsolutePosition
        self.Popup.Position = UDim2.fromOffset(ap.X - 210 + 20, ap.Y + 20)
        self.Popup.Visible = true; self.Open = true
        self._icon.ImageColor3 = T.Accent
    end

    P.Gear = Gear
end

end)(); __m(P) end
-- ==== Widgets/Viewport ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local RunService = game:GetService("RunService")
    local Viewport = {}
    Viewport.__index = Viewport

    -- handler generico: mete cualquier modelo/instancia y lo muestra (auto-frame + auto-rotate)
    function Viewport.new(Panel, opts)
        opts = opts or {}
        local base = P.Base.new(Panel, { LabelText = nil, Height = opts.Height or 180 })
        local self = setmetatable({ _base = base, Library = Panel.Library,
            AutoRotate = opts.AutoRotate ~= false, Speed = opts.RotateSpeed or 40,
            Pitch = opts.Pitch or 0.35, _angle = 0 }, Viewport)
        base._widget = self
        base.Control.Visible = false

        self.VF = U.Create("ViewportFrame", { Parent = base.Row, Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = opts.Background or T.Surface2, BorderSizePixel = 0,
            Ambient = Color3.fromRGB(170, 170, 175), LightColor = Color3.fromRGB(255, 255, 255),
            LightDirection = Vector3.new(-0.4, -1, -0.5),
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }) })
        self.Cam = Instance.new("Camera"); self.Cam.Parent = self.VF; self.VF.CurrentCamera = self.Cam
        self.World = Instance.new("WorldModel"); self.World.Parent = self.VF
        self.Library:Maid(self.VF)
        return self
    end

    function Viewport:Clear()
        if self._conn then self._conn:Disconnect(); self._conn = nil end
        for _, c in ipairs(self.World:GetChildren()) do c:Destroy() end
        self.Model = nil
    end

    -- inst: cualquier Model / BasePart / Folder de partes. opts.AutoRotate opcional override.
    function Viewport:SetModel(inst, opts)
        self:Clear()
        if not inst then return end
        opts = opts or {}
        local m
        pcall(function() m = inst:Clone() end)
        if not m then
            -- Archivable=false devuelve nil: forzarlo temporalmente
            local prev = inst.Archivable
            inst.Archivable = true
            pcall(function() m = inst:Clone() end)
            inst.Archivable = prev
        end
        if not m then return end
        if not m:IsA("Model") then
            local wrap = Instance.new("Model")
            m.Parent = wrap
            m = wrap
        end
        m.Parent = self.World
        self.Model = m

        local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
        if not ok or not cf then cf, size = CFrame.new(), Vector3.new(4, 4, 4) end
        self._center = cf.Position
        self._radius = math.max(size.Magnitude / 2, 1)
        self._dist = self._radius / math.tan(math.rad(30)) + self._radius
        self:_apply(0)

        local rotate = opts.AutoRotate
        if rotate == nil then rotate = self.AutoRotate end
        if rotate then
            self._conn = RunService.RenderStepped:Connect(function(dt) self:_spin(dt) end)
            self.Library:Maid(self._conn)
        end
        return self
    end

    function Viewport:_apply(angle)
        local c = self._center
        local pos = c + Vector3.new(math.sin(angle) * self._dist, self._radius * self.Pitch, math.cos(angle) * self._dist)
        self.Cam.CFrame = CFrame.lookAt(pos, c)
    end
    function Viewport:_spin(dt)
        self._angle = self._angle + math.rad(self.Speed) * dt
        self:_apply(self._angle)
    end

    function Viewport:SetAutoRotate(b)
        self.AutoRotate = b
        if not b and self._conn then self._conn:Disconnect(); self._conn = nil
        elseif b and self.Model and not self._conn then
            self._conn = RunService.RenderStepped:Connect(function(dt) self:_spin(dt) end)
            self.Library:Maid(self._conn)
        end
    end
    function Viewport:SetSpeed(s) self.Speed = s end
    function Viewport:DependsOn(f, e) self._base:DependsOn(f, e); return self end
    function Viewport:SetVisible(b) self._base:SetVisible(b) end

    P.Viewport = Viewport
end

end)(); __m(P) end
-- ==== Widgets/Grid ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local Grid = {}
    Grid.__index = Grid

    -- grid de thumbnails (estilo Skins de primordial). opts: Height, CellSize, Callback
    function Grid.new(Panel, opts)
        opts = opts or {}
        local base = P.Base.new(Panel, { LabelText = nil, Height = opts.Height or 200 })
        local self = setmetatable({ _base = base, Library = Panel.Library,
            Cell = opts.CellSize or 54, Callback = opts.Callback, Items = {}, Selected = nil }, Grid)
        base._widget = self
        base.Control.Visible = false

        self.Scroll = U.Create("ScrollingFrame", { Parent = base.Row, BackgroundColor3 = T.Surface2,
            BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 0,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }),
            U.Create("UIGridLayout", { CellSize = UDim2.fromOffset(self.Cell, self.Cell),
                CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder,
                HorizontalAlignment = Enum.HorizontalAlignment.Left }),
            U.Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6),
                PaddingBottom = UDim.new(0, 6) }) })
        return self
    end

    -- item: { Image = assetId, Name = string?, Callback = fn? }
    function Grid:AddItem(item)
        local i = #self.Items + 1
        local cell = U.Create("TextButton", { Parent = self.Scroll, AutoButtonColor = false, Text = "",
            BackgroundColor3 = T.Surface3, LayoutOrder = i,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
            U.Create("UIStroke", { Name = "Sel", Color = T.Accent, Thickness = 1, Transparency = 1 }),
            U.Create("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = item.Image or "",
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromScale(0.78, 0.78), ScaleType = Enum.ScaleType.Fit }) })
        if item.Name then
            cell.Icon.Position = UDim2.fromScale(0.5, 0.42)
            cell.Icon.Size = UDim2.fromScale(0.66, 0.66)
            U.Create("TextLabel", { Parent = cell, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1),
                Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(1, -4, 0, 11),
                Font = T.Font, TextSize = 10, TextColor3 = T.SubText, Text = item.Name,
                TextTruncate = Enum.TextTruncate.AtEnd })
        end
        local rec = { cell = cell, item = item }
        table.insert(self.Items, rec)
        cell.MouseButton1Click:Connect(function() self:Select(i) end)
        return rec
    end

    function Grid:Select(i)
        for idx, rec in ipairs(self.Items) do
            rec.cell.Sel.Transparency = (idx == i) and 0 or 1
        end
        self.Selected = i
        local it = self.Items[i]
        if it then
            if it.item.Callback then task.spawn(it.item.Callback, it.item) end
            if self.Callback then task.spawn(self.Callback, it.item, i) end
        end
    end
    function Grid:GetSelected() local r = self.Items[self.Selected]; return r and r.item end
    function Grid:Clear()
        for _, r in ipairs(self.Items) do r.cell:Destroy() end
        self.Items = {}; self.Selected = nil
    end
    function Grid:SetVisible(b) self._base:SetVisible(b) end

    P.Grid = Grid
end

end)(); __m(P) end
-- ==== Widgets/List ====
do local __m = (function()
return function(P)
    local U, T = P.Util, P.Theme
    local List = {}
    List.__index = List

    -- list-box permanente (dropdown pre-abierto). opts: Text, Values, Multi, Default, Height, Callback
    function List.new(Panel, flag, opts)
        local titleH = opts.Text and 18 or 0
        local boxH = opts.Height or 120
        local base = P.Base.new(Panel, { LabelText = nil, Height = titleH + boxH, Tooltip = opts.Tooltip })
        local self = setmetatable({ _base = base, Library = Panel.Library, Flag = flag,
            Values = opts.Values or {}, Multi = opts.Multi and true or false, Callback = opts.Callback,
            Items = {} }, List)
        base._widget = self
        base.Control.Visible = false

        if opts.Text then
            self.Title = U.Create("TextLabel", { Parent = base.Row, BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 16), Font = T.FontBold, TextSize = T.TextSize,
                Text = opts.Text, TextColor3 = T.SubText, TextXAlignment = Enum.TextXAlignment.Left })
        end

        self.Box = U.Create("Frame", { Parent = base.Row, Position = UDim2.fromOffset(0, titleH),
            Size = UDim2.new(1, 0, 0, boxH), BackgroundColor3 = T.Surface2, BorderSizePixel = 0, ClipsDescendants = true,
        }, { U.Create("UICorner", { CornerRadius = UDim.new(0, T.Radius) }),
            U.Create("UIStroke", { Color = T.Border, Thickness = 1 }) })
        self.Scroll = U.Create("ScrollingFrame", { Parent = self.Box, BackgroundTransparency = 1,
            BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 0,
        }, { U.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
            U.Create("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }) })

        if self.Multi then self.Value = {} else self.Value = nil end
        self:_build()

        self.Library.Options[flag] = self
        local def = opts.Default
        if self.Multi then
            if type(def) == "table" then for _, v in ipairs(def) do self.Value[v] = true end end
        elseif def == nil and not opts.AllowNull then def = self.Values[1] end
        self:SetValue(self.Multi and self:GetValue() or def)
        return self
    end

    function List:_build()
        for _, it in ipairs(self.Items) do it.btn:Destroy() end
        self.Items = {}
        for i, v in ipairs(self.Values) do
            local btn = U.Create("TextButton", { Parent = self.Scroll, AutoButtonColor = false,
                BackgroundColor3 = T.Surface3, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22),
                LayoutOrder = i, Text = "",
            }, { U.Create("TextLabel", { Name = "L", BackgroundTransparency = 1,
                Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -12, 1, 0), Font = T.Font,
                TextSize = T.TextSize, Text = tostring(v), TextColor3 = T.Text,
                TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }) })
            table.insert(self.Items, { btn = btn, value = v })
            btn.MouseButton1Click:Connect(function() self:_click(v) end)
        end
        self:_render()
    end

    function List:_click(v)
        if self.Multi then
            self.Value[v] = (not self.Value[v]) or nil
        else
            self.Value = v
        end
        self:_render()
        self.Library:SetFlag(self.Flag, self:GetValue())
        self._base.Changed:Fire(self:GetValue())
        if self.Callback then task.spawn(self.Callback, self:GetValue()) end
    end

    function List:_isSel(v)
        if self.Multi then return self.Value[v] == true else return self.Value == v end
    end
    function List:_render()
        for _, it in ipairs(self.Items) do
            local sel = self:_isSel(it.value)
            it.btn.BackgroundTransparency = sel and 0.4 or 1
            it.btn.L.TextColor3 = sel and T.Accent or T.Text
        end
    end

    function List:GetValue()
        if not self.Multi then return self.Value end
        local out = {}
        for _, v in ipairs(self.Values) do if self.Value[v] then table.insert(out, v) end end
        return out
    end
    function List:SetValue(v)
        if self.Multi then
            self.Value = {}
            if type(v) == "table" then for _, x in ipairs(v) do self.Value[x] = true end end
        else
            self.Value = v
        end
        self:_render()
        self.Library:SetFlag(self.Flag, self:GetValue())
        self._base.Changed:Fire(self:GetValue())
        if self.Callback then task.spawn(self.Callback, self:GetValue()) end
    end
    function List:SetValues(list) self.Values = list; self:_build() end
    function List:DependsOn(f, e) self._base:DependsOn(f, e); return self end
    function List:OnChanged(fn) self._base:OnChanged(fn); return self end
    function List:SetVisible(b) self._base:SetVisible(b) end

    P.List = List
end

end)(); __m(P) end
return P.Library
end)()
local LIP
local function require(name)
    if _cache[name] then return _cache[name] end
    local m = _MODS[name](require, LIP, Lib)
    _cache[name] = m
    return m
end
LIP = _MODS["Core.State"](require, nil, Lib)
_cache["Core.State"] = LIP
LIP.Library = Lib
LIP.require = require
_MODS["main"](require, LIP, Lib)
return LIP
