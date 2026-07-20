-- main.lua — FACTORY. Driver: Window PrimordialUI + loop de estado.
--  M1 self-ragdoll (op23) · M2 auto-punch/melee-aura · M3 silent aim (op14 passive swap).
-- El __namecall hook (Net) es passive + precache: el driver computa targets AFUERA del hook.
return function(require, LIP, Lib)
    local RunService = game:GetService("RunService")
    local Players    = game:GetService("Players")
    local LP = Players.LocalPlayer

    local UIS = game:GetService("UserInputService")

    local Ragdoll = require("Combat.Ragdoll")
    local Target  = require("Combat.Target")
    local Melee   = require("Combat.Melee")
    local Strafe  = require("Combat.Strafe")
    local Weapon  = require("Combat.Weapon")
    local Net     = require("Net")
    local Move    = require("Movement.Movement")
    local Vehicle = require("Movement.Vehicle")
    local ESP     = require("Visuals.ESP")
    local UI      = require("UI")

    local Window = Lib:CreateWindow({ Title = "life in prison", Size = Vector2.new(834, 586) })
    LIP.Library = Lib
    UI.build(Window)
    Net.install()    -- 1 hook __namecall (silent aim op14 + melee aura op16)
    Move.init()      -- Movement (fly/noclip/speed/jump, client-side)
    Vehicle.init()   -- Vehicle (speed multiplier, client-owned physics)
    ESP.init()       -- Visuals (Drawing + Highlight, client-side)

    -- Rapid fire: al disparar (mouse1), ráfaga extra de op14 al target de silent aim
    LIP.track(UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
           and Lib.Toggles.RapidFire and Lib.Toggles.RapidFire.Value then
            Weapon.rapidBurst()
        end
    end))

    local T, O = Lib.Toggles, Lib.Options

    -- precache del hit de silent aim (Head/HRP del target) — afuera del hook (sin reentrancy)
    local function cacheHit()
        local t = LIP.target
        local ch = t and t.Character
        local part = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
        LIP.cachedHitPart = part
        if part then
            local base = part.Position
            if T.Resolver and T.Resolver.Value then base = Strafe.resolvePos(t, base) end  -- centro resuelto
            LIP.cachedHitPos = LIP.antiInvis and (base + Vector3.new(0, -1.4, 0)) or base
        else
            LIP.cachedHitPos = nil
        end
    end

    -- ── DRIVER (Heartbeat) ──────────────────────────────────────────────────────
    LIP.track(RunService.Heartbeat:Connect(function()
        LIP.antiInvis = T.AntiInvis and T.AntiInvis.Value or false
        LIP.swapOn    = T.SilentAim and T.SilentAim.Value or false
        LIP.meleeOn   = T.MeleeAura and T.MeleeAura.Value or false

        local filters = { teamCheck = T.TeamCheck.Value, friendCheck = T.FriendCheck.Value }

        -- Silent aim: elige target + precache
        if LIP.swapOn then
            Target.pick({ mode = O.SelMode.Value, fov = O.FOV.Value, wallcheck = T.Wallcheck.Value,
                          teamCheck = filters.teamCheck, friendCheck = filters.friendCheck })
            cacheHit()
        else
            LIP.cachedHitPart, LIP.cachedHitPos = nil, nil
        end

        -- Target Strafe (desync HvH) + resolver sampling
        local strafeOn = T.TargetStrafe and T.TargetStrafe.Value
        if LIP.swapOn or strafeOn then Strafe.sampleAll(os.clock()) end
        if strafeOn then
            -- target del strafe = el de silent aim (mismo que apuntás), o el enemigo cercano (≤200)
            -- para no teleportarte por todo el mapa a orbitar a uno lejano
            local st = LIP.target or Target.nearestEnemy({ range = 200,
                          teamCheck = filters.teamCheck, friendCheck = filters.friendCheck })
            if st then
                Strafe.tick(st, { mode = O.StrafeMode.Value, radius = O.StrafeRadius.Value,
                                  speed = O.StrafeSpeed.Value, height = O.StrafeHeight.Value })
            end
        end

        -- Melee aura: precache del target (el hook redirige op16)
        if LIP.meleeOn then
            Melee.cacheMelee({ range = O.MeleeRange.Value, teamCheck = filters.teamCheck, friendCheck = filters.friendCheck })
        else
            LIP.meleePart = nil
        end

        -- Auto-punch (op33 activo, sin GST)
        if T.AutoPunch and T.AutoPunch.Value then
            Melee.autoPunch({ range = O.PunchRange.Value, rate = 0.5,
                              teamCheck = filters.teamCheck, friendCheck = filters.friendCheck })
        end

        -- Permanent ragdoll
        if T.RagdollLock and T.RagdollLock.Value then Ragdoll.tickLock() end
    end))

    pcall(function() if Window.AddSettingsTab then Window:AddSettingsTab() end end)
    pcall(function()
        if Lib.SetWatermark then Lib:SetWatermark("life in prison \226\128\162 primordial") end
        if Lib.SetWatermarkVisibility then Lib:SetWatermarkVisibility(true) end
    end)
    pcall(function() if Lib.LoadAutoloadConfig then Lib:LoadAutoloadConfig() end end)
    Lib:Notify({ Title = "LifeInPrisonPrimordial", Description = "Ragdoll + Melee + Silent Aim cargado.", Time = 5 })
end
