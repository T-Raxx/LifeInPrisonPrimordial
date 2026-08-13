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
        local ok, suite = pcall(function()
            return LIP.Visuals.Attach(Lib, Window, { adapter = "primordial",
                modules = { "world", "esp", "selffx", "aura", "combat" }, profile = "lifeinprison" })
        end)
        if ok and suite and suite.Unload then
            LIP.onCleanup(function() pcall(function() suite:Unload() end) end)
        end
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
            local voidAuto = T.VoidAutofire and T.VoidAutofire.Value
            if fireResOn and didDef and resolved then
                LIP.cachedHitPos = resolved; LIP.didDefensive = true
            elseif inVoid and voidAuto then
                -- VOID AUTOFIRE: target estático hondo en el void (50M+) = su pos del void ES su pos real →
                -- apuntá ahí (resuelta si hay, si no la cruda) + didDefensive=true para bypassear el gate de
                -- rango (50M >> FireRange). A los void-spammers los filtra la baja estabilidad de fireConfidence.
                LIP.cachedHitPos = (resolveOn and resolved) or base; LIP.didDefensive = true
            elseif inVoid and LIP.lastGoodHitPos then
                LIP.cachedHitPos = LIP.lastGoodHitPos; LIP.didDefensive = false   -- guard anti-void: nunca latch al ghost
            else
                LIP.cachedHitPos = base; LIP.didDefensive = false
            end
            if not inVoid then LIP.lastGoodHitPos = base; LIP.lastGoodT = os.clock() end
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
                    -- AUTO TIME (por arma): el ciclo IN+OUT = período del firerate del arma → 1 disparo por ciclo.
                    -- OUT = ventana de disparo (slider, lo único configurable); IN = resto del período (auto).
                    local outT = O.VoidOutTime.Value
                    local inT
                    if T.VoidAutoTime and T.VoidAutoTime.Value then
                        local period = math.max(LIP.observedFirerate or 0, 1 / math.max(O.AutoFireRate.Value or 30, 0.01))
                        inT = math.max(0.05, period - outT)
                    else
                        inT = O.VoidInTime.Value
                    end
                    local phase = Void.voidStep({ inTime = inT, outTime = outT,
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

        -- spectator: cámara al humanoide del target manual. CLEANUP: si Spectate off O no hay target válido →
        -- restaurar CameraSubject a tu propio humanoide (si no, la cámara queda pegada al target al apagar
        -- Spectate / Target Strafe). Salvo en desync/weld: ahí la cámara la maneja Spoof (no pisar).
        do
            local specHum
            if T.Spectate and T.Spectate.Value then
                local tp = Strafe.manualPlayer(); local tc = tp and tp.Character
                specHum = tc and tc:FindFirstChildOfClass("Humanoid")
            end
            if specHum then
                pcall(function() if cam.CameraSubject ~= specHum then cam.CameraSubject = specHum end end)
            elseif not (LIP.spoofOn or LIP.connRep) then
                local myHum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                if myHum and cam.CameraSubject ~= myHum then pcall(function() cam.CameraSubject = myHum end) end
            end
        end

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
