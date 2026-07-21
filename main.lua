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
    local Net     = require("Net")
    local Move    = require("Movement.Movement")
    local Vehicle = require("Movement.Vehicle")
    local Void    = require("Movement.Void")
    local ESP     = require("Visuals.ESP")
    local UI      = require("UI")

    local Window = Lib:CreateWindow({ Title = "life in prison", Size = Vector2.new(834, 586) })
    LIP.Library = Lib
    UI.build(Window)
    Net.install()    -- __namecall silent aim op14 + melee aura op16
    Move.init()      -- fly/noclip/speed/jump
    Vehicle.init()   -- vehicle speed
    Strafe.init()    -- Spoof.init (hook __index + restore RenderStepped, compartido con Void)
    Void.init()      -- void spam + visualizador (Spoof.init idempotente)
    ESP.init()       -- Visuals

    -- ANTI-SLEEP: Roblox pausa la replicación de posición si el assembly está QUIETO (rompe el
    -- desync/spoof). Mantenemos una velocity pasiva mínima (0.003 studs/s hacia arriba) cuando estás
    -- quieto → el assembly no "duerme" → la posición sigue replicando. Persiste en muerte (lee el
    -- Character cada frame). Solo aplica cuando estás casi quieto (no pisa caminar/saltar/caer).
    LIP.track(RunService.Heartbeat:Connect(function()
        local c = LP.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if root and root.AssemblyLinearVelocity.Magnitude < 0.05 then
            root.AssemblyLinearVelocity = Vector3.new(0, 0.003, 0)
        end
    end))

    local T, O = Lib.Toggles, Lib.Options

    -- precache del hit de silent aim / autofire (Head del target, resolver opcional)
    local function cacheHit()
        local t = LIP.target
        local ch = t and t.Character
        local part = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
        LIP.cachedHitPart = part
        if part then
            -- HBE-SAFE: hitPos = CENTRO EXACTO del hitPart (objspace ZERO). El server aplica daño al
            -- hitPart real igual → NO predecir/offsetear el hit (predict/antiInvis lo sacan del hitbox
            -- = detección Hitbox Expander → ban). El resolver/predict se usa solo para el strafe orbit.
            local base = part.Position
            LIP.cachedHitPos = base
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
            LIP.cachedHitPos = nil; LIP.cachedOrigin = nil
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

    -- target: manual (persiste muerte/rejoin) > STICKY (mantiene el actual si sigue válido) > pick
    local function resolveTarget(filters, needAim)
        local manual = Strafe.manualPlayer()
        if manual then LIP.target = manual; return end
        if needAim then
            if LIP.target and stillValid(LIP.target, filters) then return end   -- lock: no saltar a otro
            Target.pick({ mode = O.SelMode.Value, fov = O.FOV.Value, wallcheck = T.Wallcheck.Value,
                          teamCheck = filters.teamCheck, friendCheck = filters.friendCheck })
        else
            LIP.target = nil
        end
    end

    LIP.track(RunService.Heartbeat:Connect(function()
        LIP.antiInvis = T.AntiInvis and T.AntiInvis.Value or false
        LIP.swapOn    = T.SilentAim and T.SilentAim.Value or false
        LIP.meleeOn   = T.MeleeAura and T.MeleeAura.Value or false
        LIP.wallbang  = T.Wallbang and T.Wallbang.Value or false
        local filters = { teamCheck = T.TeamCheck.Value, friendCheck = T.FriendCheck.Value }
        local cam = Workspace.CurrentCamera

        local strafeOn = T.TargetStrafe and T.TargetStrafe.Value
        local autoOn   = T.AutoFire and T.AutoFire.Value
        local godOn    = T.Godmode and T.Godmode.Value
        local voidOn   = T.VoidSpam and T.VoidSpam.Value
        local needAim  = LIP.swapOn or strafeOn or autoOn

        -- resolver sampling (historial de enemigos)
        if needAim or (T.Resolver and T.Resolver.Value) then Strafe.sampleAll(os.clock(), O.ResolverReject.Value) end

        -- target + precache (para silent aim swap Y autofire)
        resolveTarget(filters, needAim)
        if LIP.target then cacheHit() else LIP.cachedHitPart, LIP.cachedHitPos = nil, nil end

        -- ── POSICIÓN: Godmode > Strafe > Void (excluyentes) ──
        if godOn then Godmode.tick() end   -- no-op + aviso (godmode = ban HBE, neutralizado)

        -- MASTER Pos Spoof controla strafe Y void. Prioridad: Strafe > Void.
        local posSpoof = T.PosSpoof and T.PosSpoof.Value
        if strafeOn then
            local st = LIP.target or Target.nearestEnemy({ range = 200,
                          teamCheck = filters.teamCheck, friendCheck = filters.friendCheck })
            if st then
                Strafe.tick(st, { mode = O.StrafeMode.Value, radius = O.StrafeRadius.Value,
                                  speed = O.StrafeSpeed.Value, height = O.StrafeHeight.Value,
                                  posSpoof = posSpoof, chase = T.StrafeChase.Value,
                                  bait = T.StrafeBait.Value, predict = O.ResolverPredict.Value })
            else Strafe.stop() end
        elseif voidOn then
            Void.tick({ dist = O.VoidDist.Value, pattern = O.VoidPattern.Value, posSpoof = posSpoof })
        elseif LIP.spoofOn then
            Strafe.stop()
        end

        -- spectator (override de cámara al target manual)
        if T.Spectate and T.Spectate.Value then Strafe.spectate(cam) end

        -- auto/rapid fire (op14 directo con ammo tracking; funciona ragdolleado)
        Weapon.tickAuto()

        -- melee aura / auto punch
        if LIP.meleeOn then
            Melee.cacheMelee({ range = O.MeleeRange.Value, teamCheck = filters.teamCheck, friendCheck = filters.friendCheck })
        else LIP.meleePart = nil end
        if T.AutoPunch and T.AutoPunch.Value then
            Melee.autoPunch({ range = O.PunchRange.Value, rate = 0.5, teamCheck = filters.teamCheck, friendCheck = filters.friendCheck })
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
