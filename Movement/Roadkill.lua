-- Movement/Roadkill.lua — EXPERIMENTO roadkill. El roadkill de LiP es server-side (colisión vehículo↔jugador,
-- sin remote en el client). Idea: owneás un vehículo/tu cuerpo → lo hacés aparecer en el target (server-side) a
-- velocidad brutal → el server registra la colisión → roadkill. Varios métodos client-side seleccionables,
-- disparo MANUAL (keybind). Ninguno confirmado — es un harness para que el usuario pruebe cuál pega.
--
-- Métodos:
--  · PhysRep    : connection weld del VEHÍCULO al target (sethidden PhysicsRepRootPart=targetHRP) + velocidad.
--                 El server reps el vehículo EN el target SIN escribir CFrame → tu cliente queda quieto (sin
--                 auto-fling, el bug de Method A). El más prometedor.
--  · VehicleRam : teleport el vehículo detrás del target UNA vez + velocidad hacia él (self-fling, raw collision).
--  · SelfPhysRep: tu CUERPO rep'd en el target + velocidad (proyectil, sin vehículo).
--  · BringTarget: escribís la CFrame del target al frente tuyo (dudoso — no owneás su char; muestra si se puede).
return function(require, LIP, Lib)
    local Players   = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Spoof  = require("Combat.Spoof")
    local Target = require("Combat.Target")
    local Roadkill = {}
    local sethidden = sethiddenproperty

    local function O(f) local o = Lib.Options[f]; return o and o.Value end

    local function tgt()
        if LIP.target then return LIP.target end
        return (Target.nearestEnemy and Target.nearestEnemy({ range = 1e9 })) or nil
    end
    local function tgtHRP() local t = tgt(); local c = t and t.Character; return c and c:FindFirstChild("HumanoidRootPart") end
    local function myHRP() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
    local function seatedVehicleRoot()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if not hum then return nil end
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("VehicleSeat") and d.Occupant == hum then return d.AssemblyRootPart end
        end
        return nil
    end
    local function notify(m) if LIP.Library and LIP.Library.Notify then pcall(function() LIP.Library:Notify({ Title = "Roadkill", Description = m, Time = 3 }) end) end end

    -- dispara el método seleccionado durante RKDuration seg (ram sostenido). Manual (keybind).
    function Roadkill.fire()
        local method = O("RKMethod") or "PhysRep"
        local vel    = O("RKVelocity") or 800
        local dur    = O("RKDuration") or 0.5
        local th = tgtHRP()
        if not th then return notify("sin target") end
        task.spawn(function()
            local t0 = os.clock()
            if method == "PhysRep" then
                local vr = seatedVehicleRoot(); if not vr then return notify("sentate en un vehículo") end
                while os.clock() - t0 < dur do
                    local h = tgtHRP(); if not h then break end
                    pcall(function()
                        if sethidden then sethidden(vr, "PhysicsRepRootPart", h) end
                        vr.AssemblyLinearVelocity = (h.Position - vr.Position).Unit * vel
                    end)
                    task.wait()
                end
                pcall(function() if sethidden then sethidden(vr, "PhysicsRepRootPart", vr) end end)   -- restore

            elseif method == "VehicleRam" then
                local vr = seatedVehicleRoot(); if not vr then return notify("sentate en un vehículo") end
                local h0 = tgtHRP()
                pcall(function() vr.CFrame = CFrame.new(h0.Position - (h0.CFrame.LookVector * 22) + Vector3.new(0, 3, 0)) end)
                while os.clock() - t0 < dur do
                    local h = tgtHRP(); if not h then break end
                    pcall(function() vr.AssemblyLinearVelocity = (h.Position - vr.Position).Unit * vel end)
                    task.wait()
                end

            elseif method == "SelfPhysRep" then
                local r = myHRP(); if not r then return end
                while os.clock() - t0 < dur do
                    local h = tgtHRP(); if not h then break end
                    pcall(function()
                        Spoof.setPhysRep(h)
                        r.AssemblyLinearVelocity = (h.Position - r.Position).Unit * vel
                    end)
                    task.wait()
                end
                Spoof.unweld()

            elseif method == "BringTarget" then
                local r = myHRP(); if not r then return end
                while os.clock() - t0 < dur do
                    local h = tgtHRP(); if not h then break end
                    pcall(function()
                        h.CFrame = r.CFrame * CFrame.new(0, 0, -6)   -- al frente tuyo (dudoso: no owneás su char)
                        h.AssemblyLinearVelocity = Vector3.zero
                    end)
                    task.wait()
                end
            end
        end)
    end

    return Roadkill
end
