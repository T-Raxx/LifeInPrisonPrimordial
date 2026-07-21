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

    local T, O = Lib.Toggles, Lib.Options

    -- precache del hit de silent aim / autofire (Head del target, resolver opcional)
    local function cacheHit()
        local t = LIP.target
        local ch = t and t.Character
        local part = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
        LIP.cachedHitPart = part
        if part then
            local base = part.Position
            if T.Resolver and T.Resolver.Value then
                base = Strafe.resolvePos(t, base, O.ResolverMethod.Value, O.ResolverSamples.Value, O.ResolverPredict.Value)
            end
            LIP.cachedHitPos = LIP.antiInvis and (base + Vector3.new(0, -1.4, 0)) or base
        else
            LIP.cachedHitPos = nil
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
        if godOn then
            if LIP.spoofOn then Strafe.stop() end
            Godmode.tick()
        else
            if LIP.godBase then Godmode.stop() end
            if strafeOn and voidOn then
                -- COMBO strafe+void: void en modo ABSOLUTO por intervalos (posiciones fijas, no relativas)
                Void.tick({ pattern = O.VoidPattern.Value, height = O.VoidHeight.Value, dist = O.VoidDist.Value,
                            speed = O.VoidSpeed.Value, absolute = true, interval = O.VoidInterval.Value })
            elseif strafeOn then
                local st = LIP.target or Target.nearestEnemy({ range = 200,
                              teamCheck = filters.teamCheck, friendCheck = filters.friendCheck })
                if st then
                    Strafe.tick(st, { mode = O.StrafeMode.Value, radius = O.StrafeRadius.Value,
                                      speed = O.StrafeSpeed.Value, height = O.StrafeHeight.Value,
                                      posSpoof = T.StrafePosSpoof.Value, chase = T.StrafeChase.Value,
                                      bait = T.StrafeBait.Value, predict = O.ResolverPredict.Value })
                else Strafe.stop() end
            elseif voidOn then
                Void.tick({ pattern = O.VoidPattern.Value, height = O.VoidHeight.Value,
                            dist = O.VoidDist.Value, speed = O.VoidSpeed.Value,
                            absolute = T.VoidAbsolute.Value, interval = O.VoidInterval.Value })
            elseif LIP.spoofOn then
                Strafe.stop()
            end
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
